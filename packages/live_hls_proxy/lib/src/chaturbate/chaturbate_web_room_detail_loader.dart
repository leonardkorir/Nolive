import 'dart:async';
import 'dart:collection';

import 'package:live_core/live_core.dart';
import 'package:live_providers/src/providers/chaturbate/chaturbate_mapper.dart';
import 'package:live_providers/src/providers/chaturbate/chaturbate_room_page_parser.dart';
import 'package:meta/meta.dart';

import '../hls_proxy_platform_adapter.dart';

/// Default wall-clock budget for headless room-detail bootstrap.
@visibleForTesting
/// Default wall-clock budget for headless room-detail WebView.
///
/// 12s leaves headroom for cold WebView startup (grace + retries) without
/// returning to the old 18s waterfall; warm paths still finish earlier.
const Duration kChaturbateWebRoomDetailDefaultTimeout = Duration(seconds: 12);

class ChaturbateWebRoomDetailLoader {
  ChaturbateWebRoomDetailLoader({
    required HlsProxyPlatformAdapter platformAdapter,
    Future<String> Function()? loadCookie,
    ChaturbateRoomPageParser roomPageParser = const ChaturbateRoomPageParser(),
    Duration timeout = kChaturbateWebRoomDetailDefaultTimeout,
    Duration pollInterval = const Duration(milliseconds: 250),
    Duration realtimeBootstrapGracePeriod = const Duration(seconds: 4),
    int webViewStartupRetryCount = 2,
    Duration webViewStartupRetryDelay = const Duration(milliseconds: 650),
    Duration webViewRecreateCooldown = const Duration(milliseconds: 350),
    int maxConcurrentWebViews = 1,
    void Function(String message)? diagnostics,
  }) : _platformAdapter = platformAdapter,
       _loadCookie = loadCookie,
       _roomPageParser = roomPageParser,
       _timeout = timeout,
       _pollInterval = pollInterval,
       _realtimeBootstrapGracePeriod = realtimeBootstrapGracePeriod,
       _webViewStartupRetryCount = webViewStartupRetryCount < 0
           ? 0
           : webViewStartupRetryCount,
       _webViewStartupRetryDelay = webViewStartupRetryDelay.isNegative
           ? Duration.zero
           : webViewStartupRetryDelay,
       _webViewRecreateCooldown = webViewRecreateCooldown.isNegative
           ? Duration.zero
           : webViewRecreateCooldown,
       _loadQueue = _ChaturbateWebViewLoadQueue(
         maxConcurrent: maxConcurrentWebViews,
       ),
       _diagnostics = diagnostics;

  static const String homeUrl = 'https://chaturbate.com/';
  static const String embeddedBrowserUserAgent =
      'Mozilla/5.0 (Linux; Android 14; Pixel 7) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/125.0.0.0 Mobile Safari/537.36';
  static const String _roomBootstrapExtractionScript = r'''
(() => {
  const scripts = Array.from(document.scripts || []);
  const chunks = [];
  for (const script of scripts) {
    const text = script && typeof script.textContent === 'string'
      ? script.textContent
      : '';
    if (
      text.includes('window.initialRoomDossier') ||
      text.includes('push_services') ||
      text.includes('csrftoken')
    ) {
      chunks.push(text);
    }
  }
  if (chunks.length > 0) {
    return chunks.join('\n');
  }
  const root = document.documentElement;
  return root && typeof root.outerHTML === 'string' ? root.outerHTML : '';
})()
''';

  final HlsProxyPlatformAdapter _platformAdapter;
  final Future<String> Function()? _loadCookie;
  final ChaturbateRoomPageParser _roomPageParser;
  final Duration _timeout;
  final Duration _pollInterval;
  final Duration _realtimeBootstrapGracePeriod;
  final int _webViewStartupRetryCount;
  final Duration _webViewStartupRetryDelay;
  final Duration _webViewRecreateCooldown;
  final _ChaturbateWebViewLoadQueue _loadQueue;
  final void Function(String message)? _diagnostics;
  DateTime? _lastWebViewDisposeAt;

  Future<LiveRoomDetail?> call({
    required ProviderId providerId,
    required String roomId,
  }) async {
    if (providerId != ProviderId.chaturbate || !_supportsPlatform) {
      return null;
    }
    return load(roomId);
  }

  Future<LiveRoomDetail> load(String roomId) async {
    final normalizedRoomId = roomId.trim();
    if (normalizedRoomId.isEmpty) {
      throw ProviderParseException(
        providerId: ProviderId.chaturbate,
        message: 'Chaturbate 房间号不能为空。',
      );
    }

    await _seedCookiesFromSettings();

    return _loadQueue.run(() => _loadWithWebView(normalizedRoomId));
  }

