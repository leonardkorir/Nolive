import 'package:live_sync/live_sync.dart';

import 'sync_preferences_use_case.dart';

class PushLocalSyncSnapshotUseCase {
  const PushLocalSyncSnapshotUseCase({
    required this.snapshotService,
    required this.client,
  });

  final RepositorySyncSnapshotService snapshotService;
  final LocalSyncClient client;

  Future<void> call(SyncPreferences preferences) async {
    final peerAddress = preferences.localPeerAddress.trim();
    if (peerAddress.isEmpty) {
      throw const FormatException('请先填写局域网目标地址');
    }
    final snapshot = await snapshotService.exportSnapshot();
    await client.pushSnapshot(
      peer: DiscoveredPeer(
        deviceId: 'manual-peer',
        displayName: '手动同步目标',
        address: peerAddress,
        port: preferences.localPeerPort,
      ),
      snapshot: snapshot,
    );
  }
}
