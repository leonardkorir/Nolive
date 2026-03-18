import 'package:flutter/material.dart';
import 'package:live_storage/live_storage.dart';
import 'package:nolive_app/src/features/profile/application/manage_theme_mode_use_case.dart';
import 'package:nolive_app/src/features/settings/application/manage_layout_preferences_use_case.dart';

const List<String> kDefaultBlockedKeywords = ['剧透'];
const List<String> kDefaultTags = ['常看', '收藏'];

void seedDefaultAppState({
  required SettingsRepository settingsRepository,
  required TagRepository tagRepository,
  required ValueNotifier<ThemeMode> themeModeNotifier,
}) {
  themeModeNotifier.value = ThemeMode.system;
  settingsRepository.writeValue(
    'blocked_keywords',
    kDefaultBlockedKeywords,
  );
  settingsRepository.writeValue('theme_mode', 'system');
  settingsRepository.writeValue('player_auto_play', true);
  settingsRepository.writeValue('player_prefer_highest_quality', false);
  settingsRepository.writeValue('player_backend', 'mpv');
  settingsRepository.writeValue('player_volume', 1.0);
  settingsRepository.writeValue('player_mpv_hardware_acceleration', true);
  settingsRepository.writeValue('player_mpv_compat_mode', false);
  settingsRepository.writeValue('player_mdk_low_latency', true);
  settingsRepository.writeValue('player_mdk_android_tunnel', false);
  settingsRepository.writeValue('player_force_https', false);
  settingsRepository.writeValue('player_android_auto_fullscreen', true);
  settingsRepository.writeValue('player_android_background_auto_pause', true);
  settingsRepository.writeValue('player_android_pip_hide_danmaku', true);
  settingsRepository.writeValue('player_scale_mode', 'contain');
  settingsRepository.writeValue('danmaku_enabled_by_default', true);
  settingsRepository.writeValue('danmaku_font_size', 16.0);
  settingsRepository.writeValue('danmaku_font_weight', 3);
  settingsRepository.writeValue('danmaku_area', 0.8);
  settingsRepository.writeValue('danmaku_speed', 18.0);
  settingsRepository.writeValue('danmaku_opacity', 1.0);
  settingsRepository.writeValue('danmaku_stroke_width', 2.0);
  settingsRepository.writeValue('danmaku_line_height', 1.25);
  settingsRepository.writeValue('danmaku_top_margin', 0.0);
  settingsRepository.writeValue('danmaku_bottom_margin', 0.0);
  settingsRepository.writeValue('room_chat_text_size', 14.0);
  settingsRepository.writeValue('room_chat_text_gap', 4.0);
  settingsRepository.writeValue('room_chat_bubble_style', false);
  settingsRepository.writeValue('room_show_player_super_chat', true);
  settingsRepository.writeValue(
    'layout_shell_tab_order',
    LayoutPreferences.defaultShellTabOrder
        .map((item) => item.value)
        .toList(growable: false),
  );
  settingsRepository.writeValue(
    'layout_provider_order',
    LayoutPreferences.defaultProviderOrder,
  );
  settingsRepository.writeValue('follow_auto_refresh_enabled', true);
  settingsRepository.writeValue('follow_auto_refresh_interval_minutes', 10);
  settingsRepository.writeValue('follow_display_mode', 'list');
  settingsRepository.writeValue('history_record_watch_enabled', true);
  for (final tag in kDefaultTags) {
    tagRepository.create(tag);
  }
}

