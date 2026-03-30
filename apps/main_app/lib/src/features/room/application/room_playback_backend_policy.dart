import 'package:flutter/foundation.dart';
import 'package:live_core/live_core.dart';
import 'package:live_player/live_player.dart';

PlayerBackend resolveRoomPlaybackBackend({
  required ProviderId providerId,
  required PlayerBackend preferredBackend,
  required TargetPlatform targetPlatform,
  bool isWeb = kIsWeb,
}) {
  if (isWeb) {
    return preferredBackend;
  }

  final sanitizedPreferred = preferredBackend == PlayerBackend.memory
      ? PlayerBackend.mpv
      : preferredBackend;

  if (targetPlatform != TargetPlatform.android) {
    return sanitizedPreferred;
  }

  if (_prefersMpvOnAndroid(providerId)) {
    return PlayerBackend.mpv;
  }

  return sanitizedPreferred;
}

bool _prefersMpvOnAndroid(ProviderId providerId) {
  return switch (providerId) {
    ProviderId.youtube || ProviderId.twitch || ProviderId.chaturbate => true,
    _ => false,
  };
}
