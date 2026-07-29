import 'package:live_storage/live_storage.dart';
import 'package:live_sync/live_sync.dart';

import '../../../shared/application/secure_credential_store.dart';
import 'sensitive_setting_keys.dart';

/// Called after a snapshot / category import commits to storage.
///
/// Used to invalidate in-memory UI caches (especially 关注列表) without
/// requiring an app restart.
typedef SnapshotImportSideEffect =
    Future<void> Function({
      required bool followDataChanged,
      required bool settingsChanged,
    });

class SecureSnapshotImportCoordinator {
  const SecureSnapshotImportCoordinator({
    required this.snapshotService,
    required this.secureCredentialStore,
    this.onAfterImport,
  });

  final RepositorySyncSnapshotService snapshotService;
  final SecureCredentialStore secureCredentialStore;

  /// Optional side effects after import (LAN / WebDAV / JSON 共用).
  final SnapshotImportSideEffect? onAfterImport;

  Future<void> importCategory(
    SyncDataCategory category,
    SyncSnapshot snapshot, {
    bool clearExisting = true,
  }) async {
    final persistSecureSettings = category == SyncDataCategory.settings;
    final sanitized = await sanitizeAndPersist(
      snapshot,
      persistSecureSettings: persistSecureSettings,
      clearExistingSecureSettings: false,
    );
    await snapshotService.importCategory(
      category,
      sanitized,
      clearExisting: clearExisting,
    );
    await _notifyAfterImport(
      followDataChanged: category == SyncDataCategory.library,
      settingsChanged:
          category == SyncDataCategory.settings ||
          category == SyncDataCategory.blockedKeywords,
    );
  }

  Future<void> restoreCategoryBackup(
    SyncDataCategory category,
    SyncSnapshot snapshot,
  ) async {
    final persistSecureSettings = category == SyncDataCategory.settings;
    await secureCredentialStore.ensureReady();
    final settingsBackedSecureValues =
        persistSecureSettings &&
            !secureCredentialStore.storesSecureValuesSeparately
        ? await secureCredentialStore.readAll()
        : const <String, String>{};
    final sanitized = await sanitizeAndPersist(
      snapshot,
      persistSecureSettings: persistSecureSettings,
      clearExistingSecureSettings: false,
    );
    await snapshotService.importCategory(
      category,
      sanitized,
      clearExisting: true,
    );
    if (settingsBackedSecureValues.isNotEmpty) {
      await secureCredentialStore.writeAll(settingsBackedSecureValues);
    }
    await _notifyAfterImport(
      followDataChanged: category == SyncDataCategory.library,
      settingsChanged:
          category == SyncDataCategory.settings ||
          category == SyncDataCategory.blockedKeywords,
    );
  }

  Future<void> importSnapshot(
    SyncSnapshot snapshot, {
    bool clearExisting = true,
    SyncImportMode mode = SyncImportMode.replace,
    DateTime? lastSyncAt,
  }) async {
    final sanitized = await sanitizeAndPersist(
      snapshot,
      persistSecureSettings: true,
      clearExistingSecureSettings: false,
    );
    await snapshotService.importSnapshot(
      sanitized,
      clearExisting: clearExisting,
      mode: mode,
      lastSyncAt: lastSyncAt,
    );
    await _notifyAfterImport(followDataChanged: true, settingsChanged: true);
  }

  Future<void> _notifyAfterImport({
    required bool followDataChanged,
    required bool settingsChanged,
  }) async {
    final hook = onAfterImport;
    if (hook == null) {
      return;
    }
    if (!followDataChanged && !settingsChanged) {
      return;
    }
    await hook(
      followDataChanged: followDataChanged,
      settingsChanged: settingsChanged,
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
        secureValues[key] = normalized;
        continue;
      }
      if (SensitiveSettingKeys.isSnapshotExcludedKey(key)) {
        continue;
      }
      sanitized[key] = rawValue;
    }

    if (persistSecureSettings) {
      final keysToClear = clearExistingSecureSettings
          ? SensitiveSettingKeys.secureCredentialKeys
          : secureValues.keys;
      for (final key in keysToClear) {
        final val = secureValues[key] ?? '';
        if (val.isEmpty) {
          await secureCredentialStore.delete(key);
        } else {
          await secureCredentialStore.write(key, val);
        }
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

    if (!secureCredentialStore.storesSecureValuesSeparately) {
      return;
    }

    for (final key in SensitiveSettingKeys.secureCredentialKeys) {
      if (settings.containsKey(key)) {
        await settingsRepository.remove(key);
      }
    }
  }
}
