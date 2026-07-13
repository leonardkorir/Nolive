import 'package:live_core/live_core.dart';

/// Shared decision for whether a failed provider `fetchRoomDetail` may fall
/// back to an app-level [roomDetailOverride] (e.g. WebView-assisted loader).
///
/// Used by both open-room ([LoadRoomUseCase]) and follow watchlist
/// ([LoadFollowWatchlistUseCase]) so the two paths cannot diverge.
bool shouldAllowRoomDetailOverride(ProviderId providerId) {
  // Chaturbate room detail + danmaku bootstrap must stay on the pure-Dart
  // provider path. WebView overrides can hang list fan-out and strip tokens.
  return providerId != ProviderId.chaturbate;
}
