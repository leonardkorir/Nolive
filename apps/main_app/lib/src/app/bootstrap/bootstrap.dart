import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:live_player/live_player.dart';
import 'package:live_providers/live_providers.dart';
import 'package:live_storage/live_storage.dart';
import 'package:live_sync/live_sync.dart';
import 'package:path_provider/path_provider.dart';
import 'package:nolive_app/src/app/bootstrap/default_state.dart';
import 'package:nolive_app/src/app/platform/douyin_danmaku_signature_service.dart';
import 'package:nolive_app/src/features/browse/application/load_provider_highlights_use_case.dart';
import 'package:nolive_app/src/features/category/application/load_category_rooms_use_case.dart';
import 'package:nolive_app/src/features/category/application/load_provider_categories_use_case.dart';
import 'package:nolive_app/src/features/home/application/list_available_providers_use_case.dart';
import 'package:nolive_app/src/features/home/application/load_home_dashboard_use_case.dart';
import 'package:nolive_app/src/features/home/application/load_provider_recommend_rooms_use_case.dart';
import 'package:nolive_app/src/features/home/application/load_reference_room_preview_use_case.dart';
import 'package:nolive_app/src/features/library/application/clear_history_use_case.dart';
import 'package:nolive_app/src/features/library/application/clear_tags_use_case.dart';
import 'package:nolive_app/src/features/library/application/create_tag_use_case.dart';
import 'package:nolive_app/src/features/library/application/is_followed_room_use_case.dart';
import 'package:nolive_app/src/features/library/application/list_library_snapshot_use_case.dart';
import 'package:nolive_app/src/features/library/application/list_tags_use_case.dart';
import 'package:nolive_app/src/features/library/application/load_follow_watchlist_use_case.dart';
import 'package:nolive_app/src/features/library/application/load_library_dashboard_use_case.dart';
import 'package:nolive_app/src/features/library/application/manage_follow_transfer_use_case.dart';
import 'package:nolive_app/src/features/library/application/remove_follow_room_use_case.dart';
import 'package:nolive_app/src/features/library/application/remove_history_record_use_case.dart';
import 'package:nolive_app/src/features/library/application/remove_tag_use_case.dart';
import 'package:nolive_app/src/features/library/application/toggle_follow_room_use_case.dart';
import 'package:nolive_app/src/features/library/application/update_follow_tags_use_case.dart';
import 'package:nolive_app/src/features/parse/application/inspect_parsed_room_use_case.dart';
import 'package:nolive_app/src/features/parse/application/parse_room_input_use_case.dart';
import 'package:nolive_app/src/features/profile/application/clear_follows_use_case.dart';
import 'package:nolive_app/src/features/profile/application/manage_blocked_keywords_use_case.dart';
import 'package:nolive_app/src/features/profile/application/manage_theme_mode_use_case.dart';
import 'package:nolive_app/src/features/room/application/chaturbate_web_room_detail_loader.dart';
import 'package:nolive_app/src/features/room/application/load_room_use_case.dart';
import 'package:nolive_app/src/features/room/application/open_room_danmaku_use_case.dart';
import 'package:nolive_app/src/features/room/application/resolve_play_source_use_case.dart';
import 'package:nolive_app/src/features/room/application/twitch_ad_guard_proxy.dart';
import 'package:nolive_app/src/features/room/application/twitch_web_playback_bridge.dart';
import 'package:nolive_app/src/features/search/application/search_provider_rooms_use_case.dart';
import 'package:nolive_app/src/features/settings/application/load_sync_snapshot_use_case.dart';
import 'package:nolive_app/src/features/settings/application/manage_danmaku_preferences_use_case.dart';
import 'package:nolive_app/src/features/settings/application/manage_follow_preferences_use_case.dart';
import 'package:nolive_app/src/features/settings/application/manage_history_preferences_use_case.dart';
import 'package:nolive_app/src/features/settings/application/manage_layout_preferences_use_case.dart';
import 'package:nolive_app/src/features/settings/application/manage_player_preferences_use_case.dart';
import 'package:nolive_app/src/features/settings/application/manage_provider_accounts_use_case.dart';
import 'package:nolive_app/src/features/settings/application/manage_room_ui_preferences_use_case.dart';
import 'package:nolive_app/src/features/settings/application/manage_snapshot_data_use_case.dart';
import 'package:nolive_app/src/features/sync/application/manage_local_sync_use_case.dart';
import 'package:nolive_app/src/features/sync/application/manage_remote_sync_use_case.dart';
import 'package:nolive_app/src/features/sync/application/sync_preferences_use_case.dart';

part 'bootstrap_internals.dart';

enum AppRuntimeMode { preview, live }

