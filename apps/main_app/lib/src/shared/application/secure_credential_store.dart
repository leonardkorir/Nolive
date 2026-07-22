import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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
  const SecureCredentialStoreUnavailableException(this.message, {this.cause});

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

  /// Cold-start open must not block the UI shell for tens of seconds when the
  /// device Keystore hangs (observed on some Sony / ChromeOS ARC devices).
  static const Duration openStorageOperationTimeout = Duration(seconds: 3);
  static const int openStorageRetryAttempts = 1;

  static const Duration _storageOperationTimeout = Duration(seconds: 8);
  static const int _storageRetryAttempts = 2;
  static const Duration _storageRetryDelay = Duration(milliseconds: 250);

  final FlutterSecureStorage _storage;
  final Map<String, String> _cache = <String, String>{};

  @override
  bool get storesSecureValuesSeparately => true;

  /// Default Android backends tried at open (encrypted first, then legacy).
  static List<FlutterSecureStorage> defaultAndroidStorageCandidates() {
    return const <FlutterSecureStorage>[
      FlutterSecureStorage(
        aOptions: AndroidOptions(encryptedSharedPreferences: true),
      ),
      FlutterSecureStorage(
        aOptions: AndroidOptions(encryptedSharedPreferences: false),
      ),
    ];
  }

  static Future<FlutterSecureCredentialStore> open({
    FlutterSecureStorage? storage,
    List<FlutterSecureStorage>? storageCandidates,
    Duration? openTimeout,
    int? openRetryAttempts,
  }) async {
    final boundTimeout = openTimeout ?? openStorageOperationTimeout;
    final boundRetries = openRetryAttempts ?? openStorageRetryAttempts;

    if (storage != null) {
      final store = FlutterSecureCredentialStore._(storage);
      await store._load(
        timeout: boundTimeout,
        retryAttempts: boundRetries,
      );
      return store;
    }

    // Desktop / iOS: single default backend. Android: try encrypted then legacy
    // keystore backends so a hung EncryptedSharedPreferences path cannot soft
    // brick cold start for ~20s.
    final List<FlutterSecureStorage> candidates;
    if (storageCandidates != null) {
      candidates = storageCandidates;
    } else if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      candidates = defaultAndroidStorageCandidates();
    } else {
      candidates = const <FlutterSecureStorage>[FlutterSecureStorage()];
    }

    Object? lastError;
    StackTrace? lastStack;
    for (var index = 0; index < candidates.length; index += 1) {
      final candidate = candidates[index];
      try {
        final store = FlutterSecureCredentialStore._(candidate);
        await store._load(
          timeout: boundTimeout,
          retryAttempts: boundRetries,
        );
        if (index > 0) {
          AppLog.instance.info(
            'bootstrap',
            'secure store open fell back to alternate Android backend '
                'index=$index keys=${store.snapshot().length}',
          );
        }
        return store;
      } catch (error, stackTrace) {
        lastError = error;
        lastStack = stackTrace;
        AppLog.instance.info(
          'bootstrap',
          'secure store open candidate failed index=$index '
              'error=$error',
        );
        // Device Keystore hangs (not just a bad EncryptedSharedPreferences
        // path): further backends would also stall cold start. Fail open fast.
        final timedOut = error is TimeoutException ||
            (error is SecureCredentialStoreUnavailableException &&
                error.message.contains('timed out'));
        if (timedOut) {
          break;
        }
      }
    }
    Error.throwWithStackTrace(
      lastError ??
          const SecureCredentialStoreUnavailableException(
            'Secure storage open failed: no backend available',
          ),
      lastStack ?? StackTrace.current,
    );
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

  Future<void> _load({
    Duration timeout = _storageOperationTimeout,
    int retryAttempts = _storageRetryAttempts,
  }) async {
    final stored = await _runStorageOperation(
      'readAll()',
      _storage.readAll,
      timeout: timeout,
      retryAttempts: retryAttempts,
    );
    _cache
      ..clear()
      ..addEntries(
        stored.entries
            .where((entry) {
              return entry.key.startsWith(_keyPrefix) &&
                  entry.value.trim().isNotEmpty;
            })
            .map(
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
    Future<T> Function() action, {
    Duration timeout = _storageOperationTimeout,
    int retryAttempts = _storageRetryAttempts,
  }) async {
    final maxAttempts = retryAttempts.clamp(1, 5);
    for (var attempt = 1; attempt <= maxAttempts; attempt += 1) {
      try {
        return await action().timeout(timeout);
      } on TimeoutException catch (error) {
        if (attempt < maxAttempts) {
          await Future<void>.delayed(_storageRetryDelay);
          continue;
        }
        throw SecureCredentialStoreUnavailableException(
          'Secure storage operation timed out: $operation',
          cause: error,
        );
      } catch (error) {
        if (_isTransientStorageError(error) && attempt < maxAttempts) {
          await Future<void>.delayed(_storageRetryDelay);
          continue;
        }
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

  bool _isTransientStorageError(Object error) {
    if (error is TimeoutException) {
      return true;
    }
    if (error is PlatformException) {
      final code = error.code.toLowerCase();
      final message = (error.message ?? '').toLowerCase();
      return code.contains('timeout') ||
          code.contains('temporar') ||
          code.contains('unavailable') ||
          code.contains('busy') ||
          message.contains('timeout') ||
          message.contains('temporar') ||
          message.contains('try again') ||
          message.contains('unavailable') ||
          message.contains('busy');
    }
    return false;
  }
}

class SettingsBackedSecureCredentialStore implements SecureCredentialStore {
  SettingsBackedSecureCredentialStore._({
    required SettingsRepository settingsRepository,
    required Set<String> allowedKeys,
  }) : _settingsRepository = settingsRepository,
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
  }) : _settingsRepository = settingsRepository,
       _allowedKeys = {...allowedKeys, _migrationSentinelKey},
       _loader = loader,
       _fallbackStore = SettingsBackedSecureCredentialStore.seeded(
         settingsRepository: settingsRepository,
         allowedKeys: [...allowedKeys, _migrationSentinelKey],
         initialSettings: initialSettings,
       ),
       _onSnapshotChanged = onSnapshotChanged,
       _activeStore = SettingsBackedSecureCredentialStore.seeded(
         settingsRepository: settingsRepository,
         allowedKeys: [...allowedKeys, _migrationSentinelKey],
         initialSettings: initialSettings,
       ),
       _publishedSnapshot = _extractAllowedSecureValues(
         initialSettings,
         {...allowedKeys, _migrationSentinelKey},
       );

  static const String _migrationSentinelKey = 'nolive.secure.migration_complete';

  final SettingsRepository _settingsRepository;
  final Set<String> _allowedKeys;
  final Future<SecureCredentialStore> Function() _loader;
  final SettingsBackedSecureCredentialStore _fallbackStore;
  final void Function(Map<String, String> snapshot)? _onSnapshotChanged;

  SecureCredentialStore _activeStore;
  SecureCredentialStore? _resolvedStore;
  Map<String, String> _publishedSnapshot;
  Future<void>? _readyFuture;
  bool _ready = false;

  final Set<String> _writtenKeysDuringWarmup = <String>{};
  final Set<String> _deletedKeysDuringWarmup = <String>{};
  Future<void> _transactionQueue = Future.value();

  Future<void> _enqueue(Future<void> Function() action) {
    final completer = Completer<void>();
    _transactionQueue = _transactionQueue.then(
      (_) => action(),
      onError: (_) => action(),
    ).then(
      completer.complete,
      onError: completer.completeError,
    );
    return completer.future;
  }

  @override
  bool get storesSecureValuesSeparately =>
      _activeStore.storesSecureValuesSeparately;

  /// Ensures the store is fully initialized and ready.
  ///
  /// This method is fail-open: if the underlying secure storage resolution (warmup)
  /// fails, it logs the error and falls back to using the legacy, unencrypted
  /// settings-backed store, allowing the application to proceed. Once failed, it will
  /// not attempt to retry warming up/promoting for the remainder of the session.
  @override
  Future<void> ensureReady() async {
    if (_ready) {
      return;
    }
    await (_readyFuture ??= _warmUp());
  }

  @override
  Future<void> clear() {
    return _enqueue(() async {
      await _activeStore.clear();
      await _fallbackStore.clear();
      final resolved = _resolvedStore;
      if (resolved != null && _activeStore != resolved) {
        await resolved.clear();
      }
      if (!_ready) {
        _deletedKeysDuringWarmup.addAll(_allowedKeys);
        _writtenKeysDuringWarmup.clear();
      }
      await _publishSnapshotIfChanged();
    });
  }

  @override
  Future<void> delete(String key) {
    return _enqueue(() async {
      await _activeStore.delete(key);
      await _fallbackStore.delete(key);
      final resolved = _resolvedStore;
      if (resolved != null && _activeStore != resolved) {
        await resolved.delete(key);
      }
      if (!_ready) {
        _deletedKeysDuringWarmup.add(key);
        _writtenKeysDuringWarmup.remove(key);
      }
      await _publishSnapshotIfChanged();
    });
  }

  @override
  Future<void> deleteAll(Iterable<String> keys) {
    return _enqueue(() async {
      await _activeStore.deleteAll(keys);
      await _fallbackStore.deleteAll(keys);
      final resolved = _resolvedStore;
      if (resolved != null && _activeStore != resolved) {
        await resolved.deleteAll(keys);
      }
      if (!_ready) {
        _deletedKeysDuringWarmup.addAll(keys);
        _writtenKeysDuringWarmup.removeAll(keys);
      }
      await _publishSnapshotIfChanged();
    });
  }

  @override
  Future<String> read(String key) async {
    return _activeStore.read(key);
  }

  @override
  Future<Map<String, String>> readAll() async {
    return snapshot();
  }

  @override
  Map<String, String> snapshot() {
    return _activeStore.snapshot();
  }

  @override
  Future<void> write(String key, String value) {
    return _enqueue(() async {
      await _activeStore.write(key, value);
      await _fallbackStore.write(key, value);
      final resolved = _resolvedStore;
      if (resolved != null && _activeStore != resolved) {
        await resolved.write(key, value);
      }
      if (!_ready) {
        _writtenKeysDuringWarmup.add(key);
        _deletedKeysDuringWarmup.remove(key);
      }
      await _publishSnapshotIfChanged();
    });
  }

  @override
  Future<void> writeAll(Map<String, String> values) {
    return _enqueue(() async {
      await _activeStore.writeAll(values);
      await _fallbackStore.writeAll(values);
      final resolved = _resolvedStore;
      if (resolved != null && _activeStore != resolved) {
        await resolved.writeAll(values);
      }
      if (!_ready) {
        _writtenKeysDuringWarmup.addAll(values.keys);
        _deletedKeysDuringWarmup.removeAll(values.keys);
      }
      await _publishSnapshotIfChanged();
    });
  }

  Future<void> _warmUp() async {
    AppLog.instance.info(
      'bootstrap',
      'secure store prewarm start backend=flutter_secure_storage '
          'fallbackKeys=${_fallbackStore.snapshot().length}',
    );
    try {
      final resolvedStore = await _loader();
      _resolvedStore = resolvedStore;
      await _enqueue(() => _promoteResolvedStore(resolvedStore));
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
      // Do not dual-write to a store that failed open/promote.
      _resolvedStore = null;
      await _publishSnapshotIfChanged();
      AppLog.instance.info(
        'bootstrap',
        'secure store fallback active backend=settings_repository '
            'keys=${_fallbackStore.snapshot().length}',
      );
    } finally {
      // Fail-open logic: we set _ready = true unconditionally so the application
      // can proceed with the fallback SettingsBackedSecureCredentialStore even if
      // the secure storage resolution failed.
      _ready = true;
    }
  }

  Future<void> _promoteResolvedStore(
    SecureCredentialStore resolvedStore,
  ) async {
    final activeSnapshot = _activeStore.snapshot();
    final resolvedSnapshot = resolvedStore.snapshot();

    final isMigrated = resolvedSnapshot.containsKey(_migrationSentinelKey);

    // Capture checkpoint of current warmup dirty sets
    final writtenDuringWarmup = Set<String>.from(_writtenKeysDuringWarmup);
    final deletedDuringWarmup = Set<String>.from(_deletedKeysDuringWarmup);

    // Remove them from the main sets since we are reconciling them now
    _writtenKeysDuringWarmup.removeAll(writtenDuringWarmup);
    _deletedKeysDuringWarmup.removeAll(deletedDuringWarmup);

    final valuesToWrite = <String, String>{};
    final keysToDelete = <String>[];

    try {
      // 1. Determine writes
      for (final entry in activeSnapshot.entries) {
        final key = entry.key;
        if (key == _migrationSentinelKey) {
          continue;
        }

        final isDirty = writtenDuringWarmup.contains(key);
        final isNotMigratedAndMissing = !isMigrated && !resolvedSnapshot.containsKey(key);
        final shouldWrite = (isDirty || isNotMigratedAndMissing) && !deletedDuringWarmup.contains(key);
        if (shouldWrite) {
          // Skip if a concurrent operation modified this key after our checkpoint
          if (!_writtenKeysDuringWarmup.contains(key) && !_deletedKeysDuringWarmup.contains(key)) {
            if (resolvedSnapshot[key] != entry.value) {
              valuesToWrite[key] = entry.value;
            }
          }
        }
      }

      // 2. Determine deletes
      for (final key in resolvedSnapshot.keys) {
        if (key == _migrationSentinelKey) {
          continue;
        }
        final shouldDelete = deletedDuringWarmup.contains(key);
        if (shouldDelete) {
          // Skip if a concurrent operation modified this key after our checkpoint
          if (!_writtenKeysDuringWarmup.contains(key) && !_deletedKeysDuringWarmup.contains(key)) {
            keysToDelete.add(key);
          }
        }
      }

      // 3. Apply changes to resolvedStore
      if (valuesToWrite.isNotEmpty) {
        await resolvedStore.writeAll(valuesToWrite);
      }
      if (keysToDelete.isNotEmpty) {
        await resolvedStore.deleteAll(keysToDelete);
      }

      // 4. Write sentinel if not migrated yet
      if (!isMigrated) {
        await resolvedStore.write(_migrationSentinelKey, 'true');
      }
    } catch (error, stackTrace) {
      // Rollback: restore the checkpointed warmup keys so they can be tried again
      _writtenKeysDuringWarmup.addAll(writtenDuringWarmup);
      _deletedKeysDuringWarmup.addAll(deletedDuringWarmup);

      // Rollback writes and deletes to resolvedStore
      try {
        final rollbackWrites = <String, String>{};
        final rollbackDeletes = <String>[];
        for (final key in valuesToWrite.keys) {
          if (resolvedSnapshot.containsKey(key)) {
            rollbackWrites[key] = resolvedSnapshot[key]!;
          } else {
            rollbackDeletes.add(key);
          }
        }
        for (final key in keysToDelete) {
          if (resolvedSnapshot.containsKey(key)) {
            rollbackWrites[key] = resolvedSnapshot[key]!;
          }
        }
        if (rollbackWrites.isNotEmpty) {
          await resolvedStore.writeAll(rollbackWrites);
        }
        if (rollbackDeletes.isNotEmpty) {
          await resolvedStore.deleteAll(rollbackDeletes);
        }
      } catch (rollbackError, rollbackStackTrace) {
        AppLog.instance.error(
          'bootstrap',
          'secure store promotion rollback failed',
          error: rollbackError,
          stackTrace: rollbackStackTrace,
        );
      }

      AppLog.instance.error(
        'bootstrap',
        'secure store promotion failed during reconciliation. '
        'Tainted write keys: ${valuesToWrite.keys.toList()}, '
        'Tainted delete keys: $keysToDelete',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }

    _activeStore = resolvedStore;
    await _publishSnapshotIfChanged();

    // Clean up legacy settings if resolved store is separate secure storage
    if (resolvedStore.storesSecureValuesSeparately) {
      try {
        for (final key in _allowedKeys) {
          if (key != _migrationSentinelKey) {
            await _settingsRepository.remove(key);
          }
        }
      } catch (error, stackTrace) {
        AppLog.instance.error(
          'bootstrap',
          'secure store legacy cleanup failed after promotion',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
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
