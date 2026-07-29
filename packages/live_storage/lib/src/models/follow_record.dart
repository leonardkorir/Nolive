import 'package:live_core/live_core.dart';

/// Follow identity + optional multi-device merge / snapshot fields.
///
/// New fields default so older storage JSON remains loadable.
class FollowRecord {
  const FollowRecord({
    required this.providerId,
    required this.roomId,
    required this.streamerName,
    this.streamerAvatarUrl,
    this.lastTitle,
    this.lastAreaName,
    this.lastCoverUrl,
    this.lastKeyframeUrl,
    this.tags = const [],
    this.remark,
    this.deleted = false,
    this.addedAt,
    this.updatedAt,
    this.watchDurationSec = 0,
    this.syncDurationSec = 0,
    this.lastLiveStatus,
    this.lastOnline,
  });

  final ProviderId providerId;
  final String roomId;
  final String streamerName;
  final String? streamerAvatarUrl;
  final String? lastTitle;
  final String? lastAreaName;
  final String? lastCoverUrl;
  final String? lastKeyframeUrl;
  final List<String> tags;

  /// Optional user remark / alias.
  final String? remark;

  /// Tombstone: true means unfollowed; keep until merge propagates.
  final bool deleted;

  final DateTime? addedAt;

  /// Last mutation time (follow/unfollow/metadata). Used for LWW merge.
  final DateTime? updatedAt;

  /// Cumulative watch seconds attributed to this follow (synced base).
  final int watchDurationSec;

  /// Local watch seconds not yet merged into a remote baseline.
  final int syncDurationSec;

  /// Cached live status for cold start: 0 unknown, 1 offline, 2 live.
  final int? lastLiveStatus;

  final int? lastOnline;

  String get identityKey => '${providerId.value}_$roomId';

  FollowRecord copyWith({
    ProviderId? providerId,
    String? roomId,
    String? streamerName,
    String? streamerAvatarUrl,
    String? lastTitle,
    String? lastAreaName,
    String? lastCoverUrl,
    String? lastKeyframeUrl,
    List<String>? tags,
    String? remark,
    bool? deleted,
    DateTime? addedAt,
    DateTime? updatedAt,
    int? watchDurationSec,
    int? syncDurationSec,
    int? lastLiveStatus,
    int? lastOnline,
    bool clearRemark = false,
    bool clearAddedAt = false,
    bool clearUpdatedAt = false,
    bool clearLastLiveStatus = false,
    bool clearLastOnline = false,
  }) {
    return FollowRecord(
      providerId: providerId ?? this.providerId,
      roomId: roomId ?? this.roomId,
      streamerName: streamerName ?? this.streamerName,
      streamerAvatarUrl: streamerAvatarUrl ?? this.streamerAvatarUrl,
      lastTitle: lastTitle ?? this.lastTitle,
      lastAreaName: lastAreaName ?? this.lastAreaName,
      lastCoverUrl: lastCoverUrl ?? this.lastCoverUrl,
      lastKeyframeUrl: lastKeyframeUrl ?? this.lastKeyframeUrl,
      tags: tags ?? this.tags,
      remark: clearRemark ? null : (remark ?? this.remark),
      deleted: deleted ?? this.deleted,
      addedAt: clearAddedAt ? null : (addedAt ?? this.addedAt),
      updatedAt: clearUpdatedAt ? null : (updatedAt ?? this.updatedAt),
      watchDurationSec: watchDurationSec ?? this.watchDurationSec,
      syncDurationSec: syncDurationSec ?? this.syncDurationSec,
      lastLiveStatus: clearLastLiveStatus
          ? null
          : (lastLiveStatus ?? this.lastLiveStatus),
      lastOnline: clearLastOnline ? null : (lastOnline ?? this.lastOnline),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is! FollowRecord) {
      return false;
    }
    if (other.providerId != providerId ||
        other.roomId != roomId ||
        other.streamerName != streamerName ||
        other.streamerAvatarUrl != streamerAvatarUrl ||
        other.lastTitle != lastTitle ||
        other.lastAreaName != lastAreaName ||
        other.lastCoverUrl != lastCoverUrl ||
        other.lastKeyframeUrl != lastKeyframeUrl ||
        other.remark != remark ||
        other.deleted != deleted ||
        other.addedAt != addedAt ||
        other.updatedAt != updatedAt ||
        other.watchDurationSec != watchDurationSec ||
        other.syncDurationSec != syncDurationSec ||
        other.lastLiveStatus != lastLiveStatus ||
        other.lastOnline != lastOnline ||
        other.tags.length != tags.length) {
      return false;
    }
    for (var i = 0; i < tags.length; i++) {
      if (other.tags[i] != tags[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode {
    return Object.hash(
      providerId,
      roomId,
      streamerName,
      streamerAvatarUrl,
      lastTitle,
      lastAreaName,
      lastCoverUrl,
      lastKeyframeUrl,
      Object.hashAll(tags),
      remark,
      deleted,
      addedAt,
      updatedAt,
      watchDurationSec,
      syncDurationSec,
      lastLiveStatus,
      lastOnline,
    );
  }
}
