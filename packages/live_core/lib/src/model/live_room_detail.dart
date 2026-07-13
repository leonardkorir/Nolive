import '../text/well_formed_string_extension.dart';
import '../provider/provider_id.dart';
import 'model_equality.dart';
import 'danmaku_token.dart';

class LiveRoomDetail {
  const LiveRoomDetail({
    required this.providerId,
    required this.roomId,
    required String title,
    required String streamerName,
    this.streamerAvatarUrl,
    this.coverUrl,
    this.keyframeUrl,
    String? areaName,
    String? description,
    this.sourceUrl,
    this.startedAt,
    this.isLive = true,
    this.viewerCount,
    this.danmakuToken,
    this.metadata,
  }) : _title = title,
       _streamerName = streamerName,
       _areaName = areaName,
       _description = description;

  final ProviderId providerId;
  final String roomId;
  final String _title;
  final String _streamerName;
  final String? streamerAvatarUrl;
  final String? coverUrl;
  final String? keyframeUrl;
  final String? _areaName;
  final String? _description;
  final String? sourceUrl;
  final DateTime? startedAt;
  final bool isLive;
  final int? viewerCount;
  final DanmakuToken? danmakuToken;
  final Map<String, Object?>? metadata;

  String get title => _title.toWellFormed();
  String get streamerName => _streamerName.toWellFormed();
  String? get areaName => _areaName?.toWellFormed();
  String? get description => _description?.toWellFormed();

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is LiveRoomDetail &&
            other.providerId == providerId &&
            other.roomId == roomId &&
            other.title == title &&
            other.streamerName == streamerName &&
            other.streamerAvatarUrl == streamerAvatarUrl &&
            other.coverUrl == coverUrl &&
            other.keyframeUrl == keyframeUrl &&
            other.areaName == areaName &&
            other.description == description &&
            other.sourceUrl == sourceUrl &&
            other.startedAt == startedAt &&
            other.isLive == isLive &&
            other.viewerCount == viewerCount &&
            modelValueEquals(other.danmakuToken, danmakuToken) &&
            modelMapEquals(other.metadata, metadata);
  }

  @override
  int get hashCode => Object.hash(
    providerId,
    roomId,
    title,
    streamerName,
    streamerAvatarUrl,
    coverUrl,
    keyframeUrl,
    areaName,
    description,
    sourceUrl,
    startedAt,
    isLive,
    viewerCount,
    modelValueHash(danmakuToken),
    modelMapHash(metadata),
  );
}
