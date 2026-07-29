import 'package:live_core/live_core.dart';

/// What Twitch needs to open a danmaku session.
///
/// Owned by this provider: `live_core` only knows the opaque
/// [DanmakuToken] base, so a new platform never edits the core contract.
final class TwitchDanmakuToken extends DanmakuToken {
  const TwitchDanmakuToken({required this.roomId, this.oauthToken = ''});

  final String roomId;
  final String oauthToken;

  @override
  List<Object?> get props => [roomId, oauthToken];
}
