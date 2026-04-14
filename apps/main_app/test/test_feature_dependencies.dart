import 'package:nolive_app/src/app/bootstrap/bootstrap.dart';
import 'package:nolive_app/src/app/home/application/home_feature_dependencies.dart';
import 'package:nolive_app/src/app/shell/app_shell_dependencies.dart';
import 'package:nolive_app/src/features/browse/application/browse_feature_dependencies.dart';
import 'package:nolive_app/src/features/category/application/category_feature_dependencies.dart';
import 'package:nolive_app/src/features/library/application/library_feature_dependencies.dart';
import 'package:nolive_app/src/features/library/application/watch_history_feature_dependencies.dart';
import 'package:nolive_app/src/features/parse/application/parse_feature_dependencies.dart';
import 'package:nolive_app/src/features/search/application/search_feature_dependencies.dart';
import 'package:nolive_app/src/features/settings/application/settings_page_dependencies.dart';

SearchFeatureDependencies buildSearchFeatureDependencies(
  AppBootstrap bootstrap,
) {
  return SearchFeatureDependencies(
    layoutPreferences: bootstrap.layoutPreferences,
    providerCatalogRevision: bootstrap.providerCatalogRevision,
    listAvailableProviders: bootstrap.listAvailableProviders,
    searchProviderRooms: bootstrap.searchProviderRooms,
  );
}

HomeFeatureDependencies buildHomeFeatureDependencies(AppBootstrap bootstrap) {
  return HomeFeatureDependencies(
    layoutPreferences: bootstrap.layoutPreferences,
    providerCatalogRevision: bootstrap.providerCatalogRevision,
    listAvailableProviders: bootstrap.listAvailableProviders,
    loadProviderRecommendRooms: bootstrap.loadProviderRecommendRooms,
    searchDependencies: buildSearchFeatureDependencies(bootstrap),
  );
}

BrowseFeatureDependencies buildBrowseFeatureDependencies(
    AppBootstrap bootstrap) {
  return BrowseFeatureDependencies(
    layoutPreferences: bootstrap.layoutPreferences,
    providerCatalogRevision: bootstrap.providerCatalogRevision,
    listAvailableProviders: bootstrap.listAvailableProviders,
    loadProviderHighlights: bootstrap.loadProviderHighlights,
    loadProviderCategories: bootstrap.loadProviderCategories,
    loadFavoriteCategoryTags: bootstrap.loadFavoriteCategoryTags,
    searchDependencies: buildSearchFeatureDependencies(bootstrap),
  );
}

CategoryFeatureDependencies buildCategoryFeatureDependencies(
  AppBootstrap bootstrap,
) {
  return CategoryFeatureDependencies(
    loadProviderCategories: bootstrap.loadProviderCategories,
    loadFavoriteCategoryTags: bootstrap.loadFavoriteCategoryTags,
    toggleFavoriteCategoryTag: bootstrap.toggleFavoriteCategoryTag,
    loadCategoryRooms: bootstrap.loadCategoryRooms,
    searchDependencies: buildSearchFeatureDependencies(bootstrap),
  );
}

LibraryFeatureDependencies buildLibraryFeatureDependencies(
  AppBootstrap bootstrap,
) {
  return LibraryFeatureDependencies(
    followDataRevision: bootstrap.followDataRevision,
    followWatchlistSnapshot: bootstrap.followWatchlistSnapshot,
    listFollowRecords: bootstrap.listFollowRecords,
    listTags: bootstrap.listTags,
    loadFollowPreferences: bootstrap.loadFollowPreferences,
    updateFollowPreferences: bootstrap.updateFollowPreferences,
    loadFollowWatchlist: bootstrap.loadFollowWatchlist,
    removeFollowRoom: bootstrap.removeFollowRoom,
    createTag: bootstrap.createTag,
    updateFollowTags: bootstrap.updateFollowTags,
    findProviderDescriptorById: bootstrap.findProviderDescriptorById,
  );
}

