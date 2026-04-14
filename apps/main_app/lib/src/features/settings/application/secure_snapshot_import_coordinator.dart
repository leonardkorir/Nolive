import 'package:live_storage/live_storage.dart';
import 'package:live_sync/live_sync.dart';

import '../../../shared/application/secure_credential_store.dart';
import 'sensitive_setting_keys.dart';

class SecureSnapshotImportCoordinator {
  const SecureSnapshotImportCoordinator({
    required this.snapshotService,
    required this.secureCredentialStore,
  });

  final RepositorySyncSnapshotService snapshotService;
  final SecureCredentialStore secureCredentialStore;

  Future<void> importCategory(
    SyncDataCategory category,
    SyncSnapshot snapshot, {
    bool clearExisting = true,
  }) async {
    final persistSecureSettings = category == SyncDataCategory.settings;
    final sanitized = await sanitizeAndPersist(
      snapshot,
      persistSecureSettings: persistSecureSettings,
      clearExistingSecureSettings: persistSecureSettings && clearExisting,
    );
    await snapshotService.importCategory(
      category,
      sanitized,
      clearExisting: clearExisting,
    );
  }

  Future<void> importSnapshot(
    SyncSnapshot snapshot, {
    bool clearExisting = true,
  }) async {
    final sanitized = await sanitizeAndPersist(
      snapshot,
      persistSecureSettings: true,
      clearExistingSecureSettings: clearExisting,
    );
    await snapshotService.importSnapshot(
      sanitized,
      clearExisting: clearExisting,
    );
  }

  Future<SyncSnapshot> sanitizeAndPersist(
    SyncSnapshot snapshot, {
    bool persistSecureSettings = true,
    bool clearExistingSecureSettings = false,
  }) async {
    final sanitizedSettings = await sanitizeAndPersistSettings(
      snapshot.settings,
      persistSecureSettings: persistSecureSettings,
      clearExistingSecureSettings: clearExistingSecureSettings,
    );
    return SyncSnapshot(
      settings: sanitizedSettings,
      blockedKeywords: snapshot.blockedKeywords,
      history: snapshot.history,
      follows: snapshot.follows,
      tags: snapshot.tags,
    );
  }

  Future<Map<String, Object?>> sanitizeAndPersistSettings(
    Map<String, Object?> settings, {
    bool persistSecureSettings = true,
    bool clearExistingSecureSettings = false,
  }) async {
    final secureValues = <String, String>{};
    final sanitized = <String, Object?>{};

    for (final entry in settings.entries) {
      final key = entry.key;
      final rawValue = entry.value;
      if (SensitiveSettingKeys.isSecureCredentialKey(key)) {
        final normalized = rawValue?.toString().trim() ?? '';
        if (normalized.isNotEmpty) {
          secureValues[key] = normalized;
        }
        continue;
      }
      if (SensitiveSettingKeys.isSnapshotExcludedKey(key)) {
        continue;
      }
      sanitized[key] = rawValue;
    }

    if (persistSecureSettings) {
      if (clearExistingSecureSettings) {
        await secureCredentialStore.deleteAll(
          SensitiveSettingKeys.secureCredentialKeys,
        );
      }
      if (secureValues.isNotEmpty) {
        await secureCredentialStore.writeAll(secureValues);
      }
    }

    return sanitized;
  }
}

class MigrateSensitiveSettingsToSecureStoreUseCase {
  const MigrateSensitiveSettingsToSecureStoreUseCase({
    required this.settingsRepository,
    required this.secureCredentialStore,
  });

  final SettingsRepository settingsRepository;
  final SecureCredentialStore secureCredentialStore;

  Future<void> call() async {
    final settings = await settingsRepository.listAll();
    final secureValues = <String, String>{};

    for (final key in SensitiveSettingKeys.secureCredentialKeys) {
      final value = settings[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) {
        secureValues[key] = value;
      }
    }

    if (secureValues.isNotEmpty) {
      await secureCredentialStore.writeAll(secureValues);
    }

    for (final key in SensitiveSettingKeys.secureCredentialKeys) {
      if (settings.containsKey(key)) {
        await settingsRepository.remove(key);
      }
    }
  }
}
