import 'package:flutter_test/flutter_test.dart';
import 'package:nolive_app/src/app/runtime_bridges/twitch/twitch_web_playback_lifecycle.dart';

void main() {
  testWidgets('idle dispose waits until the last active use completes', (
    tester,
  ) async {
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
    await tester.pump(const Duration(seconds: 5));
    expect(reasons, isEmpty);
    expect(lifecycle.activeUseCount, 1);

    lifecycle.endUse(secondLease, idleReason: 'second');
    await tester.pump(const Duration(seconds: 5));

    expect(reasons, <String>['second']);
    lifecycle.dispose();
  });

  testWidgets('invalidate cancels pending idle dispose from a stale lease', (
    tester,
  ) async {
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
    await tester.pump(const Duration(seconds: 5));

    expect(reasons, isEmpty);
    lifecycle.endUse(lease, idleReason: 'ignored');
    await tester.pump(const Duration(seconds: 5));
    expect(reasons, isEmpty);
    lifecycle.dispose();
  });
}
