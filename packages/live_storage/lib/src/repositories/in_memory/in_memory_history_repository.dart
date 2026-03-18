import '../../models/history_record.dart';
import '../history_repository.dart';

class InMemoryHistoryRepository implements HistoryRepository {
  final List<HistoryRecord> _records = [];

  @override
  Future<void> add(HistoryRecord record) async {
    _records.removeWhere(
      (item) =>
          item.providerId == record.providerId && item.roomId == record.roomId,
    );
    _records.insert(0, record);
  }

  @override
  Future<void> clear() async {
    _records.clear();
  }

  @override
  Future<List<HistoryRecord>> listRecent({int limit = 100}) async {
    return _records.take(limit).toList(growable: false);
  }

  @override
  Future<void> remove(String providerId, String roomId) async {
    _records.removeWhere(
      (item) => item.providerId == providerId && item.roomId == roomId,
    );
  }
}
