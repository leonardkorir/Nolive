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
      port: 28234,
    );
    await server.start();

    final client = HttpLocalSyncClient();
    await client.pushSnapshot(
      peer: const DiscoveredPeer(
        deviceId: 'dev-1',
        displayName: '桌面端',
        address: '127.0.0.1',
        port: 28234,
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
      readInfo: () async => const LocalSyncPeerInfo(displayName: '测试设备'),
      port: 28235,
    );
    await server.start();

    final client = HttpLocalSyncClient();
    final info = await client.fetchInfo(
      peer: const DiscoveredPeer(
        deviceId: 'dev-2',
        displayName: '手机',
        address: '127.0.0.1',
        port: 28235,
      ),
    );

    expect(info.displayName, '测试设备');
    expect(info.snapshotPath, '/snapshot');

    await server.stop();
  });
}
