import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nolive_app/src/app/bootstrap/bootstrap.dart';
import 'package:nolive_app/src/shared/application/secure_credential_store.dart';

void main() {
  test('persistent bootstrap keeps settings and follow data across reopen',
      () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'nolive-bootstrap-persistence-',
    );

    try {
      final secureCredentialStore = InMemorySecureCredentialStore();
      final first = await createPersistentAppBootstrap(
        mode: AppRuntimeMode.live,
        storageDirectory: tempDir,
        secureCredentialStore: secureCredentialStore,
      );
      await first.updateThemeMode(ThemeMode.dark);
      await first.toggleFollowRoom(
        providerId: 'bilibili',
        roomId: '66666',
        streamerName: '架构迁移验证房间',
        streamerAvatarUrl: 'https://example.com/persisted-avatar.png',
        title: '持久化标题',
        areaName: '持久化分区',
        coverUrl: 'https://example.com/persisted-cover.png',
        keyframeUrl: 'https://example.com/persisted-keyframe.png',
      );

      final reopened = await createPersistentAppBootstrap(
        mode: AppRuntimeMode.live,
        storageDirectory: tempDir,
        secureCredentialStore: secureCredentialStore,
      );
      final snapshot = await reopened.listLibrarySnapshot();
      final tags = await reopened.listTags();

      expect(reopened.themeMode.value, ThemeMode.dark);
      expect(snapshot.follows, hasLength(1));
      expect(snapshot.follows.single.roomId, '66666');
      expect(
        snapshot.follows.single.streamerAvatarUrl,
        'https://example.com/persisted-avatar.png',
      );
      expect(snapshot.follows.single.lastTitle, '持久化标题');
      expect(snapshot.follows.single.lastAreaName, '持久化分区');
      expect(
        snapshot.follows.single.lastCoverUrl,
        'https://example.com/persisted-cover.png',
      );
      expect(
        snapshot.follows.single.lastKeyframeUrl,
        'https://example.com/persisted-keyframe.png',
      );
      expect(tags, containsAll(['常看', '收藏']));
    } finally {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    }
  });

  test('persistent bootstrap migrates legacy simplelive storage file',
      () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'nolive-bootstrap-migration-',
    );

    try {
      final secureCredentialStore = InMemorySecureCredentialStore();
      final legacyFile = File(
        '${tempDir.path}${Platform.pathSeparator}simplelive_storage.json',
      );
      await legacyFile.writeAsString(
        jsonEncode({
          'settings': {
            'theme_mode': 'dark',
          },
          'follows': [
            {
              'provider_id': 'bilibili',
              'room_id': '77777',
              'streamer_name': '旧文件迁移房间',
              'streamer_avatar_url': 'https://example.com/legacy-avatar.png',
              'last_title': '旧文件标题',
              'last_area_name': '旧文件分区',
              'last_cover_url': 'https://example.com/legacy-cover.png',
              'last_keyframe_url': 'https://example.com/legacy-keyframe.png',
              'tags': ['常看'],
            },
          ],
          'tags': ['常看', '收藏'],
        }),
      );

      final migrated = await createPersistentAppBootstrap(
        mode: AppRuntimeMode.live,
        storageDirectory: tempDir,
        secureCredentialStore: secureCredentialStore,
      );
      final snapshot = await migrated.listLibrarySnapshot();

      expect(
        File('${tempDir.path}${Platform.pathSeparator}nolive_storage.json')
            .existsSync(),
        isTrue,
      );
      expect(legacyFile.existsSync(), isFalse);
      expect(migrated.themeMode.value, ThemeMode.dark);
      expect(snapshot.follows, hasLength(1));
      expect(snapshot.follows.single.roomId, '77777');
      expect(snapshot.follows.single.streamerName, '旧文件迁移房间');
      expect(
        snapshot.follows.single.lastTitle,
        '旧文件标题',
      );
    } finally {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    }
  });
}
