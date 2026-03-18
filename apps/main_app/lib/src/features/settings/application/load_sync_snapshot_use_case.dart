import 'package:live_sync/live_sync.dart';

class LoadSyncSnapshotUseCase {
  const LoadSyncSnapshotUseCase(this.snapshotService);

  final RepositorySyncSnapshotService snapshotService;

  Future<SyncSnapshot> call() => snapshotService.exportSnapshot();
}
