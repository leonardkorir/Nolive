import 'package:flutter_test/flutter_test.dart';
import 'package:live_storage/live_storage.dart';
import 'package:live_sync/live_sync.dart';
import 'package:nolive_app/src/features/settings/application/secure_snapshot_import_coordinator.dart';
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
  });

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
  });

  test(
      'snapshot import coordinator clears stale secure credentials on replace import',
      () async {
    final settingsRepository = InMemorySettingsRepository();
    final historyRepository = InMemoryHistoryRepository();
    final followRepository = InMemoryFollowRepository();
    final tagRepository = InMemoryTagRepository();
    final secureCredentialStore = InMemorySecureCredentialStore(
      initialValues: const {
        'account_bilibili_cookie': 'SESSDATA=stale',
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
        settings: const {
          'theme_mode': 'dark',
        },
      ),
      clearExisting: true,
    );

    expect(await settingsRepository.readValue<String>('theme_mode'), 'dark');
    expect(
        await secureCredentialStore.read('account_bilibili_cookie'), isEmpty);
    expect(await secureCredentialStore.read('sync_webdav_password'), isEmpty);
  });

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
      providerId: 'bilibili',
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

    expect(await secureCredentialStore.read('account_douyin_cookie'), isEmpty);
    expect(await secureCredentialStore.read('sync_webdav_password'), isEmpty);
    expect((await historyRepository.listRecent()).single.roomId, '1');
  });
}
