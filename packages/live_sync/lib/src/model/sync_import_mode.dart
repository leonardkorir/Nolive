/// How a remote/local snapshot should be applied.
enum SyncImportMode {
  /// Replace local category data with the incoming snapshot.
  replace,

  /// Bidirectional merge (tombstones, duration increments, LWW timestamps).
  merge,
}
