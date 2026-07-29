import 'package:live_core/live_core.dart';

/// What Douyu needs to open a danmaku session.
///
/// Owned by this provider: `live_core` only knows the opaque
/// [DanmakuToken] base, so a new platform never edits the core contract.
final class DouyuDanmakuToken extends DanmakuToken {
  const DouyuDanmakuToken({required this.roomId, this.socketUrls = const []});

  final String roomId;
  final List<String> socketUrls;

  @override
  List<Object?> get props => [roomId, socketUrls];
}
