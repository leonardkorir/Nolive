import '../models/follow_record.dart';

abstract class FollowRepository {
  Future<List<FollowRecord>> listAll();

  Future<bool> exists(String providerId, String roomId);

  Future<void> upsert(FollowRecord record);

  Future<void> upsertAll(Iterable<FollowRecord> records) async {
    for (final record in records) {
      await upsert(record);
    }
  }

  Future<void> remove(String providerId, String roomId);

  Future<void> clear();
}
