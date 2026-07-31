import 'package:live_player/live_player.dart';

/// Pure setting string decoders (ponytail F14 — lift out of bootstrap_internals).

bool decodeBoolSetting(String? raw, {bool fallback = false}) {
  if (raw == null || raw.isEmpty) {
    return fallback;
  }
  switch (raw.trim().toLowerCase()) {
    case 'true':
    case '1':
    case 'yes':
    case 'on':
      return true;
    case 'false':
    case '0':
    case 'no':
    case 'off':
      return false;
    default:
      return fallback;
  }
}

PlayerBackend decodePlayerBackend(String? raw) {
  return PlayerBackend.values.firstWhere(
    (item) => item.name == raw,
    orElse: () => PlayerBackend.mpv,
  );
}
