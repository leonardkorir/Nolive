import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_storage/live_storage.dart';
import 'package:nolive_app/src/features/settings/application/manage_provider_accounts_use_case.dart';
import 'package:nolive_app/src/features/settings/application/secure_snapshot_import_coordinator.dart';
import 'package:nolive_app/src/features/settings/application/sensitive_setting_keys.dart';
import 'package:nolive_app/src/features/sync/application/sync_preferences_use_case.dart';
import 'package:nolive_app/src/shared/application/secure_credential_store.dart';

void main() {
  test(
      'settings-backed secure store keeps legacy values during startup migration fallback',
      () async {
    final settingsRepository = InMemorySettingsRepository();
    await settingsRepository.writeValue(
      SensitiveSettingKeys.accountBilibiliCookie,
      'SESSDATA=demo;bili_jct=test;',
    );
    await settingsRepository.writeValue(
      SensitiveSettingKeys.syncWebDavPassword,
      'demo-webdav-password',
    );

    final secureCredentialStore =
        await SettingsBackedSecureCredentialStore.open(
      settingsRepository: settingsRepository,
      allowedKeys: SensitiveSettingKeys.secureCredentialKeys,
    );

    await MigrateSensitiveSettingsToSecureStoreUseCase(
      settingsRepository: settingsRepository,
      secureCredentialStore: secureCredentialStore,
    )();

    expect(
      await settingsRepository.readValue<String>(
        SensitiveSettingKeys.accountBilibiliCookie,
      ),
      'SESSDATA=demo;bili_jct=test;',
    );
    expect(
      await settingsRepository.readValue<String>(
        SensitiveSettingKeys.syncWebDavPassword,
      ),
      'demo-webdav-password',
    );
    expect(
      await secureCredentialStore.read(
        SensitiveSettingKeys.accountBilibiliCookie,
      ),
      'SESSDATA=demo;bili_jct=test;',
    );
    expect(
      await secureCredentialStore.read(
        SensitiveSettingKeys.syncWebDavPassword,
      ),
      'demo-webdav-password',
    );
  });

  test(
      'settings-backed secure store keeps provider and sync credentials persisted in legacy settings',
      () async {
    final settingsRepository = InMemorySettingsRepository();
    final secureCredentialStore =
        await SettingsBackedSecureCredentialStore.open(
      settingsRepository: settingsRepository,
      allowedKeys: SensitiveSettingKeys.secureCredentialKeys,
    );

    await UpdateProviderAccountSettingsUseCase(
      settingsRepository,
      secureCredentialStore,
    )(
      const ProviderAccountSettings(
        bilibiliCookie: '',
        bilibiliUserId: 0,
        chaturbateCookie: '',
        douyinCookie: 'douyin-cookie',
        twitchCookie: '',
        youtubeCookie: '',
      ),
    );
    await UpdateSyncPreferencesUseCase(
      settingsRepository,
      secureCredentialStore,
    )(
      const SyncPreferences(
        webDavBaseUrl: 'https://example.com/dav',
        webDavRemotePath: 'nolive/snapshot.json',
        webDavUsername: 'nolive',
        webDavPassword: 'webdav-password',
        localDeviceName: 'nolive-device',
        localPeerAddress: '',
        localPeerPort: 23234,
      ),
    );

    expect(
      await settingsRepository.readValue<String>(
        SensitiveSettingKeys.accountDouyinCookie,
      ),
      'douyin-cookie',
    );
    expect(
      await settingsRepository.readValue<String>(
        SensitiveSettingKeys.syncWebDavPassword,
      ),
      'webdav-password',
    );
    expect(
      await secureCredentialStore.read(
        SensitiveSettingKeys.accountDouyinCookie,
      ),
      'douyin-cookie',
    );
    expect(
      await secureCredentialStore.read(
        SensitiveSettingKeys.syncWebDavPassword,
      ),
      'webdav-password',
    );
  });

  test(
      'lazy secure store uses single-flight prewarm and migrates legacy values into secure storage',
      () async {
    final settingsRepository = InMemorySettingsRepository();
    await settingsRepository.writeValue(
      SensitiveSettingKeys.accountBilibiliCookie,
      'legacy-bilibili-cookie',
    );
    await settingsRepository.writeValue(
      SensitiveSettingKeys.syncWebDavPassword,
      'legacy-webdav-password',
    );
    final preloadSnapshots = <Map<String, String>>[];
    final loaderCompleter = Completer<SecureCredentialStore>();
    var loaderCalls = 0;
    final secureCredentialStore = LazySecureCredentialStore(
      settingsRepository: settingsRepository,
      allowedKeys: SensitiveSettingKeys.secureCredentialKeys,
      initialSettings: await settingsRepository.listAll(),
      loader: () {
        loaderCalls += 1;
        return loaderCompleter.future;
      },
      onSnapshotChanged: preloadSnapshots.add,
    );

    expect(
      await secureCredentialStore.read(
        SensitiveSettingKeys.syncWebDavPassword,
      ),
      'legacy-webdav-password',
    );

    final firstReady = secureCredentialStore.ensureReady();
    final secondReady = secureCredentialStore.ensureReady();
    expect(loaderCalls, 1);

    loaderCompleter.complete(
      InMemorySecureCredentialStore(
        initialValues: {
          SensitiveSettingKeys.accountBilibiliCookie: 'secure-bilibili-cookie',
        },
      ),
    );
    await Future.wait([firstReady, secondReady]);

    expect(
      await secureCredentialStore.read(
        SensitiveSettingKeys.accountBilibiliCookie,
      ),
      'secure-bilibili-cookie',
    );
    expect(
      await secureCredentialStore.read(
        SensitiveSettingKeys.syncWebDavPassword,
      ),
      'legacy-webdav-password',
    );
    expect(
      await settingsRepository.readValue<String>(
        SensitiveSettingKeys.accountBilibiliCookie,
      ),
      isNull,
    );
    expect(
      await settingsRepository.readValue<String>(
        SensitiveSettingKeys.syncWebDavPassword,
      ),
      isNull,
    );
    expect(preloadSnapshots, isNotEmpty);
  });

  test(
      'lazy secure store keeps legacy fallback when secure storage warmup fails',
      () async {
    final settingsRepository = InMemorySettingsRepository();
    await settingsRepository.writeValue(
      SensitiveSettingKeys.accountDouyinCookie,
      'legacy-douyin-cookie',
    );
    final secureCredentialStore = LazySecureCredentialStore(
      settingsRepository: settingsRepository,
      allowedKeys: SensitiveSettingKeys.secureCredentialKeys,
      initialSettings: await settingsRepository.listAll(),
      loader: () async {
        throw const SecureCredentialStoreUnavailableException(
          'simulated keystore failure',
        );
      },
    );

    await secureCredentialStore.ensureReady();

    expect(secureCredentialStore.storesSecureValuesSeparately, isFalse);
    expect(
      await secureCredentialStore.read(
        SensitiveSettingKeys.accountDouyinCookie,
      ),
      'legacy-douyin-cookie',
    );
    expect(
      await settingsRepository.readValue<String>(
        SensitiveSettingKeys.accountDouyinCookie,
      ),
      'legacy-douyin-cookie',
    );
  });

  test(
      'flutter secure credential store wraps deleteAll platform failures as unavailable exceptions',
      () async {
    final store = await FlutterSecureCredentialStore.open(
      storage: _ThrowingDeleteStorage(
        <String, String>{
          'nolive.secure.${SensitiveSettingKeys.accountDouyinCookie}':
              'secure-douyin-cookie',
        },
      ),
    );

    await expectLater(
      () => store.deleteAll(
        const [SensitiveSettingKeys.accountDouyinCookie],
      ),
      throwsA(isA<SecureCredentialStoreUnavailableException>()),
    );
  });

  test(
      'flutter secure credential store retries readAll once before failing warmup',
      () async {
    final store = await FlutterSecureCredentialStore.open(
      storage: _RetryingReadAllStorage(
        <String, String>{
          'nolive.secure.${SensitiveSettingKeys.accountDouyinCookie}':
              'secure-douyin-cookie',
        },
      ),
    );

    expect(
      await store.read(SensitiveSettingKeys.accountDouyinCookie),
      'secure-douyin-cookie',
    );
  });
}

class _ThrowingDeleteStorage extends FlutterSecureStorage {
  _ThrowingDeleteStorage(this._data);

  final Map<String, String> _data;

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    throw StateError('delete failed for $key');
  }

  @override
  Future<Map<String, String>> readAll({
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    return Map<String, String>.from(_data);
  }
}

class _RetryingReadAllStorage extends FlutterSecureStorage {
  _RetryingReadAllStorage(this._data);

  final Map<String, String> _data;
  int _readAllCalls = 0;

  @override
  Future<Map<String, String>> readAll({
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _readAllCalls += 1;
    if (_readAllCalls == 1) {
      throw TimeoutException('transient secure storage bootstrap timeout');
    }
    return Map<String, String>.from(_data);
  }
}
