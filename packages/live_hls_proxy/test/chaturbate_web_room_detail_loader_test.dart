import 'dart:async';
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:live_hls_proxy/live_hls_proxy.dart';
import 'package:test/test.dart';

void main() {
  test('chaturbate webview resource policy blocks non-business resources', () {
    bool blocks(String url) =>
        ChaturbateWebRoomDetailLoader.shouldBlockWebViewResource(url);

    expect(blocks('https://www.googletagmanager.com/gtag/js?id=G-1'), isTrue);
    expect(blocks('https://fonts.gstatic.com/s/roboto.woff2'), isTrue);
    expect(blocks('https://cbjpeg.highwebmedia.com/room/preview.jpg'), isTrue);
    expect(
      blocks('https://chaturbate.com/notifications/updates/?room=test'),
      isTrue,
    );

    expect(blocks('https://chaturbate.com/test_room/'), isFalse);
    expect(
      blocks('https://chaturbate.com/api/ts/room_context/test_room/'),
      isFalse,
    );
  });

  test('chaturbate loader queues concurrent headless webviews', () async {
    final gates = <String, Completer<void>>{
      'alpha': Completer<void>(),
      'beta': Completer<void>(),
    };
    final adapter = _FakePlatformAdapter(runGates: gates);
    final loader = ChaturbateWebRoomDetailLoader(
      platformAdapter: adapter,
      timeout: const Duration(seconds: 2),
      pollInterval: const Duration(milliseconds: 5),
    );

    final first = loader.load('alpha');
    await _waitFor(() => adapter.createdWebViews.length == 1);
    expect(adapter.createdWebViews.single.initialUrl, contains('/alpha/'));

    final second = loader.load('beta');
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(adapter.createdWebViews, hasLength(1));

    gates['alpha']!.complete();
    final firstDetail = await first;
    expect(firstDetail.roomId, 'alpha');

    await _waitFor(() => adapter.createdWebViews.length == 2);
    expect(adapter.createdWebViews.last.initialUrl, contains('/beta/'));
    gates['beta']!.complete();
    final secondDetail = await second;
    expect(secondDetail.roomId, 'beta');
  });

  test(
    'chaturbate loader passes resource blocker and avoids full html read',
    () async {
      final adapter = _FakePlatformAdapter();
      final loader = ChaturbateWebRoomDetailLoader(
        platformAdapter: adapter,
        timeout: const Duration(seconds: 2),
        pollInterval: const Duration(milliseconds: 5),
      );

      final detail = await loader.load('gamma');

      expect(detail.roomId, 'gamma');
      expect(adapter.resourceBlockers, hasLength(1));
      expect(
        adapter.resourceBlockers.single!(
          'https://www.googletagmanager.com/gtag/js?id=G-1',
        ),
        isTrue,
      );
      expect(adapter.createdWebViews.single.getHtmlCalls, 0);
      expect(
        adapter.createdWebViews.single.evaluateSources,
        contains(
          ChaturbateWebRoomDetailLoader.roomBootstrapExtractionScriptForTesting,
        ),
      );
    },
  );

  test('chaturbate bootstrap extraction script guards missing DOM', () {
    final script =
        ChaturbateWebRoomDetailLoader.roomBootstrapExtractionScriptForTesting;

    expect(script, contains('document.documentElement'));
    expect(script, contains("root && typeof root.outerHTML === 'string'"));
    expect(script, isNot(contains('document.documentElement.outerHTML')));
  });

  test(
    'chaturbate loader retries transient headless webview startup failure',
    () async {
      final diagnostics = <String>[];
      final adapter = _FakePlatformAdapter(
        runFailures: {
          'delta': [
            StateError(
              'PlatformException(error, Must be started before we block!, '
              'null, java.lang.RuntimeException: Must be started before we '
              'block! at addDocumentStartJavaScript)',
            ),
          ],
        },
      );
      final loader = ChaturbateWebRoomDetailLoader(
        platformAdapter: adapter,
        timeout: const Duration(seconds: 2),
        pollInterval: const Duration(milliseconds: 5),
        webViewStartupRetryDelay: Duration.zero,
        webViewRecreateCooldown: Duration.zero,
        diagnostics: diagnostics.add,
      );

      final detail = await loader.load('delta');

      expect(detail.roomId, 'delta');
      expect(adapter.createdWebViews, hasLength(2));
      expect(adapter.createdWebViews.first.disposed, isTrue);
      expect(adapter.createdWebViews.last.disposed, isTrue);
      expect(
        diagnostics.any(
          (message) =>
              message.contains('startup transient failure attempt=1/3') &&
              message.contains('Must be started before we block'),
        ),
        isTrue,
      );
    },
  );

  test(
    'chaturbate loader does not retry permanent webview startup error',
    () async {
      final adapter = _FakePlatformAdapter(
        runFailures: {
          'epsilon': [StateError('permanent webview startup failure')],
        },
      );
      final loader = ChaturbateWebRoomDetailLoader(
        platformAdapter: adapter,
        timeout: const Duration(seconds: 2),
        pollInterval: const Duration(milliseconds: 5),
        webViewStartupRetryDelay: Duration.zero,
        webViewRecreateCooldown: Duration.zero,
      );

      await expectLater(
        loader.load('epsilon'),
        throwsA(
          isA<ProviderParseException>().having(
            (error) => error.cause.toString(),
            'cause',
            contains('permanent webview startup failure'),
          ),
        ),
      );
      expect(adapter.createdWebViews, hasLength(1));
      expect(adapter.createdWebViews.single.disposed, isTrue);
    },
  );
}

