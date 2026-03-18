import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_storage/live_storage.dart';
import 'package:nolive_app/src/app/bootstrap/bootstrap.dart';
import 'package:nolive_app/src/features/library/application/load_follow_watchlist_use_case.dart';

void main() {
  test('follow transfer imports legacy-compatible follow json and creates tags',
      () async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);

    final payload = jsonEncode([
      {
        'id': 'bilibili_1',
        'roomId': '1',
        'siteId': 'bilibili',
        'userName': '主播A',
        'face': 'https://example.com/avatar-a.png',
        'title': '标题A',
        'areaName': '分区A',
        'coverUrl': 'https://example.com/cover-a.png',
        'keyframeUrl': 'https://example.com/keyframe-a.png',
        'addTime': '2026-03-13T00:00:00.000',
        'watchDuration': '00:00:00',
        'tag': '夜班',
      },
      {
        'id': 'douyu_2',
        'roomId': '2',
        'siteId': 'douyu',
        'userName': '主播B',
        'face': '',
        'addTime': '2026-03-13T00:00:00.000',
        'watchDuration': '00:00:00',
        'tag': '全部',
      },
    ]);

    final initialRevision = bootstrap.followDataRevision.value;
    bootstrap.followWatchlistSnapshot.value = const FollowWatchlist(
      entries: [],
    );
    final summary = await bootstrap.importFollowListJson(payload);
    final snapshot = await bootstrap.listLibrarySnapshot();
    final tags = await bootstrap.listTags();

    expect(summary.importedCount, 2);
    expect(summary.createdCount, 2);
    expect(summary.updatedCount, 0);
    expect(summary.createdTagCount, 1);
    expect(summary.totalCount, 2);
    expect(snapshot.follows, hasLength(2));
    final bilibiliFollow = snapshot.follows.firstWhere(
      (record) => record.providerId == 'bilibili' && record.roomId == '1',
    );
    expect(bilibiliFollow.streamerName, '主播A');
    expect(
      bilibiliFollow.streamerAvatarUrl,
      'https://example.com/avatar-a.png',
    );
    expect(bilibiliFollow.lastTitle, '标题A');
    expect(bilibiliFollow.lastAreaName, '分区A');
    expect(
      bilibiliFollow.lastCoverUrl,
      'https://example.com/cover-a.png',
    );
    expect(
      bilibiliFollow.lastKeyframeUrl,
      'https://example.com/keyframe-a.png',
    );
    expect(bilibiliFollow.tags, ['夜班']);
    expect(tags, contains('夜班'));
    expect(bootstrap.followWatchlistSnapshot.value, isNull);
    expect(bootstrap.followDataRevision.value, initialRevision + 1);
  });

  test('follow transfer exports current follows in legacy-compatible shape',
      () async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    await bootstrap.followRepository.upsert(
      const FollowRecord(
        providerId: 'huya',
        roomId: '9527',
        streamerName: '虎牙主播',
        streamerAvatarUrl: 'https://example.com/huya-avatar.png',
        lastTitle: '虎牙标题',
        lastAreaName: '赛事',
        lastCoverUrl: 'https://example.com/huya-cover.png',
        lastKeyframeUrl: 'https://example.com/huya-keyframe.png',
        tags: ['比赛'],
      ),
    );

    final payload = await bootstrap.exportFollowListJson();
    final decoded = jsonDecode(payload) as List<dynamic>;
    final first = decoded.single as Map<String, dynamic>;

    expect(first['siteId'], 'huya');
    expect(first['roomId'], '9527');
    expect(first['userName'], '虎牙主播');
    expect(first['face'], 'https://example.com/huya-avatar.png');
    expect(first['title'], '虎牙标题');
    expect(first['areaName'], '赛事');
    expect(first['coverUrl'], 'https://example.com/huya-cover.png');
    expect(
      first['keyframeUrl'],
      'https://example.com/huya-keyframe.png',
    );
    expect(first['tag'], '比赛');
    expect(first['tags'], ['比赛']);
  });
}
