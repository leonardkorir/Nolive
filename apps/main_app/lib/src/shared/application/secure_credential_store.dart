import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:live_storage/live_storage.dart';

import 'app_log.dart';

abstract class SecureCredentialStore {
  bool get storesSecureValuesSeparately => true;

  Future<void> ensureReady() async {}

  Map<String, String> snapshot();

  Future<String> read(String key);

  Future<Map<String, String>> readAll();

  Future<void> write(String key, String value);

  Future<void> writeAll(Map<String, String> values);

  Future<void> delete(String key);

  Future<void> deleteAll(Iterable<String> keys);

  Future<void> clear();
}

class SecureCredentialStoreUnavailableException implements Exception {
  const SecureCredentialStoreUnavailableException(
    this.message, {
    this.cause,
  });

  final String message;
  final Object? cause;

  @override
  String toString() {
    if (cause == null) {
      return 'SecureCredentialStoreUnavailableException: $message';
    }
    return 'SecureCredentialStoreUnavailableException: $message ($cause)';
  }
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
  bool get storesSecureValuesSeparately => true;

  @override
  Future<void> ensureReady() async {}

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
  static const Duration _storageOperationTimeout = Duration(seconds: 3);
  static const int _readAllRetryAttempts = 2;
  static const Duration _readAllRetryDelay = Duration(milliseconds: 250);

  final FlutterSecureStorage _storage;
  final Map<String, String> _cache = <String, String>{};

  @override
  bool get storesSecureValuesSeparately => true;

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
  Future<void> ensureReady() async {}

  @override
  Future<void> clear() async {
    final keys = _cache.keys.toList(growable: false);
    await deleteAll(keys);
  }

  @override
  Future<void> delete(String key) async {
    await _runStorageOperation(
      'delete($key)',
      () => _storage.delete(key: _scopedKey(key)),
    );
    _cache.remove(key);
  }

  @override
  Future<void> deleteAll(Iterable<String> keys) async {
    for (final key in keys) {
      await _runStorageOperation(
        'delete($key)',
        () => _storage.delete(key: _scopedKey(key)),
      );
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
      await _runStorageOperation(
        'delete($key)',
        () => _storage.delete(key: scopedKey),
      );
      _cache.remove(key);
      return;
    }
    await _runStorageOperation(
      'write($key)',
      () => _storage.write(key: scopedKey, value: normalized),
    );
    _cache[key] = normalized;
  }

  @override
  Future<void> writeAll(Map<String, String> values) async {
    for (final entry in values.entries) {
      await write(entry.key, entry.value);
    }
  }

  Future<void> _load() async {
    final stored = await _runStorageOperation(
      'readAll()',
      _storage.readAll,
    );
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

  Future<T> _runStorageOperation<T>(
    String operation,
    Future<T> Function() action,
  ) async {
    final maxAttempts = operation == 'readAll()' ? _readAllRetryAttempts : 1;
    for (var attempt = 1; attempt <= maxAttempts; attempt += 1) {
      try {
        return await action().timeout(_storageOperationTimeout);
      } on TimeoutException catch (error) {
        if (attempt < maxAttempts) {
          await Future<void>.delayed(_readAllRetryDelay);
          continue;
        }
        throw SecureCredentialStoreUnavailableException(
          'Secure storage operation timed out: $operation',
          cause: error,
        );
      } catch (error) {
        throw SecureCredentialStoreUnavailableException(
          'Secure storage operation failed: $operation',
          cause: error,
        );
      }
    }
    throw const SecureCredentialStoreUnavailableException(
      'Secure storage operation failed: unknown storage failure',
    );
  }
}

class SettingsBackedSecureCredentialStore implements SecureCredentialStore {
  SettingsBackedSecureCredentialStore._({
    required SettingsRepository settingsRepository,
    required Set<String> allowedKeys,
  })  : _settingsRepository = settingsRepository,
        _allowedKeys = allowedKeys;

  final SettingsRepository _settingsRepository;
  final Set<String> _allowedKeys;
  final Map<String, String> _cache = <String, String>{};

