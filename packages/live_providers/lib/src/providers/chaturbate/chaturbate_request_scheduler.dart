import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

/// Priority for Chaturbate HTTP work sharing one site-wide budget.
///
/// Home/category list must not be starved by follow room-detail fan-out.
enum ChaturbateRequestPriority {
  /// Discover room-list / carousel / active playback bootstrap.
  high,

  /// Room detail / context / page (enter room).
  normal,

  /// Follow refresh and other best-effort background work.
  low,
}

/// Process-wide scheduler: caps concurrent CB requests, enforces spacing, and
/// drains higher priority work first so list + follow can coexist.
///
/// Follow (low) uses stricter spacing and its own 429 cooldown so a follow
/// storm cannot freeze home list or enter-room traffic.
class ChaturbateRequestScheduler {
  ChaturbateRequestScheduler({
    this.maxConcurrent = 1,
    /// Spacing for home list / enter-room (high + normal).
    this.minSpacing = const Duration(milliseconds: 350),
    /// Stricter spacing only for follow / low-priority work.
    /// Keep ≥2s so follow crawl rarely trips CF 429 at all.
    this.lowMinSpacing = const Duration(seconds: 2),
    /// Short cooldown after 429 on high/normal (user-facing paths).
    this.rateLimitCooldown = const Duration(seconds: 3),
    /// Base cooldown after 429 on low (follow) only; escalates while low keeps
    /// hitting 429. Does not block high/normal. Prefer not to hit this path —
    /// follow use case aborts the batch on first 429.
    this.lowRateLimitCooldown = const Duration(seconds: 45),
    this.maxLowRateLimitCooldown = const Duration(seconds: 180),
  }) : assert(maxConcurrent >= 1);

  /// Zone flag: wrap follow CB fan-out so all nested HTTP uses low budget.
  static const Object followBudgetZoneKey = #chaturbateFollowBudget;

  /// Shared default for all [HttpChaturbateApiClient] instances in-process.
  static final ChaturbateRequestScheduler instance =
      ChaturbateRequestScheduler();

  /// Run [body] under the follow-only CB budget (low priority + long 429).
  static Future<T> runAsFollowBudget<T>(Future<T> Function() body) {
    return runZoned(body, zoneValues: {followBudgetZoneKey: true});
  }

  static bool get isInFollowBudgetZone =>
      Zone.current[followBudgetZoneKey] == true;

  final int maxConcurrent;
  final Duration minSpacing;
  final Duration lowMinSpacing;
  final Duration rateLimitCooldown;
  final Duration lowRateLimitCooldown;
  final Duration maxLowRateLimitCooldown;

  final Queue<_ChaturbateScheduledJob> _high =
      Queue<_ChaturbateScheduledJob>();
  final Queue<_ChaturbateScheduledJob> _normal =
      Queue<_ChaturbateScheduledJob>();
  final Queue<_ChaturbateScheduledJob> _low = Queue<_ChaturbateScheduledJob>();

  int _inFlight = 0;
  DateTime _nextHighNormalSlotAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _nextLowSlotAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _pumpScheduled = false;
  int _consecutiveLowRateLimits = 0;

  int get debugPendingCount =>
      _high.length + _normal.length + _low.length + _inFlight;

  int get debugConsecutiveRateLimits => _consecutiveLowRateLimits;

  ChaturbateRequestPriority _effectivePriority(
    ChaturbateRequestPriority priority,
  ) {
    // Follow fan-out always demotes to low, even if the API path is "normal".
    if (isInFollowBudgetZone) {
      return ChaturbateRequestPriority.low;
    }
    return priority;
  }

  /// Call when CB returns 429.
  ///
  /// Low (follow) gets a long escalating pause that does **not** freeze
  /// home/enter-room. High/normal only take a short shared pause.
  void notifyRateLimited({
    Duration? cooldown,
    ChaturbateRequestPriority priority = ChaturbateRequestPriority.normal,
  }) {
    final effective = _effectivePriority(priority);
    if (effective == ChaturbateRequestPriority.low) {
      _consecutiveLowRateLimits = math.min(_consecutiveLowRateLimits + 1, 4);
      final multiplier = 1 << (_consecutiveLowRateLimits - 1); // 1,2,4,8
      final baseMs = (cooldown ?? lowRateLimitCooldown).inMilliseconds;
      final waitMs = math.min(
        baseMs * multiplier,
        maxLowRateLimitCooldown.inMilliseconds,
      );
      final until = DateTime.now().add(Duration(milliseconds: waitMs));
      if (until.isAfter(_nextLowSlotAt)) {
        _nextLowSlotAt = until;
      }
      _schedulePump();
      return;
    }

    final wait = cooldown ?? rateLimitCooldown;
    final until = DateTime.now().add(wait);
    if (until.isAfter(_nextHighNormalSlotAt)) {
      _nextHighNormalSlotAt = until;
    }
    _schedulePump();
  }

