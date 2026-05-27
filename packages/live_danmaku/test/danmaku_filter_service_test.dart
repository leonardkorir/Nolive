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

  test('DanmakuFilterService ignores invalid regex rules without blocking text',
      () {
    final service = DanmakuFilterService(
      config: DanmakuFilterConfig(blockedKeywords: {'re:[', 'spam'}),
    );

    const messages = [
      LiveMessage(type: LiveMessageType.chat, content: '正常聊天'),
      LiveMessage(type: LiveMessageType.chat, content: 'spam'),
    ];

    final filtered = service.apply(messages);

    expect(filtered.map((item) => item.content), ['正常聊天']);
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

  test('DanmakuFilterConfig defensively copies blocked keywords', () {
    final blockedKeywords = <String>{'spam'};
    final config = DanmakuFilterConfig(blockedKeywords: blockedKeywords);

    blockedKeywords.add('later');

    expect(config.blockedKeywords, {'spam'});
  });

  test('DanmakuFilterConfig copyWith keeps immutability and updates fields',
      () {
    final config = DanmakuFilterConfig(blockedKeywords: {'spam'});

    final next = config.copyWith(
      blockedKeywords: {'ads'},
      caseSensitive: true,
    );

    expect(config.blockedKeywords, {'spam'});
    expect(next.blockedKeywords, {'ads'});
    expect(next.caseSensitive, isTrue);
  });

  test('WindowedDanmakuBatchMask rebuilds tracked keys after batch expiry', () {
    final mask = WindowedDanmakuBatchMask(
      window: const Duration(seconds: 1),
      maxTrackedKeys: 8,
    );

    for (var index = 0; index < 8; index += 1) {
      final batch = mask.allowListBatch(
        [
          LiveMessage(type: LiveMessageType.chat, content: '弹幕$index'),
        ],
        now: DateTime(2026, 3, 30, 1, 0, 0, index),
      );
      expect(batch, hasLength(1));
    }

    final nextBatch = mask.allowListBatch(
      const [
        LiveMessage(type: LiveMessageType.chat, content: '全新弹幕'),
      ],
      now: DateTime(2026, 3, 30, 1, 0, 3),
    );

    expect(nextBatch.single.content, '全新弹幕');
  });
}
