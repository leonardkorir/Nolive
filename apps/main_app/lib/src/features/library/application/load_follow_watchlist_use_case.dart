import 'dart:async';

import 'package:live_core/live_core.dart';
import 'package:live_providers/live_providers.dart';
import 'package:live_storage/live_storage.dart';
import 'package:meta/meta.dart';
import 'package:nolive_app/src/features/room/application/room_detail_override_policy.dart';
import 'package:nolive_app/src/shared/domain/follow_watch_entry.dart';

/// How far remote room-detail work may go for a follow watchlist load.
///
/// App default tab is 关注: cold open must not stampede Chaturbate detail APIs.
enum FollowWatchlistRefreshScope {
  /// Local FollowRecord only — no provider network.
  localOnly,

  /// Refresh non-Chaturbate details only (safe for open / auto-refresh).
  excludeChaturbate,

  /// Full remote refresh including Chaturbate (user pull / manual refresh).
  allProviders,
}

class LoadFollowWatchlistUseCase {
  const LoadFollowWatchlistUseCase({
    required this.followRepository,
    required this.registry,
    this.detailTimeout = const Duration(seconds: 8),
    this.maxConcurrent = 6,
    /// Cap concurrent Chaturbate detail fetches (only when scope includes CB).
    this.maxConcurrentChaturbate = 1,
    /// Hard cap per refresh — crawl CB slowly across cycles, never stampede.
    this.maxChaturbatePerRefresh = 8,
    /// Extra gap between CB follow detail calls (in addition to scheduler).
    /// Goal: stay under CF limits so we rarely see 429 at all.
    this.chaturbateSpacing = const Duration(seconds: 2),
    this.roomDetailOverride,
  });

  final FollowRepository followRepository;
  final ProviderRegistry registry;
  final Duration detailTimeout;
  final int maxConcurrent;
  final int maxConcurrentChaturbate;
  final int maxChaturbatePerRefresh;
  final Duration chaturbateSpacing;
  final Future<LiveRoomDetail?> Function({
    required ProviderId providerId,
    required String roomId,
  })?
  roomDetailOverride;

  Future<FollowWatchlist> call({
    FollowWatchlistRefreshScope scope = FollowWatchlistRefreshScope.allProviders,
    void Function(int index, FollowWatchEntry entry)? onEntryResolved,
    /// Fires after non-Chaturbate remote work finishes (before CB phase).
    /// Lets the follow tab drop the spinner without waiting on CF-paced CB.
    void Function()? onNonChaturbateComplete,
    /// Cycle for *background* large-list sweeps and CB crawl
    /// rotation. CB is always batched — [fullRefresh] only affects non-CB.
    int refreshCycle = 0,
    int largeListThreshold = 100,
    /// Non-CB: refresh every row when true. CB is always rate-limited batches.
    bool fullRefresh = true,
  }) async {
    final follows = await followRepository.listAll();
    if (follows.isEmpty) {
      onNonChaturbateComplete?.call();
      return const FollowWatchlist(entries: <FollowWatchEntry>[]);
    }

    if (scope == FollowWatchlistRefreshScope.localOnly) {
      final localEntries = <FollowWatchEntry>[
        for (var index = 0; index < follows.length; index += 1)
          FollowWatchEntry(record: follows[index]),
      ];
      for (var index = 0; index < localEntries.length; index += 1) {
        onEntryResolved?.call(index, localEntries[index]);
      }
      onNonChaturbateComplete?.call();
      return FollowWatchlist(entries: localEntries);
    }

    final entries = List<FollowWatchEntry?>.filled(follows.length, null);
    final updatedRecords = List<FollowRecord?>.filled(follows.length, null);

    // Always surface local rows first so UI is not blocked on network.
    // Uses lastLiveStatus snapshot when present for cold-start live chips.
    for (var index = 0; index < follows.length; index += 1) {
      final localEntry = FollowWatchEntry(record: follows[index]);
      entries[index] = localEntry;
      onEntryResolved?.call(index, localEntry);
    }

    final refreshChaturbate =
        scope == FollowWatchlistRefreshScope.allProviders;
    final nonChaturbateIndexes = <int>[];
    final chaturbateIndexes = <int>[];
    for (var index = 0; index < follows.length; index += 1) {
      if (follows[index].providerId == ProviderId.chaturbate) {
        if (refreshChaturbate) {
          chaturbateIndexes.add(index);
        }
      } else {
        nonChaturbateIndexes.add(index);
      }
    }

    final prioritisedNonCb = fullRefresh
        ? List<int>.from(nonChaturbateIndexes)
        : prioritiseFollowRefreshIndexes(
            follows: follows,
            candidateIndexes: nonChaturbateIndexes,
            cycle: refreshCycle,
            largeListThreshold: largeListThreshold,
          );
    // CB is never full-blasted. Prefer live/recent rows, then take a small
    // rotating batch so each refresh only "fills in" a few chips slowly.
    final rankedCb = prioritiseFollowRefreshIndexes(
      follows: follows,
      candidateIndexes: chaturbateIndexes,
      cycle: refreshCycle,
      // Always rank CB even for short lists so rotation still applies.
      largeListThreshold: 0,
    );
    final prioritisedCb = takeRotatingFollowBatch(
      rankedCb,
      cycle: refreshCycle,
      maxTake: maxChaturbatePerRefresh,
    );

    Future<void> runPhase(
      List<int> indexes, {
      required int concurrency,
      Duration spacing = Duration.zero,
      bool stopOnRateLimit = false,
    }) async {
      if (indexes.isEmpty) {
        return;
      }
      final base = concurrency < 1 ? 1 : concurrency;
      final workerCount = indexes.length < base ? indexes.length : base;
      var nextSlot = 0;
      var rateLimited = false;

      Future<void> worker() async {
        while (true) {
          if (rateLimited && stopOnRateLimit) {
            return;
          }
          final slot = nextSlot;
          if (slot >= indexes.length) {
            return;
          }
          nextSlot += 1;
          if (spacing > Duration.zero && slot > 0) {
            await Future<void>.delayed(spacing);
          }
          if (rateLimited && stopOnRateLimit) {
            return;
          }
          final index = indexes[slot];
          final record = follows[index];
          final result = await _inspectFollow(record);
          entries[index] = result.entry;
          updatedRecords[index] = result.updatedRecord;
          onEntryResolved?.call(index, result.entry);
          if (stopOnRateLimit &&
              isChaturbateFollowRateLimitError(result.entry.error)) {
            // Abort the rest of this CB crawl — keep lastLiveStatus for others.
            // Next auto/pull cycle continues the rotating batch after cooldown.
            rateLimited = true;
            return;
          }
        }
      }

      await Future.wait(
        List.generate(workerCount, (_) => worker()),
        eagerError: false,
      );
    }

    // Phase 1: domestic / non-CB at full concurrency — must not wait on CB.
    await runPhase(prioritisedNonCb, concurrency: maxConcurrent);
    onNonChaturbateComplete?.call();

    // Phase 2: Chaturbate crawl only — serial, spaced, small batch, stop on 429.
    // Intentionally slow: live chips fill in over successive refreshes.
    if (refreshChaturbate) {
      await ChaturbateRequestScheduler.runAsFollowBudget(
        () => runPhase(
          prioritisedCb,
          concurrency: maxConcurrentChaturbate,
          spacing: chaturbateSpacing,
          stopOnRateLimit: true,
        ),
      );
    }

    final changedRecords = updatedRecords.whereType<FollowRecord>().toList(
      growable: false,
    );
    if (changedRecords.isNotEmpty) {
      await followRepository.upsertAll(changedRecords);
    }
    return FollowWatchlist(
      entries: entries.whereType<FollowWatchEntry>().toList(growable: false),
    );
  }

