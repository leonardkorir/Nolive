import '../../persistence/local_storage_file_store.dart';
import '../tag_repository.dart';

class FileTagRepository implements TagRepository {
  FileTagRepository(this.store);

  final LocalStorageFileStore store;

  @override
  Future<void> clear() {
    return store.update((snapshot) {
      snapshot.tags.clear();
    });
  }

  @override
  Future<void> create(String tag) {
    final normalized = tag.trim();
    if (normalized.isEmpty) {
      return Future<void>.value();
    }
    return store.update((snapshot) {
      if (snapshot.tags.contains(normalized)) {
        return;
      }
      snapshot.tags.add(normalized);
      snapshot.tags.sort();
    });
  }

  @override
  Future<List<String>> listAll() {
    return store.read((snapshot) {
      final tags = List<String>.from(snapshot.tags)..sort();
      return tags;
    });
  }

  @override
  Future<void> remove(String tag) {
    return store.update((snapshot) {
      snapshot.tags.remove(tag);
    });
  }

  @override
  Future<void> rename(String oldTag, String newTag) {
    final normalized = newTag.trim();
    return store.update((snapshot) {
      final index = snapshot.tags.indexOf(oldTag);
      if (index < 0 || normalized.isEmpty) {
        return;
      }
      snapshot.tags[index] = normalized;
      snapshot.tags
        ..removeWhere((item) => item.trim().isEmpty)
        ..sort();
      final deduped = snapshot.tags.toSet().toList(growable: false)..sort();
      snapshot.tags
        ..clear()
        ..addAll(deduped);
    });
  }
}
