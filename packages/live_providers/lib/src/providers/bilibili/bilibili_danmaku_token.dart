import 'package:live_core/live_core.dart';

/// What Bilibili needs to open a danmaku session.
///
/// Owned by this provider: `live_core` only knows the opaque
/// [DanmakuToken] base, so a new platform never edits the core contract.
final class BilibiliDanmakuToken extends DanmakuToken {
  const BilibiliDanmakuToken({
    required this.roomId,
    required this.uid,
    required this.token,
    required this.serverHost,
    required this.buvid,
    required this.cookie,
  });

  final int roomId;
  final int uid;
  final String token;
  final String serverHost;
  final String buvid;
  final String cookie;

  @override
  List<Object?> get props => [roomId, uid, token, serverHost, buvid, cookie];
}
