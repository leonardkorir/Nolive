import 'package:live_core/live_core.dart';
import 'package:nolive_app/src/features/room/application/room_provider_traits.dart';

/// Shared decision for whether a failed provider `fetchRoomDetail` may fall
/// back to an app-level [roomDetailOverride] (e.g. WebView-assisted loader).
///
/// Used by both open-room ([LoadRoomUseCase]) and follow watchlist
/// ([LoadFollowWatchlistUseCase]) so the two paths cannot diverge.
bool shouldAllowRoomDetailOverride(ProviderId providerId) {
  return roomProviderTraitsFor(providerId).allowsRoomDetailOverride;
}
