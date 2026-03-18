import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_storage/live_storage.dart';
import 'package:nolive_app/src/features/settings/application/manage_follow_preferences_use_case.dart';
import 'package:nolive_app/src/app/bootstrap/bootstrap.dart';
import 'package:nolive_app/src/features/library/application/load_follow_watchlist_use_case.dart';

void main() {
  test('snapshot management exports imports and resets app state', () async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);

    await bootstrap.updateThemeMode(ThemeMode.dark);
    await bootstrap.addBlockedKeyword('广告');
    await bootstrap.createTag('夜班');
    await bootstrap.toggleFollowRoom(
      providerId: 'bilibili',
      roomId: '1',
      streamerName: '主播A',
      title: '本地标题',
      areaName: '本地分区',
      coverUrl: 'https://example.com/cover-a.png',
      keyframeUrl: 'https://example.com/keyframe-a.png',
    );

    final exported = await bootstrap.exportSyncSnapshotJson();
    bootstrap.followWatchlistSnapshot.value = const FollowWatchlist(
      entries: [],
    );
    final revisionBeforeReset = bootstrap.followDataRevision.value;

    await bootstrap.resetAppData();
    final resetSnapshot = await bootstrap.loadSyncSnapshot();
    expect(resetSnapshot.follows, isEmpty);
    expect(resetSnapshot.tags, ['常看', '收藏']);
    expect(resetSnapshot.blockedKeywords, ['剧透']);
    expect(bootstrap.followWatchlistSnapshot.value?.entries, isEmpty);
    expect(bootstrap.followDataRevision.value, revisionBeforeReset + 1);

    final revisionBeforeImport = bootstrap.followDataRevision.value;
    await bootstrap.importSyncSnapshotJson(exported);
    final importedSnapshot = await bootstrap.loadSyncSnapshot();
    expect(importedSnapshot.settings['theme_mode'], 'dark');
    expect(importedSnapshot.follows.single.roomId, '1');
    expect(importedSnapshot.follows.single.lastTitle, '本地标题');
    expect(importedSnapshot.follows.single.lastAreaName, '本地分区');
    expect(
      importedSnapshot.follows.single.lastCoverUrl,
      'https://example.com/cover-a.png',
    );
    expect(
      importedSnapshot.follows.single.lastKeyframeUrl,
      'https://example.com/keyframe-a.png',
    );
    expect(importedSnapshot.tags, contains('夜班'));
    expect(importedSnapshot.blockedKeywords, contains('广告'));
    expect(bootstrap.themeMode.value, ThemeMode.dark);
    expect(bootstrap.followWatchlistSnapshot.value, isNull);
    expect(bootstrap.followDataRevision.value, revisionBeforeImport + 1);
  });

  test('snapshot management imports legacy-compatible config export', () async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);

    await bootstrap.addBlockedKeyword('旧屏蔽');
    await bootstrap.toggleFollowRoom(
      providerId: 'bilibili',
      roomId: '1',
      streamerName: '旧关注',
    );
    await bootstrap.createTag('旧标签');

    final exported = jsonEncode({
      'type': 'simple_live',
      'platform': 'android',
      'version': 1,
      'time': 1234567890,
      'config': {
        'theme_mode': 'dark',
        'player_auto_play': false,
      },
      'shield': {
        '剧透': '剧透',
        '广告': '广告',
      },
    });

    await bootstrap.importSyncSnapshotJson(exported);
    final importedSnapshot = await bootstrap.loadSyncSnapshot();

    expect(importedSnapshot.settings['theme_mode'], 'dark');
    expect(importedSnapshot.settings['player_auto_play'], isFalse);
    expect(importedSnapshot.follows.single.roomId, '1');
    expect(importedSnapshot.history, isEmpty);
    expect(importedSnapshot.tags, contains('旧标签'));
    expect(
      importedSnapshot.blockedKeywords,
      unorderedEquals(['剧透', '广告']),
    );
    expect(bootstrap.themeMode.value, ThemeMode.dark);
    expect(bootstrap.followWatchlistSnapshot.value, isNull);
  });

  test('snapshot management maps legacy config keys to current settings',
      () async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);

    final exported = jsonEncode({
      'type': 'simple_live',
      'platform': 'android',
      'version': 1,
      'time': 1773384011720,
      'config': {
        'ThemeMode': 2,
        'AutoUpdateFollowDuration': 30,
        'BilibiliCookie': 'SESSDATA=demo;bili_jct=test;',
        'ChaturbateCookie': 'cf_clearance=demo-clearance; __cf_bm=demo-bm',
        'DouyinCookie': 'douyin-session-demo',
        'FollowStyleNotGrid': true,
        'ChatBubbleStyle': true,
        'DanmuArea': 0.4,
        'DanmuEnable': true,
        'DanmuSpeed': 20.0,
        'HomeSort': 'follow,recommend,category,user',
        'SiteSort': ['douyin', 'chaturbate', 'douyu'],
        'PlayerCompatMode': true,
        'PlayerForceHttps': true,
        'QualityLevel': 2,
        'QualityLevelCellular': 2,
        'VideoHardwareDecoder': 'mediacodec',
        'WebDAVUri': 'https://dav.jianguoyun.com/dav/',
        'WebDAVUser': 'demo-user@example.com',
        'kWebDAVPassword': 'demo-webdav-password',
      },
      'shield': {
        '人气': '人气',
        '关注': '关注',
      },
    });

    await bootstrap.importSyncSnapshotJson(exported);

    final snapshot = await bootstrap.loadSyncSnapshot();
    expect(snapshot.settings['account_bilibili_cookie'],
        'SESSDATA=demo;bili_jct=test;');
    expect(snapshot.settings['account_chaturbate_cookie'],
        'cf_clearance=demo-clearance; __cf_bm=demo-bm');
    expect(snapshot.settings['account_douyin_cookie'], 'douyin-session-demo');
    expect(snapshot.settings['theme_mode'], 'dark');
    expect(snapshot.blockedKeywords, unorderedEquals(['人气', '关注']));

    final accountSettings = await bootstrap.loadProviderAccountSettings();
    expect(accountSettings.bilibiliCookie, 'SESSDATA=demo;bili_jct=test;');
    expect(accountSettings.chaturbateCookie,
        'cf_clearance=demo-clearance; __cf_bm=demo-bm');
    expect(accountSettings.douyinCookie, 'douyin-session-demo');

    final playerPreferences = await bootstrap.loadPlayerPreferences();
    expect(playerPreferences.preferHighestQuality, isTrue);
    expect(playerPreferences.mpvCompatModeEnabled, isTrue);
    expect(playerPreferences.forceHttpsEnabled, isTrue);
    expect(playerPreferences.mpvHardwareAccelerationEnabled, isTrue);

    final danmakuPreferences = await bootstrap.loadDanmakuPreferences();
    expect(danmakuPreferences.enabledByDefault, isTrue);
    expect(danmakuPreferences.area, 0.4);
    expect(danmakuPreferences.speed, 20.0);

    final roomUiPreferences = await bootstrap.loadRoomUiPreferences();
    expect(roomUiPreferences.chatBubbleStyle, isTrue);

    final syncPreferences = await bootstrap.loadSyncPreferences();
    expect(syncPreferences.webDavBaseUrl, 'https://dav.jianguoyun.com/dav/');
    expect(syncPreferences.webDavUsername, 'demo-user@example.com');
    expect(syncPreferences.webDavPassword, 'demo-webdav-password');

    final layoutPreferences = await bootstrap.loadLayoutPreferences();
    expect(
      layoutPreferences.shellTabOrder.map((item) => item.name).toList(),
      ['library', 'home', 'browse', 'profile'],
    );
    expect(
      layoutPreferences.providerOrder.take(3).toList(),
      ['douyin', 'chaturbate', 'douyu'],
    );

    final followPreferences = await bootstrap.loadFollowPreferences();
    expect(followPreferences.autoRefreshEnabled, isTrue);
    expect(followPreferences.autoRefreshIntervalMinutes, 30);
    expect(
      followPreferences.displayMode,
      FollowDisplayModePreference.list,
    );
    expect(snapshot.settings['follow_auto_refresh_interval_minutes'], 30);
    expect(snapshot.settings['follow_display_mode'], 'list');
    expect(bootstrap.themeMode.value, ThemeMode.dark);
  });

  test(
      'legacy-compatible config import keeps follow snapshot and follow revision unchanged',
      () async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    bootstrap.followWatchlistSnapshot.value = FollowWatchlist(
      entries: const [
        FollowWatchEntry(
          record: FollowRecord(
            providerId: 'bilibili',
            roomId: '1',
            streamerName: '旧关注',
          ),
        ),
      ],
    );
    final initialRevision = bootstrap.followDataRevision.value;

    final payload = jsonEncode({
      'type': 'simple_live',
      'platform': 'android',
      'version': 1,
      'time': 1234567890,
      'config': {
        'theme_mode': 'dark',
      },
      'shield': {
        '广告': '广告',
      },
    });

    await bootstrap.importSyncSnapshotJson(payload);

    expect(bootstrap.followWatchlistSnapshot.value, isNotNull);
    expect(
      bootstrap.followWatchlistSnapshot.value!.entries.single.record.roomId,
      '1',
    );
    expect(bootstrap.followDataRevision.value, initialRevision);
  });

  test('clear follows resets follow snapshot to empty and bumps revision',
      () async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    await bootstrap.toggleFollowRoom(
      providerId: 'bilibili',
      roomId: '1',
      streamerName: '主播A',
    );
    bootstrap.followWatchlistSnapshot.value = FollowWatchlist(
      entries: const [
        FollowWatchEntry(
          record: FollowRecord(
            providerId: 'bilibili',
            roomId: '1',
            streamerName: '主播A',
          ),
        ),
      ],
    );
    final initialRevision = bootstrap.followDataRevision.value;

    await bootstrap.clearFollows();

    expect(await bootstrap.followRepository.listAll(), isEmpty);
    expect(bootstrap.followWatchlistSnapshot.value?.entries, isEmpty);
    expect(bootstrap.followDataRevision.value, initialRevision + 1);
  });

  test(
      'legacy-compatible config export keeps legacy shape and roundtrips full snapshot sections',
      () async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    final viewedAt = DateTime.utc(2026, 3, 15, 8, 0, 0);

    await bootstrap.updateThemeMode(ThemeMode.dark);
    await bootstrap.addBlockedKeyword('广告');
    await bootstrap.createTag('夜班');
    await bootstrap.toggleFollowRoom(
      providerId: 'bilibili',
      roomId: '6',
      streamerName: '系统演示主播',
      title: '系统演示标题',
      areaName: '演示分区',
      coverUrl: 'https://example.com/demo-cover.png',
      keyframeUrl: 'https://example.com/demo-keyframe.png',
    );
    await bootstrap.historyRepository.add(
      HistoryRecord(
        providerId: 'bilibili',
        roomId: '6',
        title: '系统演示房间',
        streamerName: '系统演示主播',
        viewedAt: viewedAt,
      ),
    );

    final exported = await bootstrap.exportLegacyConfigJson();
    final decoded = jsonDecode(exported) as Map<String, dynamic>;

    expect(decoded['type'], 'simple_live');
    expect(decoded['config'], isA<Map>());
    expect(decoded['shield'], isA<Map>());
    expect((decoded['settings'] as Map<String, dynamic>)['theme_mode'], 'dark');
    expect(decoded['blocked_keywords'], contains('广告'));
    expect(decoded['tags'], contains('夜班'));
    expect((decoded['history'] as List<dynamic>).single,
        containsPair('room_id', '6'));
    expect((decoded['follows'] as List<dynamic>).single,
        containsPair('room_id', '6'));
    expect(
      (decoded['follows'] as List<dynamic>).single,
      containsPair('last_title', '系统演示标题'),
    );
    expect(
      (decoded['follows'] as List<dynamic>).single,
      containsPair('last_area_name', '演示分区'),
    );
    expect(
      (decoded['follows'] as List<dynamic>).single,
      containsPair('last_cover_url', 'https://example.com/demo-cover.png'),
    );
    expect(
      (decoded['follows'] as List<dynamic>).single,
      containsPair(
        'last_keyframe_url',
        'https://example.com/demo-keyframe.png',
      ),
    );

    final importedBootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    await importedBootstrap.importSyncSnapshotJson(exported);

    final importedSnapshot = await importedBootstrap.loadSyncSnapshot();
    expect(importedSnapshot.settings['theme_mode'], 'dark');
    expect(importedSnapshot.blockedKeywords, contains('广告'));
    expect(importedSnapshot.tags, contains('夜班'));
    expect(importedSnapshot.history.single.roomId, '6');
    expect(importedSnapshot.history.single.viewedAt, viewedAt);
    expect(importedSnapshot.follows.single.roomId, '6');
    expect(importedSnapshot.follows.single.lastTitle, '系统演示标题');
    expect(importedSnapshot.follows.single.lastAreaName, '演示分区');
    expect(
      importedSnapshot.follows.single.lastCoverUrl,
      'https://example.com/demo-cover.png',
    );
    expect(
      importedSnapshot.follows.single.lastKeyframeUrl,
      'https://example.com/demo-keyframe.png',
    );
  });
}
