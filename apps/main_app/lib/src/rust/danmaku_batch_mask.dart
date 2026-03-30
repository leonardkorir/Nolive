import 'package:live_danmaku/live_danmaku.dart';

import 'danmaku_batch_mask_stub.dart'
    if (dart.library.ffi) 'danmaku_batch_mask_ffi.dart' as native;

class DanmakuBatchMaskResolution {
  const DanmakuBatchMaskResolution({
    required this.mask,
    required this.usingNative,
  });

  final DanmakuBatchMask mask;
  final bool usingNative;
}

DanmakuBatchMaskResolution resolveAppDanmakuBatchMask({
  required bool preferNative,
  Duration window = const Duration(seconds: 8),
  int burstLimit = 2,
}) {
  if (preferNative) {
    final nativeMask = native.tryCreateRustDanmakuBatchMask(
      window: window,
      burstLimit: burstLimit,
    );
    if (nativeMask != null) {
      return DanmakuBatchMaskResolution(
        mask: nativeMask,
        usingNative: true,
      );
    }
  }
  return DanmakuBatchMaskResolution(
    mask: WindowedDanmakuBatchMask(
      window: window,
      burstLimit: burstLimit,
    ),
    usingNative: false,
  );
}
