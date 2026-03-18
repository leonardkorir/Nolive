import '../../models/follow_record.dart';
import '../follow_repository.dart';

class InMemoryFollowRepository implements FollowRepository {
  final List<FollowRecord> _records = [];

  @override
  Future<void> clear() async {
    _records.clear();
  }

  @override
  Future<bool> exists(String providerId, String roomId) async {
    return _records.any(
      (item) => item.providerId == providerId && item.roomId == roomId,
    );
  }

  @override
  Future<List<FollowRecord>> listAll() async {
    return List<FollowRecord>.unmodifiable(_records);
  }

  @override
  Future<void> remove(String providerId, String roomId) async {
    _records.removeWhere(
      (item) => item.providerId == providerId && item.roomId == roomId,
    );
  }

  @override
  Future<void> upsert(FollowRecord record) async {
    final existingIndex = _records.indexWhere(
      (item) =>
          item.providerId == record.providerId && item.roomId == record.roomId,
    );
    if (existingIndex >= 0) {
      _records[existingIndex] = record;
      return;
    }
    _records.insert(0, record);
  }

  @override
  Future<void> upsertAll(Iterable<FollowRecord> records) async {
    for (final record in records) {
      await upsert(record);
    }
  }
}
