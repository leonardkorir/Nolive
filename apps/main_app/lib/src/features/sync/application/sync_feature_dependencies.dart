import 'package:live_sync/live_sync.dart';
import 'package:nolive_app/src/app/bootstrap/bootstrap.dart';

import 'manage_local_sync_use_case.dart';
import 'manage_remote_sync_use_case.dart';
import 'sync_preferences_use_case.dart';
import '../../settings/application/load_sync_snapshot_use_case.dart';

class SyncFeatureDependencies {
  const SyncFeatureDependencies({
    required this.loadSyncSnapshot,
    required this.loadSyncPreferences,
    required this.updateSyncPreferences,
    required this.verifyWebDavConnection,
    required this.uploadWebDavSnapshot,
    required this.restoreWebDavSnapshot,
    required this.pushLocalSyncSnapshot,
    required this.localDiscoveryService,
    required this.localSyncServer,
    required this.localSyncClient,
  });

  factory SyncFeatureDependencies.fromBootstrap(AppBootstrap bootstrap) {
    return SyncFeatureDependencies(
      loadSyncSnapshot: bootstrap.loadSyncSnapshot,
      loadSyncPreferences: bootstrap.loadSyncPreferences,
      updateSyncPreferences: bootstrap.updateSyncPreferences,
      verifyWebDavConnection: bootstrap.verifyWebDavConnection,
      uploadWebDavSnapshot: bootstrap.uploadWebDavSnapshot,
      restoreWebDavSnapshot: bootstrap.restoreWebDavSnapshot,
      pushLocalSyncSnapshot: bootstrap.pushLocalSyncSnapshot,
      localDiscoveryService: bootstrap.localDiscoveryService,
      localSyncServer: bootstrap.localSyncServer,
      localSyncClient: bootstrap.localSyncClient,
    );
  }

  final LoadSyncSnapshotUseCase loadSyncSnapshot;
  final LoadSyncPreferencesUseCase loadSyncPreferences;
  final UpdateSyncPreferencesUseCase updateSyncPreferences;
  final VerifyWebDavConnectionUseCase verifyWebDavConnection;
  final UploadWebDavSnapshotUseCase uploadWebDavSnapshot;
  final RestoreWebDavSnapshotUseCase restoreWebDavSnapshot;
  final PushLocalSyncSnapshotUseCase pushLocalSyncSnapshot;
  final UdpLocalDiscoveryService localDiscoveryService;
  final HttpLocalSyncServer localSyncServer;
  final HttpLocalSyncClient localSyncClient;
}