  @override
  bool get storesSecureValuesSeparately => false;

  static Future<SettingsBackedSecureCredentialStore> open({
    required SettingsRepository settingsRepository,
    required Iterable<String> allowedKeys,
  }) async {
    final store = SettingsBackedSecureCredentialStore._(
      settingsRepository: settingsRepository,
      allowedKeys: allowedKeys.toSet(),
    );
    await store._load();
    return store;
  }

  factory SettingsBackedSecureCredentialStore.seeded({
    required SettingsRepository settingsRepository,
    required Iterable<String> allowedKeys,
    required Map<String, Object?> initialSettings,
  }) {
    final allowedKeySet = allowedKeys.toSet();
    final store = SettingsBackedSecureCredentialStore._(
      settingsRepository: settingsRepository,
      allowedKeys: allowedKeySet,
    );
    store._cache
      ..clear()
      ..addAll(_extractAllowedSecureValues(initialSettings, allowedKeySet));
    return store;
  }

  @override
  Future<void> ensureReady() async {}

  @override
  Future<void> clear() async {
    await deleteAll(_cache.keys.toList(growable: false));
  }

  @override
  Future<void> delete(String key) async {
    if (!_allowedKeys.contains(key)) {
      return;
    }
    await _settingsRepository.remove(key);
    _cache.remove(key);
  }

  @override
  Future<void> deleteAll(Iterable<String> keys) async {
    for (final key in keys) {
      await delete(key);
    }
  }

  @override
  Future<String> read(String key) async {
    if (!_allowedKeys.contains(key)) {
      return '';
    }
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
    if (!_allowedKeys.contains(key)) {
      return;
    }
    final normalized = value.trim();
    if (normalized.isEmpty) {
      await _settingsRepository.remove(key);
      _cache.remove(key);
      return;
    }
    await _settingsRepository.writeValue(key, normalized);
    _cache[key] = normalized;
  }

  @override
  Future<void> writeAll(Map<String, String> values) async {
    for (final entry in values.entries) {
      await write(entry.key, entry.value);
    }
  }

  Future<void> _load() async {
    final settings = await _settingsRepository.listAll();
    _cache
      ..clear()
      ..addAll(_extractAllowedSecureValues(settings, _allowedKeys));
  }
}

class LazySecureCredentialStore implements SecureCredentialStore {
  LazySecureCredentialStore({
    required SettingsRepository settingsRepository,
    required Iterable<String> allowedKeys,
    required Map<String, Object?> initialSettings,
    required Future<SecureCredentialStore> Function() loader,
    void Function(Map<String, String> snapshot)? onSnapshotChanged,
  })  : _settingsRepository = settingsRepository,
        _allowedKeys = allowedKeys.toSet(),
        _loader = loader,
        _fallbackStore = SettingsBackedSecureCredentialStore.seeded(
          settingsRepository: settingsRepository,
          allowedKeys: allowedKeys,
          initialSettings: initialSettings,
        ),
        _onSnapshotChanged = onSnapshotChanged,
        _activeStore = SettingsBackedSecureCredentialStore.seeded(
          settingsRepository: settingsRepository,
          allowedKeys: allowedKeys,
          initialSettings: initialSettings,
        ),
        _publishedSnapshot = _extractAllowedSecureValues(
          initialSettings,
          allowedKeys.toSet(),
        );

  final SettingsRepository _settingsRepository;
  final Set<String> _allowedKeys;
  final Future<SecureCredentialStore> Function() _loader;
  final SettingsBackedSecureCredentialStore _fallbackStore;
  final void Function(Map<String, String> snapshot)? _onSnapshotChanged;

  SecureCredentialStore _activeStore;
  Map<String, String> _publishedSnapshot;
  Future<void>? _readyFuture;
  bool _ready = false;

  @override
  bool get storesSecureValuesSeparately =>
      _activeStore.storesSecureValuesSeparately;

  @override
  Future<void> ensureReady() async {
    if (_ready) {
      return;
    }
    await (_readyFuture ??= _warmUp());
  }

  @override
  Future<void> clear() async {
    await ensureReady();
    await _activeStore.clear();
    await _publishSnapshotIfChanged();
  }

