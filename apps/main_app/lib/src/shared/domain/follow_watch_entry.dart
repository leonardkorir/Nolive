import 'package:live_core/live_core.dart';
import 'package:live_storage/live_storage.dart';

class FollowWatchlist {
  const FollowWatchlist({required this.entries});

  final List<FollowWatchEntry> entries;

  int get liveCount => entries.where((item) => item.isLive).length;

  int get offlineCount => entries.where((item) => item.isOffline).length;
}

/// User-facing follow list order modes (multi-key sorts).
enum FollowWatchSortMode {
  liveFirst,
  alphabetical,
  watchDuration,
  recency,
}

List<FollowWatchEntry> sortFollowWatchEntries(
  List<FollowWatchEntry> input, {
  required FollowWatchSortMode mode,
}) {
  final entries = List<FollowWatchEntry>.from(input);
  entries.sort((left, right) {
    switch (mode) {
      case FollowWatchSortMode.liveFirst:
        final leftLive = left.isLive ? 1 : 0;
        final rightLive = right.isLive ? 1 : 0;
        final status = rightLive.compareTo(leftLive);
        if (status != 0) {
          return status;
        }
        return left.displayStreamerName.toLowerCase().compareTo(
          right.displayStreamerName.toLowerCase(),
        );
      case FollowWatchSortMode.alphabetical:
        return left.displayStreamerName.toLowerCase().compareTo(
          right.displayStreamerName.toLowerCase(),
        );
      case FollowWatchSortMode.watchDuration:
        final byDuration = right.record.watchDurationSec.compareTo(
          left.record.watchDurationSec,
        );
        if (byDuration != 0) {
          return byDuration;
        }
        return left.displayStreamerName.toLowerCase().compareTo(
          right.displayStreamerName.toLowerCase(),
        );
      case FollowWatchSortMode.recency:
        final leftTime = left.record.updatedAt ?? left.record.addedAt;
        final rightTime = right.record.updatedAt ?? right.record.addedAt;
        if (leftTime == null && rightTime == null) {
          return left.displayStreamerName.toLowerCase().compareTo(
            right.displayStreamerName.toLowerCase(),
          );
        }
        if (leftTime == null) {
          return 1;
        }
        if (rightTime == null) {
          return -1;
        }
        final byTime = rightTime.compareTo(leftTime);
        if (byTime != 0) {
          return byTime;
        }
        return left.displayStreamerName.toLowerCase().compareTo(
          right.displayStreamerName.toLowerCase(),
        );
    }
  });
  return entries;
}

class FollowWatchEntry {
  const FollowWatchEntry({
    required this.record,
    this.detail,
    this.error,
  });

  final FollowRecord record;
  final LiveRoomDetail? detail;
  final Object? error;

  bool get hasError => error != null;

  bool get isLive {
    if (detail != null) {
      return detail!.isLive;
    }
    // Cold-start snapshot from last successful refresh (2 = live).
    return record.lastLiveStatus == 2;
  }

  bool get isOffline => !hasError && !isLive;

  bool get isUnavailable => hasError && !isLive;

  String get roomId => detail?.roomId ?? record.roomId;

  String get displayStreamerName {
    final detailName = normalizeDisplayText(detail?.streamerName);
    if (detailName.isNotEmpty) {
      return detailName;
    }
    return normalizeDisplayText(record.streamerName);
  }

  String get displayAreaName {
    final detailArea = normalizeDisplayText(detail?.areaName);
    if (detailArea.isNotEmpty) {
      return detailArea;
    }
    return normalizeDisplayText(record.lastAreaName);
  }

  String? get displayStreamerAvatarUrl {
    final detailAvatar = detail?.streamerAvatarUrl?.trim() ?? '';
    if (detailAvatar.isNotEmpty) {
      return detailAvatar;
    }
    final recordAvatar = record.streamerAvatarUrl?.trim() ?? '';
    return recordAvatar.isEmpty ? null : recordAvatar;
  }

  List<String> get displayTags => record.tags
      .map(normalizeDisplayText)
      .where((item) => item.isNotEmpty)
      .toList(growable: false);

  String get title {
    final detailTitle = normalizeDisplayText(detail?.title);
    if (detailTitle.isNotEmpty) {
      return detailTitle;
    }
    final recordTitle = normalizeDisplayText(record.lastTitle);
    if (recordTitle.isNotEmpty) {
      return recordTitle;
    }
    return '$displayStreamerName 的直播间';
  }

  String? get displayCoverUrl {
    final detailCover = detail?.coverUrl?.trim() ?? '';
    if (detailCover.isNotEmpty) {
      return detailCover;
    }
    final recordCover = record.lastCoverUrl?.trim() ?? '';
    return recordCover.isEmpty ? null : recordCover;
  }

  String? get displayKeyframeUrl {
    final detailKeyframe = detail?.keyframeUrl?.trim() ?? '';
    if (detailKeyframe.isNotEmpty) {
      return detailKeyframe;
    }
    final recordKeyframe = record.lastKeyframeUrl?.trim() ?? '';
    return recordKeyframe.isEmpty ? null : recordKeyframe;
  }

  LiveRoom toLiveRoom() {
    final detail = this.detail;
    return LiveRoom(
      providerId: record.providerId,
      roomId: roomId,
      title: title,
      streamerName: displayStreamerName,
      coverUrl: displayCoverUrl,
      keyframeUrl: displayKeyframeUrl,
      areaName: displayAreaName,
      streamerAvatarUrl: displayStreamerAvatarUrl,
      viewerCount: detail?.viewerCount,
      isLive: isLive,
    );
  }
}
