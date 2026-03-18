import 'package:live_core/live_core.dart';
import 'package:live_sync/live_sync.dart';
import 'package:nolive_app/src/features/home/application/list_available_providers_use_case.dart';
import 'package:nolive_app/src/features/library/application/list_library_snapshot_use_case.dart';
import 'package:nolive_app/src/features/settings/application/load_sync_snapshot_use_case.dart';

class LoadHomeDashboardUseCase {
  const LoadHomeDashboardUseCase({
    required this.listAvailableProviders,
    required this.listLibrarySnapshot,
    required this.loadSyncSnapshot,
  });

  final ListAvailableProvidersUseCase listAvailableProviders;
  final ListLibrarySnapshotUseCase listLibrarySnapshot;
  final LoadSyncSnapshotUseCase loadSyncSnapshot;

  Future<HomeDashboard> call() async {
    final providers = listAvailableProviders();
    final library = await listLibrarySnapshot();
    final syncSnapshot = await loadSyncSnapshot();
    return HomeDashboard(
      providers: providers,
      library: library,
      syncSnapshot: syncSnapshot,
    );
  }
}

class HomeDashboard {
  const HomeDashboard({
    required this.providers,
    required this.library,
    required this.syncSnapshot,
  });

  final List<ProviderDescriptor> providers;
  final LibrarySnapshot library;
  final SyncSnapshot syncSnapshot;
}
