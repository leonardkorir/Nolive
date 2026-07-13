import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_hls_proxy/live_hls_proxy.dart';
import 'package:nolive_app/src/app/runtime_bridges/youtube_nsig_webview_solver.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (message) async {
          // Minimal JS asset content so evaluate "ready" path can succeed when
          // not testing hang/timeout create failures.
          return ByteData.sublistView(
            Uint8List.fromList(
              'globalThis.NoliveYouTubeNSigSolver={solveN:async()=>({})};'.codeUnits,
            ),
          );
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', null);
  });

  test('youtube nsig solver times out hung webview start and disposes', () async {
    final adapter = _FakeYoutubeAdapter(hangOnCreate: true);
    final solver = YouTubeWebViewNSigSolver(
      platformAdapter: adapter,
      solveTimeout: const Duration(milliseconds: 30),
      webViewStartTimeout: const Duration(milliseconds: 40),
    );

    final startedAt = DateTime.now();
    await expectLater(
      () => solver.solveNChallenges(
        playerJsUrl: 'https://www.youtube.com/s/player/abc/base.js',
        playerJs: 'function(){}',
        challenges: const ['n1'],
      ),
      throwsA(isA<TimeoutException>()),
    );
    final elapsed = DateTime.now().difference(startedAt);
    expect(elapsed, lessThan(const Duration(seconds: 2)));
    await solver.dispose();
  });

  test('youtube nsig solver releasePressure disposes idle webview', () async {
    final adapter = _FakeYoutubeAdapter(
      hangOnCreate: false,
      solveResults: {
        'n1': 'solved1',
      },
    );
    final solver = YouTubeWebViewNSigSolver(
      platformAdapter: adapter,
      solveTimeout: const Duration(seconds: 2),
      webViewStartTimeout: const Duration(seconds: 2),
    );

    final solved = await solver.solveNChallenges(
      playerJsUrl: 'https://www.youtube.com/s/player/abc/base.js',
      playerJs: 'function(){}',
      challenges: const ['n1'],
    );
    expect(solved['n1'], 'solved1');
    expect(adapter.createdWebViews, hasLength(1));
    expect(adapter.createdWebViews.single.disposed, isFalse);

    await solver.releasePressure(reason: 'test leave');
    expect(adapter.createdWebViews.single.disposed, isTrue);
    await solver.dispose();
  });
}

class _FakeYoutubeAdapter implements HlsProxyPlatformAdapter {
  _FakeYoutubeAdapter({
    required this.hangOnCreate,
    this.solveResults = const {},
  });

  final bool hangOnCreate;
  final Map<String, String> solveResults;
  final List<_FakeYoutubeWebView> createdWebViews = <_FakeYoutubeWebView>[];

  @override
  bool get isMobile => true;

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
    final webView = _FakeYoutubeWebView(solveResults: solveResults);
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

class _FakeYoutubeWebView implements HlsHeadlessWebView {
  _FakeYoutubeWebView({required this.solveResults});

  final Map<String, String> solveResults;
  bool disposed = false;

  @override
  Future<void> run() async {}

  @override
  Future<void> dispose() async {
    disposed = true;
  }

  @override
  Future<String?> getUrl() async => 'https://www.youtube.com/';

  @override
  Future<String?> getHtml() async => '<html></html>';

  @override
  Future<Object?> evaluateJavascript({required String source}) async {
    if (source.contains('NoliveYouTubeNSigSolver')) {
      return true;
    }
    return null;
  }

  @override
  Future<HlsJavaScriptResult?> callAsyncJavaScript({
    required String functionBody,
    required Map<String, dynamic> arguments,
  }) async {
    final challenges = (arguments['challenges'] as List?)
            ?.map((item) => item.toString())
            .toList(growable: false) ??
        const <String>[];
    final results = <String, String>{
      for (final challenge in challenges)
        if (solveResults.containsKey(challenge))
          challenge: solveResults[challenge]!,
    };
    return HlsJavaScriptResult(value: {'results': results});
  }
}