  /// Call after a successful (non-429) response so follow spacing can recover.
  void notifySuccess({
    ChaturbateRequestPriority priority = ChaturbateRequestPriority.normal,
  }) {
    if (_effectivePriority(priority) == ChaturbateRequestPriority.low) {
      _consecutiveLowRateLimits = 0;
    }
  }

  Future<T> schedule<T>(
    Future<T> Function() action, {
    ChaturbateRequestPriority priority = ChaturbateRequestPriority.normal,
  }) {
    final effective = _effectivePriority(priority);
    final completer = Completer<T>();
    final job = _ChaturbateScheduledJob(
      priority: effective,
      run: () async {
        try {
          final value = await action();
          if (!completer.isCompleted) {
            completer.complete(value);
          }
        } catch (error, stackTrace) {
          if (!completer.isCompleted) {
            completer.completeError(error, stackTrace);
          }
        }
      },
    );
    final queue = switch (effective) {
      ChaturbateRequestPriority.high => _high,
      ChaturbateRequestPriority.normal => _normal,
      ChaturbateRequestPriority.low => _low,
    };
    queue.add(job);
    _schedulePump();
    return completer.future;
  }

  void _schedulePump() {
    if (_pumpScheduled) {
      return;
    }
    _pumpScheduled = true;
    scheduleMicrotask(() {
      _pumpScheduled = false;
      unawaited(_pumpOnce());
    });
  }

  bool get _hasQueuedWork =>
      _high.isNotEmpty || _normal.isNotEmpty || _low.isNotEmpty;

  _ChaturbateScheduledJob? _peekNext() {
    if (_high.isNotEmpty) {
      return _high.first;
    }
    if (_normal.isNotEmpty) {
      return _normal.first;
    }
    if (_low.isNotEmpty) {
      return _low.first;
    }
    return null;
  }

  _ChaturbateScheduledJob? _takeNext() {
    if (_high.isNotEmpty) {
      return _high.removeFirst();
    }
    if (_normal.isNotEmpty) {
      return _normal.removeFirst();
    }
    if (_low.isNotEmpty) {
      return _low.removeFirst();
    }
    return null;
  }

  DateTime _slotFor(ChaturbateRequestPriority priority) {
    return priority == ChaturbateRequestPriority.low
        ? _nextLowSlotAt
        : _nextHighNormalSlotAt;
  }

  void _advanceSlot(ChaturbateRequestPriority priority) {
    final now = DateTime.now();
    if (priority == ChaturbateRequestPriority.low) {
      _nextLowSlotAt = now.add(lowMinSpacing);
    } else {
      _nextHighNormalSlotAt = now.add(minSpacing);
    }
  }

  Future<void> _pumpOnce() async {
    while (_inFlight < maxConcurrent && _hasQueuedWork) {
      final next = _peekNext();
      if (next == null) {
        return;
      }
      final now = DateTime.now();
      final slotAt = _slotFor(next.priority);
      if (now.isBefore(slotAt)) {
        // Sleep in short slices so a newly queued high/normal job can preempt
        // a long follow (low) 429 cooldown wait.
        final remaining = slotAt.difference(now);
        final slice = remaining > const Duration(milliseconds: 50)
            ? const Duration(milliseconds: 50)
            : remaining;
        await Future<void>.delayed(slice);
        continue;
      }
      final job = _takeNext();
      if (job == null) {
        return;
      }
      _inFlight += 1;
      _advanceSlot(job.priority);
      unawaited(() async {
        try {
          await job.run();
        } finally {
          _inFlight -= 1;
          _schedulePump();
        }
      }());
    }
  }
}

class _ChaturbateScheduledJob {
  _ChaturbateScheduledJob({
    required this.priority,
    required this.run,
  });

  final ChaturbateRequestPriority priority;
  final Future<void> Function() run;
}
