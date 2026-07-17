import 'dart:async';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' as foundation;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:live_hls_proxy/live_hls_proxy.dart';
import 'package:nolive_app/src/app/platform/app_platform_capabilities.dart';
import 'package:nolive_app/src/app/runtime_bridges/linux_desktop_webview_adapter.dart';
import 'package:nolive_app/src/shared/application/app_log.dart';

/// Shared Linux cookie jar for headless bridges + web login (process-wide).
final LinuxDesktopCookieJar linuxDesktopCookieJar = LinuxDesktopCookieJar();

class HlsProxyPlatformAdapterImpl implements HlsProxyPlatformAdapter {
  HlsProxyPlatformAdapterImpl({
    AppPlatformCapabilities? platformCapabilities,
    CookieManager? cookieManager,
    LinuxDesktopCookieJar? linuxCookieJar,
  }) : _platformCapabilities =
           platformCapabilities ?? AppPlatformCapabilities.current(),
       _cookieManagerOverride = cookieManager,
       _linuxCookieJar = linuxCookieJar ?? linuxDesktopCookieJar;

  final AppPlatformCapabilities _platformCapabilities;
  final CookieManager? _cookieManagerOverride;
  CookieManager? _cookieManagerLazy;
  final LinuxDesktopCookieJar _linuxCookieJar;

  CookieManager get _cookieManager =>
      _cookieManagerOverride ??
      (_cookieManagerLazy ??= CookieManager.instance());

  @override
  bool get isMobile => _platformCapabilities.isMobile;

  @override
  bool get supportsHeadlessWebView =>
      _platformCapabilities.supportsHeadlessWebView;

  @override
  bool get kDebugMode => foundation.kDebugMode;

  @override
  void log(
    String tag,
    String message, [
    Object? error,
    StackTrace? stackTrace,
  ]) {
    if (error != null) {
      AppLog.instance.error(tag, message, error: error, stackTrace: stackTrace);
    } else {
      AppLog.instance.info(tag, message);
    }
  }

  @override
  void debugPrint(String message) {
    foundation.debugPrint(message);
  }

  bool get _useLinuxDesktopWebView =>
      !foundation.kIsWeb &&
      Platform.isLinux &&
      _platformCapabilities.supportsHeadlessWebView;

  @override
  HlsProxyCookieManager get cookieManager {
    if (_useLinuxDesktopWebView) {
      return _linuxCookieJar;
    }
    return _HlsProxyCookieManagerImpl(_cookieManager);
  }

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
    if (_useLinuxDesktopWebView) {
      return LinuxDesktopHeadlessWebView(
        initialUrl: initialUrl,
        userAgent: userAgent,
        desktopMode: desktopMode,
        cookieJar: _linuxCookieJar,
        shouldBlockRequest: shouldBlockRequest,
        onConsoleMessage: onConsoleMessage,
        onHttpError: onHttpError,
        onLoadError: onLoadError,
      );
    }
    return _HlsHeadlessWebViewImpl(
      initialUrl: initialUrl,
      userAgent: userAgent,
      desktopMode: desktopMode,
      shouldBlockRequest: shouldBlockRequest,
      onConsoleMessage: onConsoleMessage,
      onHttpError: onHttpError,
      onLoadError: onLoadError,
    );
  }
}

class _HlsProxyCookieManagerImpl implements HlsProxyCookieManager {
  _HlsProxyCookieManagerImpl(this._cookieManager);
  final CookieManager _cookieManager;

  @override
  Future<void> setCookie({
    required String url,
    required String name,
    required String value,
    required String domain,
    required String path,
    bool isSecure = true,
  }) async {
    await _cookieManager.setCookie(
      url: WebUri(url),
      name: name,
      value: value,
      domain: domain,
      path: path,
      isSecure: isSecure,
      sameSite: HTTPCookieSameSitePolicy.NONE,
    );
  }

  @override
  Future<List<HlsProxyCookie>> getCookies({required String url}) async {
    final cookies = await _cookieManager.getCookies(url: WebUri(url));
    return cookies.map((c) => HlsProxyCookie(c.name, c.value ?? '')).toList();
  }
}

