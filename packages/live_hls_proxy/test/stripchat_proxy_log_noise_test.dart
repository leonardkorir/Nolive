import 'package:live_hls_proxy/live_hls_proxy.dart';
import 'package:test/test.dart';

void main() {
  test('verbose stripchat pdkey/mouflon logs suppressed outside debug mode', () {
    expect(
      shouldEmitStripchatProxyLog(verbose: true, kDebugMode: false),
      isFalse,
    );
    expect(
      shouldEmitStripchatProxyLog(verbose: true, kDebugMode: true),
      isTrue,
    );
    expect(
      shouldEmitStripchatProxyLog(verbose: false, kDebugMode: false),
      isTrue,
    );
    expect(
      shouldEmitStripchatProxyLog(verbose: false, kDebugMode: true),
      isTrue,
    );
  });
}
