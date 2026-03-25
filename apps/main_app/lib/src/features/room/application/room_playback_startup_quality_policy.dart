import 'package:flutter/foundation.dart';
import 'package:live_core/live_core.dart';

LivePlayQuality resolveRoomStartupRequestedQuality({
  required ProviderId providerId,
  required List<LivePlayQuality> qualities,
  required LivePlayQuality requestedQuality,
  required TargetPlatform targetPlatform,
  required bool explicitSelection,
  bool isWeb = kIsWeb,
}) {
  if (explicitSelection ||
      isWeb ||
      targetPlatform != TargetPlatform.android ||
      providerId != ProviderId.youtube ||
      requestedQuality.id != 'auto') {
    return requestedQuality;
  }
  final autoQuality = qualities.cast<LivePlayQuality?>().firstWhere(
        (item) => item?.id == 'auto',
        orElse: () => null,
      );
  return autoQuality ?? requestedQuality;
}
