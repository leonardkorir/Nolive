import 'package:live_storage/live_storage.dart';

enum FollowDisplayModePreference { list, grid }

class FollowPreferences {
  const FollowPreferences({
    required this.displayMode,
    required this.autoRefreshEnabled,
    required this.autoRefreshIntervalMinutes,
  });

  static const FollowPreferences defaults = FollowPreferences(
    displayMode: FollowDisplayModePreference.list,
    autoRefreshEnabled: true,
    autoRefreshIntervalMinutes: 10,
  );

  final FollowDisplayModePreference displayMode;
  final bool autoRefreshEnabled;
  final int autoRefreshIntervalMinutes;

  Duration get autoRefreshInterval =>
      Duration(minutes: autoRefreshIntervalMinutes);

  FollowPreferences copyWith({
    FollowDisplayModePreference? displayMode,
    bool? autoRefreshEnabled,
    int? autoRefreshIntervalMinutes,
  }) {
    return FollowPreferences(
      displayMode: displayMode ?? this.displayMode,
      autoRefreshEnabled: autoRefreshEnabled ?? this.autoRefreshEnabled,
      autoRefreshIntervalMinutes:
          autoRefreshIntervalMinutes ?? this.autoRefreshIntervalMinutes,
    );
  }
}

class LoadFollowPreferencesUseCase {
  const LoadFollowPreferencesUseCase(this.settingsRepository);

  final SettingsRepository settingsRepository;

  Future<FollowPreferences> call() async {
    final defaults = FollowPreferences.defaults;
    final displayMode = decodeDisplayMode(
      await settingsRepository.readValue<Object?>('follow_display_mode'),
    );
    final autoRefreshEnabled = await settingsRepository
            .readValue<bool>('follow_auto_refresh_enabled') ??
        defaults.autoRefreshEnabled;
    final autoRefreshIntervalMinutes = normalizeIntervalMinutes(
      await settingsRepository.readValue<Object?>(
        'follow_auto_refresh_interval_minutes',
      ),
    );

    return FollowPreferences(
      displayMode: displayMode,
      autoRefreshEnabled: autoRefreshEnabled,
      autoRefreshIntervalMinutes: autoRefreshIntervalMinutes,
    );
  }

  static int normalizeIntervalMinutes(Object? raw) {
    final parsed = switch (raw) {
      int value => value,
      num value => value.toInt(),
      String value => int.tryParse(value.trim()),
      _ => null,
    };
    return _clampMinutes(
      parsed,
      fallback: FollowPreferences.defaults.autoRefreshIntervalMinutes,
    );
  }

  static FollowDisplayModePreference decodeDisplayMode(Object? raw) {
    final normalized = raw?.toString().trim().toLowerCase();
    return normalized == FollowDisplayModePreference.grid.name
        ? FollowDisplayModePreference.grid
        : FollowPreferences.defaults.displayMode;
  }

  static int _clampMinutes(int? value, {required int fallback}) {
    return (value ?? fallback).clamp(1, 24 * 60);
  }
}

class UpdateFollowPreferencesUseCase {
  const UpdateFollowPreferencesUseCase(this.settingsRepository);

  final SettingsRepository settingsRepository;

  Future<void> call(FollowPreferences preferences) async {
    await settingsRepository.writeValue(
      'follow_display_mode',
      preferences.displayMode.name,
    );
    await settingsRepository.writeValue(
      'follow_auto_refresh_enabled',
      preferences.autoRefreshEnabled,
    );
    await settingsRepository.writeValue(
      'follow_auto_refresh_interval_minutes',
      LoadFollowPreferencesUseCase.normalizeIntervalMinutes(
        preferences.autoRefreshIntervalMinutes,
      ),
    );
  }
}
