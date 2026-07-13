import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../model/discovered_peer.dart';
import '../model/local_sync_peer_info.dart';

abstract class LocalDiscoveryService {
  Stream<List<DiscoveredPeer>> watchPeers();

  Future<void> start();

  Future<void> stop();

  Future<void> dispose();

  void addOrReplacePeer(DiscoveredPeer peer);

  void removePeer(String deviceId);
}

class ManualLocalDiscoveryService implements LocalDiscoveryService {
  final StreamController<List<DiscoveredPeer>> _controller =
      StreamController<List<DiscoveredPeer>>.broadcast();
  List<DiscoveredPeer> _peers = const [];

  @override
  Stream<List<DiscoveredPeer>> watchPeers() => _controller.stream;

  List<DiscoveredPeer> get currentPeers => _peers;

  @override
  Future<void> start() async {
    _emit();
  }

  @override
  Future<void> stop() async {
    updatePeers(const []);
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _controller.close();
  }

  void updatePeers(List<DiscoveredPeer> peers) {
    _peers = List<DiscoveredPeer>.unmodifiable(peers);
    _emit();
  }

  @override
  void addOrReplacePeer(DiscoveredPeer peer) {
    final next = [..._peers]
      ..removeWhere((item) => item.deviceId == peer.deviceId)
      ..add(peer.copyWith(lastSeenAt: DateTime.now()));
    updatePeers(next);
  }

  @override
  void removePeer(String deviceId) {
    updatePeers(
      _peers.where((item) => item.deviceId != deviceId).toList(growable: false),
    );
  }

  void _emit() {
    if (!_controller.isClosed) {
      _controller.add(_peers);
    }
  }
}

class UdpLocalDiscoveryService implements LocalDiscoveryService {
  UdpLocalDiscoveryService({
    required this.readInfo,
    this.broadcastPort = 23235,
    this.broadcastInterval = const Duration(seconds: 2),
    this.peerTtl = const Duration(seconds: 8),
  });

  final Future<LocalSyncPeerInfo> Function() readInfo;
  final int broadcastPort;
  final Duration broadcastInterval;
  final Duration peerTtl;

  final StreamController<List<DiscoveredPeer>> _controller =
      StreamController<List<DiscoveredPeer>>.broadcast();
  final Map<String, DiscoveredPeer> _manualPeers = <String, DiscoveredPeer>{};
  final Map<String, DiscoveredPeer> _networkPeers = <String, DiscoveredPeer>{};

  RawDatagramSocket? _socket;
  Timer? _broadcastTimer;
  Timer? _expiryTimer;
  String? _selfDeviceId;

  @override
  Stream<List<DiscoveredPeer>> watchPeers() => _controller.stream;

  @override
  void addOrReplacePeer(DiscoveredPeer peer) {
    _manualPeers[peer.deviceId] = peer.copyWith(lastSeenAt: DateTime.now());
    _emit();
  }

  @override
  void removePeer(String deviceId) {
    _manualPeers.remove(deviceId);
    _networkPeers.remove(deviceId);
    _emit();
  }

