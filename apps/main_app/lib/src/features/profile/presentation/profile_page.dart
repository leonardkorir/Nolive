import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nolive_app/src/features/settings/application/github_app_update_service.dart';
import 'package:nolive_app/src/shared/application/app_log.dart';
import 'package:nolive_app/src/shared/presentation/app_feedback.dart';
import 'package:nolive_app/src/shared/presentation/app_settings_entries.dart';
import 'package:url_launcher/url_launcher.dart';

class ProfilePage extends StatefulWidget {
  ProfilePage({
    super.key,
    GithubAppUpdateService? updateService,
    this.versionLoader = GithubAppUpdateService.loadInstalledVersion,
    this.urlLauncher = _launchExternalUrl,
    this.menuEntries = kProfileMenuEntries,
  }) : updateService = updateService ?? GithubAppUpdateService();

  final GithubAppUpdateService updateService;
  final Future<String> Function() versionLoader;
  final Future<bool> Function(Uri uri) urlLauncher;

  /// Original flat menu for「我的」— not the Settings-page catalog.
  final List<AppSettingsEntry> menuEntries;

  static Future<bool> _launchExternalUrl(Uri uri) {
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  String? _currentVersion;
  bool _checkingUpdate = false;

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
    } catch (error, stackTrace) {
      AppLog.instance.error(
        'profile',
        'installed version load failed',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _currentVersion = null;
      });
    }
  }

  Future<void> _openHomepage() async {
    final opened = await widget.urlLauncher(
      widget.updateService.repoHomepageUri,
    );
    if (!opened && mounted) {
      showAppSnackBar(context, '无法打开开源主页。');
    }
  }

  Future<void> _checkForUpdate() async {
    if (_checkingUpdate) {
      return;
    }
    setState(() {
      _checkingUpdate = true;
    });
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
        showAppSnackBar(context, '当前已经是最新版本 v${result.currentVersion}');
        return;
      }

      final openRelease =
          await showDialog<bool>(
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
        showAppSnackBar(context, '无法打开更新页面。');
      }
    } catch (error, stackTrace) {
      AppLog.instance.error(
        'profile',
        'update check failed',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) {
        return;
      }
      showAppErrorSnackBar(context, error, prefix: '检查更新失败：');
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
    final colorScheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        children: [
          const _TopAppTile(),
          const SizedBox(height: 8),
          // Original flat menu — same order as before IA refactor.
          for (var index = 0; index < widget.menuEntries.length; index += 1) ...[
            _ProfileEntryTile(entry: widget.menuEntries[index]),
            const Divider(height: 1),
          ],
          _ActionProfileEntryTile(
            icon: Icons.code_rounded,
            title: '开源主页',
            trailing: Icon(
              Icons.chevron_right_rounded,
              color: colorScheme.onSurfaceVariant,
            ),
            onTap: _openHomepage,
          ),
          const Divider(height: 1),
          _ActionProfileEntryTile(
            icon: Icons.system_update_rounded,
            title: '检查更新',
            trailing: _checkingUpdate
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colorScheme.primary,
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _currentVersion == null
                            ? 'Ver -'
                            : 'Ver ${_currentVersion!}',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: colorScheme.onSurfaceVariant,
                      ),
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
          color: colorScheme.onSurface,
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

class _ProfileEntryTile extends StatelessWidget {
  const _ProfileEntryTile({required this.entry});

  final AppSettingsEntry entry;

  @override
  Widget build(BuildContext context) {
    return _ActionProfileEntryTile(
      icon: entry.icon,
      title: entry.title,
      trailing: Icon(
        Icons.chevron_right_rounded,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
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
    final theme = Theme.of(context);
    // Match original「我的」row chrome: outline icons + onSurface title.
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      leading: Icon(icon, color: colorScheme.onSurfaceVariant, size: 30),
      title: Text(
        title,
        style: theme.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w500,
          color: colorScheme.onSurface,
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
