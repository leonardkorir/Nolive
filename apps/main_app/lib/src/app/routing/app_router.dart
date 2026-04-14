import 'package:flutter/material.dart';
import 'package:nolive_app/src/app/bootstrap/bootstrap.dart';
import 'package:nolive_app/src/app/routing/app_routes.dart';
import 'package:nolive_app/src/app/shell/app_shell_dependencies.dart';
import 'package:nolive_app/src/app/shell/app_shell_page.dart';
import 'package:nolive_app/src/app/home/application/home_feature_dependencies.dart';
import 'package:nolive_app/src/features/browse/application/browse_feature_dependencies.dart';
import 'package:nolive_app/src/features/category/application/category_feature_dependencies.dart';
import 'package:nolive_app/src/features/category/presentation/provider_categories_page.dart';
import 'package:nolive_app/src/features/library/application/library_feature_dependencies.dart';
import 'package:nolive_app/src/features/library/application/watch_history_feature_dependencies.dart';
import 'package:nolive_app/src/features/library/presentation/watch_history_page.dart';
import 'package:nolive_app/src/features/parse/application/parse_feature_dependencies.dart';
import 'package:nolive_app/src/features/parse/presentation/parse_room_page.dart';
import 'package:nolive_app/src/features/room/application/room_preview_dependencies.dart';
import 'package:nolive_app/src/features/room/presentation/room_preview_page.dart';
import 'package:nolive_app/src/features/search/application/search_feature_dependencies.dart';
import 'package:nolive_app/src/features/settings/application/settings_feature_dependencies.dart';
import 'package:nolive_app/src/features/settings/application/settings_page_dependencies.dart';
import 'package:nolive_app/src/features/settings/presentation/account_settings_page.dart';
import 'package:nolive_app/src/features/settings/presentation/appearance_settings_page.dart';
import 'package:nolive_app/src/features/settings/presentation/bilibili_qr_login_page.dart';
import 'package:nolive_app/src/features/settings/presentation/danmaku_settings_page.dart';
import 'package:nolive_app/src/features/settings/presentation/disclaimer_page.dart';
import 'package:nolive_app/src/features/settings/presentation/danmaku_shield_page.dart';
import 'package:nolive_app/src/features/settings/presentation/follow_settings_page.dart';
import 'package:nolive_app/src/features/settings/presentation/layout_settings_page.dart';
import 'package:nolive_app/src/features/settings/presentation/other_settings_page.dart';
import 'package:nolive_app/src/features/settings/presentation/player_settings_page.dart';
import 'package:nolive_app/src/features/settings/presentation/room_settings_page.dart';
import 'package:nolive_app/src/features/settings/presentation/release_info_page.dart';
import 'package:nolive_app/src/features/settings/presentation/settings_page.dart';
import 'package:nolive_app/src/features/sync/application/sync_feature_dependencies.dart';
import 'package:nolive_app/src/features/sync/presentation/sync_center_page.dart';
import 'package:nolive_app/src/features/sync/presentation/sync_local_page.dart';
import 'package:nolive_app/src/features/sync/presentation/sync_webdav_page.dart';

class AppRouter {
  const AppRouter(this.bootstrap);

  final AppBootstrap bootstrap;

