import '../models/history_record.dart';

abstract class HistoryRepository {
  Future<List<HistoryRecord>> listRecent({int limit = 100});

  Future<void> add(HistoryRecord record);

  Future<void> remove(String providerId, String roomId);

  Future<void> clear();
}
