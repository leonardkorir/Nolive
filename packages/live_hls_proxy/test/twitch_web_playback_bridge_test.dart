import 'dart:async';

import 'package:live_core/live_core.dart';
import 'package:live_hls_proxy/live_hls_proxy.dart';
import 'package:live_providers/src/providers/twitch/twitch_playback_bootstrap.dart';
import 'package:test/test.dart';

void main() {
  test(
    'twitch bridge bootstrap times out and disposes hung headless webview',
    () async {
      final adapter = _FakeTwitchAdapter(hangOnCreate: true);
      final bridge = TwitchWebPlaybackBridge(
        platformAdapter: adapter,
        timeout: const Duration(milliseconds: 40),
        pollInterval: const Duration(milliseconds: 10),
        bootstrapScriptTimeout: const Duration(milliseconds: 20),
        webViewStartTimeout: const Duration(milliseconds: 50),
        idleDisposeDelay: const Duration(hours: 1),
      );

      final startedAt = DateTime.now();
      final result = await bridge.call(
        const LiveRoomDetail(
          providerId: ProviderId.twitch,
          roomId: 'shroud',
          title: 't',
          streamerName: 'shroud',
          isLive: true,
          sourceUrl: 'https://www.twitch.tv/shroud',
        ),
      );
      final elapsed = DateTime.now().difference(startedAt);

      expect(result, isNull);
      expect(elapsed, lessThan(const Duration(seconds: 2)));
      expect(adapter.createdWebViews, isEmpty);
      await bridge.dispose();
    },
  );

  test(
    'twitch bridge releasePressure disposes idle webview after successful create',
    () async {
      final adapter = _FakeTwitchAdapter(readyState: 'complete');
      final bridge = TwitchWebPlaybackBridge(
        platformAdapter: adapter,
        timeout: const Duration(milliseconds: 80),
        pollInterval: const Duration(milliseconds: 10),
        bootstrapScriptTimeout: const Duration(milliseconds: 30),
        webViewStartTimeout: const Duration(milliseconds: 100),
        idleDisposeDelay: const Duration(hours: 1),
      );

      // warmUp creates webview; bootstrap script returns unusable so call nulls
      await bridge.warmUp();
      expect(adapter.createdWebViews, hasLength(1));
      expect(adapter.createdWebViews.single.disposed, isFalse);

      await bridge.releasePressure(reason: 'test leave');
      expect(adapter.createdWebViews.single.disposed, isTrue);

      await bridge.dispose();
    },
  );

  test('twitch bridge serializes concurrent calls (single webview)', () async {
    final adapter = _FakeTwitchAdapter(
      readyState: 'complete',
      bootstrapDelay: const Duration(milliseconds: 40),
      usableBootstrap: true,
    );
    final bridge = TwitchWebPlaybackBridge(
      platformAdapter: adapter,
      timeout: const Duration(milliseconds: 200),
      pollInterval: const Duration(milliseconds: 10),
      bootstrapScriptTimeout: const Duration(milliseconds: 100),
      webViewStartTimeout: const Duration(milliseconds: 100),
      idleDisposeDelay: const Duration(hours: 1),
    );

    final detail = const LiveRoomDetail(
      providerId: ProviderId.twitch,
      roomId: 'xqc',
      title: 't',
      streamerName: 'xqc',
      isLive: true,
      sourceUrl: 'https://www.twitch.tv/xqc',
    );

    final results = await Future.wait([
      bridge.call(detail),
      bridge.call(detail),
    ]);
    expect(results.whereType<TwitchPlaybackBootstrap>(), hasLength(2));
    // Single-flight reuse: only one headless webview.
    expect(adapter.createdWebViews, hasLength(1));
    await bridge.dispose();
  });

  test(
    'twitch bridge retries Must be started before we block then succeeds',
    () async {
      final adapter = _FakeTwitchAdapter(
        readyState: 'complete',
        usableBootstrap: true,
        failRunTimes: 1,
      );
      final bridge = TwitchWebPlaybackBridge(
        platformAdapter: adapter,
        timeout: const Duration(milliseconds: 80),
        pollInterval: const Duration(milliseconds: 10),
        bootstrapScriptTimeout: const Duration(milliseconds: 40),
        webViewStartTimeout: const Duration(milliseconds: 100),
        webViewStartupRetryCount: 2,
        webViewStartupRetryDelay: const Duration(milliseconds: 20),
        webViewRecreateCooldown: Duration.zero,
        idleDisposeDelay: const Duration(hours: 1),
      );

      final result = await bridge.call(
        const LiveRoomDetail(
          providerId: ProviderId.twitch,
          roomId: 'pokimane',
          title: 't',
          streamerName: 'pokimane',
          isLive: true,
          sourceUrl: 'https://www.twitch.tv/pokimane',
        ),
      );

      expect(result, isNotNull);
      expect(result!.signature, 'sig');
      // First run() throws cold-start race; second create/run succeeds.
      expect(adapter.createdWebViews, hasLength(2));
      expect(adapter.createdWebViews.first.disposed, isTrue);
      expect(adapter.createdWebViews.last.disposed, isFalse);
      expect(adapter.runAttempts, 2);
      await bridge.dispose();
    },
  );

  test(
    'twitch bridge exhausts cold-start retries then fail-soft GraphQL path',
    () async {
      final adapter = _FakeTwitchAdapter(
        readyState: 'complete',
        usableBootstrap: true,
        failRunTimes: 99,
      );
      final bridge = TwitchWebPlaybackBridge(
        platformAdapter: adapter,
        timeout: const Duration(milliseconds: 40),
        pollInterval: const Duration(milliseconds: 10),
        bootstrapScriptTimeout: const Duration(milliseconds: 20),
        webViewStartTimeout: const Duration(milliseconds: 50),
        webViewStartupRetryCount: 2,
        webViewStartupRetryDelay: const Duration(milliseconds: 10),
        webViewRecreateCooldown: Duration.zero,
        idleDisposeDelay: const Duration(hours: 1),
      );

      final result = await bridge.call(
        const LiveRoomDetail(
          providerId: ProviderId.twitch,
          roomId: 'shroud',
          title: 't',
          streamerName: 'shroud',
          isLive: true,
          sourceUrl: 'https://www.twitch.tv/shroud',
        ),
      );

      expect(result, isNull);
      // 1 initial + 2 retries = 3 creates
      expect(adapter.createdWebViews, hasLength(3));
      expect(adapter.runAttempts, 3);
      expect(adapter.createdWebViews.every((w) => w.disposed), isTrue);
      await bridge.dispose();
    },
  );

  test(
    'twitch bridge does not retry non-transient TimeoutException on create',
    () async {
      final adapter = _FakeTwitchAdapter(hangOnCreate: true);
      final bridge = TwitchWebPlaybackBridge(
        platformAdapter: adapter,
        timeout: const Duration(milliseconds: 40),
        pollInterval: const Duration(milliseconds: 10),
        bootstrapScriptTimeout: const Duration(milliseconds: 20),
        webViewStartTimeout: const Duration(milliseconds: 40),
        webViewStartupRetryCount: 2,
        webViewStartupRetryDelay: const Duration(milliseconds: 10),
        webViewRecreateCooldown: Duration.zero,
        idleDisposeDelay: const Duration(hours: 1),
      );

      final startedAt = DateTime.now();
      final result = await bridge.call(
        const LiveRoomDetail(
          providerId: ProviderId.twitch,
          roomId: 'xqc',
          title: 't',
          streamerName: 'xqc',
          isLive: true,
          sourceUrl: 'https://www.twitch.tv/xqc',
        ),
      );
      final elapsed = DateTime.now().difference(startedAt);

      expect(result, isNull);
      // Timeout is not treated as cold-start race — no recreate storm.
      expect(adapter.createdWebViews, isEmpty);
      expect(elapsed, lessThan(const Duration(seconds: 2)));
      await bridge.dispose();
    },
  );
}