Future<void> ensureDefaultAppState({
  required SettingsRepository settingsRepository,
  required TagRepository tagRepository,
  required ValueNotifier<ThemeMode> themeModeNotifier,
}) async {
  await _writeDefaultIfMissing<List<String>>(
    settingsRepository,
    'blocked_keywords',
    kDefaultBlockedKeywords,
  );
  await _writeDefaultIfMissing<String>(
    settingsRepository,
    'theme_mode',
    'system',
  );
  await _writeDefaultIfMissing<bool>(
    settingsRepository,
    'player_auto_play',
    true,
  );
  await _writeDefaultIfMissing<bool>(
    settingsRepository,
    'player_prefer_highest_quality',
    false,
  );
  await _writeDefaultIfMissing<String>(
    settingsRepository,
    'player_backend',
    'mpv',
  );
  await _writeDefaultIfMissing<double>(
    settingsRepository,
    'player_volume',
    1.0,
  );
  await _writeDefaultIfMissing<bool>(
    settingsRepository,
    'player_mpv_hardware_acceleration',
    true,
  );
  await _writeDefaultIfMissing<bool>(
    settingsRepository,
    'player_mpv_compat_mode',
    false,
  );
  await _writeDefaultIfMissing<bool>(
    settingsRepository,
    'player_mdk_low_latency',
    true,
  );
  await _writeDefaultIfMissing<bool>(
    settingsRepository,
    'player_mdk_android_tunnel',
    false,
  );
  await _writeDefaultIfMissing<bool>(
    settingsRepository,
    'player_force_https',
    false,
  );
  await _writeDefaultIfMissing<bool>(
    settingsRepository,
    'player_android_auto_fullscreen',
    true,
  );
  await _writeDefaultIfMissing<bool>(
    settingsRepository,
    'player_android_background_auto_pause',
    true,
  );
  await _writeDefaultIfMissing<bool>(
    settingsRepository,
    'player_android_pip_hide_danmaku',
    true,
  );
  await _writeDefaultIfMissing<String>(
    settingsRepository,
    'player_scale_mode',
    'contain',
  );
  await _writeDefaultIfMissing<bool>(
    settingsRepository,
    'danmaku_enabled_by_default',
    true,
  );
  await _writeDefaultIfMissing<double>(
    settingsRepository,
    'danmaku_font_size',
    16.0,
  );
  await _writeDefaultIfMissing<int>(
    settingsRepository,
    'danmaku_font_weight',
    3,
  );
  await _writeDefaultIfMissing<double>(
    settingsRepository,
    'danmaku_area',
    0.8,
  );
  await _writeDefaultIfMissing<double>(
    settingsRepository,
    'danmaku_speed',
    12.0,
  );
  await _writeDefaultIfMissing<double>(
    settingsRepository,
    'danmaku_opacity',
    1.0,
  );
  await _writeDefaultIfMissing<double>(
    settingsRepository,
    'danmaku_stroke_width',
    2.0,
  );
  await _writeDefaultIfMissing<double>(
    settingsRepository,
    'danmaku_line_height',
    1.25,
  );
  await _writeDefaultIfMissing<double>(
    settingsRepository,
    'danmaku_top_margin',
    0.0,
  );
  await _writeDefaultIfMissing<double>(
    settingsRepository,
    'danmaku_bottom_margin',
    0.0,
  );
  await _writeDefaultIfMissing<double>(
    settingsRepository,
    'room_chat_text_size',
    14.0,
  );
  await _writeDefaultIfMissing<double>(
    settingsRepository,
    'room_chat_text_gap',
    4.0,
  );
  await _writeDefaultIfMissing<bool>(
    settingsRepository,
    'room_chat_bubble_style',
    false,
  );
  await _writeDefaultIfMissing<bool>(
    settingsRepository,
    'room_show_player_super_chat',
    true,
  );
  await _writeDefaultIfMissing<List<String>>(
    settingsRepository,
    'layout_shell_tab_order',
    LayoutPreferences.defaultShellTabOrder
        .map((item) => item.value)
        .toList(growable: false),
  );
  await _writeDefaultIfMissing<List<String>>(
    settingsRepository,
    'layout_provider_order',
    LayoutPreferences.defaultProviderOrder,
  );
  await _writeDefaultIfMissing<bool>(
    settingsRepository,
    'history_record_watch_enabled',
    true,
  );
  await _writeDefaultIfMissing<bool>(
    settingsRepository,
    'follow_auto_refresh_enabled',
    true,
  );
  await _writeDefaultIfMissing<int>(
    settingsRepository,
    'follow_auto_refresh_interval_minutes',
    10,
  );
  await _writeDefaultIfMissing<String>(
    settingsRepository,
    'follow_display_mode',
    'list',
  );

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
