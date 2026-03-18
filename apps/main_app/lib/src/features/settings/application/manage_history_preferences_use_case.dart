import 'package:live_storage/live_storage.dart';

class HistoryPreferences {
  const HistoryPreferences({
    this.recordWatchHistory = true,
  });

  final bool recordWatchHistory;

  HistoryPreferences copyWith({
    bool? recordWatchHistory,
  }) {
    return HistoryPreferences(
      recordWatchHistory: recordWatchHistory ?? this.recordWatchHistory,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is HistoryPreferences &&
            runtimeType == other.runtimeType &&
            recordWatchHistory == other.recordWatchHistory;
  }

  @override
  int get hashCode => recordWatchHistory.hashCode;
}

class LoadHistoryPreferencesUseCase {
  const LoadHistoryPreferencesUseCase(this.settingsRepository);

  final SettingsRepository settingsRepository;

  Future<HistoryPreferences> call() async {
    return HistoryPreferences(
      recordWatchHistory: await settingsRepository
              .readValue<bool>('history_record_watch_enabled') ??
          true,
    );
  }
}

class UpdateHistoryPreferencesUseCase {
  const UpdateHistoryPreferencesUseCase(this.settingsRepository);

  final SettingsRepository settingsRepository;

  Future<void> call(HistoryPreferences preferences) {
    return settingsRepository.writeValue(
      'history_record_watch_enabled',
      preferences.recordWatchHistory,
    );
  }
}
