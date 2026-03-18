import '../../models/follow_record.dart';
import '../../persistence/local_storage_file_store.dart';
import '../follow_repository.dart';

class FileFollowRepository implements FollowRepository {
  FileFollowRepository(this.store);

  final LocalStorageFileStore store;

  @override
  Future<void> clear() {
    return store.update((snapshot) {
      snapshot.follows.clear();
    });
  }

  @override
  Future<bool> exists(String providerId, String roomId) {
    return store.read(
      (snapshot) => snapshot.follows.any(
        (item) => item.providerId == providerId && item.roomId == roomId,
      ),
    );
  }

  @override
  Future<List<FollowRecord>> listAll() {
    return store.read((snapshot) => List<FollowRecord>.from(snapshot.follows));
  }

  @override
  Future<void> remove(String providerId, String roomId) {
    return store.update((snapshot) {
      snapshot.follows.removeWhere(
        (item) => item.providerId == providerId && item.roomId == roomId,
      );
    });
  }

  @override
  Future<void> upsert(FollowRecord record) {
    return store.update((snapshot) {
      final existingIndex = snapshot.follows.indexWhere(
        (item) =>
            item.providerId == record.providerId &&
            item.roomId == record.roomId,
      );
      if (existingIndex >= 0) {
        snapshot.follows[existingIndex] = record;
        return;
      }
      snapshot.follows.insert(0, record);
    });
  }

  @override
  Future<void> upsertAll(Iterable<FollowRecord> records) {
    final nextRecords = records.toList(growable: false);
    if (nextRecords.isEmpty) {
      return Future<void>.value();
    }
    return store.update((snapshot) {
      for (final record in nextRecords) {
        final existingIndex = snapshot.follows.indexWhere(
          (item) =>
              item.providerId == record.providerId &&
              item.roomId == record.roomId,
        );
        if (existingIndex >= 0) {
          snapshot.follows[existingIndex] = record;
          continue;
        }
        snapshot.follows.insert(0, record);
      }
    });
  }
}
