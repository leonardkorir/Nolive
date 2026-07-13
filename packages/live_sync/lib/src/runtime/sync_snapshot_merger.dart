import 'dart:collection';

import 'package:live_storage/live_storage.dart';

import '../model/sync_snapshot.dart';

/// Pure merge helpers for WebDAV bidirectional sync.
class SyncSnapshotMerger {
  const SyncSnapshotMerger();

  SyncSnapshot mergeSnapshots({
    required SyncSnapshot local,
    required SyncSnapshot remote,
    DateTime? lastSyncAt,
  }) {
    final mergedFollows = mergeFollows(
      local: local.follows,
      remote: remote.follows,
      lastSyncAt: lastSyncAt,
    );
    final mergedHistory = mergeHistories(
      local: local.history,
      remote: remote.history,
    );
    final mergedTags = LinkedHashSet<String>.from([
      ...local.tags,
      ...remote.tags,
    ]).toList(growable: false)
      ..sort();
    final mergedKeywords = LinkedHashSet<String>.from([
      ...local.blockedKeywords,
      ...remote.blockedKeywords,
    ]).toList(growable: false)
      ..sort();
    final mergedSettings = <String, Object?>{
      ...local.settings,
      ...remote.settings,
    };
    return SyncSnapshot(
      settings: mergedSettings,
      history: mergedHistory,
      follows: mergedFollows,
      tags: mergedTags,
      blockedKeywords: mergedKeywords,
    );
  }

  List<FollowRecord> mergeFollows({
    required List<FollowRecord> local,
    required List<FollowRecord> remote,
    DateTime? lastSyncAt,
  }) {
    final curLast = lastSyncAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final localMap = {for (final item in local) item.identityKey: item};
    final remoteMap = {for (final item in remote) item.identityKey: item};
    final result = <String, FollowRecord>{};

    for (final localItem in local) {
      final remoteItem = remoteMap[localItem.identityKey];
      if (remoteItem != null) {
        result[localItem.identityKey] = _mergeFollowPair(localItem, remoteItem);
        continue;
      }
      if (localItem.deleted) {
        final stamp = localItem.updatedAt ?? localItem.addedAt;
        if (stamp != null && stamp.isAfter(curLast)) {
          result[localItem.identityKey] = localItem;
        }
      } else {
        final stamp = localItem.addedAt ?? localItem.updatedAt;
        if (stamp == null || stamp.isAfter(curLast)) {
          result[localItem.identityKey] = localItem;
        }
      }
    }

    for (final remoteItem in remote) {
      if (localMap.containsKey(remoteItem.identityKey)) {
        continue;
      }
      if (remoteItem.deleted) {
        final stamp = remoteItem.updatedAt ?? remoteItem.addedAt;
        if (stamp != null && stamp.isAfter(curLast)) {
          result[remoteItem.identityKey] = remoteItem;
        }
      } else {
        final stamp = remoteItem.addedAt ?? remoteItem.updatedAt;
        if (stamp == null || stamp.isAfter(curLast)) {
          result[remoteItem.identityKey] = remoteItem;
        }
      }
    }

    final list = result.values.toList(growable: false);
    list.sort((a, b) => a.identityKey.compareTo(b.identityKey));
    return list;
  }

  FollowRecord _mergeFollowPair(FollowRecord local, FollowRecord remote) {
    if (local.deleted && remote.deleted) {
      return _laterFollow(local, remote);
    }
    if (local.deleted && !remote.deleted) {
      final tombstone = local.updatedAt ?? local.addedAt;
      final remoteAdd = remote.addedAt ?? remote.updatedAt;
      if (tombstone != null &&
          remoteAdd != null &&
          !tombstone.isBefore(remoteAdd)) {
        return local;
      }
      return remote.copyWith(deleted: false, syncDurationSec: 0);
    }
    if (remote.deleted && !local.deleted) {
      final tombstone = remote.updatedAt ?? remote.addedAt;
      final localAdd = local.addedAt ?? local.updatedAt;
      if (tombstone != null &&
          localAdd != null &&
          !tombstone.isBefore(localAdd)) {
        return remote;
      }
      return local;
    }

    // Both active: keep local metadata shell, merge duration from remote base +
    // local unsent increment.
    // Remote holds the last synced baseline; local.syncDurationSec is unsent.
    final totalSeconds = remote.watchDurationSec + local.syncDurationSec;
    // Prefer newer non-duration fields.
    final preferred = _laterFollow(local, remote);
    return preferred.copyWith(
      watchDurationSec: totalSeconds,
      syncDurationSec: 0,
      deleted: false,
    );
  }

  FollowRecord _laterFollow(FollowRecord a, FollowRecord b) {
    final aTime = a.updatedAt ?? a.addedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final bTime = b.updatedAt ?? b.addedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    return aTime.isAfter(bTime) ? a : b;
  }

  List<HistoryRecord> mergeHistories({
    required List<HistoryRecord> local,
    required List<HistoryRecord> remote,
  }) {
    final map = {for (final item in local) item.identityKey: item};

    for (final remoteItem in remote) {
      final localItem = map[remoteItem.identityKey];
      if (localItem == null) {
        map[remoteItem.identityKey] = remoteItem;
        continue;
      }

      if (remoteItem.watchDurationSec == localItem.watchDurationSec &&
          localItem.syncDurationSec == 0) {
        map[remoteItem.identityKey] =
            remoteItem.effectiveUpdatedAt.isAfter(localItem.effectiveUpdatedAt)
                ? remoteItem
                : localItem;
        continue;
      }

      final totalSeconds =
          remoteItem.watchDurationSec + localItem.syncDurationSec;
      final preferred =
          remoteItem.effectiveUpdatedAt.isAfter(localItem.effectiveUpdatedAt)
              ? remoteItem
              : localItem;
      map[remoteItem.identityKey] = preferred.copyWith(
        watchDurationSec: totalSeconds,
        syncDurationSec: 0,
        viewedAt: preferred.viewedAt.isAfter(localItem.viewedAt)
            ? preferred.viewedAt
            : localItem.viewedAt,
        updatedAt: preferred.effectiveUpdatedAt,
      );
    }

    final list = map.values.toList(growable: false);
    list.sort((a, b) => b.effectiveUpdatedAt.compareTo(a.effectiveUpdatedAt));
    return list;
  }
}
