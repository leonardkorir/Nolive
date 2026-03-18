import 'package:flutter_test/flutter_test.dart';
import 'package:nolive_app/src/app/bootstrap/bootstrap.dart';
import 'package:nolive_app/src/features/settings/application/manage_danmaku_preferences_use_case.dart';

void main() {
  test('danmaku preferences persist and clamp values', () async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);

    expect(
      await bootstrap.loadDanmakuPreferences(),
      DanmakuPreferences.defaults,
    );

    const next = DanmakuPreferences(
      enabledByDefault: false,
      fontSize: 22,
      fontWeight: 7,
      area: 0.5,
      speed: 18,
      opacity: 0.7,
      strokeWidth: 2.4,
      lineHeight: 1.5,
      topMargin: 20,
      bottomMargin: 48,
    );

    await bootstrap.updateDanmakuPreferences(next);

    expect(await bootstrap.loadDanmakuPreferences(), next);
  });
}
