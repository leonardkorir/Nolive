import 'package:live_providers/src/providers/chaturbate/chaturbate_live_data_source.dart';
import 'package:test/test.dart';

void main() {
  test('Chaturbate default request timeouts stay short and cancellable', () {
    expect(
      kChaturbateDefaultDiscoverRequestTimeout.inSeconds,
      lessThanOrEqualTo(6),
    );
    expect(
      kChaturbateDefaultDiscoverOverallTimeout.inSeconds,
      lessThanOrEqualTo(12),
    );
    // Room detail: slightly longer cold-start band (≤6s), still under old 8s.
    expect(
      kChaturbateDefaultRoomPageRequestTimeout.inSeconds,
      lessThanOrEqualTo(6),
    );
    expect(
      kChaturbateDefaultRoomContextRequestTimeout.inSeconds,
      lessThanOrEqualTo(4),
    );
    // Discover per-carousel stays under overall budget.
    expect(
      kChaturbateDefaultDiscoverRequestTimeout,
      lessThan(kChaturbateDefaultDiscoverOverallTimeout),
    );
  });
}
