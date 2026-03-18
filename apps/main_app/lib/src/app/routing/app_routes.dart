import 'package:live_core/live_core.dart';

class AppRoutes {
  const AppRoutes._();

  static const home = '/';
  static const room = '/room';
  static const providerCategories = '/discover/categories';
  static const syncCenter = '/sync';
  static const syncWebDav = '/sync/webdav';
  static const syncLocal = '/sync/local';
  static const settings = '/settings';
  static const appearanceSettings = '/settings/appearance';
  static const layoutSettings = '/settings/layout';
  static const roomSettings = '/settings/room';
  static const playerSettings = '/settings/player';
  static const danmakuSettings = '/settings/danmaku';
  static const accountSettings = '/settings/accounts';
  static const bilibiliQrLogin = '/settings/accounts/bilibili/qr';
  static const followSettings = '/settings/follow';
  static const danmakuShield = '/settings/danmaku/shield';
  static const otherSettings = '/settings/other';
  static const disclaimer = '/settings/disclaimer';
  static const releaseInfo = '/settings/release';
  static const watchHistory = '/library/history';
  static const parseRoom = '/tools/parse-room';
}

class RoomRouteArguments {
  const RoomRouteArguments({
    required this.providerId,
    required this.roomId,
  });

  final ProviderId providerId;
  final String roomId;
}

class ProviderCategoriesRouteArguments {
  const ProviderCategoriesRouteArguments({
    required this.providerId,
    this.initialCategoryId,
  });

  final ProviderId providerId;
  final String? initialCategoryId;
}