  Future<LiveRoomDetail> _loadWithWebView(String normalizedRoomId) async {
    final maxAttempts = _webViewStartupRetryCount + 1;
    for (var attempt = 1; attempt <= maxAttempts; attempt += 1) {
      HlsHeadlessWebView? headlessWebView;
      try {
        await _waitForWebViewRecreateCooldown();
        headlessWebView = await _createRoomWebView(normalizedRoomId);
        await headlessWebView.run();
        return await _readRoomDetailFromWebView(
          webView: headlessWebView,
          roomId: normalizedRoomId,
        );
      } on ProviderParseException {
        rethrow;
      } on TimeoutException {
        throw ProviderParseException(
          providerId: ProviderId.chaturbate,
          message: 'Chaturbate 房间页加载超时，请先在账号管理重新完成网页登录后再试。',
        );
      } catch (error, stackTrace) {
        final canRetry =
            attempt < maxAttempts &&
            _looksLikeTransientWebViewStartupFailure(error);
        if (canRetry) {
          _logWebViewDiagnostic(
            roomId: normalizedRoomId,
            message:
                'startup transient failure attempt=$attempt/$maxAttempts '
                'retryDelayMs=${_webViewStartupRetryDelay.inMilliseconds} '
                'error=${_summarizeError(error)}',
          );
          if (headlessWebView != null) {
            await _disposeWebView(
              roomId: normalizedRoomId,
              webView: headlessWebView,
            );
            headlessWebView = null;
          }
          if (_webViewStartupRetryDelay > Duration.zero) {
            await Future<void>.delayed(_webViewStartupRetryDelay);
          }
          continue;
        }
        throw ProviderParseException(
          providerId: ProviderId.chaturbate,
          message: 'Chaturbate 房间页加载失败。',
          cause: error,
          stackTrace: stackTrace,
        );
      } finally {
        final webViewToDispose = headlessWebView;
        if (webViewToDispose != null) {
          await _disposeWebView(
            roomId: normalizedRoomId,
            webView: webViewToDispose,
          );
        }
      }
    }

    throw ProviderParseException(
      providerId: ProviderId.chaturbate,
      message: 'Chaturbate 房间页加载失败。',
    );
  }

  Future<HlsHeadlessWebView> _createRoomWebView(String normalizedRoomId) async {
    final headlessWebView = await _platformAdapter.createHeadlessWebView(
      initialUrl: _buildRoomUrl(normalizedRoomId),
      userAgent: embeddedBrowserUserAgent,
      shouldBlockRequest: shouldBlockWebViewResource,
      onConsoleMessage: (message) {
        _logWebViewDiagnostic(
          roomId: normalizedRoomId,
          message: 'console message=$message',
        );
      },
      onHttpError: (statusCode, url) {
        _logWebViewDiagnostic(
          roomId: normalizedRoomId,
          message: 'http status=$statusCode url=${_summarizeWebViewUrl(url)}',
        );
      },
      onLoadError: (description, url) {
        _logWebViewDiagnostic(
          roomId: normalizedRoomId,
          message:
              'load error description=$description url=${_summarizeWebViewUrl(url)}',
        );
      },
    );
    return headlessWebView;
  }

  Future<LiveRoomDetail> _readRoomDetailFromWebView({
    required HlsHeadlessWebView webView,
    required String roomId,
  }) async {
    final html = await _waitForRoomHtml(webView: webView, roomId: roomId);
    final cookieHeader = await _collectCookieHeader(
      roomUrl: _buildRoomUrl(roomId),
    );
    final pageContext = _roomPageParser.parsePageContext(html);
    final detail = ChaturbateMapper.mapRoomDetailFromPageContext(pageContext);
    if (cookieHeader.isEmpty) {
      return detail;
    }
    return LiveRoomDetail(
      providerId: detail.providerId,
      roomId: detail.roomId,
      title: detail.title,
      streamerName: detail.streamerName,
      streamerAvatarUrl: detail.streamerAvatarUrl,
      coverUrl: detail.coverUrl,
      keyframeUrl: detail.keyframeUrl,
      areaName: detail.areaName,
      description: detail.description,
      sourceUrl: detail.sourceUrl,
      startedAt: detail.startedAt,
      isLive: detail.isLive,
      viewerCount: detail.viewerCount,
      danmakuToken: detail.danmakuToken,
      metadata: {...?detail.metadata, 'requestCookie': cookieHeader},
    );
  }

