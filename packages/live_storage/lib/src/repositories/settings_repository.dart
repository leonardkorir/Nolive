abstract class SettingsRepository {
  Future<T?> readValue<T>(String key);

  Future<Map<String, Object?>> listAll();

  Future<void> writeValue<T>(String key, T value);

  Future<void> remove(String key);
}