AppBootstrap createAppBootstrap({
  AppRuntimeMode mode = AppRuntimeMode.preview,
  BilibiliAccountClient? bilibiliAccountClient,
  DouyinAccountClient? douyinAccountClient,
}) {
  final repositories = _BootstrapRepositories.inMemory();
  final state = _BootstrapStateBundle();

  seedDefaultAppState(
    settingsRepository: repositories.settingsRepository,
    tagRepository: repositories.tagRepository,
    themeModeNotifier: state.themeMode,
  );

  return _assembleAppBootstrap(
    _BootstrapAssemblyContext(
      mode: mode,
      state: state,
      repositories: repositories,
      settings: _BootstrapSettingReaders.fromSnapshot(
        repositories.settingsSnapshot,
      ),
      accountClients: _BootstrapAccountClients(
        bilibili: bilibiliAccountClient ?? HttpBilibiliAccountClient(),
        douyin: douyinAccountClient ?? HttpDouyinAccountClient(),
      ),
    ),
  );
}

Future<AppBootstrap> createPersistentAppBootstrap({
  AppRuntimeMode mode = AppRuntimeMode.live,
  Directory? storageDirectory,
  BilibiliAccountClient? bilibiliAccountClient,
  DouyinAccountClient? douyinAccountClient,
}) async {
  final resolvedDirectory =
      storageDirectory ?? await getApplicationSupportDirectory();
  final storageFile = await _resolveStorageFile(resolvedDirectory);
  final store = await LocalStorageFileStore.open(file: storageFile);
  final repositories = _BootstrapRepositories.persistent(store);
  final state = _BootstrapStateBundle();

  await ensureDefaultAppState(
    settingsRepository: repositories.settingsRepository,
    tagRepository: repositories.tagRepository,
    themeModeNotifier: state.themeMode,
  );
  await syncLayoutPreferencesNotifierFromSettings(
    settingsRepository: repositories.settingsRepository,
    preferencesNotifier: state.layoutPreferences,
  );

  return _assembleAppBootstrap(
    _BootstrapAssemblyContext(
      mode: mode,
      state: state,
      repositories: repositories,
      settings: _BootstrapSettingReaders.fromSnapshot(
        repositories.settingsSnapshot,
      ),
      accountClients: _BootstrapAccountClients(
        bilibili: bilibiliAccountClient ?? HttpBilibiliAccountClient(),
        douyin: douyinAccountClient ?? HttpDouyinAccountClient(),
      ),
    ),
  );
}

class AppBootstrap {
  const AppBootstrap({
    required this.mode,
    required this.themeMode,
    required this.layoutPreferences,
    required this.providerCatalogRevision,
    required this.followDataRevision,
    required this.followWatchlistSnapshot,
    required this.providerRegistry,
    required this.player,
    required this.settingsRepository,
    required this.historyRepository,
    required this.followRepository,
    required this.tagRepository,
    required this.listAvailableProviders,
    required this.loadLayoutPreferences,
    required this.updateLayoutPreferences,
    required this.loadReferenceRoomPreview,
    required this.loadHomeDashboard,
    required this.loadProviderHighlights,
    required this.loadProviderRecommendRooms,
    required this.loadProviderCategories,
    required this.loadCategoryRooms,
    required this.loadRoom,
    required this.openRoomDanmaku,
    required this.resolvePlaySource,
    required this.searchProviderRooms,
    required this.listLibrarySnapshot,
    required this.loadLibraryDashboard,
    required this.loadFollowWatchlist,
    required this.loadFollowPreferences,
    required this.updateFollowPreferences,
    required this.loadHistoryPreferences,
    required this.updateHistoryPreferences,
    required this.exportFollowListJson,
    required this.importFollowListJson,
    required this.toggleFollowRoom,
    required this.isFollowedRoom,
    required this.listTags,
    required this.createTag,
    required this.removeTag,
    required this.clearTags,
    required this.updateFollowTags,
    required this.removeFollowRoom,
    required this.removeHistoryRecord,
    required this.clearHistory,
    required this.loadSyncSnapshot,
    required this.loadSyncPreferences,
    required this.updateSyncPreferences,
    required this.verifyWebDavConnection,
    required this.uploadWebDavSnapshot,
    required this.restoreWebDavSnapshot,
    required this.pushLocalSyncSnapshot,
    required this.loadProviderAccountSettings,
    required this.updateProviderAccountSettings,
    required this.loadProviderAccountDashboard,
    required this.createBilibiliQrLoginSession,
    required this.pollBilibiliQrLoginSession,
    required this.clearProviderAccount,
    required this.localDiscoveryService,
    required this.localSyncServer,
    required this.localSyncClient,
    required this.exportLegacyConfigJson,
    required this.exportSyncSnapshotJson,
    required this.importSyncSnapshotJson,
    required this.resetAppData,
    required this.updateThemeMode,
    required this.loadBlockedKeywords,
    required this.addBlockedKeyword,
    required this.removeBlockedKeyword,
    required this.loadDanmakuPreferences,
    required this.updateDanmakuPreferences,
    required this.clearFollows,
    required this.loadRoomUiPreferences,
    required this.updateRoomUiPreferences,
    required this.loadPlayerPreferences,
    required this.updatePlayerPreferences,
    required this.parseRoomInput,
    required this.inspectParsedRoom,
  });

