import 'package:nolive_app/src/features/settings/application/manage_history_preferences_use_case.dart';
import 'package:nolive_app/src/shared/application/provider_catalog_use_cases.dart';

import 'list_library_snapshot_use_case.dart';
import 'package:nolive_app/src/shared/application/storage_query_ports.dart';

class WatchHistoryFeatureDependencies {
  const WatchHistoryFeatureDependencies({
    required this.listLibrarySnapshot,
    required this.loadHistoryPreferences,
    required this.updateHistoryPreferences,
    required this.removeHistoryRecord,
    required this.clearHistory,
    required this.findProviderDescriptorById,
  });

  final ListLibrarySnapshotUseCase listLibrarySnapshot;
  final LoadHistoryPreferencesUseCase loadHistoryPreferences;
  final UpdateHistoryPreferencesUseCase updateHistoryPreferences;
  final RemoveHistoryRecord removeHistoryRecord;
  final ClearHistory clearHistory;
  final FindProviderDescriptorByIdUseCase findProviderDescriptorById;
}
