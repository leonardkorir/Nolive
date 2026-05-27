import 'package:flutter_test/flutter_test.dart';
import 'package:live_storage/live_storage.dart';
import 'package:nolive_app/src/features/settings/application/sensitive_setting_keys.dart';
import 'package:nolive_app/src/features/sync/application/sync_preferences_use_case.dart';
import 'package:nolive_app/src/shared/application/secure_credential_store.dart';

void main() {
  test(
    'update sync preferences rolls back settings and secure password when a later settings write fails',
    () async {
      final baseRepository = InMemorySettingsRepository();
      await _seedSyncSettings(
        baseRepository,
        passwordInSettings: 'legacy-password',
      );
      final settingsRepository = _OneShotFailingSettingsRepository(
        delegate: baseRepository,
        failingWriteKey: 'sync_local_peer_port',
      );
      final secureStore = InMemorySecureCredentialStore(
        initialValues: const {
          SensitiveSettingKeys.syncWebDavPassword: 'old-password',
          SensitiveSettingKeys.syncLocalPeerAccessToken: 'old-peer-token',
        },
      );

      final useCase = UpdateSyncPreferencesUseCase(
        settingsRepository,
        secureStore,
      );

      await expectLater(
        () => useCase(
          const SyncPreferences(
            webDavBaseUrl: 'https://new.example.com',
            webDavRemotePath: 'new/snapshot.json',
            webDavUsername: 'new-user',
            webDavPassword: 'new-password',
            localDeviceName: 'new-device',
            localPeerAddress: '10.0.0.8',
            localPeerPort: 24567,
            localPeerAccessToken: 'new-peer-token',
          ),
        ),
        throwsStateError,
      );

      expect(
        settingsRepository.dump(),
        _expectedOriginalSettings(legacyPassword: 'legacy-password'),
      );
      expect(
        await secureStore.read(SensitiveSettingKeys.syncWebDavPassword),
        'old-password',
      );
      expect(
        await secureStore.read(SensitiveSettingKeys.syncLocalPeerAccessToken),
        'old-peer-token',
      );
    },
  );

  test(
    'update sync preferences rolls back earlier settings when secure password write fails',
    () async {
      final settingsRepository = InMemorySettingsRepository();
      await _seedSyncSettings(settingsRepository);
      final secureStore = _ThrowingWriteSecureCredentialStore(
        delegate: InMemorySecureCredentialStore(
          initialValues: const {
            SensitiveSettingKeys.syncWebDavPassword: 'old-password',
            SensitiveSettingKeys.syncLocalPeerAccessToken: 'old-peer-token',
          },
        ),
        failingKey: SensitiveSettingKeys.syncWebDavPassword,
      );

      final useCase = UpdateSyncPreferencesUseCase(
        settingsRepository,
        secureStore,
      );

      await expectLater(
        () => useCase(
          const SyncPreferences(
            webDavBaseUrl: 'https://new.example.com',
            webDavRemotePath: 'new/snapshot.json',
            webDavUsername: 'new-user',
            webDavPassword: 'new-password',
            localDeviceName: 'new-device',
            localPeerAddress: '10.0.0.8',
            localPeerPort: 24567,
            localPeerAccessToken: 'new-peer-token',
          ),
        ),
        throwsStateError,
      );

      expect(settingsRepository.dump(), _expectedOriginalSettings());
      expect(
        await secureStore.read(SensitiveSettingKeys.syncWebDavPassword),
        'old-password',
      );
      expect(
        await secureStore.read(SensitiveSettingKeys.syncLocalPeerAccessToken),
        'old-peer-token',
      );
    },
  );

  test(
    'update sync preferences restores settings-backed secure password on rollback',
    () async {
      final baseRepository = InMemorySettingsRepository();
      await _seedSyncSettings(
        baseRepository,
        passwordInSettings: 'old-password',
      );
      final settingsRepository = _OneShotFailingSettingsRepository(
        delegate: baseRepository,
        failingWriteKey: 'sync_local_peer_port',
      );
      final secureStore = SettingsBackedSecureCredentialStore.seeded(
        settingsRepository: settingsRepository,
        allowedKeys: const [
          SensitiveSettingKeys.syncWebDavPassword,
          SensitiveSettingKeys.syncLocalPeerAccessToken,
        ],
        initialSettings: settingsRepository.dump(),
      );

      final useCase = UpdateSyncPreferencesUseCase(
        settingsRepository,
        secureStore,
      );

      await expectLater(
        () => useCase(
          const SyncPreferences(
            webDavBaseUrl: 'https://new.example.com',
            webDavRemotePath: 'new/snapshot.json',
            webDavUsername: 'new-user',
            webDavPassword: 'new-password',
            localDeviceName: 'new-device',
            localPeerAddress: '10.0.0.8',
            localPeerPort: 24567,
            localPeerAccessToken: 'new-peer-token',
          ),
        ),
        throwsStateError,
      );

      expect(
        settingsRepository.dump(),
        _expectedOriginalSettings(legacyPassword: 'old-password'),
      );
      expect(
        await secureStore.read(SensitiveSettingKeys.syncWebDavPassword),
        'old-password',
      );
    },
  );
}

