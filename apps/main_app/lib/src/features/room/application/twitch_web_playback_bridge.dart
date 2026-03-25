import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:live_core/live_core.dart';
import 'package:live_providers/live_providers.dart';
import 'package:nolive_app/src/features/settings/application/manage_provider_accounts_use_case.dart';

class TwitchWebPlaybackBridge {
  TwitchWebPlaybackBridge({
    LoadProviderAccountSettingsUseCase? loadProviderAccountSettings,
    CookieManager? cookieManager,
    Duration timeout = const Duration(seconds: 18),
    Duration pollInterval = const Duration(milliseconds: 500),
    Duration bootstrapScriptTimeout = const Duration(seconds: 4),
  })  : _loadProviderAccountSettings = loadProviderAccountSettings,
        _cookieManager = cookieManager ?? CookieManager.instance(),
        _timeout = timeout,
        _pollInterval = pollInterval,
        _bootstrapScriptTimeout = bootstrapScriptTimeout;

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

  final LoadProviderAccountSettingsUseCase? _loadProviderAccountSettings;
  final CookieManager _cookieManager;
  final Duration _timeout;
  final Duration _pollInterval;
  final Duration _bootstrapScriptTimeout;
  HeadlessInAppWebView? _headlessWebView;
  Future<InAppWebViewController>? _controllerFuture;

  Future<void> warmUp() async {
    if (!_supportsPlatform) {
      return;
    }
    await _seedCookiesFromSettings();
    try {
      await _ensureController();
    } catch (error, stackTrace) {
      debugPrint('TwitchWebPlaybackBridge warmUp failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      await _disposeHeadlessWebView();
    }
  }

  Future<TwitchPlaybackBootstrap?> call(LiveRoomDetail detail) async {
    if (detail.providerId != ProviderId.twitch.value ||
        !detail.isLive ||
        !_supportsPlatform) {
      return null;
    }
    final roomId = detail.roomId.trim().toLowerCase();
    if (roomId.isEmpty) {
      return null;
    }

    await _seedCookiesFromSettings();

    final sourceUrl = detail.sourceUrl?.trim().isNotEmpty == true
        ? detail.sourceUrl!.trim()
        : _buildRoomUrl(roomId);

    try {
      final controller = await _ensureController();
      final bootstrap = await _waitForPlaybackBootstrap(
        controller: controller,
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
        sourceUrl:
            bootstrap.sourceUrl.isNotEmpty ? bootstrap.sourceUrl : sourceUrl,
        cookie: cookieHeader,
        userAgent: bootstrap.userAgent.isNotEmpty
            ? bootstrap.userAgent
            : embeddedBrowserUserAgent,
      );
    } catch (error, stackTrace) {
      debugPrint('TwitchWebPlaybackBridge fallback to direct GraphQL: $error');
      debugPrintStack(stackTrace: stackTrace);
      await _disposeHeadlessWebView();
      return null;
    }
  }

  Future<InAppWebViewController> _ensureController() async {
    final existing = _controllerFuture;
    if (existing != null) {
      return existing;
    }

    final controllerCompleter = Completer<InAppWebViewController>();
    final headlessWebView = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(
        url: WebUri(homeUrl),
      ),
      initialSettings: InAppWebViewSettings(
        userAgent: embeddedBrowserUserAgent,
        mediaPlaybackRequiresUserGesture: true,
        javaScriptCanOpenWindowsAutomatically: true,
        supportMultipleWindows: true,
        thirdPartyCookiesEnabled: true,
        sharedCookiesEnabled: true,
        allowsInlineMediaPlayback: true,
        supportZoom: true,
        builtInZoomControls: true,
        displayZoomControls: false,
        useWideViewPort: true,
        loadWithOverviewMode: true,
        databaseEnabled: true,
        domStorageEnabled: true,
        cacheEnabled: true,
        clearSessionCache: false,
        mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
        useHybridComposition: true,
        preferredContentMode: UserPreferredContentMode.DESKTOP,
      ),
      onWebViewCreated: controllerCompleter.complete,
    );
    _headlessWebView = headlessWebView;
    final future = () async {
      await headlessWebView.run();
      final controller = await controllerCompleter.future.timeout(_timeout);
      await _waitUntilDocumentReady(controller);
      return controller;
    }();
    _controllerFuture = future;
    try {
      return await future;
    } catch (_) {
      await _disposeHeadlessWebView();
      rethrow;
    }
  }

