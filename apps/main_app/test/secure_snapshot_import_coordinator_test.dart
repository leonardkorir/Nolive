import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_storage/live_storage.dart';
import 'package:live_sync/live_sync.dart';
import 'package:nolive_app/src/features/settings/application/secure_snapshot_import_coordinator.dart';
import 'package:nolive_app/src/features/settings/application/sensitive_setting_keys.dart';
import 'package:nolive_app/src/shared/application/secure_credential_store.dart';

void main() {
  test(
    'startup migration moves sensitive settings to secure store and clears legacy keys',
    () async {
      final settingsRepository = InMemorySettingsRepository();
      final secureCredentialStore = InMemorySecureCredentialStore();

      await settingsRepository.writeValue(
        'account_bilibili_cookie',
        'SESSDATA=demo;bili_jct=test;',
      );
      await settingsRepository.writeValue(
        'sync_webdav_password',
        'demo-webdav-password',
      );
      await settingsRepository.writeValue('theme_mode', 'dark');

      await MigrateSensitiveSettingsToSecureStoreUseCase(
        settingsRepository: settingsRepository,
        secureCredentialStore: secureCredentialStore,
      )();

      expect(
        await settingsRepository.readValue<String>('account_bilibili_cookie'),
        isNull,
      );
      expect(
        await settingsRepository.readValue<String>('sync_webdav_password'),
        isNull,
      );
      expect(await settingsRepository.readValue<String>('theme_mode'), 'dark');
      expect(
        await secureCredentialStore.read('account_bilibili_cookie'),
        'SESSDATA=demo;bili_jct=test;',
      );
      expect(
        await secureCredentialStore.read('sync_webdav_password'),
        'demo-webdav-password',
      );
    },
  );

  test(
    'snapshot import coordinator strips sensitive settings and persists them securely',
    () async {
      final settingsRepository = InMemorySettingsRepository();
      final historyRepository = InMemoryHistoryRepository();
      final followRepository = InMemoryFollowRepository();
      final tagRepository = InMemoryTagRepository();
      final secureCredentialStore = InMemorySecureCredentialStore();
      final snapshotService = RepositorySyncSnapshotService(
        settingsRepository: settingsRepository,
        historyRepository: historyRepository,
        followRepository: followRepository,
        tagRepository: tagRepository,
      );
      final coordinator = SecureSnapshotImportCoordinator(
        snapshotService: snapshotService,
        secureCredentialStore: secureCredentialStore,
      );

      await coordinator.importSnapshot(
        SyncSnapshot(
          settings: const {
            'theme_mode': 'dark',
            'account_douyin_cookie': 'douyin-session-demo',
            'sync_webdav_password': 'demo-webdav-password',
          },
          blockedKeywords: const ['广告'],
          history: const [],
          follows: const [],
          tags: const ['常看'],
        ),
      );

      expect(await settingsRepository.readValue<String>('theme_mode'), 'dark');
      expect(
        await settingsRepository.readValue<String>('account_douyin_cookie'),
        isNull,
      );
      expect(
        await settingsRepository.readValue<String>('sync_webdav_password'),
        isNull,
      );
      expect(
        await secureCredentialStore.read('account_douyin_cookie'),
        'douyin-session-demo',
      );
      expect(
        await secureCredentialStore.read('sync_webdav_password'),
        'demo-webdav-password',
      );
      expect(
        await settingsRepository.readValue<List<String>>('blocked_keywords'),
        ['广告'],
      );
      expect(await tagRepository.listAll(), ['常看']);
    },
  );

  test(
    'snapshot import pipeline keeps sensitive values out of exported snapshots',
    () async {
      final settingsRepository = InMemorySettingsRepository();
      final historyRepository = InMemoryHistoryRepository();
      final followRepository = InMemoryFollowRepository();
      final tagRepository = InMemoryTagRepository();
      final secureCredentialStore =
          await SettingsBackedSecureCredentialStore.open(
            settingsRepository: settingsRepository,
            allowedKeys: SensitiveSettingKeys.secureCredentialKeys,
          );
      final snapshotService = RepositorySyncSnapshotService(
        settingsRepository: settingsRepository,
        historyRepository: historyRepository,
        followRepository: followRepository,
        tagRepository: tagRepository,
        shouldIncludeSettingInSnapshot: (key) {
          return !SensitiveSettingKeys.isSnapshotExcludedKey(key);
        },
      );
      final coordinator = SecureSnapshotImportCoordinator(
        snapshotService: snapshotService,
        secureCredentialStore: secureCredentialStore,
      );

      await coordinator.importSnapshot(
        SyncSnapshot(
          settings: const {
            'theme_mode': 'dark',
            SensitiveSettingKeys.syncLocalAccessToken: 'local-token',
            SensitiveSettingKeys.syncWebDavPassword: 'webdav-password',
            SensitiveSettingKeys.accountTwitchCookie: 'twitch-cookie',
          },
          history: [
            HistoryRecord(
              providerId: ProviderId.bilibili,
              roomId: '6',
              title: '演示房间',
              streamerName: '主播A',
              viewedAt: DateTime(2026, 5, 4, 12),
            ),
          ],
          tags: const ['常看'],
        ),
      );

      final exported = await snapshotService.exportSnapshot();

      expect(exported.settings['theme_mode'], 'dark');
      expect(
        exported.settings.containsKey(
          SensitiveSettingKeys.syncLocalAccessToken,
        ),
        isFalse,
      );
      expect(
        exported.settings.containsKey(SensitiveSettingKeys.syncWebDavPassword),
        isFalse,
      );
      expect(
        exported.settings.containsKey(SensitiveSettingKeys.accountTwitchCookie),
        isFalse,
      );
      expect(exported.history.single.roomId, '6');
      expect(exported.tags, ['常看']);
      expect(
        await secureCredentialStore.read(
          SensitiveSettingKeys.syncLocalAccessToken,
        ),
        'local-token',
      );
      expect(
        await secureCredentialStore.read(
          SensitiveSettingKeys.syncWebDavPassword,
        ),
        'webdav-password',
      );
      expect(
        await secureCredentialStore.read(
          SensitiveSettingKeys.accountTwitchCookie,
        ),
        'twitch-cookie',
      );
    },
  );

  test(
    'snapshot import coordinator preserves existing secure credentials if absent, and clears them if explicitly empty',
    () async {
      final settingsRepository = InMemorySettingsRepository();
      final historyRepository = InMemoryHistoryRepository();
      final followRepository = InMemoryFollowRepository();
      final tagRepository = InMemoryTagRepository();
      final secureCredentialStore = InMemorySecureCredentialStore(
        initialValues: const {
          'account_bilibili_cookie': 'SESSDATA=keep',
          'sync_webdav_password': 'stale-password',
        },
      );
      final snapshotService = RepositorySyncSnapshotService(
        settingsRepository: settingsRepository,
        historyRepository: historyRepository,
        followRepository: followRepository,
        tagRepository: tagRepository,
      );
      final coordinator = SecureSnapshotImportCoordinator(
        snapshotService: snapshotService,
        secureCredentialStore: secureCredentialStore,
      );

      await coordinator.importSnapshot(
        SyncSnapshot(
          settings: const {'theme_mode': 'dark', 'sync_webdav_password': ''},
        ),
        clearExisting: true,
      );

      expect(await settingsRepository.readValue<String>('theme_mode'), 'dark');
      expect(
        await secureCredentialStore.read('account_bilibili_cookie'),
        'SESSDATA=keep',
      );
      expect(await secureCredentialStore.read('sync_webdav_password'), isEmpty);
    },
  );

  test(
    'snapshot category import ignores secure settings for non-settings categories',
    () async {
      final settingsRepository = InMemorySettingsRepository();
      final historyRepository = InMemoryHistoryRepository();
      final followRepository = InMemoryFollowRepository();
      final tagRepository = InMemoryTagRepository();
      final secureCredentialStore = InMemorySecureCredentialStore();
      final snapshotService = RepositorySyncSnapshotService(
        settingsRepository: settingsRepository,
        historyRepository: historyRepository,
        followRepository: followRepository,
        tagRepository: tagRepository,
      );
      final coordinator = SecureSnapshotImportCoordinator(
        snapshotService: snapshotService,
        secureCredentialStore: secureCredentialStore,
      );
      final importedHistory = HistoryRecord(
        providerId: ProviderId.bilibili,
        roomId: '1',
        title: '演示房间',
        streamerName: '主播A',
        viewedAt: DateTime(2026, 4, 13, 12),
      );

      await coordinator.importCategory(
        SyncDataCategory.history,
        SyncSnapshot(
          settings: const {
            'account_douyin_cookie': 'unexpected-cookie',
            'sync_webdav_password': 'unexpected-password',
          },
          history: [importedHistory],
        ),
      );

      expect(
        await secureCredentialStore.read('account_douyin_cookie'),
        isEmpty,
      );
      expect(await secureCredentialStore.read('sync_webdav_password'), isEmpty);
      expect((await historyRepository.listRecent()).single.roomId, '1');
    },
  );

  test(
    'category backup restore preserves existing secure credentials',
    () async {
      final settingsRepository = InMemorySettingsRepository();
      final historyRepository = InMemoryHistoryRepository();
      final followRepository = InMemoryFollowRepository();
      final tagRepository = InMemoryTagRepository();
      final secureCredentialStore = InMemorySecureCredentialStore(
        initialValues: const {
          'account_bilibili_cookie': 'SESSDATA=keep',
          'sync_webdav_password': 'keep-password',
        },
      );
      final snapshotService = RepositorySyncSnapshotService(
        settingsRepository: settingsRepository,
        historyRepository: historyRepository,
        followRepository: followRepository,
        tagRepository: tagRepository,
      );
      final coordinator = SecureSnapshotImportCoordinator(
        snapshotService: snapshotService,
        secureCredentialStore: secureCredentialStore,
      );

      await settingsRepository.writeValue('theme_mode', 'dark');
      await settingsRepository.writeValue('player_backend', 'mpv');

      await coordinator.restoreCategoryBackup(
        SyncDataCategory.settings,
        const SyncSnapshot(settings: {'theme_mode': 'light'}),
      );

      expect(await settingsRepository.readValue<String>('theme_mode'), 'light');
      expect(
        await settingsRepository.readValue<String>('player_backend'),
        isNull,
      );
      expect(
        await secureCredentialStore.read('account_bilibili_cookie'),
        'SESSDATA=keep',
      );
      expect(
        await secureCredentialStore.read('sync_webdav_password'),
        'keep-password',
      );
    },
  );

  test(
    'category backup restore preserves settings-backed secure credentials',
    () async {
      final settingsRepository = InMemorySettingsRepository();
      final historyRepository = InMemoryHistoryRepository();
      final followRepository = InMemoryFollowRepository();
      final tagRepository = InMemoryTagRepository();

      await settingsRepository.writeValue(
        SensitiveSettingKeys.syncLocalAccessToken,
        'local-token-keep',
      );
      await settingsRepository.writeValue(
        SensitiveSettingKeys.syncWebDavPassword,
        'webdav-password-keep',
      );
      await settingsRepository.writeValue(
        SensitiveSettingKeys.accountBilibiliCookie,
        'SESSDATA=keep',
      );

      final secureCredentialStore =
          await SettingsBackedSecureCredentialStore.open(
            settingsRepository: settingsRepository,
            allowedKeys: SensitiveSettingKeys.secureCredentialKeys,
          );
      final snapshotService = RepositorySyncSnapshotService(
        settingsRepository: settingsRepository,
        historyRepository: historyRepository,
        followRepository: followRepository,
        tagRepository: tagRepository,
      );
      final coordinator = SecureSnapshotImportCoordinator(
        snapshotService: snapshotService,
        secureCredentialStore: secureCredentialStore,
      );

      await settingsRepository.writeValue('theme_mode', 'dark');
      await settingsRepository.writeValue('player_backend', 'mpv');

      await coordinator.restoreCategoryBackup(
        SyncDataCategory.settings,
        const SyncSnapshot(settings: {'theme_mode': 'light'}),
      );

      expect(await settingsRepository.readValue<String>('theme_mode'), 'light');
      expect(
        await settingsRepository.readValue<String>('player_backend'),
        isNull,
      );
      expect(
        await settingsRepository.readValue<String>(
          SensitiveSettingKeys.syncLocalAccessToken,
        ),
        'local-token-keep',
      );
      expect(
        await settingsRepository.readValue<String>(
          SensitiveSettingKeys.syncWebDavPassword,
        ),
        'webdav-password-keep',
      );
      expect(
        await settingsRepository.readValue<String>(
          SensitiveSettingKeys.accountBilibiliCookie,
        ),
        'SESSDATA=keep',
      );
      expect(
        await secureCredentialStore.read(
          SensitiveSettingKeys.syncLocalAccessToken,
        ),
        'local-token-keep',
      );
    },
  );

  test(
    'import notifies onAfterImport so follow UI can refresh without restart',
    () async {
      final settingsRepository = InMemorySettingsRepository();
      final historyRepository = InMemoryHistoryRepository();
      final followRepository = InMemoryFollowRepository();
      final tagRepository = InMemoryTagRepository();
      final secureCredentialStore = InMemorySecureCredentialStore();
      final snapshotService = RepositorySyncSnapshotService(
        settingsRepository: settingsRepository,
        historyRepository: historyRepository,
        followRepository: followRepository,
        tagRepository: tagRepository,
      );

      final notifications = <({bool follow, bool settings})>[];
      final coordinator = SecureSnapshotImportCoordinator(
        snapshotService: snapshotService,
        secureCredentialStore: secureCredentialStore,
        onAfterImport:
            ({
              required bool followDataChanged,
              required bool settingsChanged,
            }) async {
              notifications.add((
                follow: followDataChanged,
                settings: settingsChanged,
              ));
            },
      );

      await coordinator.importCategory(
        SyncDataCategory.library,
        SyncSnapshot(
          follows: [
            FollowRecord(
              providerId: ProviderId.bilibili,
              roomId: '1',
              streamerName: '主播A',
              streamerAvatarUrl: '',
              lastTitle: '',
              lastAreaName: '',
              lastCoverUrl: '',
              lastKeyframeUrl: '',
              tags: const [],
            ),
          ],
          tags: const ['常看'],
        ),
      );

      expect(notifications, hasLength(1));
      expect(notifications.single.follow, isTrue);
      expect(notifications.single.settings, isFalse);
      expect(await followRepository.listAll(), hasLength(1));

      await coordinator.importSnapshot(
        const SyncSnapshot(settings: {'theme_mode': 'dark'}),
      );
      expect(notifications, hasLength(2));
      expect(notifications.last.follow, isTrue);
      expect(notifications.last.settings, isTrue);
    },
  );
}
