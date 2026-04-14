import 'package:live_storage/live_storage.dart';
import 'package:live_sync/live_sync.dart';
import 'package:test/test.dart';

void main() {
  test('repository sync snapshot exports storage state', () async {
    final settingsRepository = InMemorySettingsRepository();
    final historyRepository = InMemoryHistoryRepository();
    final followRepository = InMemoryFollowRepository();
    final tagRepository = InMemoryTagRepository();
    final service = RepositorySyncSnapshotService(
      settingsRepository: settingsRepository,
      historyRepository: historyRepository,
      followRepository: followRepository,
      tagRepository: tagRepository,
    );

    await settingsRepository.writeValue('theme_mode', 'dark');
    await settingsRepository.writeValue('player_auto_play', true);
    await settingsRepository.writeValue('blocked_keywords', ['剧透']);
    await tagRepository.create('常看');
    await historyRepository.add(
      HistoryRecord(
        providerId: 'bilibili',
        roomId: '6',
        title: '测试房间',
        streamerName: '主播',
        viewedAt: DateTime(2026, 3, 10, 12),
      ),
    );
    await followRepository.upsert(
      const FollowRecord(
        providerId: 'douyu',
        roomId: '123',
        streamerName: '斗鱼主播',
        streamerAvatarUrl: 'https://example.com/avatar-douyu.png',
      ),
    );

    final snapshot = await service.exportSnapshot();
    expect(snapshot.settings['theme_mode'], 'dark');
    expect(snapshot.settings['player_auto_play'], isTrue);
    expect(snapshot.blockedKeywords, ['剧透']);
    expect(snapshot.tags, ['常看']);
    expect(snapshot.history.single.roomId, '6');
    expect(snapshot.follows.single.roomId, '123');
    expect(
      snapshot.follows.single.streamerAvatarUrl,
      'https://example.com/avatar-douyu.png',
    );
  });

  test('repository sync snapshot imports storage state', () async {
    final settingsRepository = InMemorySettingsRepository();
    final historyRepository = InMemoryHistoryRepository();
    final followRepository = InMemoryFollowRepository();
    final tagRepository = InMemoryTagRepository();
    final service = RepositorySyncSnapshotService(
      settingsRepository: settingsRepository,
      historyRepository: historyRepository,
      followRepository: followRepository,
      tagRepository: tagRepository,
    );

    await service.importSnapshot(
      SyncSnapshot(
        settings: const {
          'theme_mode': 'light',
          'player_auto_play': false,
        },
        blockedKeywords: const ['广告'],
        tags: const ['收藏'],
        history: [
          HistoryRecord(
            providerId: 'huya',
            roomId: '88',
            title: '测试直播',
            streamerName: '主播A',
            viewedAt: DateTime(2026, 3, 10, 18),
          ),
        ],
        follows: [
          FollowRecord(
            providerId: 'douyin',
            roomId: '66',
            streamerName: '主播B',
            streamerAvatarUrl: 'https://example.com/avatar-b.png',
            tags: ['收藏'],
          ),
        ],
      ),
    );

    expect(await settingsRepository.readValue<String>('theme_mode'), 'light');
    expect(
        await settingsRepository.readValue<bool>('player_auto_play'), isFalse);
    expect(
      await settingsRepository.readValue<List<String>>('blocked_keywords'),
      ['广告'],
    );
    expect((await historyRepository.listRecent()).single.roomId, '88');
    expect((await followRepository.listAll()).single.roomId, '66');
    expect(
      (await followRepository.listAll()).single.streamerAvatarUrl,
      'https://example.com/avatar-b.png',
    );
    expect(await tagRepository.listAll(), ['收藏']);
  });

  test('repository sync snapshot exports and imports categories', () async {
    final settingsRepository = InMemorySettingsRepository();
    final historyRepository = InMemoryHistoryRepository();
    final followRepository = InMemoryFollowRepository();
    final tagRepository = InMemoryTagRepository();
    final service = RepositorySyncSnapshotService(
      settingsRepository: settingsRepository,
      historyRepository: historyRepository,
      followRepository: followRepository,
      tagRepository: tagRepository,
    );

    await settingsRepository.writeValue('theme_mode', 'dark');
    await settingsRepository.writeValue('blocked_keywords', ['刷屏']);
    await tagRepository.create('收藏');
    await followRepository.upsert(
      const FollowRecord(
        providerId: 'douyu',
        roomId: '77',
        streamerName: '主播C',
      ),
    );

    final library = await service.exportCategory(SyncDataCategory.library);
    final blocked = await service.exportCategory(
      SyncDataCategory.blockedKeywords,
    );

    expect(library.follows.single.roomId, '77');
    expect(library.tags, ['收藏']);
    expect(blocked.blockedKeywords, ['刷屏']);

    await followRepository.clear();
    await tagRepository.clear();
    await settingsRepository.writeValue('blocked_keywords', const <String>[]);

    await service.importCategory(SyncDataCategory.library, library);
    await service.importCategory(
      SyncDataCategory.blockedKeywords,
      blocked,
      clearExisting: false,
    );

    expect((await followRepository.listAll()).single.roomId, '77');
    expect(await tagRepository.listAll(), ['收藏']);
    expect(
      await settingsRepository.readValue<List<String>>('blocked_keywords'),
      ['刷屏'],
    );
  });

  test('repository sync snapshot can exclude sensitive settings from export',
      () async {
    final settingsRepository = InMemorySettingsRepository();
    final historyRepository = InMemoryHistoryRepository();
    final followRepository = InMemoryFollowRepository();
    final tagRepository = InMemoryTagRepository();
    final service = RepositorySyncSnapshotService(
      settingsRepository: settingsRepository,
      historyRepository: historyRepository,
      followRepository: followRepository,
      tagRepository: tagRepository,
      shouldIncludeSettingInSnapshot: (key) =>
          key != 'account_bilibili_cookie' && key != 'sync_webdav_password',
    );

    await settingsRepository.writeValue('theme_mode', 'dark');
    await settingsRepository.writeValue(
      'account_bilibili_cookie',
      'SESSDATA=demo',
    );
    await settingsRepository.writeValue(
      'sync_webdav_password',
      'demo-password',
    );

    final snapshot = await service.exportSnapshot();

    expect(snapshot.settings['theme_mode'], 'dark');
    expect(snapshot.settings.containsKey('account_bilibili_cookie'), isFalse);
    expect(snapshot.settings.containsKey('sync_webdav_password'), isFalse);
  });
}
