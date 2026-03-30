import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:nolive_app/src/app/bootstrap/default_state.dart';

void main() {
  test('default danmaku rules filter urls and noisy prompt keywords', () {
    final service = DanmakuFilterService(
      config: DanmakuFilterConfig(
        blockedKeywords: kDefaultBlockedKeywords.toSet(),
      ),
    );

    final filtered = service.apply([
      const LiveMessage(
        type: LiveMessageType.chat,
        userName: 'a',
        content: '正常弹幕',
      ),
      const LiveMessage(
        type: LiveMessageType.chat,
        userName: 'b',
        content: '点击前往 https://example.com',
      ),
      const LiveMessage(
        type: LiveMessageType.chat,
        userName: 'c',
        content: 'Menu 已展开',
      ),
      const LiveMessage(
        type: LiveMessageType.chat,
        userName: 'd',
        content: 'token 已更新',
      ),
    ]);

    expect(filtered.map((item) => item.content).toList(), ['正常弹幕']);
  });
}
