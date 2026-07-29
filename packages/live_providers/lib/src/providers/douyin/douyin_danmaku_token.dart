import 'package:live_core/live_core.dart';

/// What Douyin needs to open a danmaku session.
///
/// Owned by this provider: `live_core` only knows the opaque
/// [DanmakuToken] base, so a new platform never edits the core contract.
final class DouyinDanmakuToken extends DanmakuToken {
  const DouyinDanmakuToken({
    required this.webRid,
    required this.roomId,
    required this.cookie,
    required this.userUniqueId,
    this.websocketUris = const [],
  });

  final String webRid;
  final String roomId;
  final String cookie;
  final String userUniqueId;
  final List<Uri> websocketUris;

  @override
  List<Object?> get props => [
    webRid,
    roomId,
    cookie,
    userUniqueId,
    websocketUris,
  ];
}
