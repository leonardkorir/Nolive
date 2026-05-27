abstract class TagRepository {
  Future<void> clear();

  /// Returns tags sorted by display value.
  Future<List<String>> listAll();

  /// Creates [tag] if it does not already exist.
  ///
  /// Duplicate creates are intentionally idempotent.
  Future<void> create(String tag);

  /// Renames an existing tag.
  ///
  /// Implementations throw [StateError] when [oldTag] does not exist.
  Future<void> rename(String oldTag, String newTag);

  Future<void> remove(String tag);
}
