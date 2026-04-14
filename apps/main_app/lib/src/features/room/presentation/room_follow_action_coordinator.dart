import 'package:live_core/live_core.dart';
import 'package:live_storage/live_storage.dart';
import 'package:nolive_app/src/features/library/application/load_follow_watchlist_use_case.dart';
import 'package:nolive_app/src/features/room/application/load_room_use_case.dart';
import 'package:nolive_app/src/features/room/application/room_preview_dependencies.dart';
import 'package:nolive_app/src/features/room/presentation/room_preview_page_follow.dart';

typedef RoomConfirmUnfollow = Future<bool?> Function(String displayName);
typedef RoomCommitFollowRoomNavigation = Future<void> Function(
  FollowWatchEntry entry,
);
typedef RoomReplaceFollowWatchlistSnapshot = void Function(
  FollowWatchlist? watchlist, {
  required bool hydrated,
});

class RoomFollowActionContext {
  const RoomFollowActionContext({
    required this.currentProviderId,
    required this.currentRoomId,
    required this.showMessage,
    required this.isMounted,
    required this.confirmUnfollow,
    required this.applyCurrentFollowed,
    required this.replaceWatchlistSnapshot,
    required this.ensureFollowWatchlistLoaded,
    required this.commitFollowRoomNavigation,
  });

  final ProviderId currentProviderId;
  final String currentRoomId;
  final void Function(String message) showMessage;
  final bool Function() isMounted;
  final RoomConfirmUnfollow confirmUnfollow;
  final void Function(bool followed) applyCurrentFollowed;
  final RoomReplaceFollowWatchlistSnapshot replaceWatchlistSnapshot;
  final Future<void> Function({bool force}) ensureFollowWatchlistLoaded;
  final RoomCommitFollowRoomNavigation commitFollowRoomNavigation;
}

class RoomFollowActionCoordinator {
  RoomFollowActionCoordinator({
    required this.dependencies,
    required this.context,
  });

  final RoomFollowActionDependencies dependencies;
  final RoomFollowActionContext context;

  Future<void> toggleCurrentRoomFollow({
    required LoadedRoomSnapshot snapshot,
    required bool currentlyFollowed,
    required bool followPanelSelected,
  }) async {
    final currentWatchlist = dependencies.followWatchlistSnapshot.value;
    var shouldReloadWatchlist = false;
    if (currentlyFollowed) {
      final confirmed = await context.confirmUnfollow(
        displayFollowTarget(snapshot.detail),
      );
      if (confirmed != true || !context.isMounted()) {
        return;
      }
    }

    final followed = await dependencies.toggleFollowRoom(
      providerId: snapshot.providerId.value,
      roomId: snapshot.detail.roomId,
      streamerName: snapshot.detail.streamerName,
      streamerAvatarUrl: snapshot.detail.streamerAvatarUrl,
      title: snapshot.detail.title,
      areaName: snapshot.detail.areaName,
      coverUrl: snapshot.detail.coverUrl,
      keyframeUrl: snapshot.detail.keyframeUrl,
    );
    if (!context.isMounted()) {
      return;
    }

    FollowWatchlist? nextWatchlist;
    if (followed) {
      if (currentWatchlist != null) {
        final record = await _findFollowRecord(
          providerId: snapshot.providerId.value,
          roomId: snapshot.detail.roomId,
        );
        if (!context.isMounted()) {
          return;
        }
        if (record != null) {
          final currentEntry = FollowWatchEntry(
            record: record,
            detail: snapshot.detail,
          );
          nextWatchlist = FollowWatchlist(
            entries: [
              currentEntry,
              ...currentWatchlist.entries.where(
                (entry) =>
                    entry.record.providerId != snapshot.providerId.value ||
                    entry.record.roomId != snapshot.detail.roomId,
              ),
            ],
          );
        } else {
          nextWatchlist = currentWatchlist;
          shouldReloadWatchlist = true;
        }
      }
    } else if (currentWatchlist != null) {
      nextWatchlist = FollowWatchlist(
        entries: currentWatchlist.entries
            .where(
              (entry) =>
                  entry.record.providerId != snapshot.providerId.value ||
                  entry.record.roomId != snapshot.detail.roomId,
            )
            .toList(growable: false),
      );
    }

    context.applyCurrentFollowed(followed);
    if (!identical(nextWatchlist, currentWatchlist)) {
      context.replaceWatchlistSnapshot(
        nextWatchlist,
        hydrated: nextWatchlist != null,
      );
    }
    if (shouldReloadWatchlist ||
        (followPanelSelected && nextWatchlist == null)) {
      await context.ensureFollowWatchlistLoaded(force: true);
    }
  }

  Future<void> openFollowRoom(FollowWatchEntry entry) async {
    if (entry.record.providerId == context.currentProviderId.value &&
        entry.roomId == context.currentRoomId) {
      context.showMessage('当前已经在这个直播间里了');
      return;
    }
    await context.commitFollowRoomNavigation(entry);
  }

  List<RoomFollowEntryViewData> buildEntryViewData(
    FollowWatchlist watchlist,
  ) {
    return resolveLiveFollowEntries(
      watchlist,
      currentProviderId: context.currentProviderId,
      currentRoomId: context.currentRoomId,
    ).map((entry) {
      final descriptor =
          dependencies.findProviderDescriptorById(entry.record.providerId) ??
              ProviderDescriptor(
                id: ProviderId(entry.record.providerId),
                displayName: entry.record.providerId,
                capabilities: const {},
                supportedPlatforms: const {ProviderPlatform.android},
                maturity: ProviderMaturity.inMigration,
              );
      return RoomFollowEntryViewData(
        entry: entry,
        providerDescriptor: descriptor,
        isPlaying: entry.record.providerId == context.currentProviderId.value &&
            entry.roomId == context.currentRoomId,
      );
    }).toList(growable: false);
  }

  Future<FollowRecord?> _findFollowRecord({
    required String providerId,
    required String roomId,
  }) async {
    final records = await dependencies.listFollowRecords();
    for (final record in records) {
      if (record.providerId == providerId && record.roomId == roomId) {
        return record;
      }
    }
    return null;
  }
}

List<FollowWatchEntry> resolveLiveFollowEntries(
  FollowWatchlist watchlist, {
  required ProviderId currentProviderId,
  required String currentRoomId,
}) {
  return watchlist.entries
      .where((entry) => entry.isLive)
      .toList(growable: false)
    ..sort((left, right) {
      final leftCurrent = left.record.providerId == currentProviderId.value &&
          left.roomId == currentRoomId;
      final rightCurrent = right.record.providerId == currentProviderId.value &&
          right.roomId == currentRoomId;
      if (leftCurrent != rightCurrent) {
        return leftCurrent ? -1 : 1;
      }
      final liveCompare = (right.isLive ? 1 : 0).compareTo(left.isLive ? 1 : 0);
      if (liveCompare != 0) {
        return liveCompare;
      }
      return left.displayStreamerName.compareTo(right.displayStreamerName);
    });
}

String displayFollowTarget(LiveRoomDetail detail) {
  final streamerName = detail.streamerName.trim();
  if (streamerName.isNotEmpty) {
    return streamerName;
  }
  final title = detail.title.trim();
  if (title.isNotEmpty) {
    return title;
  }
  return detail.roomId;
}
