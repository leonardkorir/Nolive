import 'package:live_sync/live_sync.dart';
import 'package:live_storage/live_storage.dart';

import '../../../shared/application/secure_credential_store.dart';
import '../../settings/application/sensitive_setting_keys.dart';

const _syncPreferenceSettingKeys = <String>[
  'sync_webdav_base_url',
  'sync_webdav_remote_path',
  'sync_webdav_username',
  SensitiveSettingKeys.syncWebDavPassword,
  SensitiveSettingKeys.syncLocalPeerAccessToken,
  'sync_local_device_name',
  'sync_local_peer_address',
  'sync_local_peer_port',
];

class SyncPreferences {
  const SyncPreferences({
    required this.webDavBaseUrl,
    required this.webDavRemotePath,
    required this.webDavUsername,
    required this.webDavPassword,
    required this.localDeviceName,
    required this.localPeerAddress,
    required this.localPeerPort,
    this.localPeerAccessToken = '',
  });

  final String webDavBaseUrl;
  final String webDavRemotePath;
  final String webDavUsername;
  final String webDavPassword;
  final String localDeviceName;
  final String localPeerAddress;
  final int localPeerPort;
  final String localPeerAccessToken;

  WebDavBackupConfig toWebDavConfig() {
    return WebDavBackupConfig(
      baseUrl: webDavBaseUrl,
      remotePath: webDavRemotePath,
      username: webDavUsername,
      passwordResolver: () => webDavPassword,
    );
  }

  SyncPreferences copyWith({
    String? webDavBaseUrl,
    String? webDavRemotePath,
    String? webDavUsername,
    String? webDavPassword,
    String? localDeviceName,
    String? localPeerAddress,
    int? localPeerPort,
    String? localPeerAccessToken,
  }) {
    return SyncPreferences(
      webDavBaseUrl: webDavBaseUrl ?? this.webDavBaseUrl,
      webDavRemotePath: webDavRemotePath ?? this.webDavRemotePath,
      webDavUsername: webDavUsername ?? this.webDavUsername,
      webDavPassword: webDavPassword ?? this.webDavPassword,
      localDeviceName: localDeviceName ?? this.localDeviceName,
      localPeerAddress: localPeerAddress ?? this.localPeerAddress,
      localPeerPort: localPeerPort ?? this.localPeerPort,
      localPeerAccessToken: localPeerAccessToken ?? this.localPeerAccessToken,
    );
  }
}

class LoadSyncPreferencesUseCase {
  const LoadSyncPreferencesUseCase(
    this.settingsRepository,
    this.secureCredentialStore,
  );

  final SettingsRepository settingsRepository;
  final SecureCredentialStore secureCredentialStore;

  Future<SyncPreferences> call() async {
    await secureCredentialStore.ensureReady();
    final securePassword = await secureCredentialStore.read(
      SensitiveSettingKeys.syncWebDavPassword,
    );
    final secureLocalPeerAccessToken = await secureCredentialStore.read(
      SensitiveSettingKeys.syncLocalPeerAccessToken,
    );
    return SyncPreferences(
      webDavBaseUrl:
          await settingsRepository.readValue<String>('sync_webdav_base_url') ??
          '',
      webDavRemotePath:
          await settingsRepository.readValue<String>(
            'sync_webdav_remote_path',
          ) ??
          'nolive/snapshot.json',
      webDavUsername:
          await settingsRepository.readValue<String>('sync_webdav_username') ??
          '',
      webDavPassword: securePassword.isNotEmpty
          ? securePassword
          : await settingsRepository.readValue<String>(
                  SensitiveSettingKeys.syncWebDavPassword,
                ) ??
                '',
      localDeviceName:
          await settingsRepository.readValue<String>(
            'sync_local_device_name',
          ) ??
          'nolive-device',
      localPeerAddress:
          await settingsRepository.readValue<String>(
            'sync_local_peer_address',
          ) ??
          '',
      localPeerPort:
          await settingsRepository.readValue<int>('sync_local_peer_port') ??
          23234,
      localPeerAccessToken: secureLocalPeerAccessToken.isNotEmpty
          ? secureLocalPeerAccessToken
          : await settingsRepository.readValue<String>(
                  SensitiveSettingKeys.syncLocalPeerAccessToken,
                ) ??
                '',
    );
  }
}

