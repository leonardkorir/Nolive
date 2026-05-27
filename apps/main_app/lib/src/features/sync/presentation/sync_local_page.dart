import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:live_sync/live_sync.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:nolive_app/src/features/sync/application/sync_feature_dependencies.dart';
import 'package:nolive_app/src/features/sync/application/sync_preferences_use_case.dart';
import 'package:nolive_app/src/shared/presentation/widgets/app_surface_card.dart';
import 'package:nolive_app/src/shared/presentation/widgets/empty_state_card.dart';
import 'package:nolive_app/src/shared/presentation/widgets/section_header.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'sync_local_platform.dart';

class _LocalSyncPairingPayload {
  const _LocalSyncPairingPayload({
    required this.accessToken,
    this.host,
    this.port,
  });

  final String accessToken;
  final String? host;
  final int? port;
}

String _normalizeBarePairingCode(String value) {
  return value
      .trim()
      .replaceFirst(RegExp(r'^nolive-sync:', caseSensitive: false), '')
      .replaceAll(RegExp(r'[\s-]'), '');
}

_LocalSyncPairingPayload? _parseLocalSyncPairingPayload(
  String value, {
  bool allowBareToken = true,
}) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return null;
  }

  final uri = Uri.tryParse(trimmed);
  if (uri != null &&
      uri.scheme.toLowerCase() == 'nolive-sync' &&
      uri.host == 'pair') {
    final token = _normalizeBarePairingCode(
      uri.queryParameters['token'] ?? uri.queryParameters['accessToken'] ?? '',
    );
    if (token.isEmpty) {
      return null;
    }
    final host = uri.queryParameters['host'] ?? uri.queryParameters['address'];
    final normalizedHost = host?.trim();
    return _LocalSyncPairingPayload(
      accessToken: token,
      host: normalizedHost == null || normalizedHost.isEmpty
          ? null
          : normalizedHost,
      port: int.tryParse(uri.queryParameters['port'] ?? ''),
    );
  }

  if (!allowBareToken && !trimmed.toLowerCase().startsWith('nolive-sync:')) {
    return null;
  }

  final token = _normalizeBarePairingCode(trimmed);
  if (token.isEmpty) {
    return null;
  }
  return _LocalSyncPairingPayload(accessToken: token);
}

String _normalizeLocalSyncPairingCode(String value) {
  return _parseLocalSyncPairingPayload(value)?.accessToken ?? '';
}

String _formatLocalSyncPairingCode(String value) {
  final normalized = _normalizeLocalSyncPairingCode(value);
  if (normalized.isEmpty) {
    return '';
  }
  final buffer = StringBuffer();
  for (var index = 0; index < normalized.length; index += 4) {
    if (index > 0) {
      buffer.write('-');
    }
    final end = (index + 4).clamp(0, normalized.length).toInt();
    buffer.write(normalized.substring(index, end));
  }
  return buffer.toString();
}

String _buildLocalSyncPairingQrData({
  required SyncPreferences preferences,
  required List<String> addresses,
  required int port,
  required String accessToken,
}) {
  return Uri(
    scheme: 'nolive-sync',
    host: 'pair',
    queryParameters: <String, String>{
      if (addresses.isNotEmpty) 'host': addresses.first,
      'port': port.toString(),
      'token': accessToken,
      'name': preferences.localDeviceName,
    },
  ).toString();
}

class SyncLocalPage extends StatefulWidget {
  const SyncLocalPage({
    required this.dependencies,
    this.readLocalAddresses = readLocalIPv4Addresses,
    this.supportsPairingScanner = supportsLocalSyncPairingScanner,
    this.platformName = currentLocalSyncPlatformName,
    super.key,
  });

  final SyncFeatureDependencies dependencies;
  final Future<List<String>> Function() readLocalAddresses;
  final bool Function() supportsPairingScanner;
  final String Function() platformName;

