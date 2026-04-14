import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract class SecureCredentialStore {
  Map<String, String> snapshot();

  Future<String> read(String key);

  Future<Map<String, String>> readAll();

  Future<void> write(String key, String value);

  Future<void> writeAll(Map<String, String> values);

  Future<void> delete(String key);

  Future<void> deleteAll(Iterable<String> keys);

  Future<void> clear();
}

class InMemorySecureCredentialStore implements SecureCredentialStore {
  InMemorySecureCredentialStore({Map<String, String>? initialValues})
      : _values = {
          if (initialValues != null)
            for (final entry in initialValues.entries)
              if (entry.value.trim().isNotEmpty) entry.key: entry.value.trim(),
        };

  final Map<String, String> _values;

  @override
  Future<void> clear() async {
    _values.clear();
  }

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }

  @override
  Future<void> deleteAll(Iterable<String> keys) async {
    for (final key in keys) {
      _values.remove(key);
    }
  }

  @override
  Future<String> read(String key) async {
    return _values[key] ?? '';
  }

  @override
  Future<Map<String, String>> readAll() async {
    return snapshot();
  }

  @override
  Map<String, String> snapshot() {
    return Map<String, String>.from(_values);
  }

  @override
  Future<void> write(String key, String value) async {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      _values.remove(key);
      return;
    }
    _values[key] = normalized;
  }

  @override
  Future<void> writeAll(Map<String, String> values) async {
    for (final entry in values.entries) {
      await write(entry.key, entry.value);
    }
  }
}

class FlutterSecureCredentialStore implements SecureCredentialStore {
  FlutterSecureCredentialStore._(this._storage);

  static const String _keyPrefix = 'nolive.secure.';

  final FlutterSecureStorage _storage;
  final Map<String, String> _cache = <String, String>{};

  static Future<FlutterSecureCredentialStore> open({
    FlutterSecureStorage? storage,
  }) async {
    final store = FlutterSecureCredentialStore._(
      storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(encryptedSharedPreferences: true),
          ),
    );
    await store._load();
    return store;
  }

  @override
  Future<void> clear() async {
    final keys = _cache.keys.toList(growable: false);
    await deleteAll(keys);
  }

  @override
  Future<void> delete(String key) async {
    await _storage.delete(key: _scopedKey(key));
    _cache.remove(key);
  }

  @override
  Future<void> deleteAll(Iterable<String> keys) async {
    for (final key in keys) {
      await _storage.delete(key: _scopedKey(key));
      _cache.remove(key);
    }
  }

  @override
  Future<String> read(String key) async {
    return _cache[key] ?? '';
  }

  @override
  Future<Map<String, String>> readAll() async {
    return snapshot();
  }

  @override
  Map<String, String> snapshot() {
    return Map<String, String>.from(_cache);
  }

  @override
  Future<void> write(String key, String value) async {
    final normalized = value.trim();
    final scopedKey = _scopedKey(key);
    if (normalized.isEmpty) {
      await _storage.delete(key: scopedKey);
      _cache.remove(key);
      return;
    }
    await _storage.write(key: scopedKey, value: normalized);
    _cache[key] = normalized;
  }

  @override
  Future<void> writeAll(Map<String, String> values) async {
    for (final entry in values.entries) {
      await write(entry.key, entry.value);
    }
  }

  Future<void> _load() async {
    final stored = await _storage.readAll();
    _cache
      ..clear()
      ..addEntries(
        stored.entries.where((entry) {
          return entry.key.startsWith(_keyPrefix) &&
              entry.value.trim().isNotEmpty;
        }).map(
          (entry) => MapEntry(
            entry.key.substring(_keyPrefix.length),
            entry.value.trim(),
          ),
        ),
      );
  }

  String _scopedKey(String key) => '$_keyPrefix$key';
}
