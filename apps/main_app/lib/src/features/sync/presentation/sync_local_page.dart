import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:live_sync/live_sync.dart';
import 'package:nolive_app/src/app/bootstrap/bootstrap.dart';
import 'package:nolive_app/src/features/sync/application/sync_preferences_use_case.dart';
import 'package:nolive_app/src/shared/presentation/widgets/app_surface_card.dart';
import 'package:nolive_app/src/shared/presentation/widgets/empty_state_card.dart';
import 'package:nolive_app/src/shared/presentation/widgets/section_header.dart';

class SyncLocalPage extends StatefulWidget {
  const SyncLocalPage({required this.bootstrap, super.key});

  final AppBootstrap bootstrap;

  @override
  State<SyncLocalPage> createState() => _SyncLocalPageState();
}

class _SyncLocalPageState extends State<SyncLocalPage> {
  late Future<_SyncLocalPageData> _future;
  StreamSubscription<List<DiscoveredPeer>>? _peerSubscription;
  List<DiscoveredPeer> _peers = const [];
  List<String> _localAddresses = const [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
    widget.bootstrap.localDiscoveryService.start();
    _peerSubscription =
        widget.bootstrap.localDiscoveryService.watchPeers().listen((peers) {
      if (!mounted) {
        return;
      }
      setState(() {
        _peers = peers;
      });
    });
  }

  @override
  void dispose() {
    _peerSubscription?.cancel();
    super.dispose();
  }

  Future<_SyncLocalPageData> _load() async {
    final snapshot = await widget.bootstrap.loadSyncSnapshot();
    final preferences = await widget.bootstrap.loadSyncPreferences();
    final addresses = await _readLocalAddresses();
    _localAddresses = addresses;
    if (widget.bootstrap.localSyncServer.isRunning) {
      _syncSelfPeer(preferences, addresses: addresses);
    }
    return _SyncLocalPageData(snapshot: snapshot, preferences: preferences);
  }

