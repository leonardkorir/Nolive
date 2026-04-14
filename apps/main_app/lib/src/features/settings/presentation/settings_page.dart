import 'package:flutter/material.dart';
import 'package:nolive_app/src/app/routing/app_routes.dart';
import 'package:nolive_app/src/shared/presentation/widgets/app_surface_card.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: const [
          _SettingsBlock(
            entries: [
              _SettingsEntryData(
                icon: Icons.palette_outlined,
                title: '外观设置',
                subtitle: '主题和显示风格',
                routeName: AppRoutes.appearanceSettings,
              ),
              _SettingsEntryData(
                icon: Icons.home_outlined,
                title: '主页设置',
                subtitle: '底部导航和平台顺序',
                routeName: AppRoutes.layoutSettings,
              ),
              _SettingsEntryData(
                icon: Icons.live_tv_outlined,
                title: '直播间设置',
                subtitle: '房间行为、聊天区样式和观看期常用开关',
                routeName: AppRoutes.roomSettings,
              ),
              _SettingsEntryData(
                icon: Icons.play_circle_outline_rounded,
                title: '播放器设置',
                subtitle: 'MPV / MDK、画质、全屏和 PiP',
                routeName: AppRoutes.playerSettings,
              ),
              _SettingsEntryData(
                icon: Icons.subtitles_outlined,
                title: '弹幕设置',
                subtitle: '屏蔽词和观看干扰项',
                routeName: AppRoutes.danmakuSettings,
              ),
              _SettingsEntryData(
                icon: Icons.account_circle_outlined,
                title: '账号设置',
                subtitle: 'Bilibili 登录和抖音凭据',
                routeName: AppRoutes.accountSettings,
              ),
              _SettingsEntryData(
                icon: Icons.collections_bookmark_outlined,
                title: '关注与历史',
                subtitle: '关注列表、观看历史和标签',
                routeName: AppRoutes.followSettings,
              ),
              _SettingsEntryData(
                icon: Icons.sync_outlined,
                title: '同步中心',
                subtitle: '本地快照、WebDAV 与局域网同步',
                routeName: AppRoutes.syncCenter,
              ),
              _SettingsEntryData(
                icon: Icons.link_rounded,
                title: '房间解析',
                subtitle: '解析直播间链接并立即校验',
                routeName: AppRoutes.parseRoom,
              ),
              _SettingsEntryData(
                icon: Icons.settings_backup_restore_outlined,
                title: '其他设置',
                subtitle: '导入导出、恢复默认和本地维护',
                routeName: AppRoutes.otherSettings,
              ),
              _SettingsEntryData(
                icon: Icons.info_outline,
                title: '应用信息',
                subtitle: '查看应用基础信息',
                routeName: AppRoutes.releaseInfo,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SettingsBlock extends StatelessWidget {
  const _SettingsBlock({required this.entries});

  final List<_SettingsEntryData> entries;

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      child: Column(
        children: [
          for (var index = 0; index < entries.length; index += 1) ...[
            _SettingsEntry(item: entries[index]),
            if (index != entries.length - 1) const Divider(height: 1),
          ],
        ],
      ),
    );
  }
}

class _SettingsEntryData {
  const _SettingsEntryData({
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

class _SettingsEntry extends StatelessWidget {
  const _SettingsEntry({required this.item});

  final _SettingsEntryData item;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(item.icon, color: colorScheme.onSurface),
      ),
      title: Text(item.title),
      subtitle: Text(
        item.subtitle,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
      ),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => Navigator.of(context).pushNamed(item.routeName),
    );
  }
}