  @override
  State<SyncLocalPage> createState() => _SyncLocalPageState();
}

class _SyncLocalPageState extends State<SyncLocalPage> {
  late Future<_SyncLocalPageData> _future;
  StreamSubscription<List<DiscoveredPeer>>? _peerSubscription;
  String? _selfPeerDeviceId;
  List<DiscoveredPeer> _peers = const [];
  List<String> _localAddresses = const [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
    widget.dependencies.localDiscoveryService.start();
    _peerSubscription = widget.dependencies.localDiscoveryService
        .watchPeers()
        .listen((peers) {
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
    unawaited(widget.dependencies.localDiscoveryService.stop());
    super.dispose();
  }

  Future<_SyncLocalPageData> _load() async {
    final snapshot = await widget.dependencies.loadSyncSnapshot();
    final preferences = await widget.dependencies.loadSyncPreferences();
    final localInfo = await widget.dependencies.localSyncServer.readInfo();
    final addresses = await _readLocalAddresses();
    _localAddresses = addresses;
    if (widget.dependencies.localSyncServer.isRunning) {
      _syncSelfPeer(preferences, addresses: addresses);
    }
    return _SyncLocalPageData(
      snapshot: snapshot,
      preferences: preferences,
      localPairingCode: localInfo.accessToken ?? '',
    );
  }

  Future<List<String>> _readLocalAddresses() async {
    return widget.readLocalAddresses();
  }

  List<String> _shareableEndpoints(int port) {
    if (_localAddresses.isEmpty) {
      return const [];
    }
    return _localAddresses
        .map((address) => 'http://$address:$port/snapshot')
        .toList(growable: false);
  }

  void _syncSelfPeer(SyncPreferences preferences, {List<String>? addresses}) {
    unawaited(_syncSelfPeerAsync(preferences, addresses: addresses));
  }

  Future<void> _syncSelfPeerAsync(
    SyncPreferences preferences, {
    List<String>? addresses,
  }) async {
    final availableAddresses = addresses ?? _localAddresses;
    if (availableAddresses.isEmpty) {
      _removeSelfPeer();
      return;
    }
    final host = availableAddresses.first;
    final info = await widget.dependencies.localSyncServer.readInfo();
    if (!mounted) {
      return;
    }
    final previousSelfPeerId = _selfPeerDeviceId;
    if (previousSelfPeerId != null && previousSelfPeerId != info.deviceId) {
      widget.dependencies.localDiscoveryService.removePeer(previousSelfPeerId);
    }
    _selfPeerDeviceId = info.deviceId;
    widget.dependencies.localDiscoveryService.addOrReplacePeer(
      DiscoveredPeer(
        deviceId: info.deviceId,
        displayName: preferences.localDeviceName,
        address: host,
        port: widget.dependencies.localSyncServer.endpoint.port,
        platform: widget.platformName(),
        accessToken: info.accessToken,
        lastSeenAt: DateTime.now(),
      ),
    );
  }

  void _removeSelfPeer() {
    final selfPeerDeviceId = _selfPeerDeviceId;
    if (selfPeerDeviceId != null) {
      widget.dependencies.localDiscoveryService.removePeer(selfPeerDeviceId);
      _selfPeerDeviceId = null;
    }
    widget.dependencies.localDiscoveryService.removePeer('self');
  }

  bool _isSelfPeer(DiscoveredPeer peer) {
    final selfPeerDeviceId = _selfPeerDeviceId;
    return peer.deviceId == 'self' ||
        (selfPeerDeviceId != null && peer.deviceId == selfPeerDeviceId);
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _load();
    });
    await _future;
  }

