import 'package:live_hls_proxy/live_hls_proxy.dart';
import 'package:test/test.dart';

void main() {
  test('Chaturbate web room detail default timeout cold-start band', () {
    // 12s: room for cold WebView; still well under legacy 18s.
    expect(
      kChaturbateWebRoomDetailDefaultTimeout.inSeconds,
      lessThanOrEqualTo(14),
    );
    expect(
      kChaturbateWebRoomDetailDefaultTimeout.inSeconds,
      greaterThanOrEqualTo(10),
    );
    expect(
      kChaturbateWebRoomDetailDefaultTimeout,
      lessThan(const Duration(seconds: 18)),
    );
  });
}
