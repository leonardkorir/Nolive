import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:live_hls_proxy/live_hls_proxy.dart';
import 'package:live_providers/live_providers.dart';

class YouTubeWebViewNSigSolver implements YouTubeNSigSolver {
  YouTubeWebViewNSigSolver({
    required HlsProxyPlatformAdapter platformAdapter,
    Duration solveTimeout = const Duration(seconds: 8),
    Duration webViewStartTimeout = const Duration(seconds: 10),
  }) : _platformAdapter = platformAdapter,
       _solveTimeout = solveTimeout,
       _webViewStartTimeout = webViewStartTimeout;

  static const String _scriptAsset = 'assets/js/youtube-nsig-solver.js';
  static const String _homeUrl = 'https://www.youtube.com/';
  static const String _userAgent =
      'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/146.0.0.0 Safari/537.36';
  static const String _solveScript = r'''
return await (async () => {
  const solver = globalThis.NoliveYouTubeNSigSolver;
  if (!solver || typeof solver.solveN !== 'function') {
    return {error: 'YouTube n-sig solver is not initialized'};
  }
  try {
    const results = await solver.solveN({
      playerJsUrl: args.playerJsUrl,
      playerJs: args.playerJs,
      challenges: args.challenges
    });
    return {results};
  } catch (error) {
    return {
      error: error instanceof Error
        ? `${error.message}\n${error.stack || ''}`
        : `${error}`
    };
  }
})()
''';

  final HlsProxyPlatformAdapter _platformAdapter;
  final Duration _solveTimeout;
  final Duration _webViewStartTimeout;
  HlsHeadlessWebView? _webView;
  Future<HlsHeadlessWebView>? _webViewFuture;
  Future<void> _operationChain = Future<void>.value();
  DateTime? _lastDisposeAt;
  int _activeOperations = 0;

  Duration get operationTimeout => _webViewStartTimeout + _solveTimeout;

  @override
  Future<Map<String, String>> solveNChallenges({
    required String playerJsUrl,
    required String playerJs,
    required List<String> challenges,
  }) async {
    final normalizedChallenges = challenges
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (normalizedChallenges.isEmpty) {
      return const {};
    }

    return _runSerialized(() async {
      _activeOperations += 1;
      try {
        return await _solveWithBounds(
          playerJsUrl: playerJsUrl,
          playerJs: playerJs,
          challenges: normalizedChallenges,
        ).timeout(operationTimeout);
      } on TimeoutException catch (error, stackTrace) {
        _platformAdapter.log(
          'youtube-nsig',
          'solve timed out; disposing webview',
          error,
          stackTrace,
        );
        await _disposeWebView();
        rethrow;
      } catch (error, stackTrace) {
        _platformAdapter.log(
          'youtube-nsig',
          'solve failed; disposing webview',
          error,
          stackTrace,
        );
        await _disposeWebView();
        rethrow;
      } finally {
        _activeOperations -= 1;
      }
    });
  }

  Future<Map<String, String>> _solveWithBounds({
    required String playerJsUrl,
    required String playerJs,
    required List<String> challenges,
  }) async {
    final webView = await _ensureWebView();
    final result = await webView
        .callAsyncJavaScript(
          functionBody: _solveScript,
          arguments: {
            'playerJsUrl': playerJsUrl,
            'playerJs': playerJs,
            'challenges': challenges,
          },
        )
        .timeout(_solveTimeout);
    if (result == null) {
      throw StateError('YouTube n-sig solver returned no result.');
    }
    final scriptError = result.error;
    if (scriptError != null && scriptError.trim().isNotEmpty) {
      throw StateError(scriptError);
    }
    final rawMap = _asMap(result.value);
    final errorMessage = rawMap['error']?.toString().trim() ?? '';
    if (errorMessage.isNotEmpty) {
      throw StateError(errorMessage);
    }
    return _asStringMap(rawMap['results']);
  }