  Future<void> _editPreferences(SyncPreferences preferences) async {
    final localDeviceName = TextEditingController(
      text: preferences.localDeviceName,
    );
    final localPeerAddress = TextEditingController(
      text: preferences.localPeerAddress,
    );
    final localPeerPort = TextEditingController(
      text: preferences.localPeerPort.toString(),
    );
    final localPeerAccessToken = TextEditingController(
      text: _formatPairingCode(preferences.localPeerAccessToken),
    );

    final confirmed =
        await showDialog<bool>(
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
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextField(
                              key: const Key('sync-local-pairing-code-field'),
                              controller: localPeerAccessToken,
                              decoration: const InputDecoration(
                                labelText: '目标配对码',
                                helperText: '在目标设备查看或扫码录入',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            key: const Key('sync-local-scan-pairing-button'),
                            onPressed: () => _scanPairingCodeInto(
                              addressController: localPeerAddress,
                              portController: localPeerPort,
                              tokenController: localPeerAccessToken,
                            ),
                            icon: const Icon(Icons.qr_code_scanner_outlined),
                            label: const Text('扫码'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text('扫描目标设备二维码可自动填写地址、端口和配对码。'),
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
      localPeerAccessToken: _normalizePairingCode(localPeerAccessToken.text),
    );
    DiscoveredPeer? verifiedPeer;
    if (nextPreferences.localPeerAddress.trim().isNotEmpty) {
      final candidate = _manualPeerFromPreferences(nextPreferences);
      final info = await widget.dependencies.localSyncClient.fetchInfo(
        peer: candidate,
      );
      verifiedPeer = candidate.copyWith(
        deviceId: info.deviceId,
        displayName: info.displayName,
        platform: info.platform,
        accessToken: candidate.accessToken,
      );
    }
    await widget.dependencies.updateSyncPreferences(nextPreferences);
    if (nextPreferences.localPeerAddress.trim().isEmpty) {
      widget.dependencies.localDiscoveryService.removePeer('manual-peer');
    } else if (verifiedPeer != null) {
      widget.dependencies.localDiscoveryService.addOrReplacePeer(
        verifiedPeer.copyWith(
          deviceId: 'manual-peer',
          lastSeenAt: DateTime.now(),
        ),
      );
    }
    if (widget.dependencies.localSyncServer.isRunning) {
      _syncSelfPeer(nextPreferences);
    }
    await _refresh();
  }

  Future<void> _scanPairingCodeInto({
    required TextEditingController addressController,
    required TextEditingController portController,
    required TextEditingController tokenController,
  }) async {
    if (!widget.supportsPairingScanner()) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('当前平台不支持扫码，请手动输入配对码')));
      return;
    }
    final payload = await Navigator.of(context).push<_LocalSyncPairingPayload>(
      MaterialPageRoute(
        builder: (context) => const _LocalSyncPairingScannerPage(),
      ),
    );
    if (payload == null) {
      return;
    }
    if (payload.host != null) {
      addressController.text = payload.host!;
    }
    if (payload.port != null) {
      portController.text = payload.port!.toString();
    }
    tokenController.text = _formatPairingCode(payload.accessToken);
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$error')));
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
      if (widget.dependencies.localSyncServer.isRunning) {
        await widget.dependencies.localSyncServer.stop();
        _removeSelfPeer();
      } else {
        await widget.dependencies.localSyncServer.start();
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
            widget.dependencies.localSyncServer.isRunning
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
    if (preferences.localPeerAccessToken.trim().isEmpty) {
      throw const FormatException('请先填写局域网同步配对码。');
    }
    return DiscoveredPeer(
      deviceId: 'manual-peer',
      displayName: preferences.localDeviceName,
      address: peerAddress,
      port: preferences.localPeerPort,
      platform: 'manual',
      accessToken: preferences.localPeerAccessToken,
      lastSeenAt: DateTime.now(),
    );
  }

  Future<void> _probeTarget(SyncPreferences preferences) async {
    await _runBusy(() async {
      final info = await widget.dependencies.localSyncClient.fetchInfo(
        peer: _manualPeerFromPreferences(preferences),
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('目标在线：${info.displayName}')));
    });
  }

