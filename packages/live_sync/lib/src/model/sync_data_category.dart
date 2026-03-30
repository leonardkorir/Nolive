enum SyncDataCategory {
  settings('settings'),
  library('library'),
  history('history'),
  blockedKeywords('blocked_keywords');

  const SyncDataCategory(this.apiValue);

  final String apiValue;

  static SyncDataCategory? tryParse(String? raw) {
    if (raw == null) {
      return null;
    }
    for (final value in SyncDataCategory.values) {
      if (value.apiValue == raw) {
        return value;
      }
    }
    return null;
  }
}
