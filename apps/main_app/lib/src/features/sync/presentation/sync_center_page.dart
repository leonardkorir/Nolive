import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:live_sync/live_sync.dart';
import 'package:nolive_app/src/app/routing/app_routes.dart';
import 'package:nolive_app/src/features/sync/application/sync_feature_dependencies.dart';
import 'package:nolive_app/src/features/sync/application/sync_preferences_use_case.dart';
import 'package:nolive_app/src/shared/presentation/widgets/app_surface_card.dart';
import 'package:nolive_app/src/shared/presentation/widgets/empty_state_card.dart';
import 'package:nolive_app/src/shared/presentation/widgets/section_header.dart';

class SyncCenterPage extends StatefulWidget {
  const SyncCenterPage({required this.dependencies, super.key});

  final SyncFeatureDependencies dependencies;

  @override
  State<SyncCenterPage> createState() => _SyncCenterPageState();
}

class _SyncCenterPageState extends State<SyncCenterPage> {
  late Future<SyncSnapshotView> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<SyncSnapshotView> _load() async {
    final snapshot = await widget.dependencies.loadSyncSnapshot();
    final preferences = await widget.dependencies.loadSyncPreferences();
    return SyncSnapshotView(snapshot: snapshot, preferences: preferences);
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _load();
    });
    await _future;
  }

  Future<void> _copySummary() async {
    final payload = SyncSnapshotJsonCodec.encode(
        await widget.dependencies.loadSyncSnapshot());
    await Clipboard.setData(ClipboardData(text: payload));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('快照 JSON 已复制到剪贴板')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('数据同步')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<SyncSnapshotView>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator.adaptive());
            }
            if (snapshot.hasError || !snapshot.hasData) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                children: [
                  EmptyStateCard(
                    title: '数据同步加载失败',
                    message: '${snapshot.error}',
                    icon: Icons.error_outline,
                  ),
                ],
              );
            }

            final data = snapshot.data!;
            final preferences = data.preferences;
            final localServerRunning =
                widget.dependencies.localSyncServer.isRunning;
            final webDavSummary = preferences.toWebDavConfig().isConfigured
                ? '${preferences.webDavBaseUrl} · ${preferences.webDavRemotePath}'
                : '未配置';
            final localSummary = localServerRunning
                ? '已启动'
                : preferences.localPeerAddress.trim().isEmpty
                    ? '未配置'
                    : '${preferences.localPeerAddress}:${preferences.localPeerPort}';

            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
              children: [
                SectionHeader(
                  title: '数据同步',
                  trailing: FilledButton.tonalIcon(
                    onPressed: _copySummary,
                    icon: const Icon(Icons.copy_all_outlined),
                    label: const Text('复制快照'),
                  ),
                ),
                const SizedBox(height: 12),
                AppSurfaceCard(
                  child: Column(
                    children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.settings_suggest_outlined),
                        title: const Text('设置项'),
                        trailing: Text('${data.snapshot.settings.length}'),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.favorite_border),
                        title: const Text('关注记录'),
                        trailing: Text('${data.snapshot.follows.length}'),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.history),
                        title: const Text('历史记录'),
                        trailing: Text('${data.snapshot.history.length}'),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.sell_outlined),
                        title: const Text('标签'),
                        trailing: Text('${data.snapshot.tags.length}'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                AppSurfaceCard(
                  child: Column(
                    children: [
                      ListTile(
                        key: const Key('sync-entry-webdav'),
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.cloud_outlined),
                        title: const Text('WebDAV 同步'),
                        subtitle: Text(webDavSummary),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => Navigator.of(context).pushNamed(
                          AppRoutes.syncWebDav,
                        ),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        key: const Key('sync-entry-local'),
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.wifi_tethering_outlined),
                        title: const Text('局域网数据同步'),
                        subtitle: Text(localSummary),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => Navigator.of(context).pushNamed(
                          AppRoutes.syncLocal,
                        ),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        key: const Key('sync-entry-tools'),
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.import_export_rounded),
                        title: const Text('导入 / 导出'),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => Navigator.of(context).pushNamed(
                          AppRoutes.otherSettings,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class SyncSnapshotView {
  const SyncSnapshotView({
    required this.snapshot,
    required this.preferences,
  });

  final SyncSnapshot snapshot;
  final SyncPreferences preferences;
}