  Future<_ResolvedFollowEntry> _inspectFollow(FollowRecord record) async {
    try {
      final provider = registry.create(record.providerId);
      final detailFuture = () async {
        Object? providerError;
        StackTrace? providerStackTrace;
        try {
          return await provider
              .requireContract<SupportsRoomDetail>(
                ProviderCapability.roomDetail,
              )
              .fetchRoomDetail(record.roomId);
        } catch (error, stackTrace) {
          providerError = error;
          providerStackTrace = stackTrace;
        }

        if (shouldAllowRoomDetailOverride(provider.descriptor.id)) {
          final overridden = await roomDetailOverride?.call(
            providerId: provider.descriptor.id,
            roomId: record.roomId,
          );
          if (overridden != null) {
            return overridden;
          }
        }
        Error.throwWithStackTrace(providerError, providerStackTrace);
      }();
      final detail = await detailFuture.timeout(detailTimeout);
      final syncedRecord = _buildSyncedRecord(record, detail);
      return _ResolvedFollowEntry(
        entry: FollowWatchEntry(record: syncedRecord ?? record, detail: detail),
        updatedRecord: syncedRecord,
      );
    } catch (error) {
      return _ResolvedFollowEntry(
        entry: FollowWatchEntry(record: record, error: error),
      );
    }
  }

