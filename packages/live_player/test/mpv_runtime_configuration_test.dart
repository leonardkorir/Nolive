import 'package:flutter_test/flutter_test.dart';
import 'package:live_player/live_player.dart';

void main() {
  test('resolveMpvRuntimeConfiguration sanitizes empty custom output values',
      () {
    final config = resolveMpvRuntimeConfiguration(
      enableHardwareAcceleration: true,
      compatMode: false,
      doubleBufferingEnabled: false,
      customOutputEnabled: true,
      videoOutputDriver: '   ',
      hardwareDecoder: '',
      logEnabled: false,
    );

    expect(config.controllerConfiguration.vo, 'gpu-next');
    expect(config.controllerConfiguration.hwdec, 'auto-safe');
  });
}
