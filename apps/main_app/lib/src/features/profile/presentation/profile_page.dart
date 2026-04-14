import 'package:flutter/material.dart';
import 'package:nolive_app/src/app/routing/app_routes.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        children: [
          const _TopAppTile(),
          const SizedBox(height: 8),
          for (var index = 0; index < _entries.length; index += 1) ...[
            _ProfileEntryTile(entry: _entries[index]),
            const Divider(height: 1),
          ],
        ],
      ),
    );
  }

  static const List<_ProfileEntry> _entries = [
    _ProfileEntry(
        icon: Icons.history_rounded,
        title: '观看记录',
        routeName: AppRoutes.watchHistory),
    _ProfileEntry(
        icon: Icons.account_circle_outlined,
        title: '账号管理',
        routeName: AppRoutes.accountSettings),
    _ProfileEntry(
        icon: Icons.sync_outlined,
        title: '数据同步',
        routeName: AppRoutes.syncCenter),
    _ProfileEntry(
        icon: Icons.link_rounded,
        title: '链接解析',
        routeName: AppRoutes.parseRoom),
    _ProfileEntry(
        icon: Icons.dark_mode_outlined,
        title: '外观设置',
        routeName: AppRoutes.appearanceSettings),
    _ProfileEntry(
        icon: Icons.home_outlined,
        title: '主页设置',
        routeName: AppRoutes.layoutSettings),
    _ProfileEntry(
        icon: Icons.live_tv_outlined,
        title: '直播间设置',
        routeName: AppRoutes.roomSettings),
    _ProfileEntry(
        icon: Icons.video_settings_outlined,
        title: '播放器设置',
        routeName: AppRoutes.playerSettings),
    _ProfileEntry(
        icon: Icons.subtitles_outlined,
        title: '弹幕设置',
        routeName: AppRoutes.danmakuSettings),
    _ProfileEntry(
        icon: Icons.favorite_border_rounded,
        title: '关注设置',
        routeName: AppRoutes.followSettings),
    _ProfileEntry(
        icon: Icons.widgets_outlined,
        title: '其他设置',
        routeName: AppRoutes.otherSettings),
    _ProfileEntry(
        icon: Icons.info_outline_rounded,
        title: '免责声明',
        routeName: AppRoutes.disclaimer),
  ];
}

class _TopAppTile extends StatelessWidget {
  const _TopAppTile();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Image.asset(
            'assets/branding/nolive_brand_mark.png',
            width: 64,
            height: 64,
            fit: BoxFit.cover,
            semanticLabel: 'Nolive brand mark',
          ),
        ),
      ),
      title: Text(
        'Nolive',
        style: theme.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
      subtitle: Text(
        '多平台直播聚合',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _ProfileEntry {
  const _ProfileEntry({
    required this.icon,
    required this.title,
    required this.routeName,
  });

  final IconData icon;
  final String title;
  final String routeName;
}

class _ProfileEntryTile extends StatelessWidget {
  const _ProfileEntryTile({required this.entry});

  final _ProfileEntry entry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      leading: Icon(entry.icon, color: colorScheme.onSurfaceVariant, size: 30),
      title: Text(
        entry.title,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w500,
            ),
      ),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => Navigator.of(context).pushNamed(entry.routeName),
    );
  }
}
