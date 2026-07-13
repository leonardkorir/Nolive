import 'dart:async';

typedef HlsWebViewResourceBlocker = bool Function(String url);

abstract class HlsProxyPlatformAdapter {
  bool get isMobile;
  bool get kDebugMode;
  void log(String tag, String message, [Object? error, StackTrace? stackTrace]);
  void debugPrint(String message);

  HlsProxyCookieManager get cookieManager;

  Future<HlsHeadlessWebView> createHeadlessWebView({
    required String initialUrl,
    required String userAgent,
    bool desktopMode = false,
    HlsWebViewResourceBlocker? shouldBlockRequest,
    void Function(String message)? onConsoleMessage,
    void Function(int statusCode, String url)? onHttpError,
    void Function(String description, String url)? onLoadError,
  });
}

abstract class HlsProxyCookieManager {
  Future<void> setCookie({
    required String url,
    required String name,
    required String value,
    required String domain,
    required String path,
    bool isSecure = true,
  });

  Future<List<HlsProxyCookie>> getCookies({required String url});
}

class HlsProxyCookie {
  HlsProxyCookie(this.name, this.value);
  final String name;
  final String value;
}

abstract class HlsHeadlessWebView {
  Future<void> run();
  Future<void> dispose();
  Future<String?> getUrl();
  Future<String?> getHtml();
  Future<Object?> evaluateJavascript({required String source});
  Future<HlsJavaScriptResult?> callAsyncJavaScript({
    required String functionBody,
    required Map<String, dynamic> arguments,
  });
}

class HlsJavaScriptResult {
  HlsJavaScriptResult({this.value, this.error});
  final Object? value;
  final String? error;
}
