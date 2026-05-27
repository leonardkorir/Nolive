import 'package:flutter/material.dart';
import 'package:live_storage/live_storage.dart';
import 'package:nolive_app/src/features/profile/application/manage_theme_mode_use_case.dart';
import 'package:nolive_app/src/features/settings/application/manage_layout_preferences_use_case.dart';

const List<String> kDefaultBlockedKeywords = [
  r're:(https?://|www\.|[A-Za-z0-9.-]+\.[A-Za-z]{2,})(/\S*)?',
  '进入了',
  '送出了',
  'token',
  '点击前往',
  'Tip',
  'Menu',
];
const List<String> kDefaultTags = ['常看', '收藏'];

Map<String, Object?> buildDefaultAppSettings() {
  return {
    'blocked_keywords': kDefaultBlockedKeywords,
    'theme_mode': 'system',
    'player_auto_play': true,
    'player_prefer_highest_quality': false,
    'player_backend': 'mpv',
    'player_volume': 1.0,
    'player_mpv_hardware_acceleration': true,
    'player_mpv_compat_mode': false,
    'player_mdk_low_latency': true,
    'player_mdk_android_tunnel': false,
    'player_mdk_android_hardware_video_decoder': true,
    'player_force_https': false,
    'player_android_auto_fullscreen': true,
    'player_android_background_auto_pause': true,
    'player_android_pip_hide_danmaku': true,
    'player_scale_mode': 'contain',
    'danmaku_enabled_by_default': true,
    'danmaku_font_size': 16.0,
    'danmaku_font_weight': 3,
    'danmaku_area': 0.8,
    'danmaku_speed': 12.0,
    'danmaku_opacity': 1.0,
    'danmaku_stroke_width': 2.0,
    'danmaku_line_height': 1.25,
    'danmaku_top_margin': 0.0,
    'danmaku_bottom_margin': 0.0,
    'room_chat_text_size': 14.0,
    'room_chat_text_gap': 4.0,
    'room_chat_bubble_style': false,
    'room_show_player_super_chat': true,
    'layout_shell_tab_order': LayoutPreferences.defaultShellTabOrder
        .map((item) => item.value)
        .toList(growable: false),
    'layout_provider_order': LayoutPreferences.defaultProviderOrder,
    'layout_provider_enabled_ids': LayoutPreferences.defaultEnabledProviderIds,
    'follow_auto_refresh_enabled': true,
    'follow_auto_refresh_interval_minutes': 10,
    'follow_display_mode': 'list',
    'history_record_watch_enabled': true,
  };
}

void seedDefaultAppState({
  required SettingsRepository settingsRepository,
  required TagRepository tagRepository,
  required ValueNotifier<ThemeMode> themeModeNotifier,
}) {
  themeModeNotifier.value = ThemeMode.system;
  for (final entry in buildDefaultAppSettings().entries) {
    _writeDefaultSetting(settingsRepository, entry.key, entry.value);
  }
  for (final tag in kDefaultTags) {
    tagRepository.create(tag);
  }
}

Future<void> ensureDefaultAppState({
  required SettingsRepository settingsRepository,
  required TagRepository tagRepository,
  required ValueNotifier<ThemeMode> themeModeNotifier,
}) async {
  for (final entry in buildDefaultAppSettings().entries) {
    await _writeDefaultSettingIfMissing(
      settingsRepository,
      entry.key,
      entry.value,
    );
  }

  final existingTags = await tagRepository.listAll();
  for (final tag in kDefaultTags) {
    if (!existingTags.contains(tag)) {
      await tagRepository.create(tag);
    }
  }

  await syncThemeModeNotifierFromSettings(
    settingsRepository: settingsRepository,
    themeModeNotifier: themeModeNotifier,
  );
}

Future<void> syncThemeModeNotifierFromSettings({
  required SettingsRepository settingsRepository,
  required ValueNotifier<ThemeMode> themeModeNotifier,
}) async {
  final encoded = await settingsRepository.readValue<String>('theme_mode');
  themeModeNotifier.value = UpdateThemeModeUseCase.decode(encoded);
}

Future<void> _writeDefaultIfMissing<T>(
  SettingsRepository settingsRepository,
  String key,
  T value,
) async {
  final existing = await settingsRepository.readValue<T>(key);
  if (existing != null) {
    return;
  }
  await settingsRepository.writeValue<T>(key, value);
}

void _writeDefaultSetting(
  SettingsRepository settingsRepository,
  String key,
  Object? value,
) {
  switch (value) {
    case List<String> typed:
      settingsRepository.writeValue<List<String>>(key, typed);
    case String typed:
      settingsRepository.writeValue<String>(key, typed);
    case bool typed:
      settingsRepository.writeValue<bool>(key, typed);
    case int typed:
      settingsRepository.writeValue<int>(key, typed);
    case double typed:
      settingsRepository.writeValue<double>(key, typed);
    default:
      throw ArgumentError.value(value, key, 'Unsupported default setting type');
  }
}

Future<void> _writeDefaultSettingIfMissing(
  SettingsRepository settingsRepository,
  String key,
  Object? value,
) {
  switch (value) {
    case List<String> typed:
      return _writeDefaultIfMissing<List<String>>(
          settingsRepository, key, typed);
    case String typed:
      return _writeDefaultIfMissing<String>(settingsRepository, key, typed);
    case bool typed:
      return _writeDefaultIfMissing<bool>(settingsRepository, key, typed);
    case int typed:
      return _writeDefaultIfMissing<int>(settingsRepository, key, typed);
    case double typed:
      return _writeDefaultIfMissing<double>(settingsRepository, key, typed);
    default:
      throw ArgumentError.value(value, key, 'Unsupported default setting type');
  }
}
