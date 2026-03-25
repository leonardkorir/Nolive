import 'package:flutter/foundation.dart';
import 'package:live_core/live_core.dart';
import 'package:live_player/live_player.dart';

PlayerBackend resolveRoomPlaybackBackend({
  required ProviderId providerId,
  required PlayerBackend preferredBackend,
  required TargetPlatform targetPlatform,
  bool isWeb = kIsWeb,
}) {
  return preferredBackend;
}
