import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_storage/live_storage.dart';
import 'package:nolive_app/src/app/bootstrap/default_state.dart';

void main() {
  test('default app settings include MDK hardware video decoder toggle', () {
    final defaults = buildDefaultAppSettings();

    expect(defaults['player_mdk_android_hardware_video_decoder'], isTrue);
  });

  test(
    'ensureDefaultAppState seeds MDK hardware video decoder preference',
    () async {
      final settingsRepository = InMemorySettingsRepository();
      final tagRepository = InMemoryTagRepository();
      final themeModeNotifier = ValueNotifier<ThemeMode>(ThemeMode.dark);

      await ensureDefaultAppState(
        settingsRepository: settingsRepository,
        tagRepository: tagRepository,
        themeModeNotifier: themeModeNotifier,
      );

      expect(
        await settingsRepository.readValue<bool>(
          'player_mdk_android_hardware_video_decoder',
        ),
        isTrue,
      );
    },
  );
}
