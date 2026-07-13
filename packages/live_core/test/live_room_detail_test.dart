import 'package:live_core/live_core.dart';
import 'package:test/test.dart';

void main() {
  group('LiveRoomDetail Tests', () {
    test('value equality and hashCode', () {
      final startedAt = DateTime(2026, 5, 29);
      final detail1 = LiveRoomDetail(
        providerId: ProviderId.bilibili,
        roomId: '111',
        title: 'Title',
        streamerName: 'Streamer',
        streamerAvatarUrl: 'avatar',
        coverUrl: 'cover',
        keyframeUrl: 'keyframe',
        areaName: 'Area',
        description: 'Desc',
        sourceUrl: 'source',
        startedAt: startedAt,
        isLive: true,
        viewerCount: 500,
        danmakuToken: const PreviewDanmakuToken(),
        metadata: const {'key': 'value'},
      );

      final detail2 = LiveRoomDetail(
        providerId: ProviderId.bilibili,
        roomId: '111',
        title: 'Title',
        streamerName: 'Streamer',
        streamerAvatarUrl: 'avatar',
        coverUrl: 'cover',
        keyframeUrl: 'keyframe',
        areaName: 'Area',
        description: 'Desc',
        sourceUrl: 'source',
        startedAt: startedAt,
        isLive: true,
        viewerCount: 500,
        danmakuToken: const PreviewDanmakuToken(),
        metadata: const {'key': 'value'},
      );

      final detail3 = LiveRoomDetail(
        providerId: ProviderId.bilibili,
        roomId: '111',
        title: 'Title',
        streamerName: 'Streamer',
        metadata: const {'key': 'different'},
      );

      expect(detail1, equals(detail2));
      expect(detail1.hashCode, equals(detail2.hashCode));
      expect(detail1, isNot(equals(detail3)));
    });

    test('toWellFormed string sanitization', () {
      const malformed = 'Hello \uD83D World';
      final expected = malformed.toWellFormed();

      final detail = LiveRoomDetail(
        providerId: ProviderId.bilibili,
        roomId: '111',
        title: malformed,
        streamerName: malformed,
        areaName: malformed,
        description: malformed,
      );

      expect(detail.title, equals(expected));
      expect(detail.streamerName, equals(expected));
      expect(detail.areaName, equals(expected));
      expect(detail.description, equals(expected));
    });
  });
}
