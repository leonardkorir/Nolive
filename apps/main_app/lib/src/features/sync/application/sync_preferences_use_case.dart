import 'package:live_sync/live_sync.dart';
import 'package:live_storage/live_storage.dart';

class SyncPreferences {
  const SyncPreferences({
    required this.webDavBaseUrl,
    required this.webDavRemotePath,
    required this.webDavUsername,
    required this.webDavPassword,
    required this.localDeviceName,
    required this.localPeerAddress,
    required this.localPeerPort,
  });

  final String webDavBaseUrl;
  final String webDavRemotePath;
  final String webDavUsername;
  final String webDavPassword;
  final String localDeviceName;
  final String localPeerAddress;
  final int localPeerPort;

  WebDavBackupConfig toWebDavConfig() {
    return WebDavBackupConfig(
      baseUrl: webDavBaseUrl,
      remotePath: webDavRemotePath,
      username: webDavUsername,
      password: webDavPassword,
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
  }) {
    return SyncPreferences(
      webDavBaseUrl: webDavBaseUrl ?? this.webDavBaseUrl,
      webDavRemotePath: webDavRemotePath ?? this.webDavRemotePath,
      webDavUsername: webDavUsername ?? this.webDavUsername,
      webDavPassword: webDavPassword ?? this.webDavPassword,
      localDeviceName: localDeviceName ?? this.localDeviceName,
      localPeerAddress: localPeerAddress ?? this.localPeerAddress,
      localPeerPort: localPeerPort ?? this.localPeerPort,
    );
  }
}

class LoadSyncPreferencesUseCase {
  const LoadSyncPreferencesUseCase(this.settingsRepository);

  final SettingsRepository settingsRepository;

  Future<SyncPreferences> call() async {
    return SyncPreferences(
      webDavBaseUrl:
          await settingsRepository.readValue<String>('sync_webdav_base_url') ??
              '',
      webDavRemotePath: await settingsRepository
              .readValue<String>('sync_webdav_remote_path') ??
          'nolive/snapshot.json',
      webDavUsername:
          await settingsRepository.readValue<String>('sync_webdav_username') ??
              '',
      webDavPassword:
          await settingsRepository.readValue<String>('sync_webdav_password') ??
              '',
      localDeviceName: await settingsRepository
              .readValue<String>('sync_local_device_name') ??
          'nolive-device',
      localPeerAddress: await settingsRepository
              .readValue<String>('sync_local_peer_address') ??
          '',
      localPeerPort:
          await settingsRepository.readValue<int>('sync_local_peer_port') ??
              23234,
    );
  }
}

class UpdateSyncPreferencesUseCase {
  const UpdateSyncPreferencesUseCase(this.settingsRepository);

  final SettingsRepository settingsRepository;

  Future<void> call(SyncPreferences preferences) async {
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
    await settingsRepository.writeValue(
      'sync_webdav_password',
      preferences.webDavPassword,
    );
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
  }
}
