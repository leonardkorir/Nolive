import 'package:live_providers/src/providers/chaturbate/chaturbate_discover_policy.dart';
import 'package:test/test.dart';

void main() {
  group('ChaturbateDiscoverBudget', () {
    test('default budget is carousel-first with optional room-list fallback', () {
      const budget = kDefaultChaturbateDiscoverBudget;
      expect(budget.maxCarouselAttempts, 2);
      expect(budget.maxAttemptsPerCarousel, 1);
      expect(budget.tryRoomListFallback, isTrue);
      expect(budget.maxRoomListAttempts, 1);
      expect(budget.skipRoomListOnRateLimit, isTrue);
      expect(budget.maxRemoteAttempts, 3);
    });

    test('rate-limit detection covers 429/408/Too Many Requests', () {
      expect(
        isChaturbateRateLimitedError(
          Exception('Chaturbate room list request failed with status 429.'),
        ),
        isTrue,
      );
      expect(
        isChaturbateRateLimitedError(
          Exception('request failed with status 408'),
        ),
        isTrue,
      );
      expect(
        isChaturbateRateLimitedError(Exception('Too Many Requests')),
        isTrue,
      );
      expect(
        isChaturbateRateLimitedError(Exception('status 500')),
        isFalse,
      );
    });

    test('shouldAttemptDiscoverRoomListFallback skips on carousel success', () {
      expect(
        shouldAttemptDiscoverRoomListFallback(
          budget: kDefaultChaturbateDiscoverBudget,
          carouselsSucceededWithRooms: true,
          lastCarouselError: null,
        ),
        isFalse,
      );
    });

    test('shouldAttemptDiscoverRoomListFallback skips when carousel was 429', () {
      expect(
        shouldAttemptDiscoverRoomListFallback(
          budget: kDefaultChaturbateDiscoverBudget,
          carouselsSucceededWithRooms: false,
          lastCarouselError: Exception('failed with status 429.'),
        ),
        isFalse,
      );
    });

    test('shouldAttemptDiscoverRoomListFallback allows empty carousel fallback', () {
      expect(
        shouldAttemptDiscoverRoomListFallback(
          budget: kDefaultChaturbateDiscoverBudget,
          carouselsSucceededWithRooms: false,
          lastCarouselError: null,
        ),
        isTrue,
      );
    });
  });
}
