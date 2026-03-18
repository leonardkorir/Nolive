import 'package:live_sync/live_sync.dart';

import 'sync_preferences_use_case.dart';

class VerifyWebDavConnectionUseCase {
  const VerifyWebDavConnectionUseCase();

  Future<void> call(SyncPreferences preferences) async {
    final service =
        HttpWebDavBackupService(config: preferences.toWebDavConfig());
    await service.testConnection();
  }
}

class UploadWebDavSnapshotUseCase {
  const UploadWebDavSnapshotUseCase(this.snapshotService);

  final RepositorySyncSnapshotService snapshotService;

  Future<void> call(SyncPreferences preferences) async {
    final service =
        HttpWebDavBackupService(config: preferences.toWebDavConfig());
    final snapshot = await snapshotService.exportSnapshot();
    await service.uploadSnapshot(snapshot);
  }
}

class RestoreWebDavSnapshotUseCase {
  const RestoreWebDavSnapshotUseCase(this.snapshotService);

  final RepositorySyncSnapshotService snapshotService;

  Future<SyncSnapshot?> call(SyncPreferences preferences) async {
    final service =
        HttpWebDavBackupService(config: preferences.toWebDavConfig());
    final snapshot = await service.restoreLatest();
    if (snapshot != null) {
      await snapshotService.importSnapshot(snapshot);
    }
    return snapshot;
  }
}
