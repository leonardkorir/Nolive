import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nolive_app/src/shared/presentation/settings_page_chrome.dart';
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
import 'package:nolive_app/src/shared/presentation/app_feedback.dart';

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
  /// 用户显式开启后，全量/设置类同步会附带平台 Cookie 与 WebDAV 密码。
  bool _includeSensitiveCredentials = false;

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
    // Auto-start LAN server so the page is usable without an extra tap
    // Always-on receive side.
    unawaited(_ensureLocalServerStarted());
  }

  Future<void> _ensureLocalServerStarted() async {
    if (widget.dependencies.localSyncServer.isRunning) {
      return;
    }
    try {
      await widget.dependencies.localSyncServer.start();
      if (!mounted) {
        return;
      }
      final addresses = await _readLocalAddresses();
      if (!mounted) {
        return;
      }
      setState(() {
        _localAddresses = addresses;
      });
      await _rememberSelfIdentity(addresses: addresses);
      await _refresh();
    } catch (error) {
      if (!mounted) {
        return;
      }
      showAppSnackBar(context, describeLocalSyncError(error));
    }
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
      await _rememberSelfIdentity(addresses: addresses);
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

  /// 只记录本机 deviceId / 地址，用于过滤发现列表；**绝不**把本机写进「附近设备」。
  Future<void> _rememberSelfIdentity({List<String>? addresses}) async {
    final availableAddresses = addresses ?? _localAddresses;
    try {
      final info = await widget.dependencies.localSyncServer.readInfo();
      if (!mounted) {
        return;
      }
      final previousSelfPeerId = _selfPeerDeviceId;
      _selfPeerDeviceId = info.deviceId;
      // 清掉历史版本误注入的本机条目。
      if (previousSelfPeerId != null) {
        widget.dependencies.localDiscoveryService.removePeer(previousSelfPeerId);
      }
      widget.dependencies.localDiscoveryService.removePeer(info.deviceId);
      widget.dependencies.localDiscoveryService.removePeer('self');
      if (availableAddresses.isNotEmpty) {
        // 保险：若旧逻辑按地址残留，remove 只能按 id；UI 侧再按地址过滤。
      }
    } catch (_) {
      // 读本机信息失败时不影响同步主流程。
    }
  }

  void _clearSelfIdentityFromDiscovery() {
    final selfPeerDeviceId = _selfPeerDeviceId;
    if (selfPeerDeviceId != null) {
      widget.dependencies.localDiscoveryService.removePeer(selfPeerDeviceId);
      _selfPeerDeviceId = null;
    }
    widget.dependencies.localDiscoveryService.removePeer('self');
  }

  bool _isSelfPeer(DiscoveredPeer peer) {
    final selfPeerDeviceId = _selfPeerDeviceId;
    if (peer.deviceId == 'self' ||
        (selfPeerDeviceId != null && peer.deviceId == selfPeerDeviceId)) {
      return true;
    }
    // 本机同步地址已在上方展示；同地址:端口视为本机，不进附近设备。
    final selfPort = widget.dependencies.localSyncServer.endpoint.port;
    if (peer.port != selfPort) {
      return false;
    }
    return _localAddresses.any((address) => address == peer.address);
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
    // 目标只保存在偏好里（上方「当前同步目标」）；不再往发现列表塞 manual-peer，
    // 避免与网络发现的同一 address:port 出现两条一模一样的设备。
    widget.dependencies.localDiscoveryService.removePeer('manual-peer');
    if (verifiedPeer != null &&
        verifiedPeer.deviceId.isNotEmpty &&
        verifiedPeer.deviceId != 'manual-peer') {
      // 可选：用真实 deviceId 刷新发现缓存，便于列表标「已选中」。
      widget.dependencies.localDiscoveryService.addOrReplacePeer(
        verifiedPeer.copyWith(lastSeenAt: DateTime.now()),
      );
    }
    if (widget.dependencies.localSyncServer.isRunning) {
      await _rememberSelfIdentity();
    }
    await _refresh();
    if (!mounted) {
      return;
    }
    if (nextPreferences.localPeerAddress.trim().isEmpty) {
      showAppSnackBar(context, '已保存本机名称');
    } else if (nextPreferences.localPeerAccessToken.trim().isEmpty) {
      showAppSnackBar(context, '已保存目标，但仍缺配对码');
    } else {
      showAppSnackBar(context, '目标已保存，可直接一键全量同步');
    }
  }

  Future<void> _scanPairingCodeInto({
    required TextEditingController addressController,
    required TextEditingController portController,
    required TextEditingController tokenController,
  }) async {
    if (!widget.supportsPairingScanner()) {
          showAppSnackBar(context, '当前平台不支持扫码，请手动输入配对码');
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
      showAppSnackBar(context, describeLocalSyncError(error));
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
        _clearSelfIdentityFromDiscovery();
      } else {
        await widget.dependencies.localSyncServer.start();
        final addresses = await _readLocalAddresses();
        if (mounted) {
          setState(() {
            _localAddresses = addresses;
          });
        }
        await _rememberSelfIdentity(addresses: addresses);
      }
      if (!mounted) {
        return;
      }
      showAppSnackBar(context, 
            widget.dependencies.localSyncServer.isRunning
                ? '局域网同步服务已启动'
                : '局域网同步服务已停止',
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
          showAppSnackBar(context, '目标在线：${info.displayName}');
    });
  }

  Future<void> _pushLocal(SyncPreferences preferences) async {
    await _runBusy(() async {
      await widget.dependencies.pushLocalSyncSnapshot(
        preferences,
        includeSensitiveCredentials: _includeSensitiveCredentials,
      );
      if (!mounted) {
        return;
      }
      showAppSnackBar(
        context,
        _includeSensitiveCredentials
            ? '已全量同步（含账号 Cookie / WebDAV 密码）'
            : '已全量同步（不含敏感账号凭证）',
      );
    });
  }

  Future<void> _pushCategory(
    SyncPreferences preferences,
    SyncDataCategory category,
  ) async {
    await _runBusy(() async {
      final includeCredentials = _includeSensitiveCredentials &&
          category == SyncDataCategory.settings;
      await widget.dependencies.pushLocalSyncSnapshot(
        preferences,
        categories: <SyncDataCategory>{category},
        includeSensitiveCredentials: includeCredentials,
      );
      if (!mounted) {
        return;
      }
      final credentialNote = includeCredentials ? '（含敏感凭证）' : '';
      showAppSnackBar(
        context,
        '已同步 ${_labelOfCategory(category)}$credentialNote',
      );
    });
  }

  Future<SyncPreferences> _savePeerAsTarget(
    SyncPreferences preferences,
    DiscoveredPeer peer, {
    bool announce = true,
  }) async {
    var accessToken = peer.accessToken?.trim() ?? '';
    if (accessToken.isEmpty) {
      accessToken = preferences.localPeerAccessToken.trim();
    }
    if (accessToken.isEmpty && announce && mounted) {
      showAppSnackBar(
        context,
        '该设备未提供配对码，请扫描对方二维码或在「编辑目标」中填写后再同步。',
      );
    }
    final nextPreferences = preferences.copyWith(
      localPeerAddress: peer.address,
      localPeerPort: peer.port,
      localPeerAccessToken: accessToken.isEmpty
          ? preferences.localPeerAccessToken
          : accessToken,
    );
    await widget.dependencies.updateSyncPreferences(nextPreferences);
    // 不写入 manual-peer，避免与 UDP 发现条目重复。
    widget.dependencies.localDiscoveryService.removePeer('manual-peer');
    if (peer.deviceId.isNotEmpty &&
        peer.deviceId != 'manual-peer' &&
        peer.deviceId != 'self') {
      widget.dependencies.localDiscoveryService.addOrReplacePeer(
        peer.copyWith(
          accessToken: accessToken.isEmpty ? peer.accessToken : accessToken,
          lastSeenAt: DateTime.now(),
        ),
      );
    }
    if (announce && mounted) {
      showAppSnackBar(
        context,
        accessToken.isEmpty
            ? '已选中 ${peer.displayName}（仍需配对码）'
            : '已选中 ${peer.displayName}，可直接点「一键全量同步」',
      );
    }
    await _refresh();
    return nextPreferences;
  }

  Future<void> _syncToPeer(
    SyncPreferences preferences,
    DiscoveredPeer peer,
  ) async {
    await _runBusy(() async {
      final next = await _savePeerAsTarget(
        preferences,
        peer,
        announce: false,
      );
      if (next.localPeerAccessToken.trim().isEmpty) {
        if (!mounted) {
          return;
        }
        showAppSnackBar(
          context,
          '缺少配对码：请扫对方二维码，或等设备广播更新后再试。',
        );
        return;
      }
      await widget.dependencies.pushLocalSyncSnapshot(
        next,
        includeSensitiveCredentials: _includeSensitiveCredentials,
      );
      if (!mounted) {
        return;
      }
      showAppSnackBar(
        context,
        _includeSensitiveCredentials
            ? '已同步到 ${peer.displayName}（含账号 Cookie / WebDAV 密码）'
            : '已同步到 ${peer.displayName}',
      );
    });
  }

  Future<void> _setIncludeSensitiveCredentials(bool enabled) async {
    if (!enabled) {
      setState(() {
        _includeSensitiveCredentials = false;
      });
      return;
    }
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: const Text('传输敏感凭证'),
              content: const Text(
                '开启后，全量同步与「我的-设置」同步会把本机的：\n'
                '· 各平台账号 Cookie\n'
                '· WebDAV 密码\n'
                '一并推到目标设备。\n\n'
                '仅建议在你信任的私有局域网、且目标设备也是你本人时使用。'
                '本机局域网身份（设备 ID / 本机配对码）不会被覆盖。',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('确认开启'),
                ),
              ],
            );
          },
        ) ??
        false;
    if (!mounted) {
      return;
    }
    setState(() {
      _includeSensitiveCredentials = confirmed;
    });
  }

  Future<void> _copyAddress(String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) {
      return;
    }
        showAppSnackBar(context, '同步地址已复制');
  }

  Future<void> _copyPairingCode(String value) async {
    await Clipboard.setData(ClipboardData(text: _formatPairingCode(value)));
    if (!mounted) {
      return;
    }
        showAppSnackBar(context, '配对码已复制');
  }

  String _normalizePairingCode(String value) {
    return _normalizeLocalSyncPairingCode(value);
  }

  String _formatPairingCode(String value) {
    return _formatLocalSyncPairingCode(value);
  }

  String _labelOfCategory(SyncDataCategory category) {
    return switch (category) {
      SyncDataCategory.settings => '我的-设置',
      SyncDataCategory.library => '关注与标签',
      SyncDataCategory.history => '观看历史',
      SyncDataCategory.blockedKeywords => '弹幕屏蔽词',
    };
  }

  String _subtitleOfCategory(SyncDataCategory category) {
    return switch (category) {
      SyncDataCategory.settings => '主题、播放器、布局等偏好（不含敏感密码，除非上方开关开启）',
      SyncDataCategory.library => '关注的主播记录 + 自定义标签',
      SyncDataCategory.history => '最近观看的直播间记录',
      SyncDataCategory.blockedKeywords => '弹幕关键词屏蔽列表',
    };
  }

  bool _isSelectedPeer(SyncPreferences preferences, DiscoveredPeer peer) {
    return preferences.localPeerAddress == peer.address &&
        preferences.localPeerPort == peer.port;
  }

  /// 附近设备：排除本机，并按 address:port 再去重（UI 层兜底）。
  List<DiscoveredPeer> _remotePeers() {
    final byEndpoint = <String, DiscoveredPeer>{};
    for (final peer in _peers) {
      if (_isSelfPeer(peer)) {
        continue;
      }
      final key = '${peer.address}:${peer.port}';
      final existing = byEndpoint[key];
      if (existing == null ||
          peer.lastSeenAt.isAfter(existing.lastSeenAt) ||
          (existing.deviceId == 'manual-peer' && peer.deviceId != 'manual-peer')) {
        byEndpoint[key] = peer;
      }
    }
    return byEndpoint.values.toList(growable: false);
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
                padding: kSettingsPagePadding,
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
            final remotePeers = _remotePeers();
            final hasTarget = preferences.localPeerAddress.trim().isNotEmpty;
            final hasPairing = preferences.localPeerAccessToken.trim().isNotEmpty;

            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: kSettingsPagePadding,
              children: [
                const SectionHeader(title: '局域网数据同步'),
                const SizedBox(height: 8),
                Text(
                  '双方打开本页 → 点附近设备或扫码 → 一键全量同步。'
                  '需要账号 Cookie / WebDAV 密码时打开下方开关。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
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
                        title: const Text('当前同步目标'),
                        subtitle: Text(
                          !hasTarget
                              ? '未选择（点附近设备，或编辑目标/扫码）'
                              : '${preferences.localPeerAddress}:${preferences.localPeerPort}',
                        ),
                        trailing: Text(
                          !hasTarget
                              ? '未选择'
                              : hasPairing
                              ? '已就绪'
                              : '缺配对码',
                        ),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.storage_outlined),
                        title: const Text('本机可同步数据'),
                        subtitle: Text(
                          '关注 ${data.snapshot.follows.length} · '
                          '标签 ${data.snapshot.tags.length} · '
                          '历史 ${data.snapshot.history.length} · '
                          '弹幕屏蔽词 ${data.snapshot.blockedKeywords.length}',
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
                      SwitchListTile(
                        key: const Key('sync-local-include-credentials-switch'),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: const Text('同时传输账号与 WebDAV 密码'),
                        subtitle: Text(
                          _includeSensitiveCredentials
                              ? '已开启：全量 /「我的-设置」会附带 Cookie 与 WebDAV 密码'
                              : '默认关闭：不含敏感凭证',
                        ),
                        value: _includeSensitiveCredentials,
                        onChanged: _busy
                            ? null
                            : (value) => unawaited(
                                _setIncludeSensitiveCredentials(value),
                              ),
                      ),
                      const SizedBox(height: 4),
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
                            onPressed: _busy || !hasTarget
                                ? null
                                : () => _probeTarget(preferences),
                            icon: const Icon(Icons.verified_outlined),
                            label: const Text('测试目标'),
                          ),
                          FilledButton.icon(
                            key: const Key('sync-local-push-button'),
                            onPressed: _busy || !hasTarget || !hasPairing
                                ? null
                                : () => _pushLocal(preferences),
                            icon: const Icon(Icons.send_outlined),
                            label: const Text('一键全量同步'),
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
                        '附近设备',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '点设备选中目标；「同步到此设备」= 选中并立即全量同步。',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      if (remotePeers.isEmpty)
                        const Text(
                          '暂未发现其他设备。本机地址见上方「当前同步目标」旁的本机信息与下方二维码，不会出现在此列表。',
                        )
                      else
                        for (final peer in remotePeers)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              _isSelectedPeer(preferences, peer)
                                  ? Icons.check_circle
                                  : Icons.devices_other_outlined,
                            ),
                            title: Text(peer.displayName),
                            subtitle: Text(
                              '${peer.platform} · ${peer.address}:${peer.port}'
                              '${peer.accessToken == null || peer.accessToken!.isEmpty ? ' · 无配对码' : ''}'
                              '\n${_relativeLastSeen(peer.lastSeenAt)}',
                            ),
                            isThreeLine: true,
                            trailing: FilledButton.tonal(
                              key: Key(
                                'sync-local-peer-push-${peer.deviceId}',
                              ),
                              onPressed: _busy
                                  ? null
                                  : () => _syncToPeer(preferences, peer),
                              child: Text(
                                _isSelectedPeer(preferences, peer)
                                    ? '同步'
                                    : '同步到此设备',
                              ),
                            ),
                            onTap: _busy
                                ? null
                                : () => unawaited(
                                    _savePeerAsTarget(preferences, peer),
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
                        '分类同步',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '数据量大时可比全量更稳。每项含义如下：',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      for (final category in SyncDataCategory.values)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.sync_alt_rounded),
                          title: Text(_labelOfCategory(category)),
                          subtitle: Text(_subtitleOfCategory(category)),
                          onTap: _busy || !hasTarget || !hasPairing
                              ? null
                              : () => _pushCategory(preferences, category),
                          trailing: FilledButton.tonal(
                            key: Key(
                              'sync-local-category-${category.apiValue}',
                            ),
                            onPressed: _busy || !hasTarget || !hasPairing
                                ? null
                                : () => _pushCategory(preferences, category),
                            child: const Text('同步'),
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
                        '本机同步地址与配对二维码',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      if (!localServerRunning)
                        const Text('服务未启动（打开本页通常会自动启动）。')
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
                          '本机配对码（对方扫这个）',
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
                              : '扫码后会自动填写本机地址、端口和配对码，保存后即可同步。',
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
            showAppErrorSnackBar(context, error, prefix: '扫码器停止失败：');
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
