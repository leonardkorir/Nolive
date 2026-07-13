import 'dart:async';

import 'package:live_sync/live_sync.dart';
import 'package:test/test.dart';

void main() {
  test(
      'udp local discovery excludes self alias and self device announcements',
      () async {
    final service = UdpLocalDiscoveryService(
      readInfo: () async => const LocalSyncPeerInfo(
        displayName: '本机',
        deviceId: 'self-device',
        platform: 'android',
      ),
      broadcastPort: 28236,
      broadcastInterval: const Duration(minutes: 1),
    );
    final events = <List<DiscoveredPeer>>[];
    final subscription = service.watchPeers().listen(events.add);
    addTearDown(() async {
      await subscription.cancel();
      await service.stop();
    });

    await service.start();
    service.addOrReplacePeer(
      DiscoveredPeer(
        deviceId: 'self',
        displayName: '本机',
        address: '127.0.0.1',
        port: 23234,
        platform: 'android',
        lastSeenAt: DateTime(2026, 3, 30),
      ),
    );
    service.ingestAnnouncement(
      <String, dynamic>{
        'type': 'hello',
        'deviceId': 'self-device',
        'displayName': '本机',
        'platform': 'android',
        'port': 23234,
      },
      senderAddress: '192.168.1.10',
    );
    await Future<void>.delayed(Duration.zero);

    expect(events, isNotEmpty);
    // 本机条目不应出现在发现列表（地址已在同步页上方展示）。
    expect(events.last, isEmpty);
  });

  test(
      'udp local discovery dedupes manual-peer and network peer on same endpoint',
      () async {
    final service = UdpLocalDiscoveryService(
      readInfo: () async => const LocalSyncPeerInfo(
        displayName: '本机',
        deviceId: 'self-device',
        platform: 'android',
      ),
      broadcastPort: 28240,
      broadcastInterval: const Duration(minutes: 1),
    );
    final events = <List<DiscoveredPeer>>[];
    final subscription = service.watchPeers().listen(events.add);
    addTearDown(() async {
      await subscription.cancel();
      await service.stop();
    });

    await service.start();
    service.addOrReplacePeer(
      DiscoveredPeer(
        deviceId: 'manual-peer',
        displayName: '客厅平板',
        address: '192.168.1.20',
        port: 23234,
        platform: 'manual',
        lastSeenAt: DateTime(2026, 3, 30),
      ),
    );
    service.ingestAnnouncement(
      <String, dynamic>{
        'type': 'info',
        'deviceId': 'peer-real',
        'displayName': '客厅平板',
        'platform': 'android',
        'port': 23234,
      },
      senderAddress: '192.168.1.20',
    );
    await Future<void>.delayed(Duration.zero);

    expect(events, isNotEmpty);
    expect(events.last, hasLength(1));
    expect(events.last.single.deviceId, 'peer-real');
    expect(events.last.single.address, '192.168.1.20');
  });

  test('udp local discovery preserves announced low sync ports', () async {
    final service = UdpLocalDiscoveryService(
      readInfo: () async => const LocalSyncPeerInfo(
        displayName: '本机',
        deviceId: 'self-device',
        platform: 'android',
      ),
      broadcastPort: 28237,
      broadcastInterval: const Duration(minutes: 1),
    );
    final events = <List<DiscoveredPeer>>[];
    final subscription = service.watchPeers().listen(events.add);
    addTearDown(() async {
      await subscription.cancel();
      await service.stop();
    });

    await service.start();
    service.ingestAnnouncement(
      <String, dynamic>{
        'type': 'info',
        'deviceId': 'desktop-1',
        'displayName': '桌面端',
        'platform': 'linux',
        'port': 12000,
      },
      senderAddress: '192.168.1.20',
    );
    await Future<void>.delayed(Duration.zero);

    expect(events, isNotEmpty);
    expect(
      events.last.singleWhere((peer) => peer.deviceId == 'desktop-1').port,
      12000,
    );
  });

  test('udp local discovery ignores announcements from non-local addresses',
      () async {
    final service = UdpLocalDiscoveryService(
      readInfo: () async => const LocalSyncPeerInfo(
        displayName: '本机',
        deviceId: 'self-device',
        platform: 'android',
      ),
      broadcastPort: 28238,
      broadcastInterval: const Duration(minutes: 1),
    );
    final events = <List<DiscoveredPeer>>[];
    final subscription = service.watchPeers().listen(events.add);
    addTearDown(() async {
      await subscription.cancel();
      await service.stop();
    });

    await service.start();
    service.ingestAnnouncement(
      <String, dynamic>{
        'type': 'info',
        'deviceId': 'public-peer',
        'displayName': '公网端',
        'platform': 'linux',
        'port': 23234,
      },
      senderAddress: '8.8.8.8',
    );
    await Future<void>.delayed(Duration.zero);

    expect(
      events
          .expand((peers) => peers)
          .any((peer) => peer.deviceId == 'public-peer'),
      isFalse,
    );
  });

  test('udp local discovery ignores unsupported announcement types', () async {
    final service = UdpLocalDiscoveryService(
      readInfo: () async => const LocalSyncPeerInfo(
        displayName: '本机',
        deviceId: 'self-device',
        platform: 'android',
      ),
      broadcastPort: 28239,
      broadcastInterval: const Duration(minutes: 1),
    );
    final events = <List<DiscoveredPeer>>[];
    final subscription = service.watchPeers().listen(events.add);
    addTearDown(() async {
      await subscription.cancel();
      await service.stop();
    });

    await service.start();
    service.ingestAnnouncement(
      <String, dynamic>{
        'type': 'probe',
        'deviceId': 'unknown-peer',
        'displayName': '未知端',
        'platform': 'linux',
        'port': 23234,
      },
      senderAddress: '192.168.1.21',
    );
    await Future<void>.delayed(Duration.zero);

    expect(
      events
          .expand((peers) => peers)
          .any((peer) => peer.deviceId == 'unknown-peer'),
      isFalse,
    );
  });
}
