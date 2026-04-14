import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:nolive_app/src/features/library/application/clear_history_use_case.dart';
import 'package:nolive_app/src/features/library/application/clear_tags_use_case.dart';
import 'package:nolive_app/src/features/library/application/create_tag_use_case.dart';
import 'package:nolive_app/src/features/library/application/load_library_dashboard_use_case.dart';
import 'package:nolive_app/src/features/library/application/manage_follow_transfer_use_case.dart';
import 'package:nolive_app/src/features/library/application/remove_tag_use_case.dart';
import 'package:nolive_app/src/features/profile/application/clear_follows_use_case.dart';
import 'package:nolive_app/src/features/profile/application/manage_blocked_keywords_use_case.dart';
import 'package:nolive_app/src/features/profile/application/manage_theme_mode_use_case.dart';
import 'package:nolive_app/src/shared/application/player_runtime_controller.dart';
import 'package:nolive_app/src/shared/application/provider_catalog_use_cases.dart';

import 'manage_danmaku_preferences_use_case.dart';
import 'manage_follow_preferences_use_case.dart';
import 'manage_layout_preferences_use_case.dart';
import 'manage_player_preferences_use_case.dart';
import 'manage_room_ui_preferences_use_case.dart';

class AppearanceSettingsDependencies {
  const AppearanceSettingsDependencies({
    required this.themeMode,
    required this.updateThemeMode,
  });

  final ValueListenable<ThemeMode> themeMode;
  final UpdateThemeModeUseCase updateThemeMode;
}

class LayoutSettingsDependencies {
  const LayoutSettingsDependencies({
    required this.layoutPreferences,
    required this.updateLayoutPreferences,
    required this.findProviderDescriptorById,
  });

  final ValueListenable<LayoutPreferences> layoutPreferences;
  final UpdateLayoutPreferencesUseCase updateLayoutPreferences;
  final FindProviderDescriptorByIdUseCase findProviderDescriptorById;
}

class RoomSettingsDependencies {
  const RoomSettingsDependencies({
    required this.loadRoomUiPreferences,
    required this.updateRoomUiPreferences,
    required this.loadPlayerPreferences,
    required this.updatePlayerPreferences,
  });

  final LoadRoomUiPreferencesUseCase loadRoomUiPreferences;
  final UpdateRoomUiPreferencesUseCase updateRoomUiPreferences;
  final LoadPlayerPreferencesUseCase loadPlayerPreferences;
  final UpdatePlayerPreferencesUseCase updatePlayerPreferences;
}

class PlayerSettingsDependencies {
  const PlayerSettingsDependencies({
    required this.loadPlayerPreferences,
    required this.updatePlayerPreferences,
    required this.applyPlayerPreferencesToRuntime,
    required this.playerRuntime,
    required this.isLiveMode,
  });

  final LoadPlayerPreferencesUseCase loadPlayerPreferences;
  final UpdatePlayerPreferencesUseCase updatePlayerPreferences;
  final ApplyPlayerPreferencesToRuntimeUseCase applyPlayerPreferencesToRuntime;
  final PlayerRuntimeController playerRuntime;
  final bool isLiveMode;
}

class DanmakuSettingsDependencies {
  const DanmakuSettingsDependencies({
    required this.loadDanmakuPreferences,
    required this.updateDanmakuPreferences,
    required this.loadBlockedKeywords,
  });

  final LoadDanmakuPreferencesUseCase loadDanmakuPreferences;
  final UpdateDanmakuPreferencesUseCase updateDanmakuPreferences;
  final LoadBlockedKeywordsUseCase loadBlockedKeywords;
}

class DanmakuShieldDependencies {
  const DanmakuShieldDependencies({
    required this.loadBlockedKeywords,
    required this.addBlockedKeyword,
    required this.removeBlockedKeyword,
  });

  final LoadBlockedKeywordsUseCase loadBlockedKeywords;
  final AddBlockedKeywordUseCase addBlockedKeyword;
  final RemoveBlockedKeywordUseCase removeBlockedKeyword;
}

class FollowSettingsDependencies {
  const FollowSettingsDependencies({
    required this.loadLibraryDashboard,
    required this.loadFollowPreferences,
    required this.updateFollowPreferences,
    required this.exportFollowListJson,
    required this.importFollowListJson,
    required this.removeTag,
    required this.createTag,
    required this.clearFollows,
    required this.clearHistory,
    required this.clearTags,
  });

  final LoadLibraryDashboardUseCase loadLibraryDashboard;
  final LoadFollowPreferencesUseCase loadFollowPreferences;
  final UpdateFollowPreferencesUseCase updateFollowPreferences;
  final ExportFollowListJsonUseCase exportFollowListJson;
  final ImportFollowListJsonUseCase importFollowListJson;
  final RemoveTagUseCase removeTag;
  final CreateTagUseCase createTag;
  final ClearFollowsUseCase clearFollows;
  final ClearHistoryUseCase clearHistory;
  final ClearTagsUseCase clearTags;
}
