import 'dart:async';
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:live_providers/src/providers/twitch/twitch_playback_bootstrap.dart';

import '../hls_proxy_platform_adapter.dart';
import 'twitch_web_playback_lifecycle.dart';

class TwitchWebPlaybackBridge {
  TwitchWebPlaybackBridge({
    required HlsProxyPlatformAdapter platformAdapter,
    Future<String> Function()? loadCookie,
    Duration timeout = const Duration(seconds: 18),
    Duration pollInterval = const Duration(milliseconds: 500),
    Duration bootstrapScriptTimeout = const Duration(seconds: 4),
    Duration webViewStartTimeout = const Duration(seconds: 10),
    /// Extra attempts after the first headless create/run (CB-style cold start).
    /// Default 2 → up to 3 total tries on `Must be started before we block`.
    int webViewStartupRetryCount = 2,
    Duration webViewStartupRetryDelay = const Duration(milliseconds: 650),
    Duration webViewRecreateCooldown = const Duration(milliseconds: 350),
    Duration idleDisposeDelay = const Duration(minutes: 2),
    TwitchWebPlaybackLifecycle? lifecycle,
  }) : _platformAdapter = platformAdapter,
       _loadCookie = loadCookie,
       _timeout = timeout,
       _pollInterval = pollInterval,
       _bootstrapScriptTimeout = bootstrapScriptTimeout,
       _webViewStartTimeout = webViewStartTimeout,
       _webViewStartupRetryCount = webViewStartupRetryCount < 0
           ? 0
           : webViewStartupRetryCount,
       _webViewStartupRetryDelay = webViewStartupRetryDelay.isNegative
           ? Duration.zero
           : webViewStartupRetryDelay,
       _webViewRecreateCooldown = webViewRecreateCooldown.isNegative
           ? Duration.zero
           : webViewRecreateCooldown,
       _idleDisposeDelay = idleDisposeDelay {
    _lifecycle =
        lifecycle ??
        TwitchWebPlaybackLifecycle(
          idleDisposeDelay: idleDisposeDelay,
          onIdleDispose: _handleIdleDispose,
        );
  }

