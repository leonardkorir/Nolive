import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_player/live_player.dart';
import 'package:nolive_app/src/features/room/application/room_playback_backend_policy.dart';

void main() {
  test('youtube on android keeps preferred backend', () {
    final backend = resolveRoomPlaybackBackend(
      providerId: ProviderId.youtube,
      preferredBackend: PlayerBackend.mdk,
      targetPlatform: TargetPlatform.android,
      isWeb: false,
    );

    expect(backend, PlayerBackend.mdk);
  });

  test('non-youtube on android keeps preferred backend', () {
    final backend = resolveRoomPlaybackBackend(
      providerId: ProviderId.bilibili,
      preferredBackend: PlayerBackend.mdk,
      targetPlatform: TargetPlatform.android,
      isWeb: false,
    );

    expect(backend, PlayerBackend.mdk);
  });

  test('youtube on non-android keeps preferred backend', () {
    final backend = resolveRoomPlaybackBackend(
      providerId: ProviderId.youtube,
      preferredBackend: PlayerBackend.mdk,
      targetPlatform: TargetPlatform.iOS,
      isWeb: false,
    );

    expect(backend, PlayerBackend.mdk);
  });
}
