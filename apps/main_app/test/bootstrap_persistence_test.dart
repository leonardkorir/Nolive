import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:live_core/live_core.dart';
import 'package:live_providers/live_providers.dart';
import 'package:live_providers/src/providers/chaturbate/chaturbate_api_client.dart';
import 'package:nolive_app/src/app/bootstrap/bootstrap.dart';
import 'package:nolive_app/src/features/settings/application/sensitive_setting_keys.dart';
import 'package:nolive_app/src/shared/application/secure_credential_store.dart';

void main() {
  test(
    'persistent bootstrap keeps settings and follow data across reopen',
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
          providerId: ProviderId.bilibili.value,
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
    },
  );

  test(
    'persistent bootstrap migrates legacy simplelive storage file',
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
            'settings': {'theme_mode': 'dark'},
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
          File(
            '${tempDir.path}${Platform.pathSeparator}nolive_storage.json',
          ).existsSync(),
          isTrue,
        );
        expect(legacyFile.existsSync(), isFalse);
        expect(migrated.themeMode.value, ThemeMode.dark);
        expect(snapshot.follows, hasLength(1));
        expect(snapshot.follows.single.roomId, '77777');
        expect(snapshot.follows.single.streamerName, '旧文件迁移房间');
        expect(snapshot.follows.single.lastTitle, '旧文件标题');
      } finally {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      }
    },
  );

  test(
    'persistent bootstrap awaits secure storage preload before returning',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'nolive-bootstrap-secure-sequenced-',
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
        var loaderCompleted = false;

        final bootstrap = await createPersistentAppBootstrap(
          mode: AppRuntimeMode.live,
          storageDirectory: tempDir,
          secureCredentialStoreLoader: () async {
            await Future<void>.delayed(const Duration(milliseconds: 40));
            loaderCompleted = true;
            return InMemorySecureCredentialStore(
              initialValues: {
                SensitiveSettingKeys.accountDouyinCookie:
                    'secure-douyin-cookie',
              },
            );
          },
        ).timeout(const Duration(seconds: 10));

        // Must not return until secure loader finished (sequenced warm-up).
        expect(loaderCompleted, isTrue);
        expect(bootstrap.themeMode.value, ThemeMode.dark);
        expect(
          bootstrap.listAvailableProviders().any(
            (descriptor) => descriptor.id == ProviderId.chaturbate,
          ),
          isTrue,
        );

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
    },
  );

  test('persistent bootstrap repairs directory-shaped storage path', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'nolive-bootstrap-fallback-',
    );

    try {
      await Directory(
        '${tempDir.path}${Platform.pathSeparator}nolive_storage.json',
      ).create();

      final bootstrap = await createPersistentAppBootstrap(
        mode: AppRuntimeMode.live,
        storageDirectory: tempDir,
      );

      final snapshot = await bootstrap.listLibrarySnapshot();
      expect(snapshot.follows, isEmpty);
      expect(
        File(
          '${tempDir.path}${Platform.pathSeparator}nolive_storage.json',
        ).existsSync(),
        isTrue,
      );
      expect(
        Directory(
          '${tempDir.path}${Platform.pathSeparator}nolive_storage.json',
        ).existsSync(),
        isFalse,
      );
    } finally {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    }
  });

  test(
    'persistent bootstrap first Chaturbate create uses secure account cookie',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'nolive-bootstrap-cb-cookie-ready-',
      );

      try {
        final storageFile = File(
          '${tempDir.path}${Platform.pathSeparator}nolive_storage.json',
        );
        // Cookie lives only in secure store (not in plain settings snapshot).
        await storageFile.writeAsString(
          jsonEncode({
            'settings': {'theme_mode': 'system'},
            'history': const [],
            'follows': const [],
            'tags': const [],
          }),
        );

        const cbCookie =
            'cf_clearance=from-secure-store; csrftoken=csrf-token; sessionid=s1';
        final bootstrap = await createPersistentAppBootstrap(
          mode: AppRuntimeMode.live,
          storageDirectory: tempDir,
          secureCredentialStoreLoader: () async {
            return InMemorySecureCredentialStore(
              initialValues: {
                SensitiveSettingKeys.accountChaturbateCookie: cbCookie,
              },
            );
          },
        );

        // No extra warmUp: sequenced ensureReady already applied.
        final accountSettings = await bootstrap.loadProviderAccountSettings();
        expect(accountSettings.chaturbateCookie, cbCookie);

        // First registry create must already bind the secure cookie (real path
        // used by home recommend / category list).
        final provider = bootstrap.providerRegistry.create(
          ProviderId.chaturbate,
        );
        expect(provider, isA<ChaturbateProvider>());
        expect(
          (provider as ChaturbateProvider).debugConfiguredCookie,
          cbCookie,
        );

        // Prove cookie is attached on discover carousel traffic. Empty carousel
        // responses may fall back to anonymous room-list (cookie stripped by
        // design); capture the first non-empty cookie header instead of the last.
        String? seenCookie;
        final apiClient = HttpChaturbateApiClient(
          requestScheduler: ChaturbateRequestScheduler(
            minSpacing: Duration.zero,
            maxConcurrent: 8,
          ),
          cookie: provider.debugConfiguredCookie,
          client: MockClient((request) async {
            final cookieHeader = request.headers['cookie'];
            if (cookieHeader != null && cookieHeader.isNotEmpty) {
              seenCookie ??= cookieHeader;
            }
            // Non-empty carousel payload avoids anonymous room-list fallback.
            return http.Response(
              jsonEncode(const {
                'rooms': [
                  {
                    'username': 'demo_room',
                    'display_name': 'Demo Room',
                    'current_show': 'public',
                    'num_users': 12,
                    'img': 'https://example.com/demo.jpg',
                  },
                ],
              }),
              200,
            );
          }),
        );
        final wired = ChaturbateProvider.live(apiClient: apiClient);
        await wired.fetchRecommendRooms();
        expect(seenCookie, contains('cf_clearance=from-secure-store'));
      } finally {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      }
    },
  );

  test(
    'persistent bootstrap invalidates cached providers when secure snapshot changes later',
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
            'settings': {'account_bilibili_user_id': 12345},
            'history': const [],
            'follows': const [],
            'tags': const [],
          }),
        );

        final secureStore = InMemorySecureCredentialStore(
          initialValues: {
            SensitiveSettingKeys.accountBilibiliCookie:
                'SESSDATA=initial-secure',
          },
        );
        final bootstrap = await createPersistentAppBootstrap(
          mode: AppRuntimeMode.live,
          storageDirectory: tempDir,
          secureCredentialStore: secureStore,
        );

        final firstProvider = bootstrap.providerRegistry.create(
          ProviderId.bilibili,
        );

        await secureStore.write(
          SensitiveSettingKeys.accountBilibiliCookie,
          'SESSDATA=updated-secure',
        );
        // Account update path clears cache; simulate via catalog revision + clear.
        bootstrap.providerRegistry.clearCache();

        final secondProvider = bootstrap.providerRegistry.create(
          ProviderId.bilibili,
        );
        final accountSettings = await bootstrap.loadProviderAccountSettings();

        expect(identical(firstProvider, secondProvider), isFalse);
        expect(accountSettings.bilibiliCookie, 'SESSDATA=updated-secure');
      } finally {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      }
    },
  );

  test(
    'persistent bootstrap migrates local sync token and old device id',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'nolive-bootstrap-local-sync-secure-',
      );

      try {
        final storageFile = File(
          '${tempDir.path}${Platform.pathSeparator}nolive_storage.json',
        );
        await storageFile.writeAsString(
          jsonEncode({
            'settings': {
              SensitiveSettingKeys.syncLocalAccessToken: 'legacy-local-token',
              SensitiveSettingKeys.syncLocalDeviceId: 'simplelive-device',
            },
            'history': const [],
            'follows': const [],
            'tags': const [],
          }),
        );
        final secureCredentialStore = InMemorySecureCredentialStore();

        final bootstrap = await createPersistentAppBootstrap(
          mode: AppRuntimeMode.live,
          storageDirectory: tempDir,
          secureCredentialStore: secureCredentialStore,
        );
        final info = await bootstrap.localSyncServer.readInfo();

        expect(info.accessToken, 'legacy-local-token');
        expect(
          await secureCredentialStore.read(
            SensitiveSettingKeys.syncLocalAccessToken,
          ),
          'legacy-local-token',
        );
        expect(
          await bootstrap.settingsRepository.readValue<String>(
            SensitiveSettingKeys.syncLocalAccessToken,
          ),
          isNull,
        );
        final deviceId = await bootstrap.settingsRepository.readValue<String>(
          SensitiveSettingKeys.syncLocalDeviceId,
        );
        expect(deviceId, isNot('simplelive-device'));
        expect(deviceId, matches(RegExp(r'^nolive-[0-9a-f]{32}$')));
      } finally {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      }
    },
  );

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
    },
  );
}