  static const String homeUrl = 'https://www.twitch.tv/';
  static const String mobileHomeUrl = 'https://m.twitch.tv/';
  static const String embeddedBrowserUserAgent =
      'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/146.0.0.0 Safari/537.36';
  static const String _clientId = 'kimne78kx3ncx6brgo4mv6wki5h1ko';
  static const String _integrityScriptUrl =
      'https://k.twitchcdn.net/149e9513-01fa-4fb0-aad4-566afd725d1b/'
      '2d206a39-8ed7-437e-a3be-862e0f06eea3/p.js';
  static const String _playbackAccessTokenQuery =
      'query PlaybackAccessToken_Template('
      r'$login: String!, $isLive: Boolean!, $vodID: ID!, $isVod: Boolean!, '
      r'$playerType: String!, $platform: String!) {'
      '  streamPlaybackAccessToken('
      'channelName: \$login, '
      'params: {platform: \$platform, playerBackend: "mediaplayer", '
      'playerType: \$playerType}'
      '  ) @include(if: \$isLive) {'
      '    value'
      '    signature'
      '    authorization { isForbidden forbiddenReasonCode }'
      '    __typename'
      '  }'
      '  videoPlaybackAccessToken('
      'id: \$vodID, '
      'params: {platform: \$platform, playerBackend: "mediaplayer", '
      'playerType: \$playerType}'
      '  ) @include(if: \$isVod) {'
      '    value'
      '    signature'
      '    __typename'
      '  }'
      '}';
  static const String _bootstrapScript = r'''
return await (async () => {
  const bootstrapKey = `${args.roomId}::${args.pageUrl}`;
  const existingState = window.__noliveTwitchBootstrapState;
  if (existingState?.key !== bootstrapKey || !existingState?.promise) {
    window.__noliveTwitchBootstrapState = {
      key: bootstrapKey,
      promise: (async () => {
        const roomId = args.roomId;
        const pageUrl = args.pageUrl;
        const clientId = args.clientId;
        const integrityScriptUrl = args.integrityScriptUrl;
        const playbackQuery = args.playbackQuery;

        function parseCookieMap(rawCookie) {
          const result = {};
          if (!rawCookie) {
            return result;
          }
          for (const segment of rawCookie.split(';')) {
            const normalized = segment.trim();
            if (!normalized) {
              continue;
            }
            const separator = normalized.indexOf('=');
            if (separator <= 0) {
              continue;
            }
            const key = normalized.slice(0, separator).trim();
            const value = normalized.slice(separator + 1).trim();
            if (!key || !value) {
              continue;
            }
            result[key] = value;
          }
          return result;
        }

        function randomHex(length) {
          const bytes = new Uint8Array(Math.ceil(length / 2));
          crypto.getRandomValues(bytes);
          return Array.from(bytes, (byte) => byte.toString(16).padStart(2, '0'))
              .join('')
              .slice(0, length);
        }

        async function requestPlaybackToken(deviceId, clientSessionId, clientIntegrity) {
          const cookieMap = parseCookieMap(document.cookie);
          const headers = {
            'Client-ID': clientId,
            'Content-Type': 'text/plain; charset=UTF-8',
            'Accept': '*/*',
            'Device-ID': deviceId,
            'X-Device-Id': deviceId,
            'Client-Session-Id': clientSessionId
          };
          if (cookieMap['auth-token']) {
            headers['Authorization'] = `OAuth ${cookieMap['auth-token']}`;
          }
          if (clientIntegrity) {
            headers['Client-Integrity'] = clientIntegrity;
          }

          const response = await window.fetch('https://gql.twitch.tv/gql', {
            method: 'POST',
            mode: 'cors',
            credentials: 'omit',
            headers,
            body: JSON.stringify({
              operationName: 'PlaybackAccessToken_Template',
              query: playbackQuery,
              variables: {
                isLive: true,
                login: roomId,
                isVod: false,
                vodID: '',
                playerType: 'popout',
                platform: 'web'
              }
            })
          });

          let payload = null;
          try {
            payload = await response.json();
          } catch (_) {
            payload = null;
          }
          return {
            status: response.status,
            payload
          };
        }

        async function requestIntegrity(deviceId) {
          const cookieMap = parseCookieMap(document.cookie);
          const baseHeaders = {
            'Client-ID': clientId,
            'x-device-id': deviceId
          };
          if (cookieMap['auth-token']) {
            baseHeaders['Authorization'] = `OAuth ${cookieMap['auth-token']}`;
          }

          async function fetchIntegrity() {
            const response = await window.fetch('https://gql.twitch.tv/integrity', {
              method: 'POST',
              mode: 'cors',
              credentials: 'omit',
              headers: baseHeaders,
              body: null
            });
            if (response.status !== 200) {
              throw new Error(`Unexpected integrity response status code ${response.status}`);
            }
            return await response.json();
          }

          if (window.KPSDK && typeof window.KPSDK.configure === 'function') {
            window.KPSDK.configure([{
              protocol: 'https:',
              method: 'POST',
              domain: 'gql.twitch.tv',
              path: '/integrity'
            }]);
            return await fetchIntegrity();
          }

          return await new Promise((resolve, reject) => {
            const onLoad = () => {
              try {
                window.KPSDK.configure([{
                  protocol: 'https:',
                  method: 'POST',
                  domain: 'gql.twitch.tv',
                  path: '/integrity'
                }]);
              } catch (error) {
                reject(error);
              }
            };
            const onReady = () => {
              fetchIntegrity().then(resolve, reject);
            };
            document.addEventListener('kpsdk-load', onLoad, {once: true});
            document.addEventListener('kpsdk-ready', onReady, {once: true});
            const existingScript = document.querySelector(
              'script[data-nolive-twitch-integrity="1"]',
            );
            if (existingScript) {
              return;
            }
            const script = document.createElement('script');
            script.setAttribute('data-nolive-twitch-integrity', '1');
            script.addEventListener('error', reject, {once: true});
            script.src = integrityScriptUrl;
            (document.body || document.documentElement).appendChild(script);
          });
        }

        const cookieMap = parseCookieMap(document.cookie);
        const deviceId = cookieMap['unique_id'] || randomHex(32);
        const clientSessionId = randomHex(32);

        let clientIntegrity = '';
        let tokenResponse = await requestPlaybackToken(deviceId, clientSessionId, '');
        let tokenNode = tokenResponse?.payload?.data?.streamPlaybackAccessToken || null;
        let signature = tokenNode?.signature || '';
        let tokenValue = tokenNode?.value || '';
        let forbiddenReason =
            tokenNode?.authorization?.isForbidden ? (tokenNode?.authorization?.forbiddenReasonCode || '') : '';

        if (!signature || !tokenValue || forbiddenReason) {
          const integrityPayload = await requestIntegrity(deviceId);
          clientIntegrity = integrityPayload?.token || '';
          if (clientIntegrity) {
            tokenResponse = await requestPlaybackToken(deviceId, clientSessionId, clientIntegrity);
            tokenNode = tokenResponse?.payload?.data?.streamPlaybackAccessToken || null;
            signature = tokenNode?.signature || '';
            tokenValue = tokenNode?.value || '';
            forbiddenReason =
                tokenNode?.authorization?.isForbidden ? (tokenNode?.authorization?.forbiddenReasonCode || '') : '';
          }
        }

        return {
          roomId,
          sourceUrl: pageUrl,
          userAgent: navigator.userAgent || '',
          deviceId,
          clientSessionId,
          clientIntegrity,
          signature,
          tokenValue,
          forbiddenReason
        };
      })().catch((error) => {
        if (window.__noliveTwitchBootstrapState?.key === bootstrapKey) {
          window.__noliveTwitchBootstrapState = null;
        }
        throw error;
      })
    };
  }
  return await window.__noliveTwitchBootstrapState.promise;
})();
''';

