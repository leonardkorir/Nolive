import 'package:flutter/material.dart';
import 'package:nolive_app/src/app/routing/app_routes.dart';

/// Navigation entry shared by Settings page (and optional tooling).
@immutable
class AppSettingsEntry {
  const AppSettingsEntry({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.routeName,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String routeName;
}

/// Catalog for the dedicated [SettingsPage] route only.
///
/// Profile「我的」uses [kProfileMenuEntries] — do not dump this list onto Profile.
const List<AppSettingsEntry> kAppSettingsEntries = <AppSettingsEntry>[
  AppSettingsEntry(
    icon: Icons.palette_outlined,
    title: '外观设置',
    subtitle: '主题和显示风格',
    routeName: AppRoutes.appearanceSettings,
  ),
  AppSettingsEntry(
    icon: Icons.home_outlined,
    title: '主页设置',
    subtitle: '底部导航和平台顺序',
    routeName: AppRoutes.layoutSettings,
  ),
  AppSettingsEntry(
    icon: Icons.live_tv_outlined,
    title: '直播间设置',
    subtitle: '房间行为、聊天区样式和观看期常用开关',
    routeName: AppRoutes.roomSettings,
  ),
  AppSettingsEntry(
    icon: Icons.play_circle_outline_rounded,
    title: '播放器设置',
    subtitle: 'MPV / MDK、画质、全屏和 PiP',
    routeName: AppRoutes.playerSettings,
  ),
  AppSettingsEntry(
    icon: Icons.subtitles_outlined,
    title: '弹幕设置',
    subtitle: '屏蔽词和观看干扰项',
    routeName: AppRoutes.danmakuSettings,
  ),
  AppSettingsEntry(
    icon: Icons.account_circle_outlined,
    title: '账号设置',
    subtitle: 'Bilibili 登录和抖音凭据',
    routeName: AppRoutes.accountSettings,
  ),
  AppSettingsEntry(
    icon: Icons.collections_bookmark_outlined,
    title: '关注与历史',
    subtitle: '关注列表、观看历史和标签',
    routeName: AppRoutes.followSettings,
  ),
  AppSettingsEntry(
    icon: Icons.sync_outlined,
    title: '同步中心',
    subtitle: '本地快照、WebDAV 与局域网同步',
    routeName: AppRoutes.syncCenter,
  ),
  AppSettingsEntry(
    icon: Icons.link_rounded,
    title: '房间解析',
    subtitle: '解析直播间链接并立即校验',
    routeName: AppRoutes.parseRoom,
  ),
  AppSettingsEntry(
    icon: Icons.settings_backup_restore_outlined,
    title: '其他设置',
    subtitle: '导入导出、恢复默认和本地维护',
    routeName: AppRoutes.otherSettings,
  ),
];

/// Original「我的」flat menu (product order). No「应用信息」— that was never here.
const List<AppSettingsEntry> kProfileMenuEntries = <AppSettingsEntry>[
  AppSettingsEntry(
    icon: Icons.history_rounded,
    title: '观看记录',
    subtitle: '',
    routeName: AppRoutes.watchHistory,
  ),
  AppSettingsEntry(
    icon: Icons.account_circle_outlined,
    title: '账号管理',
    subtitle: '',
    routeName: AppRoutes.accountSettings,
  ),
  AppSettingsEntry(
    icon: Icons.sync_outlined,
    title: '数据同步',
    subtitle: '',
    routeName: AppRoutes.syncCenter,
  ),
  AppSettingsEntry(
    icon: Icons.link_rounded,
    title: '链接解析',
    subtitle: '',
    routeName: AppRoutes.parseRoom,
  ),
  AppSettingsEntry(
    icon: Icons.dark_mode_outlined,
    title: '外观设置',
    subtitle: '',
    routeName: AppRoutes.appearanceSettings,
  ),
  AppSettingsEntry(
    icon: Icons.home_outlined,
    title: '主页设置',
    subtitle: '',
    routeName: AppRoutes.layoutSettings,
  ),
  AppSettingsEntry(
    icon: Icons.live_tv_outlined,
    title: '直播间设置',
    subtitle: '',
    routeName: AppRoutes.roomSettings,
  ),
  AppSettingsEntry(
    icon: Icons.video_settings_outlined,
    title: '播放器设置',
    subtitle: '',
    routeName: AppRoutes.playerSettings,
  ),
  AppSettingsEntry(
    icon: Icons.subtitles_outlined,
    title: '弹幕设置',
    subtitle: '',
    routeName: AppRoutes.danmakuSettings,
  ),
  AppSettingsEntry(
    icon: Icons.favorite_border_rounded,
    title: '关注设置',
    subtitle: '',
    routeName: AppRoutes.followSettings,
  ),
  AppSettingsEntry(
    icon: Icons.widgets_outlined,
    title: '其他设置',
    subtitle: '',
    routeName: AppRoutes.otherSettings,
  ),
  AppSettingsEntry(
    icon: Icons.info_outline_rounded,
    title: '免责声明',
    subtitle: '',
    routeName: AppRoutes.disclaimer,
  ),
];
