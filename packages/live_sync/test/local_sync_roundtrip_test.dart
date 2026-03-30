import 'package:live_storage/live_storage.dart';
import 'package:live_sync/live_sync.dart';
import 'package:test/test.dart';

void main() {
  test('http local sync server accepts pushed snapshot', () async {
    SyncSnapshot current = const SyncSnapshot();
    final server = HttpLocalSyncServer(
      exportSnapshot: () async => current,
      importSnapshot: (snapshot) async {
        current = snapshot;
      },
      exportCategory: (_) async => current,
      importCategory: (_, snapshot) async {
        current = snapshot;
      },
      port: 28234,
    );
    await server.start();

    final client = HttpLocalSyncClient();
    await client.pushSnapshot(
      peer: DiscoveredPeer(
        deviceId: 'dev-1',
        displayName: '桌面端',
        address: '127.0.0.1',
        port: 28234,
        lastSeenAt: DateTime(2026, 3, 30),
      ),
      snapshot: const SyncSnapshot(
        tags: ['常看'],
        follows: [
          FollowRecord(providerId: 'douyu', roomId: '999', streamerName: '主播A'),
        ],
      ),
    );

    final exported = await server.exportSnapshot();
    expect(exported.tags, ['常看']);
    expect(exported.follows.single.roomId, '999');

    await server.stop();
  });

  test('http local sync server exposes peer info', () async {
    final server = HttpLocalSyncServer(
      exportSnapshot: () async => const SyncSnapshot(),
      importSnapshot: (_) async {},
      exportCategory: (_) async => const SyncSnapshot(),
      importCategory: (_, __) async {},
      readInfo: () async => const LocalSyncPeerInfo(
        displayName: '测试设备',
        deviceId: 'test-device',
        platform: 'linux',
      ),
      port: 28235,
    );
    await server.start();

    final client = HttpLocalSyncClient();
    final info = await client.fetchInfo(
      peer: DiscoveredPeer(
        deviceId: 'dev-2',
        displayName: '手机',
        address: '127.0.0.1',
        port: 28235,
        lastSeenAt: DateTime(2026, 3, 30),
      ),
    );

    expect(info.displayName, '测试设备');
    expect(info.deviceId, 'test-device');
    expect(info.platform, 'linux');
    expect(info.snapshotPath, '/snapshot');

    await server.stop();
  });
}