  final HlsProxyPlatformAdapter _platformAdapter;
  final Future<String> Function()? _loadCookie;
  final Duration _timeout;
  final Duration _pollInterval;
  final Duration _bootstrapScriptTimeout;
  final Duration _webViewStartTimeout;
  final int _webViewStartupRetryCount;
  final Duration _webViewStartupRetryDelay;
  final Duration _webViewRecreateCooldown;
  final Duration _idleDisposeDelay;
  late final TwitchWebPlaybackLifecycle _lifecycle;
  HlsHeadlessWebView? _headlessWebView;
  Future<HlsHeadlessWebView>? _headlessWebViewFuture;
  Future<void> _operationChain = Future<void>.value();
  DateTime? _lastWebViewDisposeAt;

  /// Overall bound for one bootstrap attempt (start + poll + script).
  Duration get operationTimeout =>
      _webViewStartTimeout + _timeout + _bootstrapScriptTimeout;

  Future<void> warmUp() async {
    if (!_supportsPlatform) {
      return;
    }
    return _runSerialized(() async {
      final leaseEpoch = _lifecycle.beginUse();
      await _seedCookiesFromSettings();
      try {
        _platformAdapter.log('twitch-bridge', 'warmUp start');
        await _ensureWebView().timeout(_webViewStartTimeout);
      } catch (error, stackTrace) {
        _platformAdapter.debugPrint(
          'TwitchWebPlaybackBridge warmUp failed: $error',
        );
        _platformAdapter.log(
          'twitch-bridge',
          'warmUp failed',
          error,
          stackTrace,
        );
        await _disposeHeadlessWebView();
      } finally {
        _lifecycle.endUse(leaseEpoch, idleReason: 'warmup idle');
      }
    });
  }

  Future<TwitchPlaybackBootstrap?> call(LiveRoomDetail detail) async {
    if (detail.providerId != ProviderId.twitch ||
        !detail.isLive ||
        !_supportsPlatform) {
      return null;
    }
    final roomId = detail.roomId.trim().toLowerCase();
    if (roomId.isEmpty) {
      return null;
    }

    return _runSerialized(() async {
      final leaseEpoch = _lifecycle.beginUse();
      await _seedCookiesFromSettings();

      final sourceUrl = detail.sourceUrl?.trim().isNotEmpty == true
          ? detail.sourceUrl!.trim()
          : _buildRoomUrl(roomId);

      try {
        return await _bootstrapWithBounds(
          roomId: roomId,
          sourceUrl: sourceUrl,
        ).timeout(operationTimeout);
      } on TimeoutException catch (error, stackTrace) {
        _platformAdapter.debugPrint(
          'TwitchWebPlaybackBridge bootstrap timed out: $error',
        );
        _platformAdapter.log(
          'twitch-bridge',
          'bootstrap timed out; fail-soft to direct GraphQL',
          error,
          stackTrace,
        );
        await _disposeHeadlessWebView();
        return null;
      } catch (error, stackTrace) {
        _platformAdapter.debugPrint(
          'TwitchWebPlaybackBridge fallback to direct GraphQL: $error',
        );
        _platformAdapter.log(
          'twitch-bridge',
          'fallback to direct GraphQL',
          error,
          stackTrace,
        );
        await _disposeHeadlessWebView();
        return null;
      } finally {
        _lifecycle.endUse(leaseEpoch, idleReason: 'bootstrap request settled');
      }
    });
  }

