import 'package:live_storage/live_storage.dart';

class SyncSnapshot {
  const SyncSnapshot({
    this.settings = const {},
    this.history = const [],
    this.follows = const [],
    this.tags = const [],
    this.blockedKeywords = const [],
  });

  final Map<String, Object?> settings;
  final List<HistoryRecord> history;
  final List<FollowRecord> follows;
  final List<String> tags;
  final List<String> blockedKeywords;
}
