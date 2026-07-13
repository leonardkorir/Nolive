import 'package:live_sync/live_sync.dart';

import '../../settings/application/secure_snapshot_import_coordinator.dart';
import 'sync_preferences_use_case.dart';

typedef WebDavBackupServiceFactory =
    WebDavBackupService Function(WebDavBackupConfig config);

WebDavBackupService _createWebDavBackupService(WebDavBackupConfig config) {
  return HttpWebDavBackupService(config: config);
}

class VerifyWebDavConnectionUseCase {
  const VerifyWebDavConnectionUseCase({
    WebDavBackupServiceFactory? createService,
  }) : _createService = createService;

  final WebDavBackupServiceFactory? _createService;

  Future<void> call(SyncPreferences preferences) async {
    final service = (_createService ?? _createWebDavBackupService)(
      preferences.toWebDavConfig(),
    );
    try {
      await service.testConnection();
    } finally {
      await service.close(force: true);
    }
  }
}

class UploadWebDavSnapshotUseCase {
  const UploadWebDavSnapshotUseCase(
    this.snapshotService, {
    WebDavBackupServiceFactory? createService,
  }) : _createService = createService;

  final RepositorySyncSnapshotService snapshotService;
  final WebDavBackupServiceFactory? _createService;

  Future<void> call(SyncPreferences preferences) async {
    final service = (_createService ?? _createWebDavBackupService)(
      preferences.toWebDavConfig(),
    );
    try {
      final snapshot = await snapshotService.exportSnapshot();
      await service.uploadSnapshot(snapshot);
    } finally {
      await service.close(force: true);
    }
  }
}

class RestoreWebDavSnapshotUseCase {
  const RestoreWebDavSnapshotUseCase(
    this.snapshotImportCoordinator, {
    WebDavBackupServiceFactory? createService,
  }) : _createService = createService;

  final SecureSnapshotImportCoordinator snapshotImportCoordinator;
  final WebDavBackupServiceFactory? _createService;

  Future<SyncSnapshot?> call(
    SyncPreferences preferences, {
    SyncImportMode mode = SyncImportMode.replace,
    DateTime? lastSyncAt,
  }) async {
    final service = (_createService ?? _createWebDavBackupService)(
      preferences.toWebDavConfig(),
    );
    try {
      final snapshot = await service.restoreLatest();
      if (snapshot != null) {
        await snapshotImportCoordinator.importSnapshot(
          snapshot,
          mode: mode,
          lastSyncAt: lastSyncAt,
        );
      }
      return snapshot;
    } finally {
      await service.close(force: true);
    }
  }
}
