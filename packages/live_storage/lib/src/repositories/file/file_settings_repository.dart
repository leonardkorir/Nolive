import '../../persistence/local_storage_file_store.dart';
import '../settings_repository.dart';

class FileSettingsRepository implements SettingsRepository {
  FileSettingsRepository(this.store);

  final LocalStorageFileStore store;

  @override
  Future<Map<String, Object?>> listAll() {
    return store.read(
      (snapshot) => Map<String, Object?>.from(snapshot.settings),
    );
  }

  @override
  Future<T?> readValue<T>(String key) {
    return store.read((snapshot) => _castValue<T>(snapshot.settings[key]));
  }

  @override
  Future<void> remove(String key) {
    return store.update((snapshot) {
      snapshot.settings.remove(key);
    });
  }

  @override
  Future<void> writeValue<T>(String key, T value) {
    return store.update((snapshot) {
      snapshot.settings[key] = _normalizeSettingValue(value);
    });
  }

  T? _castValue<T>(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is T) {
      return value as T;
    }
    if (T == double && value is num) {
      return value.toDouble() as T;
    }
    if (T == int && value is num) {
      return value.toInt() as T;
    }
    if (T == String) {
      return value.toString() as T;
    }
    if (<String>[] is T && value is List) {
      return value
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false) as T;
    }
    return null;
  }

  Object? _normalizeSettingValue(Object? value) {
    if (value == null || value is String || value is bool) {
      return value;
    }
    if (value is int || value is double) {
      return value;
    }
    if (value is num) {
      return value.toDouble();
    }
    if (value is List) {
      return value.map((item) => item.toString()).toList(growable: false);
    }
    if (value is Map) {
      return Map<String, Object?>.fromEntries(
        value.entries.map(
          (entry) => MapEntry(
            entry.key.toString(),
            _normalizeSettingValue(entry.value),
          ),
        ),
      );
    }
    return value.toString();
  }
}
