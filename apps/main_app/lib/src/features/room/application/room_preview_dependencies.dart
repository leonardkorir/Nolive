import 'package:flutter/foundation.dart';
import 'package:live_player/live_player.dart';
import 'package:nolive_app/src/app/bootstrap/bootstrap.dart';
import 'package:nolive_app/src/features/library/application/list_follow_records_use_case.dart';
import 'package:nolive_app/src/features/library/application/is_followed_room_use_case.dart';
import 'package:nolive_app/src/features/library/application/load_follow_watchlist_use_case.dart';
import 'package:nolive_app/src/features/library/application/toggle_follow_room_use_case.dart';
import 'package:nolive_app/src/features/profile/application/manage_blocked_keywords_use_case.dart';
import 'package:nolive_app/src/features/room/application/load_room_use_case.dart';
import 'package:nolive_app/src/features/room/application/open_room_danmaku_use_case.dart';
import 'package:nolive_app/src/features/room/application/resolve_play_source_use_case.dart';
import 'package:nolive_app/src/features/settings/application/manage_danmaku_preferences_use_case.dart';
import 'package:nolive_app/src/features/settings/application/manage_player_preferences_use_case.dart';
import 'package:nolive_app/src/features/settings/application/manage_room_ui_preferences_use_case.dart';
import 'package:nolive_app/src/features/room/presentation/room_fullscreen_session_platforms.dart';
import 'package:nolive_app/src/shared/application/player_runtime_controller.dart';
import 'package:nolive_app/src/shared/application/provider_catalog_use_cases.dart';

class RoomPreviewDependencies {
  const RoomPreviewDependencies({
    required this.followWatchlistSnapshot,
    required this.playerRuntime,
    required this.loadRoom,
    required this.openRoomDanmaku,
    required this.resolvePlaySource,
    required this.loadFollowWatchlist,
    required this.listFollowRecords,
    required this.toggleFollowRoom,
    required this.isFollowedRoom,
    required this.findProviderDescriptorById,
    required this.loadBlockedKeywords,
    required this.loadDanmakuPreferences,
    required this.loadRoomUiPreferences,
    required this.updateRoomUiPreferences,
    required this.loadPlayerPreferences,
    required this.updatePlayerPreferences,
    required this.fullscreenSessionPlatforms,
    required this.isLiveMode,
  });

  factory RoomPreviewDependencies.fromBootstrap(
    AppBootstrap bootstrap, {
    BasePlayer? playerOverride,
  }) {
    return RoomPreviewDependencies(
      followWatchlistSnapshot: bootstrap.followWatchlistSnapshot,
      playerRuntime: playerOverride == null
          ? bootstrap.playerRuntime
          : PlayerRuntimeController(playerOverride),
      loadRoom: bootstrap.loadRoom,
      openRoomDanmaku: bootstrap.openRoomDanmaku,
      resolvePlaySource: bootstrap.resolvePlaySource,
      loadFollowWatchlist: bootstrap.loadFollowWatchlist,
      listFollowRecords: bootstrap.listFollowRecords,
      toggleFollowRoom: bootstrap.toggleFollowRoom,
      isFollowedRoom: bootstrap.isFollowedRoom,
      findProviderDescriptorById: bootstrap.findProviderDescriptorById,
      loadBlockedKeywords: bootstrap.loadBlockedKeywords,
      loadDanmakuPreferences: bootstrap.loadDanmakuPreferences,
      loadRoomUiPreferences: bootstrap.loadRoomUiPreferences,
      updateRoomUiPreferences: bootstrap.updateRoomUiPreferences,
      loadPlayerPreferences: bootstrap.loadPlayerPreferences,
      updatePlayerPreferences: bootstrap.updatePlayerPreferences,
      fullscreenSessionPlatforms: RoomFullscreenSessionPlatforms.defaults(),
      isLiveMode: bootstrap.isLiveMode,
    );
  }

  final ValueNotifier<FollowWatchlist?> followWatchlistSnapshot;
  final PlayerRuntimeController playerRuntime;
  final LoadRoomUseCase loadRoom;
  final OpenRoomDanmakuUseCase openRoomDanmaku;
  final ResolvePlaySourceUseCase resolvePlaySource;
  final LoadFollowWatchlistUseCase loadFollowWatchlist;
  final ListFollowRecordsUseCase listFollowRecords;
  final ToggleFollowRoomUseCase toggleFollowRoom;
  final IsFollowedRoomUseCase isFollowedRoom;
  final FindProviderDescriptorByIdUseCase findProviderDescriptorById;
  final LoadBlockedKeywordsUseCase loadBlockedKeywords;
  final LoadDanmakuPreferencesUseCase loadDanmakuPreferences;
  final LoadRoomUiPreferencesUseCase loadRoomUiPreferences;
  final UpdateRoomUiPreferencesUseCase updateRoomUiPreferences;
  final LoadPlayerPreferencesUseCase loadPlayerPreferences;
  final UpdatePlayerPreferencesUseCase updatePlayerPreferences;
  final RoomFullscreenSessionPlatforms fullscreenSessionPlatforms;
  final bool isLiveMode;
}

