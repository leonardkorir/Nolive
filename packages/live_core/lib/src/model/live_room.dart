import '../text/well_formed_string_extension.dart';
import '../provider/provider_id.dart';

class LiveRoom {
  const LiveRoom({
    required this.providerId,
    required this.roomId,
    required String title,
    required String streamerName,
    this.coverUrl,
    this.keyframeUrl,
    String? areaName,
    this.streamerAvatarUrl,
    this.viewerCount,
    this.isLive = true,
  }) : _title = title,
       _streamerName = streamerName,
       _areaName = areaName;

  final ProviderId providerId;
  final String roomId;
  final String _title;
  final String _streamerName;
  final String? coverUrl;
  final String? keyframeUrl;
  final String? _areaName;
  final String? streamerAvatarUrl;
  final int? viewerCount;
  final bool isLive;

  String get title => _title.toWellFormed();
  String get streamerName => _streamerName.toWellFormed();
  String? get areaName => _areaName?.toWellFormed();

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is LiveRoom &&
            other.providerId == providerId &&
            other.roomId == roomId &&
            other.title == title &&
            other.streamerName == streamerName &&
            other.coverUrl == coverUrl &&
            other.keyframeUrl == keyframeUrl &&
            other.areaName == areaName &&
            other.streamerAvatarUrl == streamerAvatarUrl &&
            other.viewerCount == viewerCount &&
            other.isLive == isLive;
  }

  @override
  int get hashCode => Object.hash(
    providerId,
    roomId,
    title,
    streamerName,
    coverUrl,
    keyframeUrl,
    areaName,
    streamerAvatarUrl,
    viewerCount,
    isLive,
  );
}