class _FakeTwitchAdapter implements HlsProxyPlatformAdapter {
  _FakeTwitchAdapter({
    this.hangOnCreate = false,
    this.readyState = 'loading',
    this.bootstrapDelay = Duration.zero,
    this.usableBootstrap = false,
    this.failRunTimes = 0,
  });

  final bool hangOnCreate;
  final String readyState;
  final Duration bootstrapDelay;
  final bool usableBootstrap;

  /// First N [HlsHeadlessWebView.run] calls throw cold-start race.
  int failRunTimes;
  int runAttempts = 0;
  final List<_FakeTwitchWebView> createdWebViews = <_FakeTwitchWebView>[];

  @override
  bool get isMobile => true;

  @override
  bool get supportsHeadlessWebView => true;

  @override
  bool get kDebugMode => true;

  @override
  void log(
    String tag,
    String message, [
    Object? error,
    StackTrace? stackTrace,
  ]) {}

  @override
  void debugPrint(String message) {}

  @override
  HlsProxyCookieManager get cookieManager => _FakeCookieManager();

  @override
  Future<HlsHeadlessWebView> createHeadlessWebView({
    required String initialUrl,
    required String userAgent,
    bool desktopMode = false,
    HlsWebViewResourceBlocker? shouldBlockRequest,
    void Function(String message)? onConsoleMessage,
    void Function(int statusCode, String url)? onHttpError,
    void Function(String description, String url)? onLoadError,
  }) async {
    if (hangOnCreate) {
      return Completer<HlsHeadlessWebView>().future;
    }
    final webView = _FakeTwitchWebView(
      readyState: readyState,
      bootstrapDelay: bootstrapDelay,
      usableBootstrap: usableBootstrap,
      onRun: () async {
        runAttempts += 1;
        if (failRunTimes > 0) {
          failRunTimes -= 1;
          throw Exception(
            'PlatformException(error, Must be started before we block!, '
            'null, java.lang.RuntimeException: Must be started before we '
            'block! at addDocumentStartJavaScript)',
          );
        }
      },
    );
    createdWebViews.add(webView);
    return webView;
  }
}

