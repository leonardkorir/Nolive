import 'package:live_core/live_core.dart';
import 'package:live_player/live_player.dart';
import 'package:nolive_app/src/features/room/application/room_provider_traits.dart';

/// Tracks multi-line failover state for non–site-specialized providers.
///
/// Twitch / Chaturbate / Stripchat keep their specialized recovery paths;
/// this controller is for ordinary multi-URL domestic live playlists.
///
/// Important: [ensureSession] must be used across repeated unexpected stops so
/// retry/line counters are preserved. Only a changed play-URL set resets state.
class RoomGenericLineFailoverController {
  RoomGenericLineFailoverController({
    this.policy = const PlaybackFailoverPolicy(),
  });

  final PlaybackFailoverPolicy policy;

  List<LivePlayUrl> _lines = const [];
  int _lineIndex = 0;
  int _retryCount = 0;
  String _sessionSignature = '';
  PlaybackSource? Function(LivePlayUrl line)? _sourceBuilder;

  int get lineIndex => _lineIndex;
  int get retryCount => _retryCount;
  List<LivePlayUrl> get lines => _lines;
  String get sessionSignature => _sessionSignature;

  static String signatureFor(List<LivePlayUrl> playUrls) {
    return playUrls.map((line) => line.url).join('\u0001');
  }

  /// Full hard reset (new quality / new room playlist).
  void reset({
    required List<LivePlayUrl> playUrls,
    PlaybackSource? Function(LivePlayUrl line)? sourceBuilder,
    PlaybackSource? currentSource,
  }) {
    _lines = List<LivePlayUrl>.from(playUrls);
    _sessionSignature = signatureFor(_lines);
    _sourceBuilder = sourceBuilder;
    _retryCount = 0;
    _lineIndex = 0;
    if (currentSource != null && _lines.isNotEmpty) {
      final match = _lines.indexWhere(
        (line) => line.url.toString() == currentSource.url.toString(),
      );
      if (match >= 0) {
        _lineIndex = match;
      }
    }
  }

  /// Keeps retry/line counters when the play-URL set is unchanged.
  ///
  /// Call this on every unexpected stop before [nextStep]. Only when the
  /// playlist signature changes (or was empty) does this re-seed counters.
  bool ensureSession({
    required List<LivePlayUrl> playUrls,
    PlaybackSource? Function(LivePlayUrl line)? sourceBuilder,
    PlaybackSource? currentSource,
  }) {
    final nextSignature = signatureFor(playUrls);
    _sourceBuilder = sourceBuilder;
    if (playUrls.isEmpty) {
      clear();
      return true;
    }
    if (_sessionSignature == nextSignature && _lines.isNotEmpty) {
      // Same playlist: preserve _retryCount / _lineIndex across stops.
      return false;
    }
    reset(
      playUrls: playUrls,
      sourceBuilder: sourceBuilder,
      currentSource: currentSource,
    );
    return true;
  }

  void clear() {
    _lines = const [];
    _lineIndex = 0;
    _retryCount = 0;
    _sessionSignature = '';
    _sourceBuilder = null;
  }

  bool get canHandle => _lines.isNotEmpty;

  /// Returns the next action for an unexpected stop/error.
  ///
  /// Pass [errorMessage] so hard open failures (`Failed to open`, TCP) switch
  /// CDN immediately instead of retrying the same dead URL.
  RoomGenericLineFailoverStep? nextStep({String? errorMessage}) {
    if (_lines.isEmpty) {
      return null;
    }
    final decision = policy.decide(
      currentLineIndex: _lineIndex,
      lineCount: _lines.length,
      retryCountOnCurrentLine: _retryCount,
      preferSwitchLine: PlaybackFailoverPolicy.isHardOpenFailure(errorMessage),
    );
    switch (decision.action) {
      case PlaybackFailoverAction.retryCurrentLine:
        _retryCount = decision.nextRetryCount;
        _lineIndex = decision.nextLineIndex;
        final line = _lines[_lineIndex];
        return RoomGenericLineFailoverStep(
          action: decision.action,
          lineIndex: _lineIndex,
          retryCount: _retryCount,
          delay: decision.delay,
          line: line,
          playbackSource: _sourceBuilder?.call(line),
        );
      case PlaybackFailoverAction.switchToNextLine:
        _retryCount = 0;
        _lineIndex = decision.nextLineIndex;
        final line = _lines[_lineIndex];
        return RoomGenericLineFailoverStep(
          action: decision.action,
          lineIndex: _lineIndex,
          retryCount: _retryCount,
          delay: decision.delay,
          line: line,
          playbackSource: _sourceBuilder?.call(line),
        );
      case PlaybackFailoverAction.terminalFailure:
        return RoomGenericLineFailoverStep(
          action: decision.action,
          lineIndex: _lineIndex,
          retryCount: _retryCount,
          delay: Duration.zero,
          line: _lines[_lineIndex],
          playbackSource: null,
        );
    }
  }
}