Future<void> _seedSyncSettings(
  SettingsRepository settingsRepository, {
  String? passwordInSettings,
}) async {
  await settingsRepository.writeValue(
    'sync_webdav_base_url',
    'https://old.example.com',
  );
  await settingsRepository.writeValue(
    'sync_webdav_remote_path',
    'old/snapshot.json',
  );
  await settingsRepository.writeValue('sync_webdav_username', 'old-user');
  if (passwordInSettings != null) {
    await settingsRepository.writeValue(
      SensitiveSettingKeys.syncWebDavPassword,
      passwordInSettings,
    );
  }
  await settingsRepository.writeValue('sync_local_device_name', 'old-device');
  await settingsRepository.writeValue('sync_local_peer_address', '192.168.0.2');
  await settingsRepository.writeValue('sync_local_peer_port', 23234);
}

Map<String, Object?> _expectedOriginalSettings({String? legacyPassword}) {
  return <String, Object?>{
    'sync_webdav_base_url': 'https://old.example.com',
    'sync_webdav_remote_path': 'old/snapshot.json',
    'sync_webdav_username': 'old-user',
    if (legacyPassword != null)
      SensitiveSettingKeys.syncWebDavPassword: legacyPassword,
    'sync_local_device_name': 'old-device',
    'sync_local_peer_address': '192.168.0.2',
    'sync_local_peer_port': 23234,
  };
}

class _OneShotFailingSettingsRepository implements SettingsRepository {
  _OneShotFailingSettingsRepository({
    required this.delegate,
    this.failingWriteKey,
  });

  final InMemorySettingsRepository delegate;
  final String? failingWriteKey;
  bool _writeFailed = false;

  @override
  Future<Map<String, Object?>> listAll() => delegate.listAll();

  @override
  Future<T?> readValue<T>(String key) => delegate.readValue<T>(key);

  @override
  Future<void> remove(String key) => delegate.remove(key);

  @override
  Future<void> writeValue<T>(String key, T value) async {
    if (!_writeFailed && key == failingWriteKey) {
      _writeFailed = true;
      throw StateError('write failed for $key');
    }
    await delegate.writeValue(key, value);
  }

  Map<String, Object?> dump() => delegate.dump();
}

class _ThrowingWriteSecureCredentialStore implements SecureCredentialStore {
  _ThrowingWriteSecureCredentialStore({
    required this.delegate,
    required this.failingKey,
  });

  final InMemorySecureCredentialStore delegate;
  final String failingKey;
  bool _failed = false;

  @override
  bool get storesSecureValuesSeparately =>
      delegate.storesSecureValuesSeparately;

  @override
  Future<void> clear() => delegate.clear();

  @override
  Future<void> delete(String key) => delegate.delete(key);

  @override
  Future<void> deleteAll(Iterable<String> keys) => delegate.deleteAll(keys);

  @override
  Future<void> ensureReady() => delegate.ensureReady();

  @override
  Future<String> read(String key) => delegate.read(key);

  @override
  Future<Map<String, String>> readAll() => delegate.readAll();

  @override
  Map<String, String> snapshot() => delegate.snapshot();

  @override
  Future<void> write(String key, String value) async {
    if (!_failed && key == failingKey) {
      _failed = true;
      throw StateError('secure write failed for $key');
    }
    await delegate.write(key, value);
  }

  @override
  Future<void> writeAll(Map<String, String> values) =>
      delegate.writeAll(values);
}
