import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:nolive_app/src/features/room/application/room_playback_recovery_policy.dart';

void main() {
  group('roomShouldRecoverUnexpectedPlaybackStop', () {
    test('never auto-recovers stripchat', () {
      expect(
        roomShouldRecoverUnexpectedPlaybackStop(
          providerId: ProviderId.stripchat,
          refreshInFlight: false,
        ),
        isFalse,
      );
    });

    test('suppresses recovery while a refresh is already in flight', () {
      expect(
        roomShouldRecoverUnexpectedPlaybackStop(
          providerId: ProviderId.douyu,
          refreshInFlight: true,
        ),
        isFalse,
      );
    });

    test('recovers other providers when idle', () {
      for (final providerId in ProviderId.knownValues) {
        if (providerId == ProviderId.stripchat) {
          continue;
        }
        expect(
          roomShouldRecoverUnexpectedPlaybackStop(
            providerId: providerId,
            refreshInFlight: false,
          ),
          isTrue,
          reason: 'expected ${providerId.value} to auto-recover',
        );
      }
    });
  });

  group('roomUnexpectedStopRecoveryDelay', () {
    test('hard open failure switches line immediately', () {
      expect(
        roomUnexpectedStopRecoveryDelay(
          errorMessage: 'failed to open stream',
          hasReachedPlaying: false,
        ),
        Duration.zero,
      );
    });

    test('soft stall keeps the 2s debounce', () {
      expect(
        roomUnexpectedStopRecoveryDelay(
          errorMessage: null,
          hasReachedPlaying: true,
        ),
        const Duration(seconds: 2),
      );
    });
  });

  group('roomPipAspectRatioFor', () {
    test('falls back to 16:9 before the viewport is measured', () {
      expect(roomPipAspectRatioFor(null), (width: 16, height: 9));
    });

    test('falls back to 16:9 for a degenerate viewport', () {
      expect(roomPipAspectRatioFor(const Size(0, 480)), (width: 16, height: 9));
      expect(roomPipAspectRatioFor(const Size(640, 0)), (width: 16, height: 9));
    });

    test('rounds a measured viewport', () {
      expect(roomPipAspectRatioFor(const Size(640.4, 360.6)), (
        width: 640,
        height: 361,
      ));
    });

    test('clamps to the range Android accepts', () {
      expect(roomPipAspectRatioFor(const Size(99999, 0.2)), (
        width: 4096,
        height: 1,
      ));
    });
  });

  group('roomIsVerticalVideo', () {
    test('unknown dimensions are not vertical', () {
      expect(roomIsVerticalVideo(width: null, height: null), isFalse);
      expect(roomIsVerticalVideo(width: 0, height: 0), isFalse);
      expect(roomIsVerticalVideo(width: 0, height: 1920), isFalse);
    });

    test('portrait stream is vertical', () {
      expect(roomIsVerticalVideo(width: 1080, height: 1920), isTrue);
    });

    test('landscape and square streams are not vertical', () {
      expect(roomIsVerticalVideo(width: 1920, height: 1080), isFalse);
      expect(roomIsVerticalVideo(width: 720, height: 720), isFalse);
    });
  });
}
