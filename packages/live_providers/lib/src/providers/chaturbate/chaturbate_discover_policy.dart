import 'dart:async';

/// Budgeted Chaturbate home/category discover policy.
///
/// Pre-HAR production behavior (stable on device):
/// - **carousel-first** for home/category
/// - stop on first carousel with rooms
/// - optional anonymous room-list only as fallback
///
/// Search still uses anonymous room-list separately (HAR-aligned).
class ChaturbateDiscoverBudget {
  const ChaturbateDiscoverBudget({
    this.maxCarouselAttempts = 2,
    this.maxAttemptsPerCarousel = 1,
    this.tryRoomListFallback = true,
    this.maxRoomListAttempts = 1,
    this.skipRoomListOnRateLimit = true,
  });

  /// How many carousels to try for home/category (spy_shows excluded).
  final int maxCarouselAttempts;

  /// Attempts per carousel (HTTP layer also single-shot for list endpoints).
  final int maxAttemptsPerCarousel;

  /// After carousels fail/empty, try anonymous room-list once.
  final bool tryRoomListFallback;

  /// Room-list attempts when used as fallback (or search).
  final int maxRoomListAttempts;

  /// If carousels hit 429, do not also hit room-list (site already limited).
  final bool skipRoomListOnRateLimit;

  int get maxRemoteAttempts {
    final carousels = maxCarouselAttempts < 0 ? 0 : maxCarouselAttempts;
    final per = maxAttemptsPerCarousel < 1 ? 1 : maxAttemptsPerCarousel;
    final list = tryRoomListFallback
        ? (maxRoomListAttempts < 1 ? 1 : maxRoomListAttempts)
        : 0;
    return carousels * per + list;
  }
}

/// Default: two carousels max, then optional one anonymous room-list.
const ChaturbateDiscoverBudget kDefaultChaturbateDiscoverBudget =
    ChaturbateDiscoverBudget();

bool isChaturbateRateLimitedError(Object error) {
  final text = error.toString();
  return text.contains('status 429') ||
      text.contains('status 408') ||
      text.contains('Too Many Requests');
}

bool isChaturbateRecoverableDiscoverError(Object error) {
  if (error is TimeoutException) {
    return true;
  }
  final text = error.toString();
  return isChaturbateRateLimitedError(error) ||
      text.contains('status 502') ||
      text.contains('status 503') ||
      text.contains('status 504') ||
      text.contains('TimeoutException');
}

/// Whether discover should try room-list after carousel outcomes.
bool shouldAttemptDiscoverRoomListFallback({
  required ChaturbateDiscoverBudget budget,
  required bool carouselsSucceededWithRooms,
  Object? lastCarouselError,
}) {
  if (carouselsSucceededWithRooms) {
    return false;
  }
  if (!budget.tryRoomListFallback) {
    return false;
  }
  if (budget.maxRoomListAttempts < 1) {
    return false;
  }
  if (budget.skipRoomListOnRateLimit &&
      lastCarouselError != null &&
      isChaturbateRateLimitedError(lastCarouselError)) {
    return false;
  }
  return true;
}