class UpdateSyncPreferencesUseCase {
  const UpdateSyncPreferencesUseCase(
    this.settingsRepository,
    this.secureCredentialStore,
  );

  final SettingsRepository settingsRepository;
  final SecureCredentialStore secureCredentialStore;

  Future<void> call(SyncPreferences preferences) async {
    await secureCredentialStore.ensureReady();
    final snapshot = await _captureSnapshot();
    try {
      await settingsRepository.writeValue(
        'sync_webdav_base_url',
        preferences.webDavBaseUrl,
      );
      await settingsRepository.writeValue(
        'sync_webdav_remote_path',
        preferences.webDavRemotePath,
      );
      await settingsRepository.writeValue(
        'sync_webdav_username',
        preferences.webDavUsername,
      );
      await secureCredentialStore.write(
        SensitiveSettingKeys.syncWebDavPassword,
        preferences.webDavPassword,
      );
      await secureCredentialStore.write(
        SensitiveSettingKeys.syncLocalPeerAccessToken,
        preferences.localPeerAccessToken,
      );
      if (secureCredentialStore.storesSecureValuesSeparately) {
        await settingsRepository.remove(
          SensitiveSettingKeys.syncWebDavPassword,
        );
        await settingsRepository.remove(
          SensitiveSettingKeys.syncLocalPeerAccessToken,
        );
      }
      await settingsRepository.writeValue(
        'sync_local_device_name',
        preferences.localDeviceName,
      );
      await settingsRepository.writeValue(
        'sync_local_peer_address',
        preferences.localPeerAddress,
      );
      await settingsRepository.writeValue(
        'sync_local_peer_port',
        preferences.localPeerPort,
      );
    } catch (error, stackTrace) {
      try {
        await _restoreSnapshot(snapshot);
      } catch (rollbackError, rollbackStackTrace) {
        Error.throwWithStackTrace(
          SyncPreferencesRollbackException(
            cause: error,
            rollbackCause: rollbackError,
          ),
          rollbackStackTrace,
        );
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<_SyncPreferencesSnapshot> _captureSnapshot() async {
    final settings = await settingsRepository.listAll();
    final trackedSettings = <String, Object?>{};
    for (final key in _syncPreferenceSettingKeys) {
      if (settings.containsKey(key)) {
        trackedSettings[key] = settings[key];
      }
    }
    return _SyncPreferencesSnapshot(
      settings: trackedSettings,
      securePassword: await secureCredentialStore.read(
        SensitiveSettingKeys.syncWebDavPassword,
      ),
      secureLocalPeerAccessToken: await secureCredentialStore.read(
        SensitiveSettingKeys.syncLocalPeerAccessToken,
      ),
    );
  }

  Future<void> _restoreSnapshot(_SyncPreferencesSnapshot snapshot) async {
    for (final key in _syncPreferenceSettingKeys) {
      if (snapshot.settings.containsKey(key)) {
        await settingsRepository.writeValue(key, snapshot.settings[key]);
      } else {
        await settingsRepository.remove(key);
      }
    }
    if (snapshot.securePassword.isEmpty) {
      await secureCredentialStore.delete(
        SensitiveSettingKeys.syncWebDavPassword,
      );
    } else {
      await secureCredentialStore.write(
        SensitiveSettingKeys.syncWebDavPassword,
        snapshot.securePassword,
      );
    }
    if (snapshot.secureLocalPeerAccessToken.isEmpty) {
      await secureCredentialStore.delete(
        SensitiveSettingKeys.syncLocalPeerAccessToken,
      );
    } else {
      await secureCredentialStore.write(
        SensitiveSettingKeys.syncLocalPeerAccessToken,
        snapshot.secureLocalPeerAccessToken,
      );
    }
  }
}

class _SyncPreferencesSnapshot {
  const _SyncPreferencesSnapshot({
    required this.settings,
    required this.securePassword,
    required this.secureLocalPeerAccessToken,
  });

  final Map<String, Object?> settings;
  final String securePassword;
  final String secureLocalPeerAccessToken;
}

class SyncPreferencesRollbackException implements Exception {
  const SyncPreferencesRollbackException({
    required this.cause,
    required this.rollbackCause,
  });

  final Object cause;
  final Object rollbackCause;

  @override
  String toString() {
    return 'SyncPreferencesRollbackException('
        'cause: $cause, rollbackCause: $rollbackCause)';
  }
}
