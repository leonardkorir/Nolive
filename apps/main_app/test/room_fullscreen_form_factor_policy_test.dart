import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nolive_app/src/features/room/presentation/room_fullscreen_form_factor_policy.dart';

void main() {
  group('resolveRoomFullscreenVideoOrientationMode', () {
    test('horizontal is long-edge on phone and large screens', () {
      expect(
        resolveRoomFullscreenVideoOrientationMode(
          screenSize: const Size(360, 800),
          verticalVideo: false,
        ),
        RoomFullscreenVideoOrientationMode.longEdgeLandscape,
      );
      expect(
        resolveRoomFullscreenVideoOrientationMode(
          screenSize: const Size(1280, 800),
          verticalVideo: false,
        ),
        RoomFullscreenVideoOrientationMode.longEdgeLandscape,
      );
    });

    test('vertical phone uses hard portrait', () {
      expect(
        resolveRoomFullscreenVideoOrientationMode(
          screenSize: const Size(360, 800),
          verticalVideo: true,
        ),
        RoomFullscreenVideoOrientationMode.hardPortrait,
      );
    });

    test('ARC is always long-edge landscape (no portrait)', () {
      expect(
        resolveRoomFullscreenVideoOrientationMode(
          screenSize: const Size(360, 640),
          verticalVideo: true,
          isArcChromeOs: true,
        ),
        RoomFullscreenVideoOrientationMode.longEdgeLandscape,
      );
      expect(
        resolveRoomFullscreenVideoOrientationMode(
          screenSize: const Size(1280, 800),
          verticalVideo: false,
          isArcChromeOs: true,
        ),
        RoomFullscreenVideoOrientationMode.longEdgeLandscape,
      );
      expect(
        resolveRoomFullscreenVideoOrientationMode(
          screenSize: const Size(1280, 800),
          verticalVideo: true,
          isArcChromeOs: true,
        ),
        RoomFullscreenVideoOrientationMode.longEdgeLandscape,
      );
    });

    test('non-ARC large tablet vertical uses hold-flexible', () {
      expect(
        resolveRoomFullscreenVideoOrientationMode(
          screenSize: const Size(800, 1280),
          verticalVideo: true,
        ),
        RoomFullscreenVideoOrientationMode.userHoldPortraitOrLandscape,
      );
    });
  });

  group('orientation lists', () {
    test('ARC list is landscape only', () {
      expect(
        kRoomArcLandscapeOnlyOrientations,
        equals(const [
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]),
      );
      expect(
        kRoomArcLandscapeOnlyOrientations,
        isNot(contains(DeviceOrientation.portraitUp)),
      );
    });
  });

  group('looksLikeArcChromeOsVersion', () {
    test('matches ChromeOS ARC version strings', () {
      expect(looksLikeArcChromeOsVersion('R149-16667.55.0'), isTrue);
      expect(looksLikeArcChromeOsVersion('R149-16667.61.0 release-keys'), isTrue);
    });

    test('rejects ordinary Android versions', () {
      expect(looksLikeArcChromeOsVersion('13'), isFalse);
      expect(looksLikeArcChromeOsVersion(''), isFalse);
    });
  });
}