  Future<void> _pushLocal(SyncPreferences preferences) async {
    await _runBusy(() async {
      await widget.dependencies.pushLocalSyncSnapshot(preferences);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已推送本地快照到目标设备')));
    });
  }

  Future<void> _pushCategory(
    SyncPreferences preferences,
    SyncDataCategory category,
  ) async {
    await _runBusy(() async {
      await widget.dependencies.pushLocalSyncSnapshot(
        preferences,
        categories: <SyncDataCategory>{category},
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已同步 ${_labelOfCategory(category)}')),
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
      localPeerAccessToken: peer.accessToken ?? '',
    );
    await widget.dependencies.updateSyncPreferences(nextPreferences);
    widget.dependencies.localDiscoveryService.addOrReplacePeer(
      DiscoveredPeer(
        deviceId: 'manual-peer',
        displayName: peer.displayName,
        address: peer.address,
        port: peer.port,
        platform: peer.platform,
        accessToken: peer.accessToken,
        lastSeenAt: DateTime.now(),
      ),
    );
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已选中 ${peer.address}:${peer.port}')));
    await _refresh();
  }

  Future<void> _copyAddress(String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('同步地址已复制')));
  }

  Future<void> _copyPairingCode(String value) async {
    await Clipboard.setData(ClipboardData(text: _formatPairingCode(value)));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('配对码已复制')));
  }

  String _normalizePairingCode(String value) {
    return _normalizeLocalSyncPairingCode(value);
  }

  String _formatPairingCode(String value) {
    return _formatLocalSyncPairingCode(value);
  }

  String _labelOfCategory(SyncDataCategory category) {
    return switch (category) {
      SyncDataCategory.settings => '设置',
      SyncDataCategory.library => '资料库',
      SyncDataCategory.history => '历史',
      SyncDataCategory.blockedKeywords => '屏蔽词',
    };
  }

  String _relativeLastSeen(DateTime value) {
    final diff = DateTime.now().difference(value);
    if (diff.inSeconds < 5) {
      return '刚刚在线';
    }
    if (diff.inMinutes < 1) {
      return '${diff.inSeconds} 秒前';
    }
    if (diff.inHours < 1) {
      return '${diff.inMinutes} 分钟前';
    }
    return '${diff.inHours} 小时前';
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
                widget.dependencies.localSyncServer.isRunning;
            final endpoints = _shareableEndpoints(
              widget.dependencies.localSyncServer.endpoint.port,
            );
            final pairingCode = data.localPairingCode;
            final formattedPairingCode = _formatPairingCode(pairingCode);
            final pairingQrData = _buildLocalSyncPairingQrData(
              preferences: preferences,
              addresses: _localAddresses,
              port: widget.dependencies.localSyncServer.endpoint.port,
              accessToken: pairingCode,
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
                        trailing: preferences.localPeerAccessToken.isEmpty
                            ? const Text('未配对')
                            : const Text('已配对'),
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
                            onPressed:
                                _busy ||
                                    preferences.localPeerAddress.trim().isEmpty
                                ? null
                                : () => _probeTarget(preferences),
                            icon: const Icon(Icons.verified_outlined),
                            label: const Text('测试目标'),
                          ),
                          FilledButton.tonalIcon(
                            key: const Key('sync-local-push-button'),
                            onPressed:
                                _busy ||
                                    preferences.localPeerAddress.trim().isEmpty
                                ? null
                                : () => _pushLocal(preferences),
                            icon: const Icon(Icons.send_outlined),
                            label: const Text('一键全量同步'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          for (final category in SyncDataCategory.values)
                            OutlinedButton.icon(
                              key: Key(
                                'sync-local-category-${category.apiValue}',
                              ),
                              onPressed:
                                  _busy ||
                                      preferences.localPeerAddress
                                          .trim()
                                          .isEmpty
                                  ? null
                                  : () => _pushCategory(preferences, category),
                              icon: const Icon(Icons.sync_alt_rounded),
                              label: Text(_labelOfCategory(category)),
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
                      else if (endpoints.isEmpty)
                        const Text('未检测到可分享的局域网地址，请在目标设备上手动输入本机地址。')
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
                      if (localServerRunning && pairingCode.isNotEmpty) ...[
                        const Divider(height: 20),
                        Text(
                          '本机配对码',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        SelectableText(formattedPairingCode),
                        const SizedBox(height: 12),
                        Center(
                          child: QrImageView(data: pairingQrData, size: 180),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _localAddresses.isEmpty
                              ? '扫码后会自动填写端口和配对码；目标地址需手动输入。'
                              : '扫码后会自动填写本机地址、端口和配对码。',
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: () => _copyPairingCode(pairingCode),
                            icon: const Icon(Icons.copy_outlined),
                            label: const Text('复制配对码'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                AppSurfaceCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '已发现设备',
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
                            subtitle: Text(
                              '${peer.platform} · ${peer.address}:${peer.port}',
                            ),
                            trailing: Text(
                              _isSelfPeer(peer)
                                  ? '本机'
                                  : preferences.localPeerAddress ==
                                            peer.address &&
                                        preferences.localPeerPort == peer.port
                                  ? '已选中'
                                  : _relativeLastSeen(peer.lastSeenAt),
                            ),
                            onTap: _busy || _isSelfPeer(peer)
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
    required this.localPairingCode,
  });

  final SyncSnapshot snapshot;
  final SyncPreferences preferences;
  final String localPairingCode;
}

class _LocalSyncPairingScannerPage extends StatefulWidget {
  const _LocalSyncPairingScannerPage();

  @override
  State<_LocalSyncPairingScannerPage> createState() =>
      _LocalSyncPairingScannerPageState();
}

class _LocalSyncPairingScannerPageState
    extends State<_LocalSyncPairingScannerPage> {
  final MobileScannerController _controller = MobileScannerController();
  bool _completed = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleDetect(BarcodeCapture capture) {
    if (_completed) {
      return;
    }
    for (final barcode in capture.barcodes) {
      final payload = _parseLocalSyncPairingPayload(
        barcode.rawValue ?? '',
        allowBareToken: false,
      );
      if (payload == null) {
        continue;
      }
      _completed = true;
      unawaited(_completeScan(payload));
      return;
    }
  }

  Future<void> _completeScan(_LocalSyncPairingPayload payload) async {
    try {
      await _controller.stop();
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(payload);
    } catch (error) {
      _completed = false;
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('扫码器停止失败：$error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('扫描配对二维码'),
        actions: [
          IconButton(
            tooltip: '闪光灯',
            onPressed: _controller.toggleTorch,
            icon: const Icon(Icons.flash_on_outlined),
          ),
          IconButton(
            tooltip: '切换摄像头',
            onPressed: _controller.switchCamera,
            icon: const Icon(Icons.flip_camera_android_outlined),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            fit: BoxFit.cover,
            onDetect: _handleDetect,
          ),
          const _PairingScannerOverlay(),
          const Positioned(
            left: 24,
            right: 24,
            bottom: 32,
            child: Text(
              '扫描目标设备“本机配对码”二维码',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PairingScannerOverlay extends StatefulWidget {
  const _PairingScannerOverlay();

  @override
  State<_PairingScannerOverlay> createState() => _PairingScannerOverlayState();
}

class _PairingScannerOverlayState extends State<_PairingScannerOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );
    _animation = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(0, 1),
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    _controller.repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: Container(
          width: 240,
          height: 240,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white70, width: 2),
          ),
          child: SlideTransition(
            position: _animation,
            child: Align(
              alignment: Alignment.topCenter,
              child: Container(height: 2, color: Colors.lightGreenAccent),
            ),
          ),
        ),
      ),
    );
  }
}
