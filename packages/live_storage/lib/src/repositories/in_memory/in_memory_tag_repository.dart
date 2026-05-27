import '../tag_repository.dart';

class InMemoryTagRepository implements TagRepository {
  final List<String> _tags = [];

  @override
  Future<void> clear() async {
    _tags.clear();
  }

  @override
  Future<void> create(String tag) async {
    final normalized = tag.trim();
    if (normalized.isEmpty) {
      return;
    }
    if (_tags.contains(normalized)) {
      return;
    }
    _tags.add(normalized);
  }

  @override
  Future<List<String>> listAll() async {
    final sorted = [..._tags]..sort();
    return sorted;
  }

  @override
  Future<void> remove(String tag) async {
    _tags.remove(tag.trim());
  }

  @override
  Future<void> rename(String oldTag, String newTag) async {
    final normalized = newTag.trim();
    if (normalized.isEmpty) {
      return;
    }
    final index = _tags.indexOf(oldTag);
    if (index < 0) {
      throw StateError('Tag not found: $oldTag');
    }
    _tags[index] = normalized;
    _tags
      ..removeWhere((item) => item.trim().isEmpty)
      ..sort();
    final deduped = _tags.toSet().toList(growable: false)..sort();
    _tags
      ..clear()
      ..addAll(deduped);
  }
}
