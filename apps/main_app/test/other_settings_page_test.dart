import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_providers/live_providers.dart';
import 'package:nolive_app/src/app/bootstrap/bootstrap.dart';
import 'package:nolive_app/src/app/bootstrap/default_state.dart';
import 'package:nolive_app/src/features/settings/presentation/other_settings_page.dart';

class _FakeBilibiliAccountClient implements BilibiliAccountClient {
  @override
  Future<BilibiliQrLoginSession> createQrLoginSession() async {
    return const BilibiliQrLoginSession(
      qrcodeKey: 'preview-key',
      qrcodeUrl: 'https://example.com/qr-login',
    );
  }

  @override
  Future<BilibiliAccountProfile> loadProfile({required String cookie}) async {
    return const BilibiliAccountProfile(
      userId: 10086,
      displayName: 'preview-user',
      avatarUrl: 'https://example.com/avatar.png',
    );
  }

  @override
  Future<BilibiliQrLoginPollResult> pollQrLogin({
    required String qrcodeKey,
  }) async {
    return const BilibiliQrLoginPollResult(
      status: BilibiliQrLoginStatus.pending,
    );
  }
}

class _FakeDouyinAccountClient implements DouyinAccountClient {
  @override
  Future<DouyinAccountProfile> loadProfile({required String cookie}) async {
    return const DouyinAccountProfile(
      displayName: 'preview-douyin',
      secUid: 'sec-preview',
      avatarUrl: 'https://example.com/avatar.png',
    );
  }
}

void main() {
  testWidgets('other settings page imports and resets snapshot data', (
    tester,
  ) async {
    final bootstrap = createAppBootstrap(
      mode: AppRuntimeMode.preview,
      bilibiliAccountClient: _FakeBilibiliAccountClient(),
      douyinAccountClient: _FakeDouyinAccountClient(),
    );
    await bootstrap.updateThemeMode(ThemeMode.dark);
    await bootstrap.toggleFollowRoom(
      providerId: 'bilibili',
      roomId: '6',
      streamerName: '系统演示主播',
      title: '系统演示标题',
      areaName: '演示分区',
      coverUrl: 'https://example.com/demo-cover.png',
      keyframeUrl: 'https://example.com/demo-keyframe.png',
    );
    final exported = await bootstrap.exportSyncSnapshotJson();

    await tester.pumpWidget(
      MaterialApp(
        home: OtherSettingsPage(bootstrap: bootstrap),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('其他设置'), findsWidgets);
    expect(find.text('导出配置文件'), findsOneWidget);
    expect(find.text('导入配置文件'), findsOneWidget);
    expect(find.text('导入快照'), findsOneWidget);
    expect(find.text('恢复默认'), findsOneWidget);
    expect(find.text('运行模式'), findsNothing);
    expect(find.text('播放器后端'), findsNothing);
    expect(find.text('可用平台数量'), findsNothing);

    await tester.tap(find.text('导入快照'));
    await tester.pumpAndSettle();
    expect(find.text('导入快照 JSON'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, exported);
    await tester.tap(find.text('导入'));
    await tester.pumpAndSettle();
    expect(find.textContaining('已导入：设置'), findsOneWidget);

    await tester.tap(find.text('恢复默认'));
    await tester.pumpAndSettle();
    expect(find.text('重置本地数据'), findsOneWidget);
    await tester.tap(find.text('确认重置'));
    await tester.pumpAndSettle();

    final snapshot = await bootstrap.loadSyncSnapshot();
    expect(snapshot.follows, isEmpty);
    expect(snapshot.tags, ['常看', '收藏']);
    expect(snapshot.blockedKeywords, kDefaultBlockedKeywords);
  });

  testWidgets('other settings page imports legacy-compatible config json', (
    tester,
  ) async {
    final bootstrap = createAppBootstrap(
      mode: AppRuntimeMode.preview,
      bilibiliAccountClient: _FakeBilibiliAccountClient(),
      douyinAccountClient: _FakeDouyinAccountClient(),
    );
    await bootstrap.toggleFollowRoom(
      providerId: 'bilibili',
      roomId: '6',
      streamerName: '旧主播',
      title: '旧标题',
      areaName: '旧分区',
      coverUrl: 'https://example.com/old-cover.png',
      keyframeUrl: 'https://example.com/old-keyframe.png',
    );
    await bootstrap.createTag('旧标签');

    final legacyJson = jsonEncode({
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

    await tester.pumpWidget(
      MaterialApp(
        home: OtherSettingsPage(bootstrap: bootstrap),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('导入快照'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, legacyJson);
    await tester.tap(find.text('导入'));
    await tester.pumpAndSettle();

    expect(find.textContaining('已导入：设置'), findsOneWidget);

    final snapshot = await bootstrap.loadSyncSnapshot();
    expect(snapshot.settings['theme_mode'], 'dark');
    expect(snapshot.settings['player_auto_play'], isFalse);
    expect(snapshot.follows.single.roomId, '6');
    expect(snapshot.follows.single.lastTitle, '旧标题');
    expect(snapshot.follows.single.lastAreaName, '旧分区');
    expect(snapshot.follows.single.lastCoverUrl,
        'https://example.com/old-cover.png');
    expect(
      snapshot.follows.single.lastKeyframeUrl,
      'https://example.com/old-keyframe.png',
    );
    expect(snapshot.tags, contains('旧标签'));
    expect(snapshot.blockedKeywords, unorderedEquals(['剧透', '广告']));
    expect(bootstrap.themeMode.value, ThemeMode.dark);
    expect(find.text('运行模式'), findsNothing);
  });
}
