import 'package:live_core/live_core.dart';

/// What Stripchat needs to open a danmaku session.
///
/// Owned by this provider: `live_core` only knows the opaque
/// [DanmakuToken] base, so a new platform never edits the core contract.
final class StripchatDanmakuToken extends DanmakuToken {
  const StripchatDanmakuToken({
    required this.modelId,
    required this.websocketUrl,
    required this.jwt,
    this.historyUrl = '',
    this.requestCookie = '',
    this.roomUrl = '',
  });

  final String modelId;
  final String websocketUrl;
  final String jwt;
  final String historyUrl;
  final String requestCookie;
  final String roomUrl;

  @override
  List<Object?> get props => [
    modelId,
    websocketUrl,
    jwt,
    historyUrl,
    requestCookie,
    roomUrl,
  ];
}