  Future<TwitchPlaybackBootstrap?> _bootstrapWithBounds({
    required String roomId,
    required String sourceUrl,
  }) async {
    _platformAdapter.log(
      'twitch-bridge',
      'bootstrap request room=$roomId source=$sourceUrl',
    );
    final webView = await _ensureWebView();
    final bootstrap = await _waitForPlaybackBootstrap(
      webView: webView,
      roomId: roomId,
      sourceUrl: sourceUrl,
    );
    if (bootstrap == null || !bootstrap.isUsable) {
      return null;
    }
    final cookieHeader = await _collectCookieHeader(roomUrl: sourceUrl);
    return TwitchPlaybackBootstrap(
      roomId: bootstrap.roomId,
      signature: bootstrap.signature,
      tokenValue: bootstrap.tokenValue,
      deviceId: bootstrap.deviceId,
      clientSessionId: bootstrap.clientSessionId,
      clientIntegrity: bootstrap.clientIntegrity,
      sourceUrl: bootstrap.sourceUrl.isNotEmpty
          ? bootstrap.sourceUrl
          : sourceUrl,
      cookie: cookieHeader,
      userAgent: bootstrap.userAgent.isNotEmpty
          ? bootstrap.userAgent
          : embeddedBrowserUserAgent,
    );
  }

  Future<HlsHeadlessWebView> _ensureWebView() async {
    final existing = _headlessWebViewFuture;
    if (existing != null) {
      return existing;
    }

    final future = _createHeadlessWebViewWithStartupRetries();
    _headlessWebViewFuture = future;
    try {
      return await future;
    } catch (_) {
      // Clear only if this future is still the active one (avoid racing a
      // concurrent re-ensure after dispose).
      if (identical(_headlessWebViewFuture, future)) {
        await _disposeHeadlessWebView();
      }
      rethrow;
    }
  }

