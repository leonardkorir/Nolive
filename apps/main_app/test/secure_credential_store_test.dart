import 'package:flutter_test/flutter_test.dart';
import 'package:live_storage/live_storage.dart';
import 'package:nolive_app/src/shared/application/secure_credential_store.dart';

class MockSettingsRepository implements SettingsRepository {
  final Map<String, Object?> _storage = {};

  Future<void> clear() async {
    _storage.clear();
  }

  Future<bool> containsKey(String key) async {
    return _storage.containsKey(key);
  }

  @override
  Future<Map<String, Object?>> listAll() async {
    return Map.from(_storage);
  }

  @override
  Future<T?> readValue<T>(String key) async {
    return _storage[key] as T?;
  }

  @override
  Future<void> remove(String key) async {
    _storage.remove(key);
  }

  @override
  Future<void> writeValue<T>(String key, T value) async {
    _storage[key] = value;
  }
}

class FailureSecureCredentialStore extends InMemorySecureCredentialStore {
  bool shouldFail = false;
  int writeAllCount = 0;

  FailureSecureCredentialStore({super.initialValues});

  @override
  Future<void> writeAll(Map<String, String> values) async {
    writeAllCount++;
    if (shouldFail && writeAllCount == 1) {
      throw Exception('Simulated writeAll failure');
    }
    return super.writeAll(values);
  }
}

void main() {
  group('LazySecureCredentialStore Extra Coverage', () {
    late MockSettingsRepository settingsRepo;

    setUp(() {
      settingsRepo = MockSettingsRepository();
    });

    test('warmup write-delete ambiguity resolution', () async {
      final allowed = {'key1', 'key2', 'key3'};
      final store = LazySecureCredentialStore(
        settingsRepository: settingsRepo,
        allowedKeys: allowed,
        initialSettings: {'key1': 'val1', 'key3': 'val3'},
        loader: () async {
          return InMemorySecureCredentialStore();
        },
      );

      // Perform operations during warmup (before ensureReady)
      await store.write('key2', 'val2');
      await store.delete('key1');

      await store.ensureReady();

      // Check results
      expect(await store.read('key1'), isEmpty, reason: 'key1 was deleted during warmup');
      expect(await store.read('key2'), 'val2', reason: 'key2 was written during warmup');
      expect(await store.read('key3'), 'val3', reason: 'key3 was unmodified and copied');
    });

    test('warmup write-then-delete on same key during warmup', () async {
      final allowed = {'key1'};
      final store = LazySecureCredentialStore(
        settingsRepository: settingsRepo,
        allowedKeys: allowed,
        initialSettings: {'key1': 'val1'},
        loader: () async {
          return InMemorySecureCredentialStore();
        },
      );

      // Write then delete the same key during warmup
      await store.write('key1', 'val2');
      await store.delete('key1');

      await store.ensureReady();

      // Check results: the key should be deleted/empty
      expect(await store.read('key1'), isEmpty);
    });

    test('TOCTOU protection for concurrent writes during promotion', () async {
      final allowed = {'key1'};
      final resolved = InMemorySecureCredentialStore();

      final store = LazySecureCredentialStore(
        settingsRepository: settingsRepo,
        allowedKeys: allowed,
        initialSettings: {'key1': 'old'},
        loader: () async {
          // Return the resolved store after delay to simulate concurrent windows
          await Future.delayed(const Duration(milliseconds: 10));
          return resolved;
        },
      );

      // Wait for warmup to trigger promotion
      final ready = store.ensureReady();

      // Concurrently write to store. Since promotion hasn't finished,
      // it writes to fallbackStore and resolvedStore if resolvedStore is non-null.
      await store.write('key1', 'new');

      await ready;

      // Verify that the stale fallback snapshot value 'old' didn't overwrite the concurrent write 'new'
      expect(await store.read('key1'), 'new');
    });

    test('rollback on promotion failure restores dirty keys and resolved store', () async {
      final allowed = {'key1'};
      final resolved = FailureSecureCredentialStore();

      final store = LazySecureCredentialStore(
        settingsRepository: settingsRepo,
        allowedKeys: allowed,
        initialSettings: {'key1': 'old'},
        loader: () async {
          return resolved;
        },
      );

      // Trigger write during warmup to make it dirty
      await store.write('key1', 'new');

      // Force failure during writeAll migration in promoteResolvedStore
      resolved.shouldFail = true;

      // Run warmup, which should fail and rollback to fallback
      await store.ensureReady();

      // Since promotion failed, it should have rolled back to fallbackStore
      // and retained 'new'
      expect(await store.read('key1'), 'new');

      // The resolved store itself should have been rolled back to empty
      expect(resolved.snapshot(), isEmpty);
    });

    test('fail-open behavior when loader throws exception', () async {
      final allowed = {'key1'};
      final store = LazySecureCredentialStore(
        settingsRepository: settingsRepo,
        allowedKeys: allowed,
        initialSettings: {'key1': 'fallback-value'},
        loader: () async {
          throw Exception('Loader failed');
        },
      );

      // ensureReady should resolve successfully (fail-open)
      await expectLater(store.ensureReady(), completes);

      // Verify it fell back to fallbackStore and returns fallback values
      expect(await store.read('key1'), 'fallback-value');
    });
  });
}
