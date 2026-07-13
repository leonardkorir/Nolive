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

  test('DanmakuFilterService blocks regex rules case-insensitively when caseSensitive is false', () {
    final service = DanmakuFilterService(
      config: DanmakuFilterConfig(
        blockedKeywords: {'re:^spam.*'},
        caseSensitive: false,
      ),
    );

    const messages = [
      LiveMessage(type: LiveMessageType.chat, content: 'SPAMMY content'),
      LiveMessage(type: LiveMessageType.chat, content: 'normal chat'),
    ];

    final filtered = service.apply(messages);

    expect(filtered, hasLength(1));
    expect(filtered.single.content, 'normal chat');
  });

  test('DanmakuFilterService blocks regex rules case-sensitively when caseSensitive is true', () {
    final service = DanmakuFilterService(
      config: DanmakuFilterConfig(
        blockedKeywords: {'re:^spam.*'},
        caseSensitive: true,
      ),
    );

    const messages = [
      LiveMessage(type: LiveMessageType.chat, content: 'SPAMMY content'),
      LiveMessage(type: LiveMessageType.chat, content: 'spammy content'),
    ];

    final filtered = service.apply(messages);

    expect(filtered, hasLength(1));
    expect(filtered.single.content, 'SPAMMY content');
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

  group('WindowedDanmakuBatchMask extra coverage', () {
    test('8-second window boundary conditions (burstLimit = 1)', () {
      final mask = WindowedDanmakuBatchMask(
        window: const Duration(seconds: 8),
        burstLimit: 1,
      );

      final t0 = DateTime(2026, 5, 29, 12, 0, 0);

      // T=0: First message allowed. Queue for 'msg' gets [t0.ms] (e.g. 0)
      final batch1 = mask.allowListBatch(
        const [LiveMessage(type: LiveMessageType.chat, content: 'msg')],
        now: t0,
      );
      expect(batch1, hasLength(1));

      // T=7999ms: duplicate is suppressed.
      final batch2 = mask.allowListBatch(
        const [LiveMessage(type: LiveMessageType.chat, content: 'msg')],
        now: t0.add(const Duration(milliseconds: 7999)),
      );
      expect(batch2, isEmpty);

      // T=8000ms: exactly at window boundary.
      // threshold = 8000. t0.ms (0) is not < threshold (0).
      // So duplicate is still suppressed.
      final batch3 = mask.allowListBatch(
        const [LiveMessage(type: LiveMessageType.chat, content: 'msg')],
        now: t0.add(const Duration(milliseconds: 8000)),
      );
      expect(batch3, isEmpty);

      // T=8001ms: threshold = 8001. t0.ms (0) is < threshold (8001), so it is evicted.
      // Message is allowed again.
      final batch4 = mask.allowListBatch(
        const [LiveMessage(type: LiveMessageType.chat, content: 'msg')],
        now: t0.add(const Duration(milliseconds: 8001)),
      );
      expect(batch4, hasLength(1));
    });

    test('FIFO key eviction when maxTrackedKeys is exceeded (burstLimit = 1)', () {
      final mask = WindowedDanmakuBatchMask(
        window: const Duration(seconds: 10),
        burstLimit: 1,
        maxTrackedKeys: 3,
      );

      final now = DateTime(2026, 5, 29, 12, 0, 0);

      // Track 'a', 'b', 'c'
      expect(mask.allowListBatch(const [LiveMessage(type: LiveMessageType.chat, content: 'a')], now: now), hasLength(1));
      expect(mask.allowListBatch(const [LiveMessage(type: LiveMessageType.chat, content: 'a')], now: now), isEmpty); // confirmed tracked

      expect(mask.allowListBatch(const [LiveMessage(type: LiveMessageType.chat, content: 'b')], now: now), hasLength(1));
      expect(mask.allowListBatch(const [LiveMessage(type: LiveMessageType.chat, content: 'c')], now: now), hasLength(1));

      // At this point, seen keys: {'a', 'b', 'c'}, insertion order: ['a', 'b', 'c']
      // Track 'd', which exceeds maxTrackedKeys (3). Should evict the oldest: 'a'.
      expect(mask.allowListBatch(const [LiveMessage(type: LiveMessageType.chat, content: 'd')], now: now), hasLength(1));

      // 'b' was NOT evicted yet, so it should still be suppressed/blocked as a duplicate
      expect(mask.allowListBatch(const [LiveMessage(type: LiveMessageType.chat, content: 'b')], now: now), isEmpty);

      // 'a' was evicted, so sending it again should be allowed (and will evict 'b')
      expect(mask.allowListBatch(const [LiveMessage(type: LiveMessageType.chat, content: 'a')], now: now), hasLength(1));

      // Now 'b' has been evicted, so it is allowed again
      expect(mask.allowListBatch(const [LiveMessage(type: LiveMessageType.chat, content: 'b')], now: now), hasLength(1));

      // 'c' was evicted when 'b' was added back, but 'd' is still in the cache, so 'd' should be blocked
      expect(mask.allowListBatch(const [LiveMessage(type: LiveMessageType.chat, content: 'd')], now: now), isEmpty);
    });
  });
}

