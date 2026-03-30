import 'package:live_sync/live_sync.dart';

import 'sync_preferences_use_case.dart';

class PushLocalSyncSnapshotUseCase {
  const PushLocalSyncSnapshotUseCase({
    required this.snapshotService,
    required this.client,
  });

  final RepositorySyncSnapshotService snapshotService;
  final LocalSyncClient client;

  Future<void> call(
    SyncPreferences preferences, {
    DiscoveredPeer? peer,
    Set<SyncDataCategory>? categories,
  }) async {
    final targetPeer = peer ?? _peerFromPreferences(preferences);
    final selectedCategories = categories ?? const <SyncDataCategory>{};
    if (selectedCategories.isEmpty ||
        selectedCategories.length == SyncDataCategory.values.length) {
      final snapshot = await snapshotService.exportSnapshot();
      await client.pushSnapshot(
        peer: targetPeer,
        snapshot: snapshot,
      );
      return;
    }
    for (final category in selectedCategories) {
      final partial = await snapshotService.exportCategory(category);
      await client.pushCategory(
        peer: targetPeer,
        category: category,
        snapshot: partial,
      );
    }
  }

  DiscoveredPeer _peerFromPreferences(SyncPreferences preferences) {
    final peerAddress = preferences.localPeerAddress.trim();
    if (peerAddress.isEmpty) {
      throw const FormatException('请先填写局域网目标地址');
    }
    return DiscoveredPeer(
      deviceId: 'manual-peer',
      displayName: '手动同步目标',
      address: peerAddress,
      port: preferences.localPeerPort,
      platform: 'unknown',
      lastSeenAt: DateTime.now(),
    );
  }
}
