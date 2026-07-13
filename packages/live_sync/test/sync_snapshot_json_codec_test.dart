import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:live_storage/live_storage.dart';
import 'package:live_sync/live_sync.dart';
import 'package:test/test.dart';

void main() {
  test('sync snapshot json codec round-trips snapshot state', () {
    final snapshot = SyncSnapshot(
      settings: const {'theme_mode': 'dark', 'player_auto_play': true},
      blockedKeywords: const ['剧透'],
      tags: const ['常看'],
      history: [
        HistoryRecord(
          providerId: ProviderId.bilibili,
          roomId: '100',
          title: '测试房间',
          streamerName: '主播A',
          viewedAt: DateTime(2026, 3, 10, 20),
        ),
      ],
      follows: const [
        FollowRecord(
          providerId: ProviderId.douyu,
          roomId: '200',
          streamerName: '主播B',
          streamerAvatarUrl: 'https://example.com/avatar-b.png',
          lastTitle: '同步标题',
          lastAreaName: '同步分区',
          lastCoverUrl: 'https://example.com/cover-b.png',
          lastKeyframeUrl: 'https://example.com/keyframe-b.png',
          tags: ['常看'],
        ),
      ],
    );

    final encoded = SyncSnapshotJsonCodec.encode(snapshot);
    final encodedJson = jsonDecode(encoded) as Map<String, dynamic>;
    final decoded = SyncSnapshotJsonCodec.decode(encoded);

    expect(
      encodedJson['format_version'],
      SyncSnapshotJsonCodec.currentFormatVersion,
    );
    expect(decoded.settings['theme_mode'], 'dark');
    expect(decoded.settings['player_auto_play'], isTrue);
    expect(decoded.blockedKeywords, ['剧透']);
    expect(decoded.tags, ['常看']);
    expect(decoded.history.single.roomId, '100');
    expect(decoded.follows.single.roomId, '200');
    expect(
      decoded.follows.single.streamerAvatarUrl,
      'https://example.com/avatar-b.png',
    );
    expect(decoded.follows.single.lastTitle, '同步标题');
    expect(decoded.follows.single.lastAreaName, '同步分区');
    expect(
      decoded.follows.single.lastCoverUrl,
      'https://example.com/cover-b.png',
    );
    expect(
      decoded.follows.single.lastKeyframeUrl,
      'https://example.com/keyframe-b.png',
    );
  });

  test('sync snapshot json codec rejects unrelated object payload', () {
    expect(
      () => SyncSnapshotJsonCodec.decode('{"type":"simple_live","config":{}}'),
      throwsA(isA<FormatException>()),
    );
  });

  test(
    'sync snapshot json codec accepts legacy payload without format version',
    () {
      final decoded = SyncSnapshotJsonCodec.decode(
        '{"settings":{"theme_mode":"dark"},"blocked_keywords":["剧透"],"tags":["常看"],"history":[],"follows":[]}',
      );

      expect(decoded.settings['theme_mode'], 'dark');
      expect(decoded.blockedKeywords, ['剧透']);
      expect(decoded.tags, ['常看']);
    },
  );

  test('sync snapshot json codec rejects unsupported future format version', () {
    expect(
      () => SyncSnapshotJsonCodec.decode(
        '{"format_version":99,"settings":{},"blocked_keywords":[],"tags":[],"history":[],"follows":[]}',
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test(
    'sync snapshot json codec skips malformed history timestamps and parses valid ones',
    () {
      final decoded = SyncSnapshotJsonCodec.decode(
        '{"settings":{},"blocked_keywords":[],"tags":[],"history":[{"provider_id":"bilibili","room_id":"100","title":"坏记录","streamer_name":"主播","viewed_at":"not-a-date"},{"provider_id":"bilibili","room_id":"101","title":"好记录","streamer_name":"主播","viewed_at":"2026-03-10T20:00:00Z"}],"follows":[]}',
      );
      expect(decoded.history, hasLength(1));
      expect(decoded.history.first.roomId, '101');
      expect(decoded.history.first.title, '好记录');
    },
  );
}