class _HlsHeadlessWebViewImpl implements HlsHeadlessWebView {
  _HlsHeadlessWebViewImpl({
    required String initialUrl,
    required String userAgent,
    required bool desktopMode,
    this.shouldBlockRequest,
    this.onConsoleMessage,
    this.onHttpError,
    this.onLoadError,
  }) : _headlessWebView = HeadlessInAppWebView(
         initialUrlRequest: URLRequest(url: WebUri(initialUrl)),
         initialSettings: _buildHlsHeadlessWebViewSettings(
           userAgent: userAgent,
           desktopMode: desktopMode,
           interceptRequests: shouldBlockRequest != null,
         ),
         onConsoleMessage: onConsoleMessage != null
             ? (controller, message) => onConsoleMessage(message.message)
             : null,
         onReceivedHttpError: onHttpError != null
             ? (controller, request, errorResponse) => onHttpError(
                 errorResponse.statusCode ?? 0,
                 request.url.toString(),
               )
             : null,
         onReceivedError: onLoadError != null
             ? (controller, request, error) =>
                   onLoadError(error.description, request.url.toString())
             : null,
         shouldInterceptRequest: shouldBlockRequest != null
             ? (controller, request) async {
                 final url = request.url.toString();
                 if (!shouldBlockRequest(url)) {
                   return null;
                 }
                 return WebResourceResponse(
                   contentType: 'text/plain',
                   contentEncoding: 'utf-8',
                   data: Uint8List(0),
                   statusCode: 204,
                   reasonPhrase: 'No Content',
                   headers: const <String, String>{},
                 );
               }
             : null,
       );

  final HeadlessInAppWebView _headlessWebView;
  final HlsWebViewResourceBlocker? shouldBlockRequest;
  final void Function(String message)? onConsoleMessage;
  final void Function(int statusCode, String url)? onHttpError;
  final void Function(String description, String url)? onLoadError;

  @override
  Future<void> run() async {
    await _headlessWebView.run();
  }

  @override
  Future<void> dispose() async {
    await _headlessWebView.dispose();
  }

  @override
  Future<String?> getUrl() async {
    final uri = await _headlessWebView.webViewController?.getUrl();
    return uri?.toString();
  }

  @override
  Future<String?> getHtml() async {
    return await _headlessWebView.webViewController?.getHtml();
  }

  @override
  Future<Object?> evaluateJavascript({required String source}) async {
    final controller = _headlessWebView.webViewController;
    if (controller == null) return null;
    return await controller.evaluateJavascript(source: source);
  }

  @override
  Future<HlsJavaScriptResult?> callAsyncJavaScript({
    required String functionBody,
    required Map<String, dynamic> arguments,
  }) async {
    final controller = _headlessWebView.webViewController;
    if (controller == null) return null;
    final result = await controller.callAsyncJavaScript(
      functionBody: functionBody,
      arguments: arguments,
    );
    if (result == null) return null;
    return HlsJavaScriptResult(value: result.value, error: result.error);
  }
}

InAppWebViewSettings _buildHlsHeadlessWebViewSettings({
  required String userAgent,
  required bool desktopMode,
  required bool interceptRequests,
}) {
  return InAppWebViewSettings(
    isInspectable: foundation.kDebugMode,
    userAgent: userAgent,
    mediaPlaybackRequiresUserGesture: true,
    javaScriptCanOpenWindowsAutomatically: false,
    supportMultipleWindows: false,
    thirdPartyCookiesEnabled: true,
    sharedCookiesEnabled: true,
    allowsInlineMediaPlayback: false,
    supportZoom: false,
    builtInZoomControls: false,
    displayZoomControls: false,
    useWideViewPort: true,
    loadWithOverviewMode: false,
    databaseEnabled: false,
    domStorageEnabled: true,
    cacheEnabled: true,
    clearSessionCache: false,
    loadsImagesAutomatically: false,
    blockNetworkImage: true,
    disableContextMenu: true,
    disableHorizontalScroll: true,
    disableVerticalScroll: true,
    horizontalScrollBarEnabled: false,
    verticalScrollBarEnabled: false,
    offscreenPreRaster: false,
    useShouldInterceptAjaxRequest: false,
    useShouldInterceptFetchRequest: false,
    useShouldInterceptRequest: interceptRequests,
    mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
    useHybridComposition: true,
    preferredContentMode: desktopMode
        ? UserPreferredContentMode.DESKTOP
        : UserPreferredContentMode.RECOMMENDED,
  );
}

@foundation.visibleForTesting
InAppWebViewSettings buildHlsHeadlessWebViewSettingsForTesting({
  required String userAgent,
  bool desktopMode = false,
  bool interceptRequests = false,
}) {
  return _buildHlsHeadlessWebViewSettings(
    userAgent: userAgent,
    desktopMode: desktopMode,
    interceptRequests: interceptRequests,
  );
}