  @visibleForTesting
  static bool shouldBlockWebViewResource(String rawUrl) {
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null) {
      return false;
    }
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') {
      return false;
    }
    final host = uri.host.toLowerCase();
    final path = uri.path.toLowerCase();

    const blockedHostSuffixes = <String>{
      'googletagmanager.com',
      'google-analytics.com',
      'analytics.google.com',
      'doubleclick.net',
      'googlesyndication.com',
      'googleadservices.com',
      'fonts.googleapis.com',
      'fonts.gstatic.com',
      'hotjar.com',
      'sentry.io',
      'clarity.ms',
    };
    for (final suffix in blockedHostSuffixes) {
      if (host == suffix || host.endsWith('.$suffix')) {
        return true;
      }
    }

    if (host == 'chaturbate.com' &&
        path.startsWith('/notifications/updates/')) {
      return true;
    }
    if (path.contains('/analytics') ||
        path.contains('/gtag/') ||
        path.contains('/ads/')) {
      return true;
    }

    const blockedExtensions = <String>{
      '.avif',
      '.gif',
      '.ico',
      '.jpeg',
      '.jpg',
      '.m3u8',
      '.m4s',
      '.mp4',
      '.otf',
      '.png',
      '.svg',
      '.ts',
      '.ttf',
      '.webm',
      '.webp',
      '.woff',
      '.woff2',
    };
    return blockedExtensions.any(path.endsWith);
  }

  Future<void> _seedCookiesFromSettings() async {
    final rawCookie = await _loadCookie?.call() ?? '';
    if (rawCookie.isEmpty) {
      return;
    }

    final seenNames = <String>{};
    for (final entry in _parseCookieHeader(rawCookie)) {
      if (!seenNames.add(entry.key)) {
        continue;
      }
      await _platformAdapter.cookieManager.setCookie(
        url: homeUrl,
        name: entry.key,
        value: entry.value,
        domain: '.chaturbate.com',
        path: '/',
        isSecure: true,
      );
    }
  }

  Future<String> _collectCookieHeader({required String roomUrl}) async {
    final cookieMap = <String, String>{};
    for (final url in {homeUrl, roomUrl}) {
      final cookies = await _platformAdapter.cookieManager.getCookies(url: url);
      for (final cookie in cookies) {
        final name = cookie.name.trim();
        final value = cookie.value.trim();
        if (name.isEmpty || value.isEmpty) {
          continue;
        }
        cookieMap[name] = value;
      }
    }
    return cookieMap.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join('; ');
  }

  Iterable<MapEntry<String, String>> _parseCookieHeader(
    String rawCookie,
  ) sync* {
    const ignoredAttributes = <String>{
      'path',
      'domain',
      'expires',
      'max-age',
      'secure',
      'httponly',
      'samesite',
      'priority',
      'partitioned',
    };

    for (final segment in rawCookie.split(';')) {
      final normalizedSegment = segment.trim();
      if (normalizedSegment.isEmpty) {
        continue;
      }
      final separatorIndex = normalizedSegment.indexOf('=');
      if (separatorIndex <= 0) {
        continue;
      }
      final name = normalizedSegment.substring(0, separatorIndex).trim();
      final value = normalizedSegment.substring(separatorIndex + 1).trim();
      if (name.isEmpty ||
          value.isEmpty ||
          ignoredAttributes.contains(name.toLowerCase())) {
        continue;
      }
      yield MapEntry(name, value);
    }
  }

  Future<String> _waitForRoomHtml({
    required HlsHeadlessWebView webView,
    required String roomId,
  }) async {
    final deadline = DateTime.now().add(_timeout);
    String lastHtml = '';
    String lastUrl = '';
    String? dossierHtml;
    DateTime? dossierDetectedAt;
    while (DateTime.now().isBefore(deadline)) {
      lastUrl = (await webView.getUrl()) ?? lastUrl;
      lastHtml = (await _readRoomBootstrapHtml(webView)).trim();
      final hasDossier = lastHtml.contains('window.initialRoomDossier');
      final hasRealtimeBootstrap = _roomPageParser.hasRealtimeBootstrap(
        lastHtml,
      );
      if (hasDossier) {
        dossierHtml = lastHtml;
        dossierDetectedAt ??= DateTime.now();
      }
      if (hasDossier && hasRealtimeBootstrap) {
        return lastHtml;
      }
      if (hasDossier &&
          await _isDocumentComplete(webView) &&
          dossierDetectedAt != null &&
          DateTime.now().difference(dossierDetectedAt) >=
              _realtimeBootstrapGracePeriod) {
        return dossierHtml!;
      }
      await Future<void>.delayed(_pollInterval);
    }

    if (dossierHtml != null) {
      return dossierHtml;
    }

    if (_looksLikeCloudflareChallenge(lastHtml)) {
      throw ProviderParseException(
        providerId: ProviderId.chaturbate,
        message:
            'Chaturbate 房间页仍然被 Cloudflare 或站点风控拦截。请先在账号管理使用“网页登录”打开并验证该房间，再重试。',
      );
    }
    throw ProviderParseException(
      providerId: ProviderId.chaturbate,
      message:
          'Chaturbate 房间页没有返回可解析 of initialRoomDossier。当前地址：${lastUrl.isEmpty ? _buildRoomUrl(roomId) : lastUrl}',
    );
  }

  Future<bool> _isDocumentComplete(HlsHeadlessWebView webView) async {
    try {
      final readyState = await webView.evaluateJavascript(
        source: 'document.readyState',
      );
      final normalized = readyState?.toString().replaceAll('"', '').trim();
      return normalized == 'complete';
    } catch (_) {
      return false;
    }
  }

  Future<String> _readRoomBootstrapHtml(HlsHeadlessWebView webView) async {
    try {
      final result = await webView.evaluateJavascript(
        source: _roomBootstrapExtractionScript,
      );
      final text = result?.toString().trim() ?? '';
      if (text.isNotEmpty) {
        return text;
      }
    } catch (_) {}
    return (await webView.getHtml())?.trim() ?? '';
  }

  @visibleForTesting
  static String get roomBootstrapExtractionScriptForTesting =>
      _roomBootstrapExtractionScript;

  bool _looksLikeCloudflareChallenge(String html) {
    final normalized = html.toLowerCase();
    return normalized.contains('cf-challenge') ||
        normalized.contains('just a moment') ||
        normalized.contains('attention required') ||
        normalized.contains('cloudflare') ||
        normalized.contains('/cdn-cgi/challenge-platform/');
  }

  String _buildRoomUrl(String roomId) => 'https://chaturbate.com/$roomId/';

  Future<void> _waitForWebViewRecreateCooldown() async {
    final lastDisposeAt = _lastWebViewDisposeAt;
    if (lastDisposeAt == null || _webViewRecreateCooldown == Duration.zero) {
      return;
    }
    final elapsed = DateTime.now().difference(lastDisposeAt);
    if (elapsed < _webViewRecreateCooldown) {
      await Future<void>.delayed(_webViewRecreateCooldown - elapsed);
    }
  }

  Future<void> _disposeWebView({
    required String roomId,
    required HlsHeadlessWebView webView,
  }) async {
    try {
      await webView.dispose();
    } catch (error, stackTrace) {
      _platformAdapter.log(
        'chaturbate/webview',
        'room=$roomId dispose failed',
        error,
        stackTrace,
      );
    } finally {
      _lastWebViewDisposeAt = DateTime.now();
    }
  }

  bool _looksLikeTransientWebViewStartupFailure(Object error) {
    final message = error.toString();
    return message.contains('Must be started before we block') ||
        message.contains('addDocumentStartJavaScript');
  }

  String _summarizeError(Object error) {
    final normalized = error.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= 220) {
      return normalized;
    }
    return '${normalized.substring(0, 220)}...';
  }

  void _logWebViewDiagnostic({
    required String roomId,
    required String message,
  }) {
    final line = 'room=$roomId $message';
    final diagnostics = _diagnostics;
    if (diagnostics != null) {
      diagnostics(line);
      return;
    }
    _platformAdapter.log('chaturbate/webview', line);
  }

  String _summarizeWebViewUrl(String rawUrl) {
    final uri = Uri.tryParse(rawUrl);
    if (uri == null) {
      return rawUrl;
    }
    final path = uri.path.isEmpty ? '/' : uri.path;
    return '${uri.host}$path';
  }

  bool get _supportsPlatform {
    return _platformAdapter.supportsHeadlessWebView;
  }
}

class _ChaturbateWebViewLoadQueue {
  _ChaturbateWebViewLoadQueue({required int maxConcurrent})
    : _maxConcurrent = maxConcurrent < 1 ? 1 : maxConcurrent;

  final int _maxConcurrent;
  final Queue<Completer<void>> _waiters = Queue<Completer<void>>();
  int _active = 0;

  Future<T> run<T>(Future<T> Function() task) async {
    final slot = Completer<void>();
    _waiters.add(slot);
    _drain();
    await slot.future;
    try {
      return await task();
    } finally {
      _active -= 1;
      _drain();
    }
  }

  void _drain() {
    while (_active < _maxConcurrent && _waiters.isNotEmpty) {
      _active += 1;
      _waiters.removeFirst().complete();
    }
  }
}