class _FakePlatformAdapter implements HlsProxyPlatformAdapter {
  _FakePlatformAdapter({
    Map<String, Completer<void>>? runGates,
    Map<String, List<Object>>? runFailures,
  }) : runGates = runGates ?? const <String, Completer<void>>{},
       runFailures = {
         for (final entry
             in (runFailures ?? const <String, List<Object>>{}).entries)
           entry.key: List<Object>.of(entry.value),
       };

  final Map<String, Completer<void>> runGates;
  final Map<String, List<Object>> runFailures;
  final List<_FakeHeadlessWebView> createdWebViews = <_FakeHeadlessWebView>[];
  final List<HlsWebViewResourceBlocker?> resourceBlockers =
      <HlsWebViewResourceBlocker?>[];
  final _FakeCookieManager _cookieManager = _FakeCookieManager();

  @override
  bool get isMobile => true;

  @override
  bool get supportsHeadlessWebView => true;

  @override
  bool get kDebugMode => true;

  @override
  HlsProxyCookieManager get cookieManager => _cookieManager;

  @override
  void debugPrint(String message) {}

  @override
  void log(
    String tag,
    String message, [
    Object? error,
    StackTrace? stackTrace,
  ]) {}

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
    resourceBlockers.add(shouldBlockRequest);
    final roomId = Uri.parse(initialUrl).pathSegments.first;
    final webView = _FakeHeadlessWebView(
      initialUrl: initialUrl,
      html: _buildRoomHtml(roomId),
      runGate: runGates[roomId],
      runError: _takeRunFailure(roomId),
    );
    createdWebViews.add(webView);
    return webView;
  }

  Object? _takeRunFailure(String roomId) {
    final failures = runFailures[roomId];
    if (failures == null || failures.isEmpty) {
      return null;
    }
    return failures.removeAt(0);
  }
}

class _FakeCookieManager implements HlsProxyCookieManager {
  @override
  Future<List<HlsProxyCookie>> getCookies({required String url}) async {
    return const <HlsProxyCookie>[];
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

class _FakeHeadlessWebView implements HlsHeadlessWebView {
  _FakeHeadlessWebView({
    required this.initialUrl,
    required this.html,
    this.runGate,
    this.runError,
  });

  final String initialUrl;
  final String html;
  final Completer<void>? runGate;
  final Object? runError;
  final List<String> evaluateSources = <String>[];
  int getHtmlCalls = 0;
  bool disposed = false;

  @override
  Future<void> run() async {
    final error = runError;
    if (error != null) {
      throw error;
    }
    final gate = runGate;
    if (gate != null) {
      await gate.future;
    }
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }

  @override
  Future<String?> getUrl() async {
    return initialUrl;
  }

  @override
  Future<String?> getHtml() async {
    getHtmlCalls += 1;
    return html;
  }

  @override
  Future<Object?> evaluateJavascript({required String source}) async {
    evaluateSources.add(source);
    if (source == 'document.readyState') {
      return 'complete';
    }
    return html;
  }

  @override
  Future<HlsJavaScriptResult?> callAsyncJavaScript({
    required String functionBody,
    required Map<String, dynamic> arguments,
  }) async {
    throw UnimplementedError();
  }
}

String _buildRoomHtml(String roomId) {
  final dossierRaw = _embeddedJsonString(<String, Object?>{
    'broadcaster_username': roomId,
    'broadcaster_uid': 'uid-$roomId',
    'room_uid': 'room-$roomId',
    'room_status': 'public',
    'room_title': '$roomId room',
    'broadcaster_gender': 'f',
    'num_viewers': 42,
    'hls_source': 'https://edge.example.test/playlist.m3u8',
  });
  final pushServicesRaw = _embeddedJsonString(<Map<String, Object?>>[
    <String, Object?>{
      'backend': 'a',
      'host': 'realtime.pa.highwebmedia.com',
      'port': 443,
    },
  ]);
  return '''
<html>
  <head>
    <script>
      window.initialRoomDossier = "$dossierRaw";
      window.__roomConfig = {
        csrftoken: 'csrf-$roomId',
        push_services: JSON.parse('$pushServicesRaw')
      };
    </script>
  </head>
  <body></body>
</html>
''';
}

String _embeddedJsonString(Object value) {
  final encoded = jsonEncode(jsonEncode(value));
  return encoded.substring(1, encoded.length - 1);
}

Future<void> _waitFor(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 1),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('condition was not met before timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}
