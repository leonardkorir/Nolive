import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../model/discovered_peer.dart';
import '../model/local_sync_peer_info.dart';

abstract class LocalDiscoveryService {
  Stream<List<DiscoveredPeer>> watchPeers();

  Future<void> start();

  Future<void> stop();
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

  void updatePeers(List<DiscoveredPeer> peers) {
    _peers = List<DiscoveredPeer>.unmodifiable(peers);
    _emit();
  }

  void addOrReplacePeer(DiscoveredPeer peer) {
    final next = [..._peers]
      ..removeWhere((item) => item.deviceId == peer.deviceId)
      ..add(peer.copyWith(lastSeenAt: DateTime.now()));
    updatePeers(next);
  }

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

  void addOrReplacePeer(DiscoveredPeer peer) {
    _manualPeers[peer.deviceId] = peer.copyWith(lastSeenAt: DateTime.now());
    _emit();
  }

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
    final socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      broadcastPort,
      reuseAddress: true,
      reusePort: true,
    );
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

  Future<void> _broadcastHello() async {
    final socket = _socket;
    if (socket == null) {
      return;
    }
    final info = await readInfo();
    final payload = utf8.encode(
      jsonEncode(<String, Object?>{
        'type': 'hello',
        'deviceId': info.deviceId,
        'displayName': info.displayName,
        'platform': info.platform,
        'port': _resolveSyncPort(info.snapshotPath),
      }),
    );
    socket.send(payload, InternetAddress('255.255.255.255'), broadcastPort);
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
    final type = payload['type']?.toString();
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
        ...info.toJson(),
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

  void _emit() {
    if (_controller.isClosed) {
      return;
    }
    final peers = <DiscoveredPeer>[
      ..._manualPeers.values,
      ..._networkPeers.values
          .where((peer) => !_manualPeers.containsKey(peer.deviceId)),
    ]..sort((left, right) {
        if (left.deviceId == 'self') {
          return -1;
        }
        if (right.deviceId == 'self') {
          return 1;
        }
        return right.lastSeenAt.compareTo(left.lastSeenAt);
      });
    _controller.add(List<DiscoveredPeer>.unmodifiable(peers));
  }
}