  Route<dynamic> onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case AppRoutes.home:
        return _buildRoute(
          settings: settings,
          builder: (_) => AppShellPage(
            dependencies: _buildAppShellDependencies(),
          ),
        );
      case AppRoutes.room:
        final arguments = settings.arguments;
        if (arguments is! RoomRouteArguments) {
          return _errorRoute('缺少房间路由参数');
        }
        return _buildRoute(
          settings: settings,
          builder: (_) => RoomPreviewPage(
            dependencies: RoomPreviewDependencies.fromBootstrap(bootstrap),
            providerId: arguments.providerId,
            roomId: arguments.roomId,
            startInFullscreen: arguments.startInFullscreen,
          ),
        );
      case AppRoutes.providerCategories:
        final arguments = settings.arguments;
        if (arguments is! ProviderCategoriesRouteArguments) {
          return _errorRoute('缺少分区路由参数');
        }
        return _buildRoute(
          settings: settings,
          builder: (_) => ProviderCategoriesPage(
            dependencies: _buildCategoryFeatureDependencies(),
            providerId: arguments.providerId,
            initialCategoryId: arguments.initialCategoryId,
          ),
        );
      case AppRoutes.syncCenter:
        return _buildRoute(
          settings: settings,
          builder: (_) => SyncCenterPage(
            dependencies: SyncFeatureDependencies.fromBootstrap(bootstrap),
          ),
        );
      case AppRoutes.syncWebDav:
        return _buildRoute(
          settings: settings,
          builder: (_) => SyncWebDavPage(
            dependencies: SyncFeatureDependencies.fromBootstrap(bootstrap),
          ),
        );
      case AppRoutes.syncLocal:
        return _buildRoute(
          settings: settings,
          builder: (_) => SyncLocalPage(
            dependencies: SyncFeatureDependencies.fromBootstrap(bootstrap),
          ),
        );
      case AppRoutes.settings:
        return _buildRoute(
          settings: settings,
          builder: (_) => const SettingsPage(),
        );
      case AppRoutes.appearanceSettings:
        return _buildRoute(
          settings: settings,
          builder: (_) => AppearanceSettingsPage(
            dependencies: _buildAppearanceSettingsDependencies(),
          ),
        );
      case AppRoutes.layoutSettings:
        return _buildRoute(
          settings: settings,
          builder: (_) => LayoutSettingsPage(
            dependencies: _buildLayoutSettingsDependencies(),
          ),
        );
      case AppRoutes.roomSettings:
        return _buildRoute(
          settings: settings,
          builder: (_) => RoomSettingsPage(
            dependencies: _buildRoomSettingsDependencies(),
          ),
        );
      case AppRoutes.playerSettings:
        return _buildRoute(
          settings: settings,
          builder: (_) => PlayerSettingsPage(
            dependencies: _buildPlayerSettingsDependencies(),
          ),
        );
      case AppRoutes.danmakuSettings:
        return _buildRoute(
          settings: settings,
          builder: (_) => DanmakuSettingsPage(
            dependencies: _buildDanmakuSettingsDependencies(),
          ),
        );
      case AppRoutes.accountSettings:
        return _buildRoute(
          settings: settings,
          builder: (_) => AccountSettingsPage(
            dependencies: SettingsFeatureDependencies.fromBootstrap(bootstrap),
          ),
        );
      case AppRoutes.bilibiliQrLogin:
        return _buildRoute(
          settings: settings,
          builder: (_) => BilibiliQrLoginPage(
            dependencies: SettingsFeatureDependencies.fromBootstrap(bootstrap),
          ),
        );
      case AppRoutes.followSettings:
        return _buildRoute(
          settings: settings,
          builder: (_) => FollowSettingsPage(
            dependencies: _buildFollowSettingsDependencies(),
          ),
        );
      case AppRoutes.danmakuShield:
        return _buildRoute(
          settings: settings,
          builder: (_) => DanmakuShieldPage(
            dependencies: _buildDanmakuShieldDependencies(),
          ),
        );
      case AppRoutes.otherSettings:
        return _buildRoute(
          settings: settings,
          builder: (_) => OtherSettingsPage(
            dependencies: SettingsFeatureDependencies.fromBootstrap(bootstrap),
          ),
        );
      case AppRoutes.disclaimer:
        return _buildRoute(
          settings: settings,
          builder: (_) => const DisclaimerPage(),
        );
      case AppRoutes.releaseInfo:
        return _buildRoute(
          settings: settings,
          builder: (_) => const ReleaseInfoPage(),
        );
      case AppRoutes.watchHistory:
        return _buildRoute(
          settings: settings,
          builder: (_) => WatchHistoryPage(
            dependencies: _buildWatchHistoryFeatureDependencies(),
          ),
        );
      case AppRoutes.parseRoom:
        return _buildRoute(
          settings: settings,
          builder: (_) => ParseRoomPage(
            dependencies: _buildParseFeatureDependencies(),
          ),
        );
      default:
        return _errorRoute('未找到路由：${settings.name}');
    }
  }

  MaterialPageRoute<void> _buildRoute({
    required RouteSettings settings,
    required WidgetBuilder builder,
  }) {
    return MaterialPageRoute<void>(
      settings: settings,
      builder: builder,
    );
  }

  MaterialPageRoute<void> _errorRoute(String message) {
    return MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        appBar: AppBar(title: const Text('路由错误')),
        body: Center(child: Text(message)),
      ),
    );
  }

  AppShellDependencies _buildAppShellDependencies() {
    final searchDependencies = _buildSearchFeatureDependencies();
    return AppShellDependencies(
      home: _buildHomeFeatureDependencies(
        searchDependencies: searchDependencies,
      ),
      browse: _buildBrowseFeatureDependencies(
        searchDependencies: searchDependencies,
      ),
      library: _buildLibraryFeatureDependencies(),
    );
  }

  HomeFeatureDependencies _buildHomeFeatureDependencies({
    required SearchFeatureDependencies searchDependencies,
  }) {
    return HomeFeatureDependencies(
      layoutPreferences: bootstrap.layoutPreferences,
      providerCatalogRevision: bootstrap.providerCatalogRevision,
      listAvailableProviders: bootstrap.listAvailableProviders,
      loadProviderRecommendRooms: bootstrap.loadProviderRecommendRooms,
      searchDependencies: searchDependencies,
    );
  }

  BrowseFeatureDependencies _buildBrowseFeatureDependencies({
    required SearchFeatureDependencies searchDependencies,
  }) {
    return BrowseFeatureDependencies(
      layoutPreferences: bootstrap.layoutPreferences,
      providerCatalogRevision: bootstrap.providerCatalogRevision,
      listAvailableProviders: bootstrap.listAvailableProviders,
      loadProviderHighlights: bootstrap.loadProviderHighlights,
      loadProviderCategories: bootstrap.loadProviderCategories,
      loadFavoriteCategoryTags: bootstrap.loadFavoriteCategoryTags,
      searchDependencies: searchDependencies,
    );
  }

  CategoryFeatureDependencies _buildCategoryFeatureDependencies() {
    return CategoryFeatureDependencies(
      loadProviderCategories: bootstrap.loadProviderCategories,
      loadFavoriteCategoryTags: bootstrap.loadFavoriteCategoryTags,
      toggleFavoriteCategoryTag: bootstrap.toggleFavoriteCategoryTag,
      loadCategoryRooms: bootstrap.loadCategoryRooms,
      searchDependencies: _buildSearchFeatureDependencies(),
    );
  }

  SearchFeatureDependencies _buildSearchFeatureDependencies() {
    return SearchFeatureDependencies(
      layoutPreferences: bootstrap.layoutPreferences,
      providerCatalogRevision: bootstrap.providerCatalogRevision,
      listAvailableProviders: bootstrap.listAvailableProviders,
      searchProviderRooms: bootstrap.searchProviderRooms,
    );
  }

  LibraryFeatureDependencies _buildLibraryFeatureDependencies() {
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

  WatchHistoryFeatureDependencies _buildWatchHistoryFeatureDependencies() {
    return WatchHistoryFeatureDependencies(
      listLibrarySnapshot: bootstrap.listLibrarySnapshot,
      loadHistoryPreferences: bootstrap.loadHistoryPreferences,
      updateHistoryPreferences: bootstrap.updateHistoryPreferences,
      removeHistoryRecord: bootstrap.removeHistoryRecord,
      clearHistory: bootstrap.clearHistory,
      findProviderDescriptorById: bootstrap.findProviderDescriptorById,
    );
  }

  ParseFeatureDependencies _buildParseFeatureDependencies() {
    return ParseFeatureDependencies(
      listProviderDescriptors: bootstrap.listProviderDescriptors,
      parseRoomInput: bootstrap.parseRoomInput,
      inspectParsedRoom: bootstrap.inspectParsedRoom,
    );
  }

  AppearanceSettingsDependencies _buildAppearanceSettingsDependencies() {
    return AppearanceSettingsDependencies(
      themeMode: bootstrap.themeMode,
      updateThemeMode: bootstrap.updateThemeMode,
    );
  }

  LayoutSettingsDependencies _buildLayoutSettingsDependencies() {
    return LayoutSettingsDependencies(
      layoutPreferences: bootstrap.layoutPreferences,
      updateLayoutPreferences: bootstrap.updateLayoutPreferences,
      findProviderDescriptorById: bootstrap.findProviderDescriptorById,
    );
  }

  RoomSettingsDependencies _buildRoomSettingsDependencies() {
    return RoomSettingsDependencies(
      loadRoomUiPreferences: bootstrap.loadRoomUiPreferences,
      updateRoomUiPreferences: bootstrap.updateRoomUiPreferences,
      loadPlayerPreferences: bootstrap.loadPlayerPreferences,
      updatePlayerPreferences: bootstrap.updatePlayerPreferences,
    );
  }

  PlayerSettingsDependencies _buildPlayerSettingsDependencies() {
    return PlayerSettingsDependencies(
      loadPlayerPreferences: bootstrap.loadPlayerPreferences,
      updatePlayerPreferences: bootstrap.updatePlayerPreferences,
      applyPlayerPreferencesToRuntime:
          bootstrap.applyPlayerPreferencesToRuntime,
      playerRuntime: bootstrap.playerRuntime,
      isLiveMode: bootstrap.isLiveMode,
    );
  }

  DanmakuSettingsDependencies _buildDanmakuSettingsDependencies() {
    return DanmakuSettingsDependencies(
      loadDanmakuPreferences: bootstrap.loadDanmakuPreferences,
      updateDanmakuPreferences: bootstrap.updateDanmakuPreferences,
      loadBlockedKeywords: bootstrap.loadBlockedKeywords,
    );
  }

  DanmakuShieldDependencies _buildDanmakuShieldDependencies() {
    return DanmakuShieldDependencies(
      loadBlockedKeywords: bootstrap.loadBlockedKeywords,
      addBlockedKeyword: bootstrap.addBlockedKeyword,
      removeBlockedKeyword: bootstrap.removeBlockedKeyword,
    );
  }

  FollowSettingsDependencies _buildFollowSettingsDependencies() {
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
}
