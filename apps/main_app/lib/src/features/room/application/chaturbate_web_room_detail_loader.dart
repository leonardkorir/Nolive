import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:live_core/live_core.dart';
import 'package:live_providers/live_providers.dart';
import 'package:nolive_app/src/features/settings/application/manage_provider_accounts_use_case.dart';

class ChaturbateWebRoomDetailLoader {
  ChaturbateWebRoomDetailLoader({
    LoadProviderAccountSettingsUseCase? loadProviderAccountSettings,
    CookieManager? cookieManager,
    ChaturbateRoomPageParser roomPageParser = const ChaturbateRoomPageParser(),
    Duration timeout = const Duration(seconds: 18),
    Duration pollInterval = const Duration(milliseconds: 250),
    Duration realtimeBootstrapGracePeriod = const Duration(seconds: 4),
  })  : _loadProviderAccountSettings = loadProviderAccountSettings,
        _cookieManager = cookieManager ?? CookieManager.instance(),
        _roomPageParser = roomPageParser,
        _timeout = timeout,
        _pollInterval = pollInterval,
        _realtimeBootstrapGracePeriod = realtimeBootstrapGracePeriod;

  static const String homeUrl = 'https://chaturbate.com/';

  final LoadProviderAccountSettingsUseCase? _loadProviderAccountSettings;
  final CookieManager _cookieManager;
  final ChaturbateRoomPageParser _roomPageParser;
  final Duration _timeout;
  final Duration _pollInterval;
  final Duration _realtimeBootstrapGracePeriod;

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

    final controllerCompleter = Completer<InAppWebViewController>();
    final headlessWebView = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(
        url: WebUri(_buildRoomUrl(normalizedRoomId)),
      ),
      initialSettings: InAppWebViewSettings(
        userAgent: ChaturbateProvider.browserUserAgent,
        mediaPlaybackRequiresUserGesture: false,
        thirdPartyCookiesEnabled: true,
        sharedCookiesEnabled: true,
        allowsInlineMediaPlayback: true,
      ),
      onWebViewCreated: controllerCompleter.complete,
      onReceivedError: (controller, request, error) {
        if (controllerCompleter.isCompleted) {
          return;
        }
        controllerCompleter.completeError(
          ProviderParseException(
            providerId: ProviderId.chaturbate,
            message: 'Chaturbate 房间页加载失败：${error.description}',
          ),
        );
      },
    );

    try {
      await headlessWebView.run();
      final controller = await controllerCompleter.future.timeout(_timeout);
      final html = await _waitForRoomHtml(
        controller: controller,
        roomId: normalizedRoomId,
      );
      final cookieHeader = await _collectCookieHeader(
        roomUrl: _buildRoomUrl(normalizedRoomId),
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
        metadata: {
          ...?detail.metadata,
          'requestCookie': cookieHeader,
        },
      );
    } on ProviderParseException {
      rethrow;
    } on TimeoutException {
      throw ProviderParseException(
        providerId: ProviderId.chaturbate,
        message: 'Chaturbate 房间页加载超时，请先在账号管理重新完成网页登录后再试。',
      );
    } catch (error, stackTrace) {
      throw ProviderParseException(
        providerId: ProviderId.chaturbate,
        message: 'Chaturbate 房间页加载失败。',
        cause: error,
        stackTrace: stackTrace,
      );
    } finally {
      await headlessWebView.dispose();
    }
  }

  Future<void> _seedCookiesFromSettings() async {
    final settings = await _loadProviderAccountSettings?.call();
    final rawCookie = settings?.chaturbateCookie.trim() ?? '';
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
        domain: '.chaturbate.com',
        path: '/',
        isSecure: true,
        sameSite: HTTPCookieSameSitePolicy.NONE,
      );
    }
  }

  Future<String> _collectCookieHeader({
    required String roomUrl,
  }) async {
    final cookieMap = <String, String>{};
    for (final url in {homeUrl, roomUrl}) {
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
      String rawCookie) sync* {
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
    required InAppWebViewController controller,
    required String roomId,
  }) async {
    final deadline = DateTime.now().add(_timeout);
    String lastHtml = '';
    String lastUrl = '';
    String? dossierHtml;
    DateTime? dossierDetectedAt;
    while (DateTime.now().isBefore(deadline)) {
      lastUrl = (await controller.getUrl())?.toString() ?? lastUrl;
      lastHtml = (await controller.getHtml())?.trim() ?? '';
      final hasDossier = lastHtml.contains('window.initialRoomDossier');
      final hasRealtimeBootstrap =
          _roomPageParser.hasRealtimeBootstrap(lastHtml);
      if (hasDossier) {
        dossierHtml = lastHtml;
        dossierDetectedAt ??= DateTime.now();
      }
      if (hasDossier && hasRealtimeBootstrap) {
        return lastHtml;
      }
      if (hasDossier &&
          await _isDocumentComplete(controller) &&
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
          'Chaturbate 房间页没有返回可解析的 initialRoomDossier。当前地址：${lastUrl.isEmpty ? _buildRoomUrl(roomId) : lastUrl}',
    );
  }

  Future<bool> _isDocumentComplete(InAppWebViewController controller) async {
    try {
      final readyState = await controller.evaluateJavascript(
        source: 'document.readyState',
      );
      final normalized = readyState?.toString().replaceAll('"', '').trim();
      return normalized == 'complete';
    } catch (_) {
      return false;
    }
  }

  bool _looksLikeCloudflareChallenge(String html) {
    final normalized = html.toLowerCase();
    return normalized.contains('cf-challenge') ||
        normalized.contains('just a moment') ||
        normalized.contains('attention required') ||
        normalized.contains('cloudflare') ||
        normalized.contains('/cdn-cgi/challenge-platform/');
  }

  String _buildRoomUrl(String roomId) => 'https://chaturbate.com/$roomId/';

  bool get _supportsPlatform {
    if (kIsWeb) {
      return false;
    }
    return Platform.isAndroid || Platform.isIOS;
  }
}