class RoomGenericLineFailoverStep {
  const RoomGenericLineFailoverStep({
    required this.action,
    required this.lineIndex,
    required this.retryCount,
    required this.delay,
    required this.line,
    required this.playbackSource,
  });

  final PlaybackFailoverAction action;
  final int lineIndex;
  final int retryCount;
  final Duration delay;
  final LivePlayUrl line;
  final PlaybackSource? playbackSource;
}

/// Providers that already own specialized recovery and should not use generic
/// multi-line failover.
bool shouldUseGenericMultiLineFailover(ProviderId providerId) {
  return roomProviderTraitsFor(providerId).usesGenericMultiLineFailover;
}

/// Caps full play-source reloads after multi-line terminal failure.
///
/// Without a budget, hard-open zero-delay recovery can tight-loop
/// getH5Play / rebind when every CDN edge is dead.
///
/// Budget is only spent when a reload is about to run ([consume] after
/// preconditions). [refund] undoes a spend if the reload aborts after delay.
/// [notePlaying] resets only after continuous healthy playing (not a brief blip).
class RoomTerminalPlayReloadBudget {
  RoomTerminalPlayReloadBudget({
    this.maxReloads = 2,
    this.baseDelay = const Duration(seconds: 1),
    this.maxDelay = const Duration(seconds: 8),
    this.healthyPlayingBeforeReset = const Duration(seconds: 8),
  });

  final int maxReloads;
  final Duration baseDelay;
  final Duration maxDelay;

  /// Continuous [PlaybackStatus.playing] required before [reset] via [notePlaying].
  final Duration healthyPlayingBeforeReset;

  int _used = 0;
  DateTime? _healthyPlayingSince;

  int get used => _used;
  bool get canReload => _used < maxReloads;

  /// Peek delay for the next reload without spending a slot.
  Duration? peekDelay() {
    if (_used >= maxReloads) {
      return null;
    }
    final shift = _used.clamp(0, 3);
    final millis = baseDelay.inMilliseconds << shift;
    final capped = millis > maxDelay.inMilliseconds
        ? maxDelay.inMilliseconds
        : millis;
    return Duration(milliseconds: capped);
  }

  /// Spend one reload slot and return its pre-reload delay, or `null` if exhausted.
  Duration? consume() {
    final delay = peekDelay();
    if (delay == null) {
      return null;
    }
    _used += 1;
    return delay;
  }

  /// Undo the last [consume] when the reload is aborted after the wait.
  void refund() {
    if (_used > 0) {
      _used -= 1;
    }
  }

  /// Track healthy playing; only reset the budget after [healthyPlayingBeforeReset].
  ///
  /// Pass wall-clock [now] for tests. Non-playing clears the healthy window.
  void notePlaying({required bool isPlaying, DateTime? now}) {
    if (!isPlaying) {
      _healthyPlayingSince = null;
      return;
    }
    final clock = now ?? DateTime.now();
    _healthyPlayingSince ??= clock;
    if (clock.difference(_healthyPlayingSince!) >= healthyPlayingBeforeReset) {
      reset();
    }
  }

  void reset() {
    _used = 0;
    _healthyPlayingSince = null;
  }
}
