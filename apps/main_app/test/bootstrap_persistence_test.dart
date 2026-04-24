import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:nolive_app/src/app/bootstrap/bootstrap.dart';
import 'package:nolive_app/src/features/settings/application/sensitive_setting_keys.dart';
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

  test(
      'persistent bootstrap returns before deferred secure storage preload completes',
      () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'nolive-bootstrap-secure-deferred-',
    );

    try {
      final storageFile = File(
        '${tempDir.path}${Platform.pathSeparator}nolive_storage.json',
      );
      await storageFile.writeAsString(
        jsonEncode({
          'settings': {
            'theme_mode': 'dark',
            'account_chaturbate_cookie': 'cf_clearance=legacy-cookie',
            'account_douyin_cookie': 'legacy-douyin-cookie',
          },
          'history': const [],
          'follows': const [],
          'tags': const [],
        }),
      );
      final loaderCompleter = Completer<SecureCredentialStore>();

      final bootstrap = await createPersistentAppBootstrap(
        mode: AppRuntimeMode.live,
        storageDirectory: tempDir,
        secureCredentialStoreLoader: () => loaderCompleter.future,
      ).timeout(const Duration(seconds: 10));

      expect(bootstrap.themeMode.value, ThemeMode.dark);
      expect(
        bootstrap
            .listAvailableProviders()
            .any((descriptor) => descriptor.id == ProviderId.chaturbate),
        isTrue,
      );

      loaderCompleter.complete(
        InMemorySecureCredentialStore(
          initialValues: {
            SensitiveSettingKeys.accountDouyinCookie: 'secure-douyin-cookie',
          },
        ),
      );
      await bootstrap.warmUpSecureCredentialStore();

      final accountSettings = await bootstrap.loadProviderAccountSettings();
      expect(accountSettings.douyinCookie, 'secure-douyin-cookie');
      expect(
        await bootstrap.settingsRepository.readValue<String>(
          SensitiveSettingKeys.accountDouyinCookie,
        ),
        isNull,
      );
    } finally {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    }
  });

  test(
      'persistent bootstrap invalidates cached providers after secure credential preload changes snapshot',
      () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'nolive-bootstrap-provider-cache-refresh-',
    );

    try {
      final storageFile = File(
        '${tempDir.path}${Platform.pathSeparator}nolive_storage.json',
      );
      await storageFile.writeAsString(
        jsonEncode({
          'settings': {
            'account_bilibili_cookie': 'SESSDATA=legacy-cookie',
            'account_bilibili_user_id': 12345,
          },
          'history': const [],
          'follows': const [],
          'tags': const [],
        }),
      );
      final loaderCompleter = Completer<SecureCredentialStore>();

      final bootstrap = await createPersistentAppBootstrap(
        mode: AppRuntimeMode.live,
        storageDirectory: tempDir,
        secureCredentialStoreLoader: () => loaderCompleter.future,
      );

      final firstProvider =
          bootstrap.providerRegistry.create(ProviderId.bilibili);

      loaderCompleter.complete(
        InMemorySecureCredentialStore(
          initialValues: {
            SensitiveSettingKeys.accountBilibiliCookie:
                'SESSDATA=secure-cookie',
          },
        ),
      );
      await bootstrap.warmUpSecureCredentialStore();

      final secondProvider =
          bootstrap.providerRegistry.create(ProviderId.bilibili);
      final accountSettings = await bootstrap.loadProviderAccountSettings();

      expect(identical(firstProvider, secondProvider), isFalse);
      expect(accountSettings.bilibiliCookie, 'SESSDATA=secure-cookie');
      expect(
        await bootstrap.settingsRepository.readValue<String>(
          SensitiveSettingKeys.accountBilibiliCookie,
        ),
        isNull,
      );
    } finally {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    }
  });

  test(
      'persistent bootstrap falls back to legacy settings when secure storage is unavailable',
      () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'nolive-bootstrap-secure-fallback-',
    );

    try {
      final storageFile = File(
        '${tempDir.path}${Platform.pathSeparator}nolive_storage.json',
      );
      await storageFile.writeAsString(
        jsonEncode({
          'settings': {
            'theme_mode': 'dark',
            'sync_webdav_password': 'legacy-webdav-password',
            'account_douyin_cookie': 'legacy-douyin-cookie',
          },
          'history': const [],
          'follows': const [],
          'tags': const [],
        }),
      );

      final bootstrap = await createPersistentAppBootstrap(
        mode: AppRuntimeMode.live,
        storageDirectory: tempDir,
        secureCredentialStoreLoader: () async {
          throw const SecureCredentialStoreUnavailableException(
            'simulated keystore failure',
          );
        },
      );
      final syncPreferences = await bootstrap.loadSyncPreferences();
      final accountSettings = await bootstrap.loadProviderAccountSettings();

      expect(bootstrap.themeMode.value, ThemeMode.dark);
      expect(syncPreferences.webDavPassword, 'legacy-webdav-password');
      expect(accountSettings.douyinCookie, 'legacy-douyin-cookie');
      expect(
        await bootstrap.settingsRepository.readValue<String>(
          'sync_webdav_password',
        ),
        'legacy-webdav-password',
      );
      expect(
        await bootstrap.settingsRepository.readValue<String>(
          'account_douyin_cookie',
        ),
        'legacy-douyin-cookie',
      );
    } finally {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    }
  });
}