class _FakeCookieManager implements HlsProxyCookieManager {
  @override
  Future<List<HlsProxyCookie>> getCookies({required String url}) async {
    return const [];
  }

  @override
  Future<void> setCookie({
    required String url,
    required String name,
    required String value,
    required String domain,
    required String path,
    bool isSecure = true,
  }) async {}
}

class _FakeTwitchWebView implements HlsHeadlessWebView {
  _FakeTwitchWebView({
    required this.readyState,
    required this.bootstrapDelay,
    required this.usableBootstrap,
    this.onRun,
  });

  final String readyState;
  final Duration bootstrapDelay;
  final bool usableBootstrap;
  final Future<void> Function()? onRun;
  bool disposed = false;

  @override
  Future<void> run() async {
    await onRun?.call();
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }

  @override
  Future<String?> getUrl() async => 'https://www.twitch.tv/';

  @override
  Future<String?> getHtml() async => '<html></html>';

  @override
  Future<Object?> evaluateJavascript({required String source}) async {
    if (source.contains('readyState')) {
      return readyState;
    }
    return null;
  }

  @override
  Future<HlsJavaScriptResult?> callAsyncJavaScript({
    required String functionBody,
    required Map<String, dynamic> arguments,
  }) async {
    if (bootstrapDelay > Duration.zero) {
      await Future<void>.delayed(bootstrapDelay);
    }
    if (!usableBootstrap) {
      return HlsJavaScriptResult(value: {'errorMessage': 'not ready'});
    }
    return HlsJavaScriptResult(
      value: {
        'roomId': arguments['roomId'],
        'signature': 'sig',
        'tokenValue': 'token',
        'deviceId': 'device',
        'clientSessionId': 'session',
        'clientIntegrity': 'integrity',
        'sourceUrl': arguments['pageUrl'],
        'userAgent': 'ua',
      },
    );
  }
}
