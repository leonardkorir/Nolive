import 'package:live_core/live_core.dart';
import 'package:test/test.dart';

void main() {
  group('LiveRoom Tests', () {
    test('value equality and hashCode', () {
      const room1 = LiveRoom(
        providerId: ProviderId.huya,
        roomId: '12345',
        title: 'Title 1',
        streamerName: 'Streamer 1',
        coverUrl: 'https://cover.url',
        keyframeUrl: 'https://keyframe.url',
        areaName: 'Area 1',
        streamerAvatarUrl: 'https://avatar.url',
        viewerCount: 1000,
        isLive: true,
      );

      const room2 = LiveRoom(
        providerId: ProviderId.huya,
        roomId: '12345',
        title: 'Title 1',
        streamerName: 'Streamer 1',
        coverUrl: 'https://cover.url',
        keyframeUrl: 'https://keyframe.url',
        areaName: 'Area 1',
        streamerAvatarUrl: 'https://avatar.url',
        viewerCount: 1000,
        isLive: true,
      );

      const room3 = LiveRoom(
        providerId: ProviderId.huya,
        roomId: '12345',
        title: 'Different Title',
        streamerName: 'Streamer 1',
      );

      expect(room1, equals(room2));
      expect(room1.hashCode, equals(room2.hashCode));
      expect(room1, isNot(equals(room3)));
    });

    test('toWellFormed string sanitization', () {
      const malformedTitle = 'Hello \uD83D World';
      final expectedTitle = malformedTitle.toWellFormed();

      const room = LiveRoom(
        providerId: ProviderId.huya,
        roomId: '123',
        title: malformedTitle,
        streamerName: 'Streamer',
        areaName: malformedTitle,
      );

      expect(room.title, equals(expectedTitle));
      expect(room.areaName, equals(expectedTitle));
    });
  });
}