  /// Create + run headless WebView with CB-style cold-start recreate retries.
  ///
  /// Android/WebView packages often throw `Must be started before we block`
  /// from `addDocumentStartJavaScript` on the first (or post-dispose) start.
  /// Retries dispose the failed instance, wait [webViewStartupRetryDelay], then
  /// open a fresh HeadlessInAppWebView. Non-transient errors (timeouts, etc.)
  /// do not retry so hang/timeout tests stay bounded.
  Future<HlsHeadlessWebView> _createHeadlessWebViewWithStartupRetries() async {
    final maxAttempts = _webViewStartupRetryCount + 1;
    Object? lastError;
    StackTrace? lastStackTrace;

    for (var attempt = 1; attempt <= maxAttempts; attempt += 1) {
      HlsHeadlessWebView? webView;
      try {
        await _waitForWebViewRecreateCooldown();
        _platformAdapter.log(
          'twitch-bridge',
          'create headless webview attempt=$attempt/$maxAttempts',
        );
        webView = await _platformAdapter
            .createHeadlessWebView(
              initialUrl: homeUrl,
              userAgent: embeddedBrowserUserAgent,
              desktopMode: true,
            )
            .timeout(_webViewStartTimeout);
        _headlessWebView = webView;
        await webView.run().timeout(_webViewStartTimeout);
        await _waitUntilDocumentReady(webView);
        return webView;
      } catch (error, stackTrace) {
        lastError = error;
        lastStackTrace = stackTrace;
        final canRetry =
            attempt < maxAttempts &&
            _looksLikeTransientWebViewStartupFailure(error);
        _platformAdapter.log(
          'twitch-bridge',
          canRetry
              ? 'startup transient failure attempt=$attempt/$maxAttempts '
                    'retryDelayMs=${_webViewStartupRetryDelay.inMilliseconds} '
                    'error=${_summarizeError(error)}'
              : 'startup failed attempt=$attempt/$maxAttempts '
                    'error=${_summarizeError(error)}',
          error,
          stackTrace,
        );
        // Drop the failed instance without clearing [_headlessWebViewFuture]
        // so concurrent callers keep awaiting this retry loop.
        await _disposeFailedStartupWebView(webView);
        if (!canRetry) {
          break;
        }
        if (_webViewStartupRetryDelay > Duration.zero) {
          await Future<void>.delayed(_webViewStartupRetryDelay);
        }
      }
    }

    Error.throwWithStackTrace(
      lastError ??
          StateError('Twitch headless webview startup failed without error'),
      lastStackTrace ?? StackTrace.current,
    );
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

  /// Dispose a failed create/run instance mid-retry without clearing the
  /// in-flight [_headlessWebViewFuture].
  Future<void> _disposeFailedStartupWebView(HlsHeadlessWebView? webView) async {
    final instance = webView ?? _headlessWebView;
    _headlessWebView = null;
    if (instance == null) {
      return;
    }
    try {
      await instance.dispose().timeout(const Duration(seconds: 5));
    } catch (error, stackTrace) {
      _platformAdapter.log(
        'twitch-bridge',
        'dispose failed startup webview (ignored)',
        error,
        stackTrace,
      );
    } finally {
      _lastWebViewDisposeAt = DateTime.now();
    }
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

  /// Release headless WebView pressure after leaving a room (or on demand).
  ///
  /// When no bootstrap is in-flight, disposes immediately; otherwise schedules
  /// idle dispose once the active lease ends.
  Future<void> releasePressure({String reason = 'room left'}) {
    return _runSerialized(() async {
      if (_lifecycle.activeUseCount > 0) {
        _platformAdapter.log(
          'twitch-bridge',
          'releasePressure deferred (active=${_lifecycle.activeUseCount}) '
          'reason=$reason',
        );
        return;
      }
      _platformAdapter.log('twitch-bridge', 'releasePressure reason=$reason');
      await _disposeHeadlessWebView();
    });
  }

  Future<void> _waitUntilDocumentReady(
    HlsHeadlessWebView webView,
  ) async {
    final deadline = DateTime.now().add(_timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (await _isDocumentReady(webView)) {
        return;
      }
      await Future<void>.delayed(_pollInterval);
    }
    throw TimeoutException(
      'Twitch web playback bridge document readiness timed out.',
    );
  }

  Future<void> _disposeHeadlessWebView() async {
    _lifecycle.invalidate();
    final headlessWebView = _headlessWebView;
    _headlessWebView = null;
    _headlessWebViewFuture = null;
    if (headlessWebView == null) {
      return;
    }
    _platformAdapter.log('twitch-bridge', 'dispose headless webview');
    try {
      await headlessWebView.dispose().timeout(const Duration(seconds: 5));
    } catch (error, stackTrace) {
      // Never let WebView teardown take down the process; bridges are fail-soft.
      _platformAdapter.debugPrint(
        'TwitchWebPlaybackBridge dispose failed: $error',
      );
      _platformAdapter.log(
        'twitch-bridge',
        'dispose headless webview failed (ignored)',
        error,
        stackTrace,
      );
    } finally {
      _lastWebViewDisposeAt = DateTime.now();
    }
  }

  Future<void> dispose() async {
    _lifecycle.dispose();
    await _disposeHeadlessWebView();
  }

  Future<void> _handleIdleDispose(String reason) async {
    if (!_supportsPlatform) {
      return;
    }
    _platformAdapter.log(
      'twitch-bridge',
      'idle dispose reason=$reason delay=${_idleDisposeDelay.inSeconds}s',
    );
    await _disposeHeadlessWebView();
  }

  Future<void> _seedCookiesFromSettings() async {
    final rawCookie = await _loadCookie?.call() ?? '';
    final normalized = rawCookie.trim();
    if (normalized.isEmpty) {
      return;
    }

    final seenNames = <String>{};
    for (final entry in _parseCookieHeader(normalized)) {
      if (!seenNames.add(entry.key)) {
        continue;
      }
      await _platformAdapter.cookieManager.setCookie(
        url: homeUrl,
        name: entry.key,
        value: entry.value,
        domain: '.twitch.tv',
        path: '/',
        isSecure: true,
      );
      await _platformAdapter.cookieManager.setCookie(
        url: mobileHomeUrl,
        name: entry.key,
        value: entry.value,
        domain: '.twitch.tv',
        path: '/',
        isSecure: true,
      );
    }
  }

  Future<TwitchPlaybackBootstrap?> _waitForPlaybackBootstrap({
    required HlsHeadlessWebView webView,
    required String roomId,
    required String sourceUrl,
  }) async {
    final deadline = DateTime.now().add(_timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (!await _isDocumentReady(webView)) {
        await Future<void>.delayed(_pollInterval);
        continue;
      }
      final bootstrap =
          await _resolveBootstrap(
            webView: webView,
            roomId: roomId,
            sourceUrl: sourceUrl,
          ).timeout(
            _bootstrapScriptTimeout,
            onTimeout: () {
              _platformAdapter.debugPrint('Twitch web playback bootstrap script timed out.');
              return null;
            },
          );
      if (bootstrap?.isUsable == true) {
        return bootstrap;
      }
      await Future<void>.delayed(_pollInterval);
    }
    return null;
  }

  Future<TwitchPlaybackBootstrap?> _resolveBootstrap({
    required HlsHeadlessWebView webView,
    required String roomId,
    required String sourceUrl,
  }) async {
    final result = await webView.callAsyncJavaScript(
      functionBody: _bootstrapScript,
      arguments: {
        'roomId': roomId,
        'pageUrl': sourceUrl,
        'clientId': _clientId,
        'integrityScriptUrl': _integrityScriptUrl,
        'playbackQuery': _playbackAccessTokenQuery,
      },
    );
    if (result == null || result.error != null || result.value == null) {
      return null;
    }
    final rawMap = _asMap(result.value);
    final errorMessage = rawMap['errorMessage']?.toString().trim() ?? '';
    if (errorMessage.isNotEmpty) {
      _platformAdapter.debugPrint('Twitch web playback bootstrap returned error: $errorMessage');
      return null;
    }
    final forbiddenReason = rawMap['forbiddenReason']?.toString().trim() ?? '';
    if (forbiddenReason.isNotEmpty) {
      _platformAdapter.debugPrint('Twitch web playback forbidden: $forbiddenReason');
    }
    final signature = rawMap['signature']?.toString().trim() ?? '';
    final tokenValue = rawMap['tokenValue']?.toString().trim() ?? '';
    if (signature.isEmpty || tokenValue.isEmpty) {
      return null;
    }
    return TwitchPlaybackBootstrap(
      roomId: rawMap['roomId']?.toString().trim() ?? roomId,
      signature: signature,
      tokenValue: tokenValue,
      deviceId: rawMap['deviceId']?.toString().trim() ?? '',
      clientSessionId: rawMap['clientSessionId']?.toString().trim() ?? '',
      clientIntegrity: rawMap['clientIntegrity']?.toString().trim() ?? '',
      sourceUrl: rawMap['sourceUrl']?.toString().trim() ?? sourceUrl,
      userAgent: rawMap['userAgent']?.toString().trim() ?? '',
    );
  }

  Future<String> _collectCookieHeader({required String roomUrl}) async {
    final cookieMap = <String, String>{};
    for (final url in {homeUrl, mobileHomeUrl, roomUrl}) {
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
      final normalized = segment.trim();
      if (normalized.isEmpty) {
        continue;
      }
      final separatorIndex = normalized.indexOf('=');
      if (separatorIndex <= 0) {
        continue;
      }
      final name = normalized.substring(0, separatorIndex).trim();
      final value = normalized.substring(separatorIndex + 1).trim();
      if (name.isEmpty ||
          value.isEmpty ||
          ignoredAttributes.contains(name.toLowerCase())) {
        continue;
      }
      yield MapEntry(name, value);
    }
  }

  Future<bool> _isDocumentReady(HlsHeadlessWebView webView) async {
    try {
      final readyState = await webView.evaluateJavascript(
        source: 'document.readyState',
      );
      final normalized = readyState?.toString().replaceAll('"', '').trim();
      return normalized == 'complete' || normalized == 'interactive';
    } catch (_) {
      return false;
    }
  }

  Map<String, dynamic> _asMap(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.cast<String, dynamic>();
    }
    if (value is String && value.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
        if (decoded is Map) {
          return decoded.cast<String, dynamic>();
        }
      } catch (_) {
        return const {};
      }
    }
    return const {};
  }

  String _buildRoomUrl(String roomId) => 'https://www.twitch.tv/$roomId';

  bool get _supportsPlatform {
    return _platformAdapter.supportsHeadlessWebView;
  }
}
