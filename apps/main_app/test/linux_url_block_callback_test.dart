import 'package:flutter_test/flutter_test.dart';
import 'package:live_hls_proxy/live_hls_proxy.dart';
import 'package:nolive_app/src/app/runtime_bridges/linux_desktop_webview_adapter.dart';

void main() {
  group('linuxAllowUrlRequest (shipped DecidePolicy contract)', () {
    test('Chaturbate analytics hosts are blocked (allow=false)', () {
      // Real shipped blocker used by ChaturbateWebRoomDetailLoader.
      final allow = linuxAllowUrlRequest(
        url: 'https://www.google-analytics.com/g/collect?v=2',
        shouldBlockRequest:
            ChaturbateWebRoomDetailLoader.shouldBlockWebViewResource,
      );
      expect(allow, isFalse);
    });

    test('Chaturbate room page is allowed', () {
      final allow = linuxAllowUrlRequest(
        url: 'https://chaturbate.com/some_model/',
        shouldBlockRequest:
            ChaturbateWebRoomDetailLoader.shouldBlockWebViewResource,
      );
      expect(allow, isTrue);
    });

    test('null blocker always allows', () {
      expect(
        linuxAllowUrlRequest(
          url: 'https://evil.example/tracker.js',
          shouldBlockRequest: null,
        ),
        isTrue,
      );
    });

    test('custom blocker is honored (not ignored)', () {
      bool blockAllAds(String url) => url.contains('doubleclick.net');
      expect(
        linuxAllowUrlRequest(
          url: 'https://ad.doubleclick.net/x',
          shouldBlockRequest: blockAllAds,
        ),
        isFalse,
      );
      expect(
        linuxAllowUrlRequest(
          url: 'https://example.com/',
          shouldBlockRequest: blockAllAds,
        ),
        isTrue,
      );
    });
  });
}
