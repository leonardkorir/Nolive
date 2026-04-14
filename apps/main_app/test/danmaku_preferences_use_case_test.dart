import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nolive_app/src/app/bootstrap/bootstrap.dart';
import 'package:nolive_app/src/features/settings/application/manage_danmaku_preferences_use_case.dart';
import 'package:nolive_app/src/shared/application/secure_credential_store.dart';

void main() {
  test('preview and persistent bootstrap share the same danmaku speed default',
      () async {
    final preview = createAppBootstrap(mode: AppRuntimeMode.preview);
    final directory = await Directory.systemTemp.createTemp(
      'nolive-danmaku-defaults-',
    );
    addTearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });

    final persistent = await createPersistentAppBootstrap(
      storageDirectory: directory,
      secureCredentialStore: InMemorySecureCredentialStore(),
    );

    expect(DanmakuPreferences.defaults.speed, 12);
    expect(await preview.settingsRepository.readValue<double>('danmaku_speed'),
        12);
    expect(
      await persistent.settingsRepository.readValue<double>('danmaku_speed'),
      12,
    );
    expect((await preview.loadDanmakuPreferences()).speed, 12);
    expect((await persistent.loadDanmakuPreferences()).speed, 12);
  });

  test('danmaku preferences persist and clamp values', () async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);

    expect(
      await bootstrap.loadDanmakuPreferences(),
      DanmakuPreferences.defaults,
    );

    const next = DanmakuPreferences(
      enabledByDefault: false,
      nativeBatchMaskEnabled: false,
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
