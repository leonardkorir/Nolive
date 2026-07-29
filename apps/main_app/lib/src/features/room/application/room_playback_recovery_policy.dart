import 'dart:ui' show Size;

import 'package:live_core/live_core.dart';
import 'package:live_player/live_player.dart';
import 'package:nolive_app/src/features/room/application/room_provider_traits.dart';

/// Decisions about recovering from an unexpected playback stop.
///
/// These rules used to live as anonymous closures inside the room page's
/// `initState`, which made them reachable only by mounting the whole page.
/// They are pure functions here so the product rules can be asserted directly.

/// Whether an unexpected playback stop should schedule an auto-recovery.
///
/// Stripchat is excluded: its streams involve JS-bridge key decryption and
/// private-mode/P2P status transitions, so blind hot-retries can loop forever
/// fetching play URLs that no longer exist once a broadcaster goes private or
/// the key expires.
///
/// A recovery is also suppressed while a room refresh is already in flight, so
/// the two paths do not race to rebind the player.
bool roomShouldRecoverUnexpectedPlaybackStop({
  required ProviderId providerId,
  required bool refreshInFlight,
}) {
  if (!roomProviderTraitsFor(providerId).autoRecoversUnexpectedStop) {
    return false;
  }
  if (refreshInFlight) {
    return false;
  }
  return true;
}

/// Debounce before retrying after an unexpected stop.
///
/// Hard open failures (Douyu/mpv) must switch CDN immediately; soft stalls keep
/// a 2s debounce so brief completed/error blips are not flapped.
Duration roomUnexpectedStopRecoveryDelay({
  required String? errorMessage,
  required bool hasReachedPlaying,
}) {
  if (PlaybackFailoverPolicy.isHardOpenFailure(
    errorMessage,
    hasReachedPlaying: hasReachedPlaying,
  )) {
    return Duration.zero;
  }
  return const Duration(seconds: 2);
}

/// Integral picture-in-picture aspect ratio for an inline viewport.
///
/// Falls back to 16:9 when the viewport has not been measured yet, and clamps
/// to the 1..4096 range Android accepts for PiP.
({int width, int height}) roomPipAspectRatioFor(Size? viewportSize) {
  final size =
      viewportSize != null && viewportSize.width > 0 && viewportSize.height > 0
      ? viewportSize
      : const Size(16, 9);
  return (
    width: size.width.round().clamp(1, 4096),
    height: size.height.round().clamp(1, 4096),
  );
}

/// Whether reported video diagnostics describe a portrait stream.
///
/// Unknown or zero dimensions are treated as not-vertical so fullscreen keeps
/// its landscape default until a real frame size arrives.
bool roomIsVerticalVideo({required int? width, required int? height}) {
  final w = width ?? 0;
  final h = height ?? 0;
  return w > 0 && h > 0 && h > w;
}
