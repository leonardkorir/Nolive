import 'package:live_core/live_core.dart';
import 'package:live_storage/live_storage.dart';
import 'package:test/test.dart';

void main() {
  group('HistoryRecord equality', () {
    test('same values should be equal and have same hashcode', () {
      final now = DateTime(2026, 5, 29);
      final r1 = HistoryRecord(
        providerId: ProviderId.bilibili,
        roomId: '123',
        title: 'Title',
        streamerName: 'Streamer',
        viewedAt: now,
      );
      final r2 = HistoryRecord(
        providerId: ProviderId.bilibili,
        roomId: '123',
        title: 'Title',
        streamerName: 'Streamer',
        viewedAt: now,
      );

      expect(r1, equals(r2));
      expect(r1.hashCode, equals(r2.hashCode));
    });

    test('different values should not be equal', () {
      final now = DateTime(2026, 5, 29);
      final r1 = HistoryRecord(
        providerId: ProviderId.bilibili,
        roomId: '123',
        title: 'Title',
        streamerName: 'Streamer',
        viewedAt: now,
      );
      final r2 = HistoryRecord(
        providerId: ProviderId.douyu,
        roomId: '123',
        title: 'Title',
        streamerName: 'Streamer',
        viewedAt: now,
      );

      expect(r1, isNot(equals(r2)));
    });
  });

  group('FollowRecord equality', () {
    test('same values should be equal and have same hashcode', () {
      final r1 = FollowRecord(
        providerId: ProviderId.bilibili,
        roomId: '123',
        streamerName: 'Streamer',
        streamerAvatarUrl: 'avatar',
        lastTitle: 'Title',
        lastAreaName: 'Area',
        lastCoverUrl: 'cover',
        lastKeyframeUrl: 'keyframe',
        tags: const ['tag1', 'tag2'],
      );
      final r2 = FollowRecord(
        providerId: ProviderId.bilibili,
        roomId: '123',
        streamerName: 'Streamer',
        streamerAvatarUrl: 'avatar',
        lastTitle: 'Title',
        lastAreaName: 'Area',
        lastCoverUrl: 'cover',
        lastKeyframeUrl: 'keyframe',
        tags: const ['tag1', 'tag2'],
      );

      expect(r1, equals(r2));
      expect(r1.hashCode, equals(r2.hashCode));
    });

    test('different values should not be equal', () {
      final r1 = FollowRecord(
        providerId: ProviderId.bilibili,
        roomId: '123',
        streamerName: 'Streamer',
        tags: const ['tag1'],
      );
      final r2 = FollowRecord(
        providerId: ProviderId.bilibili,
        roomId: '123',
        streamerName: 'Streamer',
        tags: const ['tag2'],
      );

      expect(r1, isNot(equals(r2)));
    });
  });
}
