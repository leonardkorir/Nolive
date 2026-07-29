import 'package:live_core/live_core.dart';

/// What Chaturbate needs to open a danmaku session.
///
/// Owned by this provider: `live_core` only knows the opaque
/// [DanmakuToken] base, so a new platform never edits the core contract.
final class ChaturbateDanmakuToken extends DanmakuToken {
  const ChaturbateDanmakuToken({
    required this.roomId,
    required this.roomUid,
    required this.broadcasterUid,
    required this.csrfToken,
    required this.backend,
    this.host,
    this.restHost,
    this.fallbackHosts = const [],
  });

  final String roomId;
  final String roomUid;
  final String broadcasterUid;
  final String csrfToken;
  final String backend;
  final String? host;
  final String? restHost;
  final List<String> fallbackHosts;

  @override
  List<Object?> get props => [
    roomId,
    roomUid,
    broadcasterUid,
    csrfToken,
    backend,
    host,
    restHost,
    fallbackHosts,
  ];
}
