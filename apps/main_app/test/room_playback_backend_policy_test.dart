import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_player/live_player.dart';
import 'package:nolive_app/src/features/room/application/room_playback_backend_policy.dart';

void main() {
  test('native runtime sanitizes memory backend to mpv on android', () {
    final backend = resolveRoomPlaybackBackend(
      providerId: ProviderId.bilibili,
      preferredBackend: PlayerBackend.memory,
      targetPlatform: TargetPlatform.android,
      isWeb: false,
    );

    expect(backend, PlayerBackend.mpv);
  });

  test('youtube on android prefers mpv over mdk', () {
    final backend = resolveRoomPlaybackBackend(
      providerId: ProviderId.youtube,
      preferredBackend: PlayerBackend.mdk,
      targetPlatform: TargetPlatform.android,
      isWeb: false,
    );

    expect(backend, PlayerBackend.mpv);
  });

  test('twitch on android prefers mpv over mdk', () {
    final backend = resolveRoomPlaybackBackend(
      providerId: ProviderId.twitch,
      preferredBackend: PlayerBackend.mdk,
      targetPlatform: TargetPlatform.android,
      isWeb: false,
    );

    expect(backend, PlayerBackend.mpv);
  });

  test('chaturbate on android prefers mpv over mdk', () {
    final backend = resolveRoomPlaybackBackend(
      providerId: ProviderId.chaturbate,
      preferredBackend: PlayerBackend.mdk,
      targetPlatform: TargetPlatform.android,
      isWeb: false,
    );

    expect(backend, PlayerBackend.mpv);
  });

  test('bilibili on android keeps preferred backend', () {
    final backend = resolveRoomPlaybackBackend(
      providerId: ProviderId.bilibili,
      preferredBackend: PlayerBackend.mdk,
      targetPlatform: TargetPlatform.android,
      isWeb: false,
    );

    expect(backend, PlayerBackend.mdk);
  });

  test('douyin on android keeps preferred backend', () {
    final backend = resolveRoomPlaybackBackend(
      providerId: ProviderId.douyin,
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

  test('web runtime keeps preferred backend unchanged', () {
    final backend = resolveRoomPlaybackBackend(
      providerId: ProviderId.youtube,
      preferredBackend: PlayerBackend.memory,
      targetPlatform: TargetPlatform.android,
      isWeb: true,
    );

    expect(backend, PlayerBackend.memory);
  });
}
