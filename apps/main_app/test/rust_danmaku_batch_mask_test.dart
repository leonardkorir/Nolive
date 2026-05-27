import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:nolive_app/src/rust/danmaku_batch_mask.dart';

void main() {
  test(
    'native danmaku batch mask falls back and preserves filtering semantics',
    () {
      final resolution = resolveAppDanmakuBatchMask(preferNative: true);

      final filtered = resolution.mask.allowListBatch(const [
        LiveMessage(type: LiveMessageType.chat, content: '刷屏'),
        LiveMessage(type: LiveMessageType.chat, content: '刷屏'),
        LiveMessage(type: LiveMessageType.chat, content: '刷屏'),
      ], now: DateTime(2026, 3, 30, 1));

      expect(filtered.map((item) => item.content), ['刷屏', '刷屏']);
      if (!Platform.isAndroid) {
        expect(resolution.usingNative, isFalse);
      }
    },
  );
}
