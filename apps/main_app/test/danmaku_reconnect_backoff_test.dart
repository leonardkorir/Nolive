import 'package:flutter_test/flutter_test.dart';
import 'package:nolive_app/src/features/room/presentation/room_danmaku_controller.dart';

void main() {
  test('defaultDanmakuReconnectDelay grows exponentially and caps', () {
    expect(defaultDanmakuReconnectDelay(1), const Duration(seconds: 2));
    expect(defaultDanmakuReconnectDelay(2), const Duration(seconds: 4));
    expect(defaultDanmakuReconnectDelay(3), const Duration(seconds: 8));
    expect(defaultDanmakuReconnectDelay(4), const Duration(seconds: 16));
    expect(defaultDanmakuReconnectDelay(5), const Duration(seconds: 30));
    expect(defaultDanmakuReconnectDelay(12), const Duration(seconds: 30));
    // N rapid closes must not all schedule at 0 delay.
    final delays = List<Duration>.generate(
      8,
      (i) => defaultDanmakuReconnectDelay(i + 1),
    );
    expect(delays.every((d) => d > Duration.zero), isTrue);
    expect(delays[2].inMilliseconds, greaterThan(delays[0].inMilliseconds));
    expect(delays[4].inMilliseconds, greaterThanOrEqualTo(delays[3].inMilliseconds));
  });

  test('healthy reset window is multi-second to stop thrash', () {
    expect(
      kDanmakuReconnectHealthyReset.inSeconds,
      greaterThanOrEqualTo(30),
    );
  });
}
