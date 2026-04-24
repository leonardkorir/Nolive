import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nolive_app/src/features/settings/application/github_app_update_service.dart';
import 'package:nolive_app/src/app/routing/app_routes.dart';
import 'package:url_launcher/url_launcher.dart';

class ProfilePage extends StatefulWidget {
  ProfilePage({
    super.key,
    GithubAppUpdateService? updateService,
    this.versionLoader = GithubAppUpdateService.loadInstalledVersion,
    this.urlLauncher = _launchExternalUrl,
  }) : updateService = updateService ?? GithubAppUpdateService();

  final GithubAppUpdateService updateService;
  final Future<String> Function() versionLoader;
  final Future<bool> Function(Uri uri) urlLauncher;

  static Future<bool> _launchExternalUrl(Uri uri) {
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  String? _currentVersion;
  bool _checkingUpdate = false;

  static const List<_ProfileEntry> _entries = [
    _ProfileEntry(
      icon: Icons.history_rounded,
      title: '观看记录',
      routeName: AppRoutes.watchHistory,
    ),
    _ProfileEntry(
      icon: Icons.account_circle_outlined,
      title: '账号管理',
      routeName: AppRoutes.accountSettings,
    ),
    _ProfileEntry(
      icon: Icons.sync_outlined,
      title: '数据同步',
      routeName: AppRoutes.syncCenter,
    ),
    _ProfileEntry(
      icon: Icons.link_rounded,
      title: '链接解析',
      routeName: AppRoutes.parseRoom,
    ),
    _ProfileEntry(
      icon: Icons.dark_mode_outlined,
      title: '外观设置',
      routeName: AppRoutes.appearanceSettings,
    ),
    _ProfileEntry(
      icon: Icons.home_outlined,
      title: '主页设置',
      routeName: AppRoutes.layoutSettings,
    ),
    _ProfileEntry(
      icon: Icons.live_tv_outlined,
      title: '直播间设置',
      routeName: AppRoutes.roomSettings,
    ),
    _ProfileEntry(
      icon: Icons.video_settings_outlined,
      title: '播放器设置',
      routeName: AppRoutes.playerSettings,
    ),
    _ProfileEntry(
      icon: Icons.subtitles_outlined,
      title: '弹幕设置',
      routeName: AppRoutes.danmakuSettings,
    ),
    _ProfileEntry(
      icon: Icons.favorite_border_rounded,
      title: '关注设置',
      routeName: AppRoutes.followSettings,
    ),
    _ProfileEntry(
      icon: Icons.widgets_outlined,
      title: '其他设置',
      routeName: AppRoutes.otherSettings,
    ),
    _ProfileEntry(
      icon: Icons.info_outline_rounded,
      title: '免责声明',
      routeName: AppRoutes.disclaimer,
    ),
  ];

  @override
  void initState() {
    super.initState();
    unawaited(_loadVersion());
  }

  Future<void> _loadVersion() async {
    try {
      final version = await widget.versionLoader();
      if (!mounted) {
        return;
      }
      setState(() {
        _currentVersion = version;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _currentVersion = null;
      });
    }
  }

  Future<void> _openHomepage() async {
    final opened =
        await widget.urlLauncher(widget.updateService.repoHomepageUri);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法打开开源主页。')),
      );
    }
  }

  Future<void> _checkForUpdate() async {
    if (_checkingUpdate) {
      return;
    }
    setState(() {
      _checkingUpdate = true;
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await widget.updateService.checkForUpdate(
        currentVersion: _currentVersion,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _currentVersion = result.currentVersion;
      });

      if (!result.hasUpdate) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('当前已经是最新版本 v${result.currentVersion}'),
          ),
        );
        return;
      }

      final openRelease = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text('发现新版本 v${result.latestRelease.version}'),
              content: Text(
                '当前版本 v${result.currentVersion}\n点击“前往更新”打开 GitHub Release 页面。',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('前往更新'),
                ),
              ],
            ),
          ) ??
          false;

      if (!openRelease) {
        return;
      }

      final opened = await widget.urlLauncher(result.latestRelease.releaseUri);
      if (!opened && mounted) {
        messenger.showSnackBar(
          const SnackBar(content: Text('无法打开更新页面。')),
        );
      }
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('检查更新失败：$error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _checkingUpdate = false;
        });
      }
    }
  }

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
          _ActionProfileEntryTile(
            icon: Icons.code_rounded,
            title: '开源主页',
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: _openHomepage,
          ),
          const Divider(height: 1),
          _ActionProfileEntryTile(
            icon: Icons.system_update_rounded,
            title: '检查更新',
            trailing: _checkingUpdate
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _currentVersion == null
                            ? 'Ver -'
                            : 'Ver ${_currentVersion!}',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.chevron_right_rounded),
                    ],
                  ),
            onTap: _checkForUpdate,
          ),
          const Divider(height: 1),
        ],
      ),
    );
  }
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
    return _ActionProfileEntryTile(
      icon: entry.icon,
      title: entry.title,
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => Navigator.of(context).pushNamed(entry.routeName),
    );
  }
}

class _ActionProfileEntryTile extends StatelessWidget {
  const _ActionProfileEntryTile({
    required this.icon,
    required this.title,
    required this.trailing,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final Widget trailing;
  final FutureOr<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      leading: Icon(icon, color: colorScheme.onSurfaceVariant, size: 30),
      title: Text(
        title,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w500,
            ),
      ),
      trailing: trailing,
      onTap: () {
        final result = onTap();
        if (result is Future<void>) {
          unawaited(result);
        }
      },
    );
  }
}
