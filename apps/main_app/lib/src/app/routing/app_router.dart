import 'package:flutter/material.dart';
import 'package:nolive_app/src/app/bootstrap/bootstrap.dart';
import 'package:nolive_app/src/app/routing/app_routes.dart';
import 'package:nolive_app/src/app/shell/app_shell_page.dart';
import 'package:nolive_app/src/features/category/presentation/provider_categories_page.dart';
import 'package:nolive_app/src/features/library/presentation/watch_history_page.dart';
import 'package:nolive_app/src/features/parse/presentation/parse_room_page.dart';
import 'package:nolive_app/src/features/room/presentation/room_preview_page.dart';
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
          builder: (_) => AppShellPage(bootstrap: bootstrap),
        );
      case AppRoutes.room:
        final arguments = settings.arguments;
        if (arguments is! RoomRouteArguments) {
          return _errorRoute('缺少房间路由参数');
        }
        return _buildRoute(
          settings: settings,
          builder: (_) => RoomPreviewPage(
            bootstrap: bootstrap,
            providerId: arguments.providerId,
            roomId: arguments.roomId,
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
            bootstrap: bootstrap,
            providerId: arguments.providerId,
            initialCategoryId: arguments.initialCategoryId,
          ),
        );
      case AppRoutes.syncCenter:
        return _buildRoute(
          settings: settings,
          builder: (_) => SyncCenterPage(bootstrap: bootstrap),
        );
      case AppRoutes.syncWebDav:
        return _buildRoute(
          settings: settings,
          builder: (_) => SyncWebDavPage(bootstrap: bootstrap),
        );
      case AppRoutes.syncLocal:
        return _buildRoute(
          settings: settings,
          builder: (_) => SyncLocalPage(bootstrap: bootstrap),
        );
      case AppRoutes.settings:
        return _buildRoute(
          settings: settings,
          builder: (_) => SettingsPage(bootstrap: bootstrap),
        );
      case AppRoutes.appearanceSettings:
        return _buildRoute(
          settings: settings,
          builder: (_) => AppearanceSettingsPage(bootstrap: bootstrap),
        );
      case AppRoutes.layoutSettings:
        return _buildRoute(
          settings: settings,
          builder: (_) => LayoutSettingsPage(bootstrap: bootstrap),
        );
      case AppRoutes.roomSettings:
        return _buildRoute(
          settings: settings,
          builder: (_) => RoomSettingsPage(bootstrap: bootstrap),
        );
      case AppRoutes.playerSettings:
        return _buildRoute(
          settings: settings,
          builder: (_) => PlayerSettingsPage(bootstrap: bootstrap),
        );
      case AppRoutes.danmakuSettings:
        return _buildRoute(
          settings: settings,
          builder: (_) => DanmakuSettingsPage(bootstrap: bootstrap),
        );
      case AppRoutes.accountSettings:
        return _buildRoute(
          settings: settings,
          builder: (_) => AccountSettingsPage(bootstrap: bootstrap),
        );
      case AppRoutes.bilibiliQrLogin:
        return _buildRoute(
          settings: settings,
          builder: (_) => BilibiliQrLoginPage(bootstrap: bootstrap),
        );
      case AppRoutes.followSettings:
        return _buildRoute(
          settings: settings,
          builder: (_) => FollowSettingsPage(bootstrap: bootstrap),
        );
      case AppRoutes.danmakuShield:
        return _buildRoute(
          settings: settings,
          builder: (_) => DanmakuShieldPage(bootstrap: bootstrap),
        );
      case AppRoutes.otherSettings:
        return _buildRoute(
          settings: settings,
          builder: (_) => OtherSettingsPage(bootstrap: bootstrap),
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
          builder: (_) => WatchHistoryPage(bootstrap: bootstrap),
        );
      case AppRoutes.parseRoom:
        return _buildRoute(
          settings: settings,
          builder: (_) => ParseRoomPage(bootstrap: bootstrap),
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
}