  Future<List<String>> _readLocalAddresses() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      ).timeout(const Duration(seconds: 2), onTimeout: () => const []);
      final addresses = <String>{};
      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          if (address.address.trim().isEmpty || address.isLoopback) {
            continue;
          }
          addresses.add(address.address);
        }
      }
      final sorted = addresses.toList()..sort();
      return sorted;
    } catch (_) {
      return const [];
    }
  }

  List<String> _shareableEndpoints(int port) {
    if (_localAddresses.isEmpty) {
      return ['http://127.0.0.1:$port/snapshot'];
    }
    return _localAddresses
        .map((address) => 'http://$address:$port/snapshot')
        .toList(growable: false);
  }

  void _syncSelfPeer(
    SyncPreferences preferences, {
    List<String>? addresses,
  }) {
    final host = (addresses ?? _localAddresses).isNotEmpty
        ? (addresses ?? _localAddresses).first
        : '127.0.0.1';
    widget.bootstrap.localDiscoveryService.addOrReplacePeer(
      DiscoveredPeer(
        deviceId: 'self',
        displayName: preferences.localDeviceName,
        address: host,
        port: widget.bootstrap.localSyncServer.endpoint.port,
      ),
    );
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _load();
    });
    await _future;
  }

  Future<void> _editPreferences(SyncPreferences preferences) async {
    final localDeviceName =
        TextEditingController(text: preferences.localDeviceName);
    final localPeerAddress =
        TextEditingController(text: preferences.localPeerAddress);
    final localPeerPort =
        TextEditingController(text: preferences.localPeerPort.toString());

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: const Text('局域网同步配置'),
              content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: localDeviceName,
                        decoration: const InputDecoration(
                          labelText: '本机设备名',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: localPeerAddress,
                        decoration: const InputDecoration(
                          labelText: '目标地址',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: localPeerPort,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: '目标端口',
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

    final nextPreferences = preferences.copyWith(
      localDeviceName: localDeviceName.text.trim().isEmpty
          ? preferences.localDeviceName
          : localDeviceName.text.trim(),
      localPeerAddress: localPeerAddress.text.trim(),
      localPeerPort: int.tryParse(localPeerPort.text.trim()) ?? 23234,
    );
    await widget.bootstrap.updateSyncPreferences(nextPreferences);
    if (nextPreferences.localPeerAddress.trim().isEmpty) {
      widget.bootstrap.localDiscoveryService.removePeer('manual-peer');
    } else {
      widget.bootstrap.localDiscoveryService.addOrReplacePeer(
        DiscoveredPeer(
          deviceId: 'manual-peer',
          displayName: nextPreferences.localDeviceName,
          address: nextPreferences.localPeerAddress.trim(),
          port: nextPreferences.localPeerPort,
        ),
      );
    }
    if (widget.bootstrap.localSyncServer.isRunning) {
      _syncSelfPeer(nextPreferences);
    }
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

  Future<void> _toggleLocalServer(SyncPreferences preferences) async {
    await _runBusy(() async {
      if (widget.bootstrap.localSyncServer.isRunning) {
        await widget.bootstrap.localSyncServer.stop();
        widget.bootstrap.localDiscoveryService.removePeer('self');
      } else {
        await widget.bootstrap.localSyncServer.start();
        final addresses = await _readLocalAddresses();
        if (mounted) {
          setState(() {
            _localAddresses = addresses;
          });
        }
        _syncSelfPeer(preferences, addresses: addresses);
      }
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.bootstrap.localSyncServer.isRunning
                ? '局域网同步服务已启动'
                : '局域网同步服务已停止',
          ),
        ),
      );
      await _refresh();
    });
  }

  DiscoveredPeer _manualPeerFromPreferences(SyncPreferences preferences) {
    final peerAddress = preferences.localPeerAddress.trim();
    if (peerAddress.isEmpty) {
      throw const FormatException('请先填写局域网目标地址。');
    }
    return DiscoveredPeer(
      deviceId: 'manual-peer',
      displayName: preferences.localDeviceName,
      address: peerAddress,
      port: preferences.localPeerPort,
    );
  }

  Future<void> _probeTarget(SyncPreferences preferences) async {
    await _runBusy(() async {
      final info = await widget.bootstrap.localSyncClient.fetchInfo(
        peer: _manualPeerFromPreferences(preferences),
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('目标在线：${info.displayName}')),
      );
    });
  }

  Future<void> _pushLocal(SyncPreferences preferences) async {
    await _runBusy(() async {
      await widget.bootstrap.pushLocalSyncSnapshot(preferences);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已推送本地快照到目标设备')),
      );
    });
  }

  Future<void> _savePeerAsTarget(
    SyncPreferences preferences,
    DiscoveredPeer peer,
  ) async {
    final nextPreferences = preferences.copyWith(
      localPeerAddress: peer.address,
      localPeerPort: peer.port,
    );
    await widget.bootstrap.updateSyncPreferences(nextPreferences);
    widget.bootstrap.localDiscoveryService.addOrReplacePeer(
      DiscoveredPeer(
        deviceId: 'manual-peer',
        displayName: peer.displayName,
        address: peer.address,
        port: peer.port,
      ),
    );
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已选中 ${peer.address}:${peer.port}')),
    );
    await _refresh();
  }

  Future<void> _copyAddress(String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('同步地址已复制')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('局域网数据同步')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<_SyncLocalPageData>(
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
                    title: '局域网同步页面加载失败',
                    message: '${snapshot.error}',
                    icon: Icons.error_outline,
                  ),
                ],
              );
            }

            final data = snapshot.data!;
            final preferences = data.preferences;
            final localServerRunning =
                widget.bootstrap.localSyncServer.isRunning;
            final endpoints = _shareableEndpoints(
              widget.bootstrap.localSyncServer.endpoint.port,
            );
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
              children: [
                const SectionHeader(title: '局域网数据同步'),
                const SizedBox(height: 12),
                AppSurfaceCard(
                  child: Column(
                    children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.smartphone_outlined),
                        title: const Text('本机设备名'),
                        subtitle: Text(preferences.localDeviceName),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.send_to_mobile_outlined),
                        title: const Text('目标设备'),
                        subtitle: Text(
                          preferences.localPeerAddress.trim().isEmpty
                              ? '未配置'
                              : '${preferences.localPeerAddress}:${preferences.localPeerPort}',
                        ),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.storage_outlined),
                        title: const Text('当前快照'),
                        subtitle: Text(
                          '关注 ${data.snapshot.follows.length} · 历史 ${data.snapshot.history.length} · 标签 ${data.snapshot.tags.length}',
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
                            key: const Key('sync-local-toggle-button'),
                            onPressed: _busy
                                ? null
                                : () => _toggleLocalServer(preferences),
                            icon: Icon(
                              localServerRunning
                                  ? Icons.pause_circle_outline
                                  : Icons.play_circle_outline,
                            ),
                            label: Text(localServerRunning ? '停止服务' : '启动服务'),
                          ),
                          FilledButton.tonalIcon(
                            key: const Key('sync-local-edit-button'),
                            onPressed: _busy
                                ? null
                                : () => _editPreferences(preferences),
                            icon: const Icon(Icons.tune_outlined),
                            label: const Text('编辑目标'),
                          ),
                          FilledButton.tonalIcon(
                            key: const Key('sync-local-test-button'),
                            onPressed: _busy ||
                                    preferences.localPeerAddress.trim().isEmpty
                                ? null
                                : () => _probeTarget(preferences),
                            icon: const Icon(Icons.verified_outlined),
                            label: const Text('测试目标'),
                          ),
                          FilledButton.tonalIcon(
                            key: const Key('sync-local-push-button'),
                            onPressed: _busy ||
                                    preferences.localPeerAddress.trim().isEmpty
                                ? null
                                : () => _pushLocal(preferences),
                            icon: const Icon(Icons.send_outlined),
                            label: const Text('推送到目标'),
                          ),
                        ],
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
                        '本机同步地址',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      if (!localServerRunning)
                        const Text('未启动')
                      else
                        for (final endpoint in endpoints)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.link_outlined),
                            title: Text(endpoint),
                            trailing: TextButton(
                              onPressed: () => _copyAddress(endpoint),
                              child: const Text('复制'),
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
                        '已记录设备',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      if (_peers.isEmpty)
                        const Text('暂无设备')
                      else
                        for (final peer in _peers)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.devices_other_outlined),
                            title: Text(peer.displayName),
                            subtitle: Text('${peer.address}:${peer.port}'),
                            trailing: Text(
                              preferences.localPeerAddress == peer.address &&
                                      preferences.localPeerPort == peer.port
                                  ? '已选中'
                                  : peer.deviceId == 'self'
                                      ? '本机'
                                      : '点击使用',
                            ),
                            onTap: _busy
                                ? null
                                : () => _savePeerAsTarget(preferences, peer),
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

class _SyncLocalPageData {
  const _SyncLocalPageData({
    required this.snapshot,
    required this.preferences,
  });

  final SyncSnapshot snapshot;
  final SyncPreferences preferences;
}