  FollowRecord? _buildSyncedRecord(FollowRecord record, LiveRoomDetail detail) {
    final normalizedName = normalizeDisplayText(detail.streamerName);
    final normalizedAvatarUrl = detail.streamerAvatarUrl?.trim() ?? '';
    final normalizedTitle = normalizeDisplayText(detail.title);
    final normalizedAreaName = normalizeDisplayText(detail.areaName);
    final normalizedCoverUrl = detail.coverUrl?.trim() ?? '';
    final normalizedKeyframeUrl = detail.keyframeUrl?.trim() ?? '';
    final liveStatus = detail.isLive ? 2 : 1;
    final nextRecord = record.copyWith(
      streamerName: normalizedName.isEmpty
          ? record.streamerName
          : normalizedName,
      streamerAvatarUrl: normalizedAvatarUrl.isEmpty
          ? record.streamerAvatarUrl
          : normalizedAvatarUrl,
      lastTitle: normalizedTitle.isEmpty ? record.lastTitle : normalizedTitle,
      lastAreaName: normalizedAreaName.isEmpty
          ? record.lastAreaName
          : normalizedAreaName,
      lastCoverUrl: normalizedCoverUrl.isEmpty
          ? record.lastCoverUrl
          : normalizedCoverUrl,
      lastKeyframeUrl: normalizedKeyframeUrl.isEmpty
          ? record.lastKeyframeUrl
          : normalizedKeyframeUrl,
      lastLiveStatus: liveStatus,
      lastOnline: detail.viewerCount,
      updatedAt: DateTime.now(),
    );
    if (nextRecord.streamerName == record.streamerName &&
        nextRecord.streamerAvatarUrl == record.streamerAvatarUrl &&
        nextRecord.lastTitle == record.lastTitle &&
        nextRecord.lastAreaName == record.lastAreaName &&
        nextRecord.lastCoverUrl == record.lastCoverUrl &&
        nextRecord.lastKeyframeUrl == record.lastKeyframeUrl &&
        nextRecord.lastLiveStatus == record.lastLiveStatus &&
        nextRecord.lastOnline == record.lastOnline) {
      return null;
    }
    return nextRecord;
  }
}

/// Pure prioritisation helper for large follow lists (multi-round).
List<int> prioritiseFollowRefreshIndexes({
  required List<FollowRecord> follows,
  required List<int> candidateIndexes,
  required int cycle,
  int largeListThreshold = 100,
}) {
  if (candidateIndexes.isEmpty) {
    return const <int>[];
  }
  // largeListThreshold <= 0: always rank, return full ranked list (no cut).
  if (largeListThreshold > 0 &&
      (follows.length <= largeListThreshold || candidateIndexes.length <= 20)) {
    return List<int>.from(candidateIndexes);
  }

  final ranked = List<int>.from(candidateIndexes)
    ..sort((left, right) {
      final a = follows[left];
      final b = follows[right];
      final scoreA = _followPriorityScore(a);
      final scoreB = _followPriorityScore(b);
      return scoreB.compareTo(scoreA);
    });

  if (largeListThreshold <= 0) {
    return ranked;
  }

  final topN = (ranked.length * 0.2).round().clamp(1, ranked.length);
  final bottomN = (ranked.length * 0.2).round().clamp(0, ranked.length - topN);
  final middleEnd = ranked.length - bottomN;
  final top = ranked.sublist(0, topN);
  if (cycle % 2 == 0) {
    return top;
  }
  return ranked.sublist(0, middleEnd);
}

/// Take up to [maxTake] indexes, rotating start by [cycle] so successive
/// refreshes crawl the whole list without one-shot storms.
@visibleForTesting
List<int> takeRotatingFollowBatch(
  List<int> rankedIndexes, {
  required int cycle,
  required int maxTake,
}) {
  if (rankedIndexes.isEmpty || maxTake <= 0) {
    return const <int>[];
  }
  if (rankedIndexes.length <= maxTake) {
    return List<int>.from(rankedIndexes);
  }
  final start = (cycle * maxTake) % rankedIndexes.length;
  final out = <int>[];
  for (var i = 0; i < maxTake; i += 1) {
    out.add(rankedIndexes[(start + i) % rankedIndexes.length]);
  }
  return out;
}

/// True when a follow-detail error looks like Chaturbate/CF rate limiting.
@visibleForTesting
bool isChaturbateFollowRateLimitError(Object? error) {
  if (error == null) {
    return false;
  }
  final text = error.toString().toLowerCase();
  return text.contains('429') ||
      text.contains('rate limit') ||
      text.contains('too many requests');
}

double _followPriorityScore(FollowRecord record) {
  final liveBoost = record.lastLiveStatus == 2 ? 1.0 : 0.3;
  final durationScore = record.watchDurationSec.toDouble();
  final recency = record.updatedAt?.millisecondsSinceEpoch.toDouble() ?? 0;
  return (durationScore + recency / 1e10) * liveBoost;
}

class _ResolvedFollowEntry {
  const _ResolvedFollowEntry({required this.entry, this.updatedRecord});

  final FollowWatchEntry entry;
  final FollowRecord? updatedRecord;
}

class _AsyncSemaphore {
  _AsyncSemaphore(int permits) : _available = permits < 1 ? 1 : permits;

  int _available;
  final List<void Function()> _waiters = <void Function()>[];

  Future<T> withPermit<T>(Future<T> Function() action) async {
    await _acquire();
    try {
      return await action();
    } finally {
      _release();
    }
  }

  Future<void> _acquire() {
    if (_available > 0) {
      _available -= 1;
      return Future<void>.value();
    }
    final completer = Completer<void>();
    _waiters.add(completer.complete);
    return completer.future;
  }

  void _release() {
    if (_waiters.isNotEmpty) {
      final next = _waiters.removeAt(0);
      next();
      return;
    }
    _available += 1;
  }
}
