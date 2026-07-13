import 'dart:convert';
import 'dart:io';

import 'package:live_core/live_core.dart';
import 'package:live_storage/live_storage.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late File storageFile;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('simplelive-storage-test');
    storageFile = File(p.join(tempDir.path, 'storage.json'));
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'file-backed repositories persist settings, follows, history, and tags',
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
          providerId: ProviderId.bilibili,
          roomId: '1000',
          title: '测试历史',
          streamerName: '主播 A',
          viewedAt: DateTime.parse('2026-03-10T00:00:00Z'),
        ),
      );
      await firstFollow.upsert(
        const FollowRecord(
          providerId: ProviderId.douyu,
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
      expect(
        follows.first.streamerAvatarUrl,
        'https://example.com/avatar-b.png',
      );
      expect(follows.first.lastTitle, '持久化标题');
      expect(follows.first.lastAreaName, '持久化分区');
      expect(follows.first.lastCoverUrl, 'https://example.com/cover-b.png');
      expect(
        follows.first.lastKeyframeUrl,
        'https://example.com/keyframe-b.png',
      );
      expect(follows.first.tags, ['常看']);

      expect(await reopenedTag.listAll(), ['常看']);
      final persisted =
          jsonDecode(await storageFile.readAsString()) as Map<String, dynamic>;
      expect(
        persisted['format_version'],
        FileStorageSnapshot.currentFormatVersion,
      );
    },
  );

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
          providerId: ProviderId.bilibili,
          roomId: '1',
          streamerName: '主播 1',
        ),
      );
      await follow.upsert(
        const FollowRecord(
          providerId: ProviderId.bilibili,
          roomId: '1',
          streamerName: '主播 1 新',
          tags: ['收藏'],
          lastTitle: '更新标题',
        ),
      );
      await history.add(
        HistoryRecord(
          providerId: ProviderId.bilibili,
          roomId: '1',
          title: '房间 1',
          streamerName: '主播 1',
          viewedAt: DateTime.parse('2026-03-10T00:00:00Z'),
        ),
      );
      await history.add(
        HistoryRecord(
          providerId: ProviderId.bilibili,
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
    },
  );

  test('file-backed follow updates preserve existing order', () async {
    final store = await LocalStorageFileStore.open(file: storageFile);
    final follow = FileFollowRepository(store);

    await follow.upsert(
      const FollowRecord(
        providerId: ProviderId.bilibili,
        roomId: '1',
        streamerName: '主播 1',
      ),
    );
    await follow.upsert(
      const FollowRecord(
        providerId: ProviderId.douyu,
        roomId: '2',
        streamerName: '主播 2',
      ),
    );
    await follow.upsert(
      const FollowRecord(
        providerId: ProviderId.bilibili,
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
    expect(() => follows.add(follows.first), throwsUnsupportedError);
  });

  test(
    'file-backed follow repository batches upserts in one logical update',
    () async {
      final store = await LocalStorageFileStore.open(file: storageFile);
      final follow = FileFollowRepository(store);

      await follow.upsertAll(const [
        FollowRecord(
          providerId: ProviderId.bilibili,
          roomId: '10',
          streamerName: '主播 10',
        ),
        FollowRecord(
          providerId: ProviderId.douyu,
          roomId: '20',
          streamerName: '主播 20',
        ),
        FollowRecord(
          providerId: ProviderId.bilibili,
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
    },
  );

  test(
    'file-backed repositories read legacy payload without format version',
    () async {
      await storageFile.writeAsString(
        '{"settings":{"theme_mode":"dark"},"history":[],"follows":[],"tags":["常看"]}',
        flush: true,
      );

      final store = await LocalStorageFileStore.open(file: storageFile);
      final settings = FileSettingsRepository(store);
      final tags = FileTagRepository(store);

      expect(await settings.readValue<String>('theme_mode'), 'dark');
      expect(await tags.listAll(), ['常看']);
    },
  );

  test(
    'file-backed settings preserve empty strings inside string lists',
    () async {
      final store = await LocalStorageFileStore.open(file: storageFile);
      final settings = FileSettingsRepository(store);

      await settings.writeValue('blocked_keywords', ['剧透', '', '广告']);

      expect(await settings.readValue<List<String>>('blocked_keywords'), [
        '剧透',
        '',
        '广告',
      ]);
    },
  );

  test(
    'file-backed tag rename throws when the source tag is missing',
    () async {
      final store = await LocalStorageFileStore.open(file: storageFile);
      final tags = FileTagRepository(store);

      await expectLater(
        () => tags.rename('不存在', '最爱'),
        throwsA(isA<StateError>()),
      );
    },
  );

  test('file-backed store recovers after a failed logical update', () async {
    final store = await LocalStorageFileStore.open(file: storageFile);

    await expectLater(
      store.update<void>((_) {
        throw StateError('boom');
      }),
      throwsA(isA<StateError>()),
    );

    await store.update<void>((snapshot) {
      snapshot.settings['theme_mode'] = 'dark';
    });

    final restoredTheme = await store.read<String?>(
      (snapshot) => snapshot.settings['theme_mode']?.toString(),
    );
    expect(restoredTheme, 'dark');
  });

  test(
    'file-backed store keeps the previous snapshot when persist fails',
    () async {
      final fileSystem = _TestLocalStorageFileSystem();
      final store = await LocalStorageFileStore.open(
        file: storageFile,
        fileSystem: fileSystem,
      );

      await store.update<void>((snapshot) {
        snapshot.settings['theme_mode'] = 'light';
      });

      fileSystem.onRename = (source, newPath) {
        if (source.path.endsWith('.tmp') && newPath == storageFile.path) {
          throw FileSystemException('rename failed', source.path);
        }
      };
      fileSystem.onCopy = (source, newPath) {
        if (source.path.endsWith('.tmp') && newPath == storageFile.path) {
          throw FileSystemException('copy failed', source.path);
        }
      };

      await expectLater(
        store.update<void>((snapshot) {
          snapshot.settings['theme_mode'] = 'dark';
        }),
        throwsA(isA<FileSystemException>()),
      );

      final inMemoryTheme = await store.read<String?>(
        (snapshot) => snapshot.settings['theme_mode']?.toString(),
      );
      expect(inMemoryTheme, 'light');

      final persisted =
          jsonDecode(await storageFile.readAsString()) as Map<String, dynamic>;
      expect(
        (persisted['settings'] as Map<String, dynamic>)['theme_mode'],
        'light',
      );
      expect(await File('${storageFile.path}.bak').exists(), isFalse);
      expect(await File('${storageFile.path}.tmp').exists(), isFalse);
    },
  );

  test(
    'file-backed store falls back to copy when rename cannot replace file',
    () async {
      final fileSystem = _TestLocalStorageFileSystem();
      final store = await LocalStorageFileStore.open(
        file: storageFile,
        fileSystem: fileSystem,
      );

      await store.update<void>((snapshot) {
        snapshot.settings['theme_mode'] = 'light';
      });

      fileSystem.onRename = (source, newPath) {
        if (source.path.endsWith('.tmp') && newPath == storageFile.path) {
          throw FileSystemException('cross-device rename', source.path);
        }
      };

      await store.update<void>((snapshot) {
        snapshot.settings['theme_mode'] = 'dark';
      });

      final persisted =
          jsonDecode(await storageFile.readAsString()) as Map<String, dynamic>;
      expect(
        (persisted['settings'] as Map<String, dynamic>)['theme_mode'],
        'dark',
      );
      expect(await File('${storageFile.path}.bak').exists(), isFalse);
      expect(await File('${storageFile.path}.tmp').exists(), isFalse);
    },
  );

  test(
    'file-backed store keeps new snapshot when temp cleanup fails after copy fallback',
    () async {
      final fileSystem = _TestLocalStorageFileSystem();
      final store = await LocalStorageFileStore.open(
        file: storageFile,
        fileSystem: fileSystem,
      );

      await store.update<void>((snapshot) {
        snapshot.settings['theme_mode'] = 'light';
      });

      fileSystem.onRename = (source, newPath) {
        if (source.path.endsWith('.tmp') && newPath == storageFile.path) {
          throw FileSystemException('cross-device rename', source.path);
        }
      };
      var deleteFailureInjected = false;
      fileSystem.onDelete = (file) {
        if (!deleteFailureInjected && file.path.endsWith('.tmp')) {
          deleteFailureInjected = true;
          throw FileSystemException('temp cleanup failed', file.path);
        }
      };

      await store.update<void>((snapshot) {
        snapshot.settings['theme_mode'] = 'dark';
      });

      final inMemoryTheme = await store.read<String?>(
        (snapshot) => snapshot.settings['theme_mode']?.toString(),
      );
      final persisted =
          jsonDecode(await storageFile.readAsString()) as Map<String, dynamic>;

      expect(inMemoryTheme, 'dark');
      expect(
        (persisted['settings'] as Map<String, dynamic>)['theme_mode'],
        'dark',
      );
    },
  );

  test('file-backed store restores replacement backup on next open', () async {
    final backupFile = File('${storageFile.path}.bak');
    await backupFile.writeAsString(
      '{"format_version":2,"settings":{"theme_mode":"light"},"history":[],"follows":[],"tags":[]}',
      flush: true,
    );

    final store = await LocalStorageFileStore.open(file: storageFile);
    final restoredTheme = await store.read<String?>(
      (snapshot) => snapshot.settings['theme_mode']?.toString(),
    );

    expect(restoredTheme, 'light');
    expect(await storageFile.exists(), isTrue);
    expect(await backupFile.exists(), isFalse);
  });

  test('file-backed store restores valid temp snapshot on next open', () async {
    final tempFile = File('${storageFile.path}.tmp');
    await tempFile.writeAsString(
      '{"format_version":2,"settings":{"theme_mode":"dark"},"history":[],"follows":[],"tags":[]}',
      flush: true,
    );

    final store = await LocalStorageFileStore.open(file: storageFile);
    final restoredTheme = await store.read<String?>(
      (snapshot) => snapshot.settings['theme_mode']?.toString(),
    );

    expect(restoredTheme, 'dark');
    expect(await storageFile.exists(), isTrue);
    expect(await tempFile.exists(), isFalse);
  });

  test(
    'file-backed store restores backup when target is invalid on next open',
    () async {
      final backupFile = File('${storageFile.path}.bak');
      await storageFile.writeAsString('{"settings":', flush: true);
      await backupFile.writeAsString(
        '{"format_version":2,"settings":{"theme_mode":"light"},"history":[],"follows":[],"tags":[]}',
        flush: true,
      );

      final store = await LocalStorageFileStore.open(file: storageFile);
      final restoredTheme = await store.read<String?>(
        (snapshot) => snapshot.settings['theme_mode']?.toString(),
      );

      expect(restoredTheme, 'light');
      expect(await backupFile.exists(), isFalse);
    },
  );

  test(
    'file-backed store removes directory-shaped target before first write',
    () async {
      await Directory(storageFile.path).create();

      final store = await LocalStorageFileStore.open(file: storageFile);
      final restoredTheme = await store.read<String?>(
        (snapshot) => snapshot.settings['theme_mode']?.toString(),
      );

      expect(restoredTheme, isNull);
      expect(await storageFile.exists(), isTrue);
      expect(await Directory(storageFile.path).exists(), isFalse);
    },
  );

  test(
    'file-backed store backs up corrupt snapshots before repairing',
    () async {
      await storageFile.writeAsString('{"settings":');

      await expectLater(
        LocalStorageFileStore.open(file: storageFile),
        throwsA(isA<LocalStorageCorruptionException>()),
      );

      final repairedStore = await LocalStorageFileStore.open(
        file: storageFile,
        repairCorruptFile: true,
      );
      final recoveryInfo = repairedStore.lastRecoveryInfo;
      expect(recoveryInfo, isNotNull);

      final backupFile = File(recoveryInfo!.backupFilePath);
      expect(await backupFile.exists(), isTrue);
      expect(await backupFile.readAsString(), '{"settings":');

      final repairedPayload =
          jsonDecode(await storageFile.readAsString()) as Map<String, dynamic>;
      expect(
        repairedPayload['format_version'],
        FileStorageSnapshot.currentFormatVersion,
      );
      expect(repairedPayload['settings'], isEmpty);
    },
  );

  test(
    'file-backed store partially recovers complete sections from corrupt JSON',
    () async {
      await storageFile.writeAsString(
        '{"settings":{"theme_mode":"dark","blocked_keywords":["剧透"]},"history":',
        flush: true,
      );

      final repairedStore = await LocalStorageFileStore.open(
        file: storageFile,
        repairCorruptFile: true,
      );
      final recoveryInfo = repairedStore.lastRecoveryInfo;
      final settings = FileSettingsRepository(repairedStore);

      expect(recoveryInfo?.recoveredSections, contains('settings'));
      expect(await settings.readValue<String>('theme_mode'), 'dark');
      expect(await settings.readValue<List<String>>('blocked_keywords'), [
        '剧透',
      ]);
    },
  );

  test('file-backed store recovers sections containing escaped quotes', () async {
    await storageFile.writeAsString(
      r'{"settings":{"theme_mode":"dark","status":"quoted \"value\" with } brace"},"history":',
      flush: true,
    );

    final repairedStore = await LocalStorageFileStore.open(
      file: storageFile,
      repairCorruptFile: true,
    );
    final settings = FileSettingsRepository(repairedStore);

    expect(
      repairedStore.lastRecoveryInfo?.recoveredSections,
      contains('settings'),
    );
    expect(await settings.readValue<String>('theme_mode'), 'dark');
    expect(
      await settings.readValue<String>('status'),
      'quoted "value" with } brace',
    );
  });

  test(
    'file-backed store ignores nested same-key sections during repair',
    () async {
      await storageFile.writeAsString(
        jsonEncode({
          'settings': {
            'history': [
              {
                'provider_id': ProviderId.douyu.value,
                'room_id': 'nested',
                'title': 'nested title',
                'streamer_name': 'nested streamer',
                'viewed_at': '2026-01-01T00:00:00.000Z',
              },
            ],
            'theme_mode': 'dark',
          },
          'history': [
            {
              'provider_id': ProviderId.bilibili.value,
              'room_id': '1000',
              'title': 'top title',
              'streamer_name': 'top streamer',
              'viewed_at': '2026-01-02T00:00:00.000Z',
            },
          ],
        }).replaceFirst(RegExp(r'}$'), ',"follows":'),
        flush: true,
      );

      final repairedStore = await LocalStorageFileStore.open(
        file: storageFile,
        repairCorruptFile: true,
      );
      final history = FileHistoryRepository(repairedStore);

      expect(
        repairedStore.lastRecoveryInfo?.recoveredSections,
        containsAll(['settings', 'history']),
      );
      final records = await history.listRecent();
      expect(records, hasLength(1));
      expect(records.single.providerId, ProviderId.bilibili);
      expect(records.single.roomId, '1000');
    },
  );
}

class _TestLocalStorageFileSystem extends LocalStorageFileSystem {
  _TestLocalStorageFileSystem();

  void Function(File source, String newPath)? onRename;
  void Function(File source, String newPath)? onCopy;
  void Function(File file)? onDelete;

  @override
  Future<File> rename(File file, String newPath) async {
    onRename?.call(file, newPath);
    return super.rename(file, newPath);
  }

  @override
  Future<File> copy(File file, String newPath) async {
    onCopy?.call(file, newPath);
    return super.copy(file, newPath);
  }

  @override
  Future<void> delete(File file) async {
    onDelete?.call(file);
    return super.delete(file);
  }
}
