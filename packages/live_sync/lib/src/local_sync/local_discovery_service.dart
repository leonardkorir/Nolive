import 'dart:async';

import '../model/discovered_peer.dart';

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
    if (!_controller.isClosed) {
      await _controller.close();
    }
  }

  void updatePeers(List<DiscoveredPeer> peers) {
    _peers = List<DiscoveredPeer>.unmodifiable(peers);
    _emit();
  }

  void addOrReplacePeer(DiscoveredPeer peer) {
    final next = [..._peers]
      ..removeWhere((item) => item.deviceId == peer.deviceId)
      ..add(peer);
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
