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
  });

  final String providerId;
  final String roomId;
  final String streamerName;
  final String? streamerAvatarUrl;
  final String? lastTitle;
  final String? lastAreaName;
  final String? lastCoverUrl;
  final String? lastKeyframeUrl;
  final List<String> tags;

  FollowRecord copyWith({
    String? providerId,
    String? roomId,
    String? streamerName,
    String? streamerAvatarUrl,
    String? lastTitle,
    String? lastAreaName,
    String? lastCoverUrl,
    String? lastKeyframeUrl,
    List<String>? tags,
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
    );
  }
}