  @override
  Future<void> start() async {
    if (_socket != null) {
      _emit();
      return;
    }
    // Android/Dart 不支持 SO_REUSEPORT；硬开 reusePort 会刷 ERROR 且无收益。
    // 仅 reuseAddress 即可满足局域网 UDP 发现。
    final socket = await _bindDiscoverySocket();
    socket.broadcastEnabled = true;
    socket.readEventsEnabled = true;
    socket.listen(_handleSocketEvent);
    _socket = socket;
    final info = await readInfo();
    _selfDeviceId = info.deviceId;
    _broadcastTimer?.cancel();
    _broadcastTimer = Timer.periodic(broadcastInterval, (_) {
      unawaited(_broadcastHello());
    });
    _expiryTimer?.cancel();
    _expiryTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _evictExpiredPeers();
    });
    await _broadcastHello();
    _emit();
  }

  @override
  Future<void> stop() async {
    _broadcastTimer?.cancel();
    _broadcastTimer = null;
    _expiryTimer?.cancel();
    _expiryTimer = null;
    _networkPeers.clear();
    _socket?.close();
    _socket = null;
    _selfDeviceId = null;
    _emit();
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _controller.close();
  }

  Future<void> _broadcastHello() async {
    final socket = _socket;
    if (socket == null) {
      return;
    }
    final info = await readInfo();
    final payload = utf8.encode(
      jsonEncode(<String, Object?>{
        'type': 'hello',
        ...info.toJson(includeAccessToken: true),
        'port': _resolveSyncPort(info.snapshotPath),
      }),
    );
    socket.send(payload, InternetAddress('255.255.255.255'), broadcastPort);
  }

  Future<RawDatagramSocket> _bindDiscoverySocket() async {
    try {
      return await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        broadcastPort,
        reuseAddress: true,
      );
    } catch (_) {
      // 端口偶发占用时再尝试 reusePort（多数移动端仍会忽略该选项）。
      return RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        broadcastPort,
        reuseAddress: true,
        reusePort: false,
      );
    }
  }

  void _handleSocketEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) {
      return;
    }
    final datagram = _socket?.receive();
    if (datagram == null) {
      return;
    }
    try {
      final decoded = json.decode(utf8.decode(datagram.data));
      if (decoded is! Map) {
        return;
      }
      ingestAnnouncement(
        decoded.cast<String, dynamic>(),
        senderAddress: datagram.address.address,
      );
    } catch (_) {
      // Ignore malformed discovery packets.
    }
  }

  void ingestAnnouncement(
    Map<String, dynamic> payload, {
    required String senderAddress,
  }) {
    if (!_isTrustedSender(senderAddress)) {
      return;
    }
    final type = payload['type']?.toString();
    if (type != 'hello' && type != 'info') {
      return;
    }
    final info = LocalSyncPeerInfo.fromJson(payload);
    if (info.deviceId == _safeSelfDeviceId) {
      return;
    }
    final port = _resolvePayloadPort(payload['port']);
    final peer = DiscoveredPeer(
      deviceId: info.deviceId,
      displayName: info.displayName,
      address: senderAddress,
      port: port,
      platform: info.platform,
      accessToken: info.accessToken,
      lastSeenAt: DateTime.now(),
    );
    _networkPeers[peer.deviceId] = peer;
    _emit();
    if (type == 'hello') {
      unawaited(_replyInfo(peer.address));
    }
  }

  void evictExpiredPeers({DateTime? now}) {
    _evictExpiredPeers(now: now);
  }

  Future<void> _replyInfo(String address) async {
    final socket = _socket;
    if (socket == null) {
      return;
    }
    final info = await readInfo();
    final payload = utf8.encode(
      jsonEncode(<String, Object?>{
        'type': 'info',
        ...info.toJson(includeAccessToken: true),
        'port': _resolveSyncPort(info.snapshotPath),
      }),
    );
    socket.send(payload, InternetAddress(address), broadcastPort);
  }

  void _evictExpiredPeers({DateTime? now}) {
    final current = now ?? DateTime.now();
    final expiredIds = _networkPeers.values
        .where((peer) => current.difference(peer.lastSeenAt) > peerTtl)
        .map((peer) => peer.deviceId)
        .toList(growable: false);
    if (expiredIds.isEmpty) {
      return;
    }
    for (final deviceId in expiredIds) {
      _networkPeers.remove(deviceId);
    }
    _emit();
  }

  int _resolveSyncPort(String snapshotPath) {
    final path = Uri.tryParse(snapshotPath);
    final fallback = 23234;
    if (path == null) {
      return fallback;
    }
    return path.port > 0 ? path.port : fallback;
  }

  int _resolvePayloadPort(Object? raw) {
    final port = int.tryParse(raw?.toString() ?? '');
    if (port == null || port <= 0) {
      return 23234;
    }
    return port;
  }

  String get _safeSelfDeviceId {
    return _selfDeviceId ?? '';
  }

  bool _isTrustedSender(String senderAddress) {
    final address = InternetAddress.tryParse(senderAddress);
    if (address == null) {
      return false;
    }
    if (address.isLoopback) {
      return true;
    }
    if (address.type != InternetAddressType.IPv4) {
      return false;
    }
    final octets = address.rawAddress;
    if (octets.length < 4) {
      return false;
    }
    final first = octets[0];
    final second = octets[1];
    if (first == 10 || first == 127) {
      return true;
    }
    if (first == 172 && second >= 16 && second <= 31) {
      return true;
    }
    if (first == 192 && second == 168) {
      return true;
    }
    if (first == 169 && second == 254) {
      return true;
    }
    return false;
  }

  void _emit() {
    if (_controller.isClosed) {
      return;
    }
    // 合并 manual + network，并按 address:port 去重。
    // 常见重复：选中目标时写入 manual-peer，网络侧仍有真实 deviceId 的同地址条目。
    final byEndpoint = <String, DiscoveredPeer>{};
    for (final peer in [
      ..._networkPeers.values,
      ..._manualPeers.values,
    ]) {
      if (_isSelfDeviceId(peer.deviceId)) {
        continue;
      }
      final key = _endpointKey(peer);
      final existing = byEndpoint[key];
      if (existing == null) {
        byEndpoint[key] = peer;
        continue;
      }
      byEndpoint[key] = _preferPeer(existing, peer);
    }
    final peers = byEndpoint.values.toList(growable: false)
      ..sort((left, right) => right.lastSeenAt.compareTo(left.lastSeenAt));
    _controller.add(List<DiscoveredPeer>.unmodifiable(peers));
  }

  bool _isSelfDeviceId(String deviceId) {
    if (deviceId == 'self') {
      return true;
    }
    final selfId = _selfDeviceId;
    return selfId != null && selfId.isNotEmpty && deviceId == selfId;
  }

  String _endpointKey(DiscoveredPeer peer) {
    return '${peer.address.trim()}:${peer.port}';
  }

  /// 同地址端口时优先保留：网络真实设备 ID > 非 manual 标签 > 更新鲜的。
  DiscoveredPeer _preferPeer(DiscoveredPeer left, DiscoveredPeer right) {
    final leftManual = left.deviceId == 'manual-peer' || left.platform == 'manual';
    final rightManual =
        right.deviceId == 'manual-peer' || right.platform == 'manual';
    if (leftManual != rightManual) {
      return leftManual ? right : left;
    }
    if (left.lastSeenAt.isAfter(right.lastSeenAt)) {
      // 合并较新 token / 名称
      return left.copyWith(
        accessToken: left.accessToken?.isNotEmpty == true
            ? left.accessToken
            : right.accessToken,
        displayName: left.displayName.isNotEmpty
            ? left.displayName
            : right.displayName,
      );
    }
    return right.copyWith(
      accessToken: right.accessToken?.isNotEmpty == true
          ? right.accessToken
          : left.accessToken,
      displayName:
          right.displayName.isNotEmpty ? right.displayName : left.displayName,
    );
  }
}
