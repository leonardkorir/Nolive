import '../../models/history_record.dart';
import '../../persistence/local_storage_file_store.dart';
import '../history_repository.dart';

class FileHistoryRepository implements HistoryRepository {
  FileHistoryRepository(this.store);

  final LocalStorageFileStore store;

  @override
  Future<void> add(HistoryRecord record) {
    return store.update((snapshot) {
      snapshot.history.removeWhere(
        (item) =>
            item.providerId == record.providerId &&
            item.roomId == record.roomId,
      );
      snapshot.history.insert(0, record);
    });
  }

  @override
  Future<void> clear() {
    return store.update((snapshot) {
      snapshot.history.clear();
    });
  }

  @override
  Future<List<HistoryRecord>> listRecent({int limit = 100}) {
    return store.read(
      (snapshot) => snapshot.history.take(limit).toList(growable: false),
    );
  }

  @override
  Future<void> remove(String providerId, String roomId) {
    return store.update((snapshot) {
      snapshot.history.removeWhere(
        (item) => item.providerId == providerId && item.roomId == roomId,
      );
    });
  }
}
