import 'package:flutter_test/flutter_test.dart';
import 'package:live_player/live_player.dart';

void main() {
  test('MemoryPlayer setVolume no-op when value unchanged', () async {
    final player = MemoryPlayer();
    await player.initialize();
    await player.setVolume(0.5);
    expect(player.currentState.volume, 0.5);

    var emissions = 0;
    final sub = player.states.listen((_) {
      emissions += 1;
    });
    // Drain initial snapshot if any.
    await Future<void>.delayed(Duration.zero);
    emissions = 0;

    await player.setVolume(0.5);
    await player.setVolume(0.5);
    await Future<void>.delayed(Duration.zero);
    expect(emissions, 0, reason: 'identical volume must not re-emit');

    await player.setVolume(0.7);
    await Future<void>.delayed(Duration.zero);
    expect(player.currentState.volume, closeTo(0.7, 0.0001));
    expect(emissions, greaterThan(0));

    await sub.cancel();
    await player.dispose();
  });
}