  Future<HlsHeadlessWebView> _ensureWebView() async {
    final existing = _webViewFuture;
    if (existing != null) {
      return existing;
    }

    final future = () async {
      await _waitForWebViewRecreateCooldown();
      _platformAdapter.log('youtube-nsig', 'create headless webview');
      try {
        return await _createInitializedWebView().timeout(_webViewStartTimeout);
      } on PlatformException catch (error) {
        if (!_looksLikeTransientWebViewStartFailure(error)) {
          rethrow;
        }
        _platformAdapter.log(
          'youtube-nsig',
          'headless webview start failed transiently, retrying',
        );
        await _disposeWebView();
        await Future<void>.delayed(const Duration(milliseconds: 500));
        return _createInitializedWebView().timeout(_webViewStartTimeout);
      }
    }();
    _webViewFuture = future;
    try {
      return await future;
    } catch (_) {
      await _disposeWebView();
      rethrow;
    }
  }

  Future<HlsHeadlessWebView> _createInitializedWebView() async {
    final webView = await _platformAdapter.createHeadlessWebView(
      initialUrl: _homeUrl,
      userAgent: _userAgent,
      desktopMode: true,
    );
    _webView = webView;
    await webView.run();
    final source = await rootBundle.loadString(_scriptAsset);
    await webView.evaluateJavascript(source: source);
    final ready = await webView.evaluateJavascript(
      source:
          'Boolean(globalThis.NoliveYouTubeNSigSolver && '
          'globalThis.NoliveYouTubeNSigSolver.solveN)',
    );
    if (ready != true && ready?.toString() != 'true') {
      throw StateError('YouTube n-sig solver asset did not initialize.');
    }
    return webView;
  }

  Future<void> _waitForWebViewRecreateCooldown() async {
    final lastDisposeAt = _lastDisposeAt;
    if (lastDisposeAt == null) {
      return;
    }
    const cooldown = Duration(milliseconds: 350);
    final elapsed = DateTime.now().difference(lastDisposeAt);
    if (elapsed < cooldown) {
      await Future<void>.delayed(cooldown - elapsed);
    }
  }

  bool _looksLikeTransientWebViewStartFailure(PlatformException error) {
    final message = '${error.message ?? ''} ${error.details ?? ''}';
    return message.contains('Must be started before we block');
  }

  Future<T> _runSerialized<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    final run = _operationChain.then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    _operationChain = run.catchError((_) {});
    return completer.future;
  }

  Map<String, Object?> _asMap(Object? value) {
    if (value is Map) {
      return {
        for (final entry in value.entries) entry.key.toString(): entry.value,
      };
    }
    if (value is String && value.trim().isNotEmpty) {
      final decoded = jsonDecode(value);
      if (decoded is Map) {
        return {
          for (final entry in decoded.entries)
            entry.key.toString(): entry.value,
        };
      }
    }
    return const {};
  }

  Map<String, String> _asStringMap(Object? value) {
    final map = _asMap(value);
    return {
      for (final entry in map.entries)
        if (entry.key.trim().isNotEmpty &&
            entry.value?.toString().trim().isNotEmpty == true)
          entry.key.trim(): entry.value!.toString().trim(),
    };
  }

  Future<void> dispose() async {
    await _runSerialized(_disposeWebView);
  }

  /// Drop idle WebView after room leave to free headless pressure.
  Future<void> releasePressure({String reason = 'room left'}) {
    return _runSerialized(() async {
      if (_activeOperations > 0) {
        _platformAdapter.log(
          'youtube-nsig',
          'releasePressure deferred (active=$_activeOperations) reason=$reason',
        );
        return;
      }
      _platformAdapter.log('youtube-nsig', 'releasePressure reason=$reason');
      await _disposeWebView();
    });
  }

  Future<void> _disposeWebView() async {
    final webView = _webView;
    _webView = null;
    _webViewFuture = null;
    if (webView != null) {
      _platformAdapter.log('youtube-nsig', 'dispose headless webview');
      await webView.dispose();
      _lastDisposeAt = DateTime.now();
    }
  }
}
