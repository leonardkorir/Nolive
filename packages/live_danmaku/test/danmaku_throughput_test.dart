import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:test/test.dart';

void main() {
  test('danmaku filtering and batch masking handles 100 messages per second',
      () {
    final filter = DanmakuFilterService(
      config: DanmakuFilterConfig(
        blockedKeywords: {'spam', 're:^BLOCK'},
      ),
    );
    final mask = WindowedDanmakuBatchMask(
      window: const Duration(seconds: 8),
      burstLimit: 2,
      maxTrackedKeys: 512,
    );
    final start = DateTime(2026, 4, 28, 12);
    var allowedCount = 0;
    var superChatCount = 0;
    final elapsed = Stopwatch()..start();

    for (var second = 0; second < 60; second++) {
      final now = start.add(Duration(seconds: second));
      final batch = List<LiveMessage>.generate(100, (index) {
        if (index % 50 == 0) {
          superChatCount += 1;
          return LiveMessage(
            type: LiveMessageType.superChat,
            content: 'SC-$second-$index',
            timestamp: now,
          );
        }
        if (index % 10 == 0) {
          return LiveMessage(
            type: LiveMessageType.chat,
            content: 'spam-$second-$index',
            timestamp: now,
          );
        }
        return LiveMessage(
          type: LiveMessageType.chat,
          content: 'Burst ${index % 12}',
          timestamp: now,
        );
      });

      final filtered = filter.apply(batch);
      final allowed = mask.allowListBatch(filtered, now: now);
      expect(allowed.any((item) => item.content.contains('spam')), isFalse);
      allowedCount += allowed.length;
    }

    elapsed.stop();

    expect(superChatCount, 120);
    expect(allowedCount, greaterThanOrEqualTo(superChatCount));
    expect(
      elapsed.elapsedMilliseconds,
      lessThan(2000),
      reason: 'pure Dart processing should stay well below device frame '
          'budgets for a 6,000-message deterministic sample',
    );
  });

  test('danmaku batch mask bounds tracked duplicate keys', () {
    final mask = WindowedDanmakuBatchMask(
      window: const Duration(minutes: 1),
      burstLimit: 1,
      maxTrackedKeys: 4,
    );
    final now = DateTime(2026, 4, 28, 12);

    final firstPass = mask.allowListBatch(
      List<LiveMessage>.generate(
        5,
        (index) => LiveMessage(
          type: LiveMessageType.chat,
          content: 'unique-$index',
        ),
      ),
      now: now,
    );
    final oldestKeyAfterEviction = mask.allowListBatch(
      const [
        LiveMessage(type: LiveMessageType.chat, content: 'unique-0'),
      ],
      now: now.add(const Duration(seconds: 1)),
    );

    expect(firstPass, hasLength(5));
    expect(oldestKeyAfterEviction.single.content, 'unique-0');
  });
}
