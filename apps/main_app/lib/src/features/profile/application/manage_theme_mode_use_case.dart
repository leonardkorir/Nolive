import 'package:flutter/material.dart';
import 'package:live_storage/live_storage.dart';

class UpdateThemeModeUseCase {
  const UpdateThemeModeUseCase({
    required this.settingsRepository,
    required this.themeModeNotifier,
  });

  final SettingsRepository settingsRepository;
  final ValueNotifier<ThemeMode> themeModeNotifier;

  Future<void> call(ThemeMode mode) async {
    themeModeNotifier.value = mode;
    await settingsRepository.writeValue('theme_mode', _encode(mode));
  }

  static ThemeMode decode(String? value) {
    switch (value) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  static String _encode(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }
}