class RoomSessionDependencies {
  const RoomSessionDependencies({
    required this.playerRuntime,
    required this.loadRoom,
    required this.resolvePlaySource,
    required this.loadPlayerPreferences,
    required this.loadBlockedKeywords,
    required this.loadDanmakuPreferences,
    required this.loadRoomUiPreferences,
  });

  factory RoomSessionDependencies.fromPreviewDependencies(
    RoomPreviewDependencies dependencies,
  ) {
    return RoomSessionDependencies(
      playerRuntime: dependencies.playerRuntime,
      loadRoom: dependencies.loadRoom,
      resolvePlaySource: dependencies.resolvePlaySource,
      loadPlayerPreferences: dependencies.loadPlayerPreferences,
      loadBlockedKeywords: dependencies.loadBlockedKeywords,
      loadDanmakuPreferences: dependencies.loadDanmakuPreferences,
      loadRoomUiPreferences: dependencies.loadRoomUiPreferences,
    );
  }

  final PlayerRuntimeController playerRuntime;
  final LoadRoomUseCase loadRoom;
  final ResolvePlaySourceUseCase resolvePlaySource;
  final LoadPlayerPreferencesUseCase loadPlayerPreferences;
  final LoadBlockedKeywordsUseCase loadBlockedKeywords;
  final LoadDanmakuPreferencesUseCase loadDanmakuPreferences;
  final LoadRoomUiPreferencesUseCase loadRoomUiPreferences;
}

class RoomAncillaryDependencies {
  const RoomAncillaryDependencies({
    required this.openRoomDanmaku,
    required this.isFollowedRoom,
  });

  factory RoomAncillaryDependencies.fromPreviewDependencies(
    RoomPreviewDependencies dependencies,
  ) {
    return RoomAncillaryDependencies(
      openRoomDanmaku: dependencies.openRoomDanmaku,
      isFollowedRoom: dependencies.isFollowedRoom,
    );
  }

  final OpenRoomDanmakuUseCase openRoomDanmaku;
  final IsFollowedRoomUseCase isFollowedRoom;
}

class RoomFollowWatchlistDependencies {
  const RoomFollowWatchlistDependencies({
    required this.followWatchlistSnapshot,
    required this.loadFollowWatchlist,
  });

  factory RoomFollowWatchlistDependencies.fromPreviewDependencies(
    RoomPreviewDependencies dependencies,
  ) {
    return RoomFollowWatchlistDependencies(
      followWatchlistSnapshot: dependencies.followWatchlistSnapshot,
      loadFollowWatchlist: dependencies.loadFollowWatchlist,
    );
  }

  final ValueNotifier<FollowWatchlist?> followWatchlistSnapshot;
  final LoadFollowWatchlistUseCase loadFollowWatchlist;
}

class RoomDanmakuDependencies {
  const RoomDanmakuDependencies({
    required this.openRoomDanmaku,
  });

  factory RoomDanmakuDependencies.fromPreviewDependencies(
    RoomPreviewDependencies dependencies,
  ) {
    return RoomDanmakuDependencies(
      openRoomDanmaku: dependencies.openRoomDanmaku,
    );
  }

  final OpenRoomDanmakuUseCase openRoomDanmaku;
}

class RoomFollowActionDependencies {
  const RoomFollowActionDependencies({
    required this.followWatchlistSnapshot,
    required this.toggleFollowRoom,
    required this.listFollowRecords,
    required this.findProviderDescriptorById,
  });

  factory RoomFollowActionDependencies.fromPreviewDependencies(
    RoomPreviewDependencies dependencies,
  ) {
    return RoomFollowActionDependencies(
      followWatchlistSnapshot: dependencies.followWatchlistSnapshot,
      toggleFollowRoom: dependencies.toggleFollowRoom,
      listFollowRecords: dependencies.listFollowRecords,
      findProviderDescriptorById: dependencies.findProviderDescriptorById,
    );
  }

  final ValueNotifier<FollowWatchlist?> followWatchlistSnapshot;
  final ToggleFollowRoomUseCase toggleFollowRoom;
  final ListFollowRecordsUseCase listFollowRecords;
  final FindProviderDescriptorByIdUseCase findProviderDescriptorById;
}