  @override
  Future<void> delete(String key) async {
    await ensureReady();
    await _activeStore.delete(key);
    await _publishSnapshotIfChanged();
  }

  @override
  Future<void> deleteAll(Iterable<String> keys) async {
    await ensureReady();
    await _activeStore.deleteAll(keys);
    await _publishSnapshotIfChanged();
  }

  @override
  Future<String> read(String key) async {
    return _activeStore.read(key);
  }

  @override
  Future<Map<String, String>> readAll() async {
    await ensureReady();
    return snapshot();
  }

  @override
  Map<String, String> snapshot() {
    return _activeStore.snapshot();
  }

  @override
  Future<void> write(String key, String value) async {
    await ensureReady();
    await _activeStore.write(key, value);
    await _publishSnapshotIfChanged();
  }

  @override
  Future<void> writeAll(Map<String, String> values) async {
    await ensureReady();
    await _activeStore.writeAll(values);
    await _publishSnapshotIfChanged();
  }

  Future<void> _warmUp() async {
    AppLog.instance.info(
      'bootstrap',
      'secure store prewarm start backend=flutter_secure_storage '
          'fallbackKeys=${_fallbackStore.snapshot().length}',
    );
    try {
      final resolvedStore = await _loader();
      await _promoteResolvedStore(resolvedStore);
      AppLog.instance.info(
        'bootstrap',
        'secure store prewarm done backend=flutter_secure_storage '
            'separate=${resolvedStore.storesSecureValuesSeparately} '
            'keys=${resolvedStore.snapshot().length}',
      );
    } catch (error, stackTrace) {
      AppLog.instance.error(
        'bootstrap',
        'secure store prewarm failed, keeping legacy settings fallback',
        error: error,
        stackTrace: stackTrace,
      );
      _activeStore = _fallbackStore;
      await _publishSnapshotIfChanged();
      AppLog.instance.info(
        'bootstrap',
        'secure store fallback active backend=settings_repository '
            'keys=${_fallbackStore.snapshot().length}',
      );
    } finally {
      _ready = true;
    }
  }

  Future<void> _promoteResolvedStore(
      SecureCredentialStore resolvedStore) async {
    final fallbackSnapshot = _fallbackStore.snapshot();
    final resolvedSnapshot = resolvedStore.snapshot();
    final valuesToWrite = <String, String>{};
    for (final entry in fallbackSnapshot.entries) {
      if (!resolvedSnapshot.containsKey(entry.key)) {
        valuesToWrite[entry.key] = entry.value;
      }
    }
    if (valuesToWrite.isNotEmpty) {
      await resolvedStore.writeAll(valuesToWrite);
    }
    if (resolvedStore.storesSecureValuesSeparately) {
      for (final key in _allowedKeys) {
        await _settingsRepository.remove(key);
      }
    }
    _activeStore = resolvedStore;
    await _publishSnapshotIfChanged();
  }

  Future<void> _publishSnapshotIfChanged() async {
    final currentSnapshot = snapshot();
    if (_sameStringMaps(_publishedSnapshot, currentSnapshot)) {
      return;
    }
    _publishedSnapshot = currentSnapshot;
    _onSnapshotChanged?.call(Map<String, String>.from(currentSnapshot));
  }
}

Map<String, String> _extractAllowedSecureValues(
  Map<String, Object?> values,
  Set<String> allowedKeys,
) {
  final filtered = <String, String>{};
  for (final entry in values.entries) {
    if (!allowedKeys.contains(entry.key)) {
      continue;
    }
    final normalized = entry.value?.toString().trim() ?? '';
    if (normalized.isEmpty) {
      continue;
    }
    filtered[entry.key] = normalized;
  }
  return filtered;
}

bool _sameStringMaps(Map<String, String> left, Map<String, String> right) {
  if (identical(left, right)) {
    return true;
  }
  if (left.length != right.length) {
    return false;
  }
  for (final entry in left.entries) {
    if (right[entry.key] != entry.value) {
      return false;
    }
  }
  return true;
}