  Future<void> _waitUntilDocumentReady(InAppWebViewController controller) async {
    final deadline = DateTime.now().add(_timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (await _isDocumentReady(controller)) {
        return;
      }
      await Future<void>.delayed(_pollInterval);
    }
    throw TimeoutException('Twitch web playback bridge document readiness timed out.');
  }

  Future<void> _disposeHeadlessWebView() async {
    final headlessWebView = _headlessWebView;
    _headlessWebView = null;
    _controllerFuture = null;
    if (headlessWebView != null) {
      await headlessWebView.dispose();
    }
  }

  Future<void> _seedCookiesFromSettings() async {
    final settings = await _loadProviderAccountSettings?.call();
    final rawCookie = settings?.twitchCookie.trim() ?? '';
    if (rawCookie.isEmpty) {
      return;
    }

    final seenNames = <String>{};
    for (final entry in _parseCookieHeader(rawCookie)) {
      if (!seenNames.add(entry.key)) {
        continue;
      }
      await _cookieManager.setCookie(
        url: WebUri(homeUrl),
        name: entry.key,
        value: entry.value,
        domain: '.twitch.tv',
        path: '/',
        isSecure: true,
        sameSite: HTTPCookieSameSitePolicy.NONE,
      );
      await _cookieManager.setCookie(
        url: WebUri(mobileHomeUrl),
        name: entry.key,
        value: entry.value,
        domain: '.twitch.tv',
        path: '/',
        isSecure: true,
        sameSite: HTTPCookieSameSitePolicy.NONE,
      );
    }
  }

  Future<TwitchPlaybackBootstrap?> _waitForPlaybackBootstrap({
    required InAppWebViewController controller,
    required String roomId,
    required String sourceUrl,
  }) async {
    final deadline = DateTime.now().add(_timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (!await _isDocumentReady(controller)) {
        await Future<void>.delayed(_pollInterval);
        continue;
      }
      final bootstrap = await _resolveBootstrap(
        controller: controller,
        roomId: roomId,
        sourceUrl: sourceUrl,
      ).timeout(
        _bootstrapScriptTimeout,
        onTimeout: () {
          debugPrint('Twitch web playback bootstrap script timed out.');
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
    required InAppWebViewController controller,
    required String roomId,
    required String sourceUrl,
  }) async {
    final result = await controller.callAsyncJavaScript(
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
      debugPrint('Twitch web playback bootstrap returned error: $errorMessage');
      return null;
    }
    final forbiddenReason = rawMap['forbiddenReason']?.toString().trim() ?? '';
    if (forbiddenReason.isNotEmpty) {
      debugPrint('Twitch web playback forbidden: $forbiddenReason');
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

  Future<String> _collectCookieHeader({
    required String roomUrl,
  }) async {
    final cookieMap = <String, String>{};
    for (final url in {homeUrl, mobileHomeUrl, roomUrl}) {
      final cookies = await _cookieManager.getCookies(url: WebUri(url));
      for (final cookie in cookies) {
        final name = cookie.name.trim();
        final value = cookie.value?.trim() ?? '';
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

  Future<bool> _isDocumentReady(InAppWebViewController controller) async {
    try {
      final readyState = await controller.evaluateJavascript(
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
    if (kIsWeb) {
      return false;
    }
    return Platform.isAndroid || Platform.isIOS;
  }
}
