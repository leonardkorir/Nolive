import 'package:nolive_app/src/features/settings/application/manage_history_preferences_use_case.dart';
import 'package:nolive_app/src/shared/application/provider_catalog_use_cases.dart';

import 'clear_history_use_case.dart';
import 'list_library_snapshot_use_case.dart';
import 'remove_history_record_use_case.dart';

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
  final RemoveHistoryRecordUseCase removeHistoryRecord;
  final ClearHistoryUseCase clearHistory;
  final FindProviderDescriptorByIdUseCase findProviderDescriptorById;
}
