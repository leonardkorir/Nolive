import 'dart:io';

import 'package:live_storage/live_storage.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late File storageFile;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('simplelive-storage-test');
    storageFile = File('${tempDir.path}${Platform.pathSeparator}storage.json');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('file-backed repositories persist settings, follows, history, and tags',
      () async {
    final firstStore = await LocalStorageFileStore.open(file: storageFile);
    final firstSettings = FileSettingsRepository(firstStore);
    final firstHistory = FileHistoryRepository(firstStore);
    final firstFollow = FileFollowRepository(firstStore);
    final firstTag = FileTagRepository(firstStore);

    await firstSettings.writeValue('theme_mode', 'dark');
    await firstSettings.writeValue('player_volume', 0.5);
    await firstSettings.writeValue('blocked_keywords', ['剧透', '广告']);
    await firstHistory.add(
      HistoryRecord(
        providerId: 'bilibili',
        roomId: '1000',
        title: '测试历史',
        streamerName: '主播 A',
        viewedAt: DateTime.parse('2026-03-10T00:00:00Z'),
      ),
    );
    await firstFollow.upsert(
      const FollowRecord(
        providerId: 'douyu',
        roomId: '2000',
        streamerName: '主播 B',
        streamerAvatarUrl: 'https://example.com/avatar-b.png',
        lastTitle: '持久化标题',
        lastAreaName: '持久化分区',
        lastCoverUrl: 'https://example.com/cover-b.png',
        lastKeyframeUrl: 'https://example.com/keyframe-b.png',
        tags: ['常看'],
      ),
    );
    await firstTag.create('常看');

    final reopenedStore = await LocalStorageFileStore.open(file: storageFile);
    final reopenedSettings = FileSettingsRepository(reopenedStore);
    final reopenedHistory = FileHistoryRepository(reopenedStore);
    final reopenedFollow = FileFollowRepository(reopenedStore);
    final reopenedTag = FileTagRepository(reopenedStore);

    expect(await reopenedSettings.readValue<String>('theme_mode'), 'dark');
    expect(await reopenedSettings.readValue<double>('player_volume'), 0.5);
    expect(
      await reopenedSettings.readValue<List<String>>('blocked_keywords'),
      ['剧透', '广告'],
    );

    final history = await reopenedHistory.listRecent();
    expect(history, hasLength(1));
    expect(history.first.title, '测试历史');

    final follows = await reopenedFollow.listAll();
    expect(follows, hasLength(1));
    expect(follows.first.streamerAvatarUrl, 'https://example.com/avatar-b.png');
    expect(follows.first.lastTitle, '持久化标题');
    expect(follows.first.lastAreaName, '持久化分区');
    expect(follows.first.lastCoverUrl, 'https://example.com/cover-b.png');
    expect(
      follows.first.lastKeyframeUrl,
      'https://example.com/keyframe-b.png',
    );
    expect(follows.first.tags, ['常看']);

    expect(await reopenedTag.listAll(), ['常看']);
  });

  test(
      'file-backed repositories preserve repository semantics for updates and clears',
      () async {
    final store = await LocalStorageFileStore.open(file: storageFile);
    final settings = FileSettingsRepository(store);
    final history = FileHistoryRepository(store);
    final follow = FileFollowRepository(store);
    final tag = FileTagRepository(store);

    await settings.writeValue('account_bilibili_user_id', 42);
    await follow.upsert(
      const FollowRecord(
        providerId: 'bilibili',
        roomId: '1',
        streamerName: '主播 1',
      ),
    );
    await follow.upsert(
      const FollowRecord(
        providerId: 'bilibili',
        roomId: '1',
        streamerName: '主播 1 新',
        tags: ['收藏'],
        lastTitle: '更新标题',
      ),
    );
    await history.add(
      HistoryRecord(
        providerId: 'bilibili',
        roomId: '1',
        title: '房间 1',
        streamerName: '主播 1',
        viewedAt: DateTime.parse('2026-03-10T00:00:00Z'),
      ),
    );
    await history.add(
      HistoryRecord(
        providerId: 'bilibili',
        roomId: '1',
        title: '房间 1 更新',
        streamerName: '主播 1',
        viewedAt: DateTime.parse('2026-03-10T01:00:00Z'),
      ),
    );
    await tag.create('收藏');
    await tag.rename('收藏', '最爱');

    expect(await settings.readValue<int>('account_bilibili_user_id'), 42);
    expect((await follow.listAll()).single.streamerName, '主播 1 新');
    expect((await follow.listAll()).single.streamerAvatarUrl, isNull);
    expect((await follow.listAll()).single.lastTitle, '更新标题');
    expect((await history.listRecent()).single.title, '房间 1 更新');
    expect(await tag.listAll(), ['最爱']);

    await settings.remove('account_bilibili_user_id');
    await follow.clear();
    await history.clear();
    await tag.clear();

    expect(await settings.readValue<int>('account_bilibili_user_id'), isNull);
    expect(await follow.listAll(), isEmpty);
    expect(await history.listRecent(), isEmpty);
    expect(await tag.listAll(), isEmpty);
  });

  test('file-backed follow updates preserve existing order', () async {
    final store = await LocalStorageFileStore.open(file: storageFile);
    final follow = FileFollowRepository(store);

    await follow.upsert(
      const FollowRecord(
        providerId: 'bilibili',
        roomId: '1',
        streamerName: '主播 1',
      ),
    );
    await follow.upsert(
      const FollowRecord(
        providerId: 'douyu',
        roomId: '2',
        streamerName: '主播 2',
      ),
    );
    await follow.upsert(
      const FollowRecord(
        providerId: 'bilibili',
        roomId: '1',
        streamerName: '主播 1',
        streamerAvatarUrl: 'https://example.com/avatar-1.png',
        lastCoverUrl: 'https://example.com/cover-1.png',
      ),
    );

    final follows = await follow.listAll();
    expect(
      follows.map((item) => '${item.providerId}:${item.roomId}').toList(),
      ['douyu:2', 'bilibili:1'],
    );
    expect(follows.last.streamerAvatarUrl, 'https://example.com/avatar-1.png');
    expect(follows.last.lastCoverUrl, 'https://example.com/cover-1.png');
  });

  test('file-backed follow repository batches upserts in one logical update',
      () async {
    final store = await LocalStorageFileStore.open(file: storageFile);
    final follow = FileFollowRepository(store);

    await follow.upsertAll(const [
      FollowRecord(
        providerId: 'bilibili',
        roomId: '10',
        streamerName: '主播 10',
      ),
      FollowRecord(
        providerId: 'douyu',
        roomId: '20',
        streamerName: '主播 20',
      ),
      FollowRecord(
        providerId: 'bilibili',
        roomId: '10',
        streamerName: '主播 10',
        lastTitle: '批量更新标题',
      ),
    ]);

    final follows = await follow.listAll();
    expect(
      follows.map((item) => '${item.providerId}:${item.roomId}').toList(),
      ['douyu:20', 'bilibili:10'],
    );
    expect(follows.last.lastTitle, '批量更新标题');
  });
}
