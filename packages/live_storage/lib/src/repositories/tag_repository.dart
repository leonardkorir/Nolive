abstract class TagRepository {
  Future<void> clear();

  Future<List<String>> listAll();

  Future<void> create(String tag);

  Future<void> rename(String oldTag, String newTag);

  Future<void> remove(String tag);
}