  final AppRuntimeMode mode;
  final ValueNotifier<ThemeMode> themeMode;
  final ValueNotifier<LayoutPreferences> layoutPreferences;
  final ValueNotifier<int> providerCatalogRevision;
  final ValueNotifier<int> followDataRevision;
  final ValueNotifier<FollowWatchlist?> followWatchlistSnapshot;
  final ProviderRegistry providerRegistry;
  final BasePlayer player;
  final SettingsRepository settingsRepository;
  final HistoryRepository historyRepository;
  final FollowRepository followRepository;
  final TagRepository tagRepository;
  final ListAvailableProvidersUseCase listAvailableProviders;
  final LoadLayoutPreferencesUseCase loadLayoutPreferences;
  final UpdateLayoutPreferencesUseCase updateLayoutPreferences;
  final LoadReferenceRoomPreviewUseCase loadReferenceRoomPreview;
  final LoadHomeDashboardUseCase loadHomeDashboard;
  final LoadProviderHighlightsUseCase loadProviderHighlights;
  final LoadProviderRecommendRoomsUseCase loadProviderRecommendRooms;
  final LoadProviderCategoriesUseCase loadProviderCategories;
  final LoadCategoryRoomsUseCase loadCategoryRooms;
  final LoadRoomUseCase loadRoom;
  final OpenRoomDanmakuUseCase openRoomDanmaku;
  final ResolvePlaySourceUseCase resolvePlaySource;
  final SearchProviderRoomsUseCase searchProviderRooms;
  final ListLibrarySnapshotUseCase listLibrarySnapshot;
  final LoadLibraryDashboardUseCase loadLibraryDashboard;
  final LoadFollowWatchlistUseCase loadFollowWatchlist;
  final LoadFollowPreferencesUseCase loadFollowPreferences;
  final UpdateFollowPreferencesUseCase updateFollowPreferences;
  final LoadHistoryPreferencesUseCase loadHistoryPreferences;
  final UpdateHistoryPreferencesUseCase updateHistoryPreferences;
  final ExportFollowListJsonUseCase exportFollowListJson;
  final ImportFollowListJsonUseCase importFollowListJson;
  final ToggleFollowRoomUseCase toggleFollowRoom;
  final IsFollowedRoomUseCase isFollowedRoom;
  final ListTagsUseCase listTags;
  final CreateTagUseCase createTag;
  final RemoveTagUseCase removeTag;
  final ClearTagsUseCase clearTags;
  final UpdateFollowTagsUseCase updateFollowTags;
  final RemoveFollowRoomUseCase removeFollowRoom;
  final RemoveHistoryRecordUseCase removeHistoryRecord;
  final ClearHistoryUseCase clearHistory;
  final LoadSyncSnapshotUseCase loadSyncSnapshot;
  final LoadSyncPreferencesUseCase loadSyncPreferences;
  final UpdateSyncPreferencesUseCase updateSyncPreferences;
  final VerifyWebDavConnectionUseCase verifyWebDavConnection;
  final UploadWebDavSnapshotUseCase uploadWebDavSnapshot;
  final RestoreWebDavSnapshotUseCase restoreWebDavSnapshot;
  final PushLocalSyncSnapshotUseCase pushLocalSyncSnapshot;
  final LoadProviderAccountSettingsUseCase loadProviderAccountSettings;
  final UpdateProviderAccountSettingsUseCase updateProviderAccountSettings;
  final LoadProviderAccountDashboardUseCase loadProviderAccountDashboard;
  final CreateBilibiliQrLoginSessionUseCase createBilibiliQrLoginSession;
  final PollBilibiliQrLoginSessionUseCase pollBilibiliQrLoginSession;
  final ClearProviderAccountUseCase clearProviderAccount;
  final ManualLocalDiscoveryService localDiscoveryService;
  final HttpLocalSyncServer localSyncServer;
  final HttpLocalSyncClient localSyncClient;
  final ExportLegacyConfigJsonUseCase exportLegacyConfigJson;
  final ExportSyncSnapshotJsonUseCase exportSyncSnapshotJson;
  final ImportSyncSnapshotJsonUseCase importSyncSnapshotJson;
  final ResetAppDataUseCase resetAppData;
  final UpdateThemeModeUseCase updateThemeMode;
  final LoadBlockedKeywordsUseCase loadBlockedKeywords;
  final AddBlockedKeywordUseCase addBlockedKeyword;
  final RemoveBlockedKeywordUseCase removeBlockedKeyword;
  final LoadDanmakuPreferencesUseCase loadDanmakuPreferences;
  final UpdateDanmakuPreferencesUseCase updateDanmakuPreferences;
  final ClearFollowsUseCase clearFollows;
  final LoadRoomUiPreferencesUseCase loadRoomUiPreferences;
  final UpdateRoomUiPreferencesUseCase updateRoomUiPreferences;
  final LoadPlayerPreferencesUseCase loadPlayerPreferences;
  final UpdatePlayerPreferencesUseCase updatePlayerPreferences;
  final ParseRoomInputUseCase parseRoomInput;
  final InspectParsedRoomUseCase inspectParsedRoom;

  bool get isLiveMode => mode == AppRuntimeMode.live;
}