WatchHistoryFeatureDependencies buildWatchHistoryFeatureDependencies(
  AppBootstrap bootstrap,
) {
  return WatchHistoryFeatureDependencies(
    listLibrarySnapshot: bootstrap.listLibrarySnapshot,
    loadHistoryPreferences: bootstrap.loadHistoryPreferences,
    updateHistoryPreferences: bootstrap.updateHistoryPreferences,
    removeHistoryRecord: bootstrap.removeHistoryRecord,
    clearHistory: bootstrap.clearHistory,
    findProviderDescriptorById: bootstrap.findProviderDescriptorById,
  );
}

ParseFeatureDependencies buildParseFeatureDependencies(AppBootstrap bootstrap) {
  return ParseFeatureDependencies(
    listProviderDescriptors: bootstrap.listProviderDescriptors,
    parseRoomInput: bootstrap.parseRoomInput,
    inspectParsedRoom: bootstrap.inspectParsedRoom,
  );
}

AppearanceSettingsDependencies buildAppearanceSettingsDependencies(
  AppBootstrap bootstrap,
) {
  return AppearanceSettingsDependencies(
    themeMode: bootstrap.themeMode,
    updateThemeMode: bootstrap.updateThemeMode,
  );
}

LayoutSettingsDependencies buildLayoutSettingsDependencies(
  AppBootstrap bootstrap,
) {
  return LayoutSettingsDependencies(
    layoutPreferences: bootstrap.layoutPreferences,
    updateLayoutPreferences: bootstrap.updateLayoutPreferences,
    findProviderDescriptorById: bootstrap.findProviderDescriptorById,
  );
}

RoomSettingsDependencies buildRoomSettingsDependencies(AppBootstrap bootstrap) {
  return RoomSettingsDependencies(
    loadRoomUiPreferences: bootstrap.loadRoomUiPreferences,
    updateRoomUiPreferences: bootstrap.updateRoomUiPreferences,
    loadPlayerPreferences: bootstrap.loadPlayerPreferences,
    updatePlayerPreferences: bootstrap.updatePlayerPreferences,
  );
}

PlayerSettingsDependencies buildPlayerSettingsDependencies(
  AppBootstrap bootstrap,
) {
  return PlayerSettingsDependencies(
    loadPlayerPreferences: bootstrap.loadPlayerPreferences,
    updatePlayerPreferences: bootstrap.updatePlayerPreferences,
    applyPlayerPreferencesToRuntime: bootstrap.applyPlayerPreferencesToRuntime,
    playerRuntime: bootstrap.playerRuntime,
    isLiveMode: bootstrap.isLiveMode,
  );
}

DanmakuSettingsDependencies buildDanmakuSettingsDependencies(
  AppBootstrap bootstrap,
) {
  return DanmakuSettingsDependencies(
    loadDanmakuPreferences: bootstrap.loadDanmakuPreferences,
    updateDanmakuPreferences: bootstrap.updateDanmakuPreferences,
    loadBlockedKeywords: bootstrap.loadBlockedKeywords,
  );
}

DanmakuShieldDependencies buildDanmakuShieldDependencies(
  AppBootstrap bootstrap,
) {
  return DanmakuShieldDependencies(
    loadBlockedKeywords: bootstrap.loadBlockedKeywords,
    addBlockedKeyword: bootstrap.addBlockedKeyword,
    removeBlockedKeyword: bootstrap.removeBlockedKeyword,
  );
}

FollowSettingsDependencies buildFollowSettingsDependencies(
  AppBootstrap bootstrap,
) {
  return FollowSettingsDependencies(
    loadLibraryDashboard: bootstrap.loadLibraryDashboard,
    loadFollowPreferences: bootstrap.loadFollowPreferences,
    updateFollowPreferences: bootstrap.updateFollowPreferences,
    exportFollowListJson: bootstrap.exportFollowListJson,
    importFollowListJson: bootstrap.importFollowListJson,
    removeTag: bootstrap.removeTag,
    createTag: bootstrap.createTag,
    clearFollows: bootstrap.clearFollows,
    clearHistory: bootstrap.clearHistory,
    clearTags: bootstrap.clearTags,
  );
}

AppShellDependencies buildAppShellDependencies(AppBootstrap bootstrap) {
  return AppShellDependencies(
    home: buildHomeFeatureDependencies(bootstrap),
    browse: buildBrowseFeatureDependencies(bootstrap),
    library: buildLibraryFeatureDependencies(bootstrap),
  );
}
