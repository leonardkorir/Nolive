import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:nolive_app/src/features/room/application/room_shell_view_data.dart';

void main() {
  group('roomViewerLabel', () {
    test('unknown viewer counts show a dash', () {
      expect(roomViewerLabel(null), '-');
    });

    test('counts below ten thousand are shown verbatim', () {
      expect(roomViewerLabel(0), '0');
      expect(roomViewerLabel(9999), '9999');
    });

    test('ten thousand and up switch to 万 with one decimal', () {
      expect(roomViewerLabel(10000), '1.0万');
      expect(roomViewerLabel(12345), '1.2万');
      expect(roomViewerLabel(99999), '10.0万');
    });

    test('a hundred thousand and up drop the decimal', () {
      expect(roomViewerLabel(100000), '10万');
      expect(roomViewerLabel(1234567), '123万');
    });
  });

  group('roomAvatarLabel', () {
    test('uses the streamer initial', () {
      expect(roomAvatarLabel(streamerName: 'alice', providerLabel: '斗鱼'), 'A');
    });

    test('falls back to the provider initial', () {
      expect(roomAvatarLabel(streamerName: '', providerLabel: 'douyu'), 'D');
    });

    test('shows a question mark when nothing is known', () {
      expect(roomAvatarLabel(streamerName: '', providerLabel: ''), '?');
    });

    test('keeps non-latin initials as-is', () {
      expect(roomAvatarLabel(streamerName: '小明', providerLabel: ''), '小');
    });
  });

  group('roomShellTitle', () {
    test('uses the room title when present', () {
      expect(roomShellTitle(roomTitle: '开黑之夜', roomId: '123'), '开黑之夜');
    });

    test('falls back to the room id', () {
      expect(roomShellTitle(roomTitle: null, roomId: '123'), '房间号 123');
      expect(roomShellTitle(roomTitle: '   ', roomId: '123'), '房间号 123');
    });
  });

  group('roomProviderLabel', () {
    test('prefers the descriptor display name', () {
      expect(
        roomProviderLabel(
          descriptorDisplayName: '斗鱼',
          providerId: ProviderId.douyu,
        ),
        '斗鱼',
      );
    });

    test('falls back to the provider id', () {
      expect(
        roomProviderLabel(
          descriptorDisplayName: null,
          providerId: ProviderId.douyu,
        ),
        'douyu',
      );
    });
  });

  group('quality badge', () {
    final requested = LivePlayQuality(id: 'hd', label: '高清');
    final same = LivePlayQuality(id: 'hd', label: '高清');
    final fallback = LivePlayQuality(id: 'sd', label: '标清');

    test('no fallback when id and label both match', () {
      expect(
        roomHasQualityFallback(requested: requested, effective: same),
        isFalse,
      );
      expect(
        roomQualityBadgeLabelOrNull(requested: requested, effective: same),
        isNull,
      );
    });

    test('a differing id counts as a fallback', () {
      expect(
        roomHasQualityFallback(requested: requested, effective: fallback),
        isTrue,
      );
      expect(
        roomQualityBadgeLabelOrNull(requested: requested, effective: fallback),
        '高清 · 实际标清',
      );
    });

    test('a differing label alone counts as a fallback', () {
      final relabelled = LivePlayQuality(id: 'hd', label: '高清(备用)');
      expect(
        roomHasQualityFallback(requested: requested, effective: relabelled),
        isTrue,
      );
    });

    test('the plain label is used when there is no fallback', () {
      expect(
        roomQualityBadgeLabel(requested: requested, effective: same),
        '高清',
      );
    });
  });
}
