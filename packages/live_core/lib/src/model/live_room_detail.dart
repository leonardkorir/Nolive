class LiveRoomDetail {
  const LiveRoomDetail({
    required this.providerId,
    required this.roomId,
    required this.title,
    required this.streamerName,
    this.streamerAvatarUrl,
    this.coverUrl,
    this.keyframeUrl,
    this.areaName,
    this.description,
    this.sourceUrl,
    this.startedAt,
    this.isLive = true,
    this.viewerCount,
    this.danmakuToken,
    this.metadata,
  });

  final String providerId;
  final String roomId;
  final String title;
  final String streamerName;
  final String? streamerAvatarUrl;
  final String? coverUrl;
  final String? keyframeUrl;
  final String? areaName;
  final String? description;
  final String? sourceUrl;
  final DateTime? startedAt;
  final bool isLive;
  final int? viewerCount;
  final Object? danmakuToken;
  final Map<String, Object?>? metadata;
}
