import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:test/test.dart';

void main() {
  test('DanmakuFilterService blocks configured keywords case-insensitively',
      () {
    final service = DanmakuFilterService(
      config: DanmakuFilterConfig(blockedKeywords: {'spam'}),
    );

    const messages = [
      LiveMessage(type: LiveMessageType.chat, content: 'hello world'),
      LiveMessage(type: LiveMessageType.chat, content: 'This is SPAM content'),
    ];

    final filtered = service.apply(messages);

    expect(filtered, hasLength(1));
    expect(filtered.first.content, 'hello world');
  });

  test('DanmakuFilterService supports regex rules with re: prefix', () {
    final service = DanmakuFilterService(
      config: DanmakuFilterConfig(blockedKeywords: {'re:^抽奖.*\$'}),
    );

    const messages = [
      LiveMessage(type: LiveMessageType.chat, content: '正常聊天'),
      LiveMessage(type: LiveMessageType.chat, content: '抽奖开始啦'),
    ];

    final filtered = service.apply(messages);

    expect(filtered, hasLength(1));
    expect(filtered.single.content, '正常聊天');
  });

  test('WindowedDanmakuBatchMask suppresses burst duplicates in time window',
      () {
    final mask = WindowedDanmakuBatchMask(
      window: const Duration(seconds: 8),
      burstLimit: 2,
    );

    final firstBatch = mask.allowListBatch(
      const [
        LiveMessage(type: LiveMessageType.chat, content: '弹幕A'),
        LiveMessage(type: LiveMessageType.chat, content: '弹幕A'),
        LiveMessage(type: LiveMessageType.chat, content: '弹幕A'),
        LiveMessage(type: LiveMessageType.superChat, content: 'SC'),
      ],
      now: DateTime(2026, 3, 30, 1),
    );
    final secondBatch = mask.allowListBatch(
      const [
        LiveMessage(type: LiveMessageType.chat, content: '弹幕A'),
      ],
      now: DateTime(2026, 3, 30, 1, 0, 9),
    );

    expect(firstBatch.map((item) => item.content), ['弹幕A', '弹幕A', 'SC']);
    expect(secondBatch.single.content, '弹幕A');
  });
}
