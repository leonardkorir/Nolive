import 'package:live_providers/src/providers/chaturbate/chaturbate_request_scheduler.dart';
import 'package:test/test.dart';

void main() {
  test('scheduler prefers high over normal when draining idle queue', () async {
    final scheduler = ChaturbateRequestScheduler(
      maxConcurrent: 1,
      minSpacing: Duration.zero,
      lowMinSpacing: Duration.zero,
    );
    final order = <String>[];
    final hold = Future<void>.delayed(const Duration(milliseconds: 30));

    // Occupy the worker so both subsequent jobs stay queued.
    final blocker = scheduler.schedule(() => hold);

    final normal = scheduler.schedule(() async {
      order.add('normal');
    }, priority: ChaturbateRequestPriority.normal);

    final high = scheduler.schedule(() async {
      order.add('high');
    }, priority: ChaturbateRequestPriority.high);

    await blocker;
    await Future.wait([normal, high]);

    expect(order, ['high', 'normal']);
  });

  test('rate-limit cooldown delays subsequent high/normal work', () async {
    final scheduler = ChaturbateRequestScheduler(
      maxConcurrent: 1,
      minSpacing: Duration.zero,
      lowMinSpacing: Duration.zero,
      rateLimitCooldown: const Duration(milliseconds: 80),
    );
    final times = <DateTime>[];

    await scheduler.schedule(() async {
      times.add(DateTime.now());
      scheduler.notifyRateLimited(priority: ChaturbateRequestPriority.normal);
    });
    await scheduler.schedule(() async {
      times.add(DateTime.now());
    }, priority: ChaturbateRequestPriority.high);

    expect(times, hasLength(2));
    final gap = times[1].difference(times[0]);
    expect(gap.inMilliseconds, greaterThanOrEqualTo(60));
  });

  test('follow low 429 does not freeze high priority work', () async {
    final scheduler = ChaturbateRequestScheduler(
      maxConcurrent: 1,
      minSpacing: Duration.zero,
      lowMinSpacing: Duration.zero,
      rateLimitCooldown: const Duration(milliseconds: 20),
      lowRateLimitCooldown: const Duration(milliseconds: 400),
      maxLowRateLimitCooldown: const Duration(seconds: 2),
    );

    // Follow path hits 429 and parks only the low queue.
    await scheduler.schedule(() async {
      scheduler.notifyRateLimited(priority: ChaturbateRequestPriority.low);
    }, priority: ChaturbateRequestPriority.low);

    final highStarted = Stopwatch()..start();
    await scheduler.schedule(() async {
      highStarted.stop();
    }, priority: ChaturbateRequestPriority.high);

    // High should run promptly, not wait for the 400ms low cooldown.
    expect(highStarted.elapsedMilliseconds, lessThan(150));
  });

  test('repeated low 429 escalates follow cooldown only', () async {
    final scheduler = ChaturbateRequestScheduler(
      maxConcurrent: 1,
      minSpacing: Duration.zero,
      lowMinSpacing: Duration.zero,
      lowRateLimitCooldown: const Duration(milliseconds: 40),
      maxLowRateLimitCooldown: const Duration(seconds: 5),
    );

    scheduler.notifyRateLimited(priority: ChaturbateRequestPriority.low);
    expect(scheduler.debugConsecutiveRateLimits, 1);
    scheduler.notifyRateLimited(priority: ChaturbateRequestPriority.low);
    expect(scheduler.debugConsecutiveRateLimits, 2);
    scheduler.notifySuccess(priority: ChaturbateRequestPriority.low);
    expect(scheduler.debugConsecutiveRateLimits, 0);
  });

  test('runAsFollowBudget demotes nested schedules to low', () async {
    final scheduler = ChaturbateRequestScheduler(
      maxConcurrent: 1,
      minSpacing: Duration.zero,
      lowMinSpacing: Duration.zero,
    );
    final order = <String>[];

    final followJob = ChaturbateRequestScheduler.runAsFollowBudget(() async {
      // Even when API asks for normal, follow zone demotes to low.
      return scheduler.schedule(() async {
        order.add('follow');
      }, priority: ChaturbateRequestPriority.normal);
    });

    final high = scheduler.schedule(() async {
      order.add('high');
    }, priority: ChaturbateRequestPriority.high);

    // Start follow first so it is queued, then high should drain first.
    await Future.wait([followJob, high]);
    expect(order.first, 'high');
    expect(order, containsAll(['high', 'follow']));
  });
}
