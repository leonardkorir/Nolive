import 'package:flutter/material.dart';
import 'package:live_sync/live_sync.dart';
import 'package:nolive_app/src/features/sync/application/sync_feature_dependencies.dart';
import 'package:nolive_app/src/features/sync/application/sync_preferences_use_case.dart';
import 'package:nolive_app/src/shared/presentation/widgets/app_surface_card.dart';
import 'package:nolive_app/src/shared/presentation/widgets/empty_state_card.dart';
import 'package:nolive_app/src/shared/presentation/widgets/section_header.dart';

class SyncWebDavPage extends StatefulWidget {
  const SyncWebDavPage({required this.dependencies, super.key});

  final SyncFeatureDependencies dependencies;

  @override
  State<SyncWebDavPage> createState() => _SyncWebDavPageState();
}

class _SyncWebDavPageState extends State<SyncWebDavPage> {
  late Future<_SyncWebDavPageData> _future;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_SyncWebDavPageData> _load() async {
    final snapshot = await widget.dependencies.loadSyncSnapshot();
    final preferences = await widget.dependencies.loadSyncPreferences();
    return _SyncWebDavPageData(snapshot: snapshot, preferences: preferences);
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _load();
    });
    await _future;
  }

  Future<void> _editPreferences(SyncPreferences preferences) async {
    final webDavBaseUrl =
        TextEditingController(text: preferences.webDavBaseUrl);
    final webDavRemotePath =
        TextEditingController(text: preferences.webDavRemotePath);
    final webDavUsername =
        TextEditingController(text: preferences.webDavUsername);
    final webDavPassword =
        TextEditingController(text: preferences.webDavPassword);

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: const Text('WebDAV 配置'),
              content: SizedBox(
                width: 560,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: webDavBaseUrl,
                        decoration: const InputDecoration(
                          labelText: 'WebDAV Base URL',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: webDavRemotePath,
                        decoration: const InputDecoration(
                          labelText: '远端文件路径',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: webDavUsername,
                        decoration: const InputDecoration(
                          labelText: '用户名',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: webDavPassword,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: '密码',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('保存'),
                ),
              ],
            );
          },
        ) ??
        false;
    if (!confirmed) {
      return;
    }

    await widget.dependencies.updateSyncPreferences(
      preferences.copyWith(
        webDavBaseUrl: webDavBaseUrl.text.trim(),
        webDavRemotePath: webDavRemotePath.text.trim(),
        webDavUsername: webDavUsername.text.trim(),
        webDavPassword: webDavPassword.text.trim(),
      ),
    );
    await _refresh();
  }

  Future<void> _runBusy(Future<void> Function() action) async {
    setState(() {
      _busy = true;
    });
    try {
      await action();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _testRemote(SyncPreferences preferences) async {
    await _runBusy(() async {
      await widget.dependencies.verifyWebDavConnection(preferences);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('WebDAV 连接正常，远端目录已就绪')),
      );
    });
  }

  Future<void> _uploadRemote(SyncPreferences preferences) async {
    await _runBusy(() async {
      await widget.dependencies.uploadWebDavSnapshot(preferences);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已上传远端快照')),
      );
    });
  }

  Future<void> _restoreRemote(SyncPreferences preferences) async {
    await _runBusy(() async {
      final snapshot =
          await widget.dependencies.restoreWebDavSnapshot(preferences);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            snapshot == null
                ? '远端暂无快照'
                : '已恢复远端快照：关注 ${snapshot.follows.length} · 历史 ${snapshot.history.length}',
          ),
        ),
      );
      await _refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('WebDAV 同步')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<_SyncWebDavPageData>(
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
                    title: 'WebDAV 页面加载失败',
                    message: '${snapshot.error}',
                    icon: Icons.error_outline,
                  ),
                ],
              );
            }

            final data = snapshot.data!;
            final configured = data.preferences.toWebDavConfig().isConfigured;
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
              children: [
                const SectionHeader(title: 'WebDAV 同步'),
                const SizedBox(height: 12),
                AppSurfaceCard(
                  child: Column(
                    children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.link_outlined),
                        title: const Text('Base URL'),
                        subtitle: Text(
                          data.preferences.webDavBaseUrl.trim().isEmpty
                              ? '未配置'
                              : data.preferences.webDavBaseUrl,
                        ),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.folder_outlined),
                        title: const Text('远端路径'),
                        subtitle: Text(
                          data.preferences.webDavRemotePath.trim().isEmpty
                              ? '未配置'
                              : data.preferences.webDavRemotePath,
                        ),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.person_outline),
                        title: const Text('用户名'),
                        subtitle: Text(
                          data.preferences.webDavUsername.trim().isEmpty
                              ? '未配置'
                              : data.preferences.webDavUsername,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                AppSurfaceCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '同步动作',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          FilledButton.tonalIcon(
                            key: const Key('sync-webdav-configure-button'),
                            onPressed: _busy
                                ? null
                                : () => _editPreferences(data.preferences),
                            icon: const Icon(Icons.edit_outlined),
                            label: const Text('配置'),
                          ),
                          FilledButton.tonalIcon(
                            key: const Key('sync-webdav-test-button'),
                            onPressed: _busy || !configured
                                ? null
                                : () => _testRemote(data.preferences),
                            icon: const Icon(Icons.wifi_tethering_outlined),
                            label: const Text('测试连接'),
                          ),
                          FilledButton.tonalIcon(
                            key: const Key('sync-webdav-upload-button'),
                            onPressed: _busy || !configured
                                ? null
                                : () => _uploadRemote(data.preferences),
                            icon: const Icon(Icons.cloud_upload_outlined),
                            label: const Text('上传快照'),
                          ),
                          FilledButton.tonalIcon(
                            key: const Key('sync-webdav-restore-button'),
                            onPressed: _busy || !configured
                                ? null
                                : () => _restoreRemote(data.preferences),
                            icon: const Icon(Icons.cloud_download_outlined),
                            label: const Text('恢复远端'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
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

class _SyncWebDavPageData {
  const _SyncWebDavPageData({
    required this.snapshot,
    required this.preferences,
  });

  final SyncSnapshot snapshot;
  final SyncPreferences preferences;
}
