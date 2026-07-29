import 'package:live_core/live_core.dart';

/// What Huya needs to open a danmaku session.
///
/// Owned by this provider: `live_core` only knows the opaque
/// [DanmakuToken] base, so a new platform never edits the core contract.
final class HuyaDanmakuToken extends DanmakuToken {
  const HuyaDanmakuToken({
    required this.ayyuid,
    required this.topSid,
    required this.subSid,
  });

  final int ayyuid;
  final int topSid;
  final int subSid;

  @override
  List<Object?> get props => [ayyuid, topSid, subSid];
}
