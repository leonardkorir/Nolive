import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';
import 'package:live_hls_proxy/src/twitch/twitch_web_playback_lifecycle.dart';

void main() {
  test('idle dispose waits until the last active use completes', () {
    fakeAsync((async) {
      final reasons = <String>[];
      final lifecycle = TwitchWebPlaybackLifecycle(
        idleDisposeDelay: const Duration(seconds: 5),
        onIdleDispose: (reason) async {
          reasons.add(reason);
        },
      );

      final firstLease = lifecycle.beginUse();
      final secondLease = lifecycle.beginUse();

      lifecycle.endUse(firstLease, idleReason: 'first');
      async.elapse(const Duration(seconds: 5));
      expect(reasons, isEmpty);
      expect(lifecycle.activeUseCount, 1);

      lifecycle.endUse(secondLease, idleReason: 'second');
      async.elapse(const Duration(seconds: 5));

      expect(reasons, <String>['second']);
      lifecycle.dispose();
    });
  });

  test('invalidate cancels pending idle dispose from a stale lease', () {
    fakeAsync((async) {
      final reasons = <String>[];
      final lifecycle = TwitchWebPlaybackLifecycle(
        idleDisposeDelay: const Duration(seconds: 5),
        onIdleDispose: (reason) async {
          reasons.add(reason);
        },
      );

      final lease = lifecycle.beginUse();
      lifecycle.endUse(lease, idleReason: 'stale');
      lifecycle.invalidate();
      async.elapse(const Duration(seconds: 5));

      expect(reasons, isEmpty);
      lifecycle.endUse(lease, idleReason: 'ignored');
      async.elapse(const Duration(seconds: 5));
      expect(reasons, isEmpty);
      lifecycle.dispose();
    });
  });
}
