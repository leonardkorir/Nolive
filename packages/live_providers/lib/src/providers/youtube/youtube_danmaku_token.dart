import 'package:live_core/live_core.dart';

/// What YouTube needs to open a danmaku session.
///
/// Owned by this provider: `live_core` only knows the opaque
/// [DanmakuToken] base, so a new platform never edits the core contract.
final class YouTubeDanmakuToken extends DanmakuToken {
  const YouTubeDanmakuToken({
    required this.apiKey,
    required this.clientVersion,
    required this.continuation,
    required this.liveChatPageUrl,
    required this.visitorData,
  });

  final String apiKey;
  final String clientVersion;
  final String continuation;
  final String liveChatPageUrl;
  final String visitorData;

  @override
  List<Object?> get props => [
    apiKey,
    clientVersion,
    continuation,
    liveChatPageUrl,
    visitorData,
  ];
}
