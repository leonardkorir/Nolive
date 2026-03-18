import '../tag_repository.dart';

class InMemoryTagRepository implements TagRepository {
  final List<String> _tags = [];

  @override
  Future<void> clear() async {
    _tags.clear();
  }

  @override
  Future<void> create(String tag) async {
    if (_tags.contains(tag)) {
      return;
    }
    _tags.add(tag);
  }

  @override
  Future<List<String>> listAll() async {
    final sorted = [..._tags]..sort();
    return sorted;
  }

  @override
  Future<void> remove(String tag) async {
    _tags.remove(tag);
  }

  @override
  Future<void> rename(String oldTag, String newTag) async {
    final index = _tags.indexOf(oldTag);
    if (index < 0) {
      return;
    }
    _tags[index] = newTag;
  }
}
