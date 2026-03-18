class LiveRoom {
  const LiveRoom({
    required this.providerId,
    required this.roomId,
    required this.title,
    required this.streamerName,
    this.coverUrl,
    this.keyframeUrl,
    this.areaName,
    this.streamerAvatarUrl,
    this.viewerCount,
    this.isLive = true,
  });

  final String providerId;
  final String roomId;
  final String title;
  final String streamerName;
  final String? coverUrl;
  final String? keyframeUrl;
  final String? areaName;
  final String? streamerAvatarUrl;
  final int? viewerCount;
  final bool isLive;
}
