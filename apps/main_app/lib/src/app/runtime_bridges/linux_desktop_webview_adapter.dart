import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:flutter/foundation.dart';
import 'package:live_hls_proxy/live_hls_proxy.dart';
import 'package:nolive_app/src/app/runtime_bridges/linux_async_js.dart';
import 'package:nolive_app/src/shared/application/app_log.dart';

/// Decide whether a navigation/resource URL may proceed under Linux WebView.
///
/// Returned to native DecidePolicy: `true` → use, `false` → ignore (block).
/// Extracted for unit tests; must stay identical to the headless adapter path.
@visibleForTesting
bool linuxAllowUrlRequest({
  required String url,
  required HlsWebViewResourceBlocker? shouldBlockRequest,
}) {
  if (shouldBlockRequest != null && shouldBlockRequest(url)) {
    return false;
  }
  return true;
}

/// Process-wide cookie jar used by Linux headless + login webviews.
///
/// `desktop_webview_window` does not expose a global cookie manager API
/// equivalent to InAppWebView's [CookieManager]. Bridges set cookies before
/// creating a headless view; we keep them here and inject via
/// `document.cookie` / `addScriptToExecuteOnDocumentCreated` on each view.
class LinuxDesktopCookieJar implements HlsProxyCookieManager {
  LinuxDesktopCookieJar();

  final Map<String, _StoredCookie> _cookies = <String, _StoredCookie>{};

  static String _key({
    required String name,
    required String domain,
    required String path,
  }) =>
      '$domain|$path|$name';

  @override
  Future<void> setCookie({
    required String url,
    required String name,
    required String value,
    required String domain,
    required String path,
    bool isSecure = true,
  }) async {
    final normalizedDomain = domain.startsWith('.') ? domain : '.$domain';
    _cookies[_key(name: name, domain: normalizedDomain, path: path)] =
        _StoredCookie(
          name: name,
          value: value,
          domain: normalizedDomain,
          path: path.isEmpty ? '/' : path,
          isSecure: isSecure,
        );
  }

  @override
  Future<List<HlsProxyCookie>> getCookies({required String url}) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return const <HlsProxyCookie>[];
    final host = uri.host.toLowerCase();
    final path = uri.path.isEmpty ? '/' : uri.path;
    final matches = <HlsProxyCookie>[];
    for (final cookie in _cookies.values) {
      if (!_domainMatches(host, cookie.domain)) continue;
      if (!path.startsWith(cookie.path)) continue;
      matches.add(HlsProxyCookie(cookie.name, cookie.value));
    }
    return matches;
  }

  /// Cookie assignment statements for document.cookie injection.
  List<String> documentCookieAssignments() {
    return _cookies.values.map((c) {
      final domain = c.domain.startsWith('.') ? c.domain : '.${c.domain}';
      final secure = c.isSecure ? '; Secure' : '';
      // SameSite=None requires Secure; used for cross-site playback domains.
      return "document.cookie=${jsonEncode('${c.name}=${c.value}; path=${c.path}; domain=$domain$secure; SameSite=None')}";
    }).toList(growable: false);
  }

  /// Merge cookies read from a live [Webview] into the jar.
  Future<void> mergeFromWebview(Webview webview) async {
    try {
      final all = await webview.getAllCookies();
      for (final cookie in all) {
        final domain = cookie.domain.startsWith('.')
            ? cookie.domain
            : '.${cookie.domain}';
        _cookies[_key(
              name: cookie.name,
              domain: domain,
              path: cookie.path.isEmpty ? '/' : cookie.path,
            )] =
            _StoredCookie(
              name: cookie.name,
              value: cookie.value,
              domain: domain,
              path: cookie.path.isEmpty ? '/' : cookie.path,
              isSecure: cookie.secure,
            );
      }
    } catch (error, stackTrace) {
      AppLog.instance.error(
        'linux/webview',
        'mergeFromWebview failed: $error',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// Export jar as `name=value; name2=value2` for account storage.
  String exportCookieHeader({List<String>? allowedHostSuffixes}) {
    final parts = <String>[];
    for (final cookie in _cookies.values) {
      if (allowedHostSuffixes != null && allowedHostSuffixes.isNotEmpty) {
        final domain = cookie.domain.toLowerCase().replaceFirst(
          RegExp(r'^\.'),
          '',
        );
        final ok = allowedHostSuffixes.any(
          (suffix) => domain == suffix || domain.endsWith('.$suffix'),
        );
        if (!ok) continue;
      }
      parts.add('${cookie.name}=${cookie.value}');
    }
    return parts.join('; ');
  }

  static bool _domainMatches(String host, String cookieDomain) {
    final domain = cookieDomain.startsWith('.')
        ? cookieDomain.substring(1).toLowerCase()
        : cookieDomain.toLowerCase();
    return host == domain || host.endsWith('.$domain');
  }
}

class _StoredCookie {
  const _StoredCookie({
    required this.name,
    required this.value,
    required this.domain,
    required this.path,
    required this.isSecure,
  });

  final String name;
  final String value;
  final String domain;
  final String path;
  final bool isSecure;
}

/// Headless WebView backed by WebKitGTK via `desktop_webview_window` (scheme B).
class LinuxDesktopHeadlessWebView implements HlsHeadlessWebView {
  LinuxDesktopHeadlessWebView({
    required this.initialUrl,
    required this.userAgent,
    required this.desktopMode,
    required LinuxDesktopCookieJar cookieJar,
    this.shouldBlockRequest,
    this.onConsoleMessage,
    this.onHttpError,
    this.onLoadError,
  }) : _cookieJar = cookieJar;

  final String initialUrl;
  final String userAgent;
  final bool desktopMode;
  final LinuxDesktopCookieJar _cookieJar;
  final HlsWebViewResourceBlocker? shouldBlockRequest;
  final void Function(String message)? onConsoleMessage;
  final void Function(int statusCode, String url)? onHttpError;
  final void Function(String description, String url)? onLoadError;

  Webview? _webview;
  String? _currentUrl;
  final Completer<void> _firstNavigation = Completer<void>();
  bool _disposed = false;

  @override
  Future<void> run() async {
    if (!Platform.isLinux) {
      throw UnsupportedError(
        'LinuxDesktopHeadlessWebView is only supported on Linux',
      );
    }
    final available = await WebviewWindow.isWebviewAvailable();
    if (!available) {
      throw StateError('WebView runtime unavailable on this Linux host');
    }

    // After mpv gpu-next external VO, X11/GLX destroy callbacks may still be
    // in flight. Creating WebKitGTK immediately races GLXBadWindow (process
    // exit). Brief settle before the first native webview window.
    await Future<void>.delayed(const Duration(milliseconds: 400));

    final webview = await WebviewWindow.create(
      configuration: const CreateConfiguration(
        windowWidth: 8,
        windowHeight: 8,
        title: 'nolive-headless',
        titleBarHeight: 0,
      ),
    );
    _webview = webview;

    // Keep off-screen / invisible for headless bridge work when supported.
    try {
      await webview.setWebviewWindowVisibility(false);
    } catch (error) {
      AppLog.instance.warn(
        'linux/webview',
        'setWebviewWindowVisibility failed (continuing headless): $error',
      );
    }

    if (userAgent.isNotEmpty) {
      // Package only supports appending an application name; inject full UA via JS.
      webview.addScriptToExecuteOnDocumentCreated(
        "Object.defineProperty(navigator, 'userAgent', {get: function() { return ${jsonEncode(userAgent)}; }});",
      );
    }

    for (final assignment in _cookieJar.documentCookieAssignments()) {
      webview.addScriptToExecuteOnDocumentCreated(assignment);
    }

    // Native DecidePolicy (vendored plugin) awaits this callback and calls
    // webkit_policy_decision_ignore when we return false.
    webview.setOnUrlRequestCallback((url) {
      final allow = linuxAllowUrlRequest(
        url: url,
        shouldBlockRequest: shouldBlockRequest,
      );
      if (allow) {
        _currentUrl = url;
      }
      return allow;
    });

    webview.launch(initialUrl);
    _currentUrl = initialUrl;

    // Wait briefly for first navigation; bridges also poll readiness.
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 400), () {
        if (!_firstNavigation.isCompleted) {
          _firstNavigation.complete();
        }
      }),
    );
    await _firstNavigation.future.timeout(
      const Duration(seconds: 8),
      onTimeout: () {},
    );

    // Re-apply cookies after load (document.cookie after navigation).
    await _injectCookies(webview);
  }

  Future<void> _injectCookies(Webview webview) async {
    final assignments = _cookieJar.documentCookieAssignments();
    if (assignments.isEmpty) return;
    final script = assignments.join(';');
    try {
      await webview.evaluateJavaScript(script);
    } catch (error) {
      AppLog.instance.warn('linux/webview', 'cookie inject failed: $error');
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final webview = _webview;
    _webview = null;
    if (webview == null) return;
    // Do NOT call getAllCookies/mergeFromWebview here: the Linux plugin uses a
    // nested GMainLoop that can deadlock Flutter's event loop. Cookies needed
    // for login export are pulled explicitly via LinuxDesktopWebLoginSession.
    // Hide before destroy to avoid a visible orphan window during teardown, and
    // yield so in-flight JS evaluation cannot hit a half-destroyed WebKit view
    // (Twitch idle dispose previously SIGSEGV'd here).
    try {
      await webview.setWebviewWindowVisibility(false);
    } catch (_) {}
    try {
      webview.close();
    } catch (error) {
      AppLog.instance.warn('linux/webview', 'dispose close failed: $error');
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }

  @override
  Future<String?> getUrl() async {
    if (_currentUrl != null) return _currentUrl;
    final result = await evaluateJavascript(source: 'location.href');
    return result?.toString();
  }

  @override
  Future<String?> getHtml() async {
    final result = await evaluateJavascript(
      source: 'document.documentElement ? document.documentElement.outerHTML : ""',
    );
    return result?.toString();
  }

  @override
  Future<Object?> evaluateJavascript({required String source}) async {
    final webview = _webview;
    if (webview == null) return null;
    try {
      return await webview.evaluateJavaScript(source);
    } catch (error, stackTrace) {
      onLoadError?.call(error.toString(), _currentUrl ?? initialUrl);
      AppLog.instance.error(
        'linux/webview',
        'evaluateJavascript failed: $error',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  @override
  Future<HlsJavaScriptResult?> callAsyncJavaScript({
    required String functionBody,
    required Map<String, dynamic> arguments,
  }) async {
    // WebKitGTK evaluate_javascript does not await Promises. Start a job that
    // writes the settled result onto window.__noliveAsyncJobs, then poll.
    final jobId =
        'job_${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(1 << 20)}';
    final startScript = LinuxAsyncJsJobCodec.buildStartScript(
      jobId: jobId,
      functionBody: functionBody,
      arguments: arguments,
    );
    final started = await evaluateJavascript(source: startScript);
    if (started == null) {
      return HlsJavaScriptResult(error: 'failed to start async javascript job');
    }

    final pollScript = LinuxAsyncJsJobCodec.buildPollScript(jobId);
    final deadline = DateTime.now().add(const Duration(seconds: 45));
    while (DateTime.now().isBefore(deadline)) {
      final raw = await evaluateJavascript(source: pollScript);
      final result = LinuxAsyncJsJobCodec.parsePollPayload(raw);
      if (result != null) {
        return result;
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return HlsJavaScriptResult(
      error: 'async javascript job timed out (jobId=$jobId)',
    );
  }
}

/// Opens a **visible** desktop WebView window for interactive web login.
///
/// Returns exported cookie header string when [onSave] is invoked by the
/// Flutter chrome page, or null if closed without save.
class LinuxDesktopWebLoginSession {
  LinuxDesktopWebLoginSession({
    required this.initialUrl,
    required this.title,
    required this.userAgent,
    required LinuxDesktopCookieJar cookieJar,
    this.allowedHostSuffixes = const <String>[],
  }) : _cookieJar = cookieJar;

  final String initialUrl;
  final String title;
  final String userAgent;
  final List<String> allowedHostSuffixes;
  final LinuxDesktopCookieJar _cookieJar;

  Webview? _webview;

  Future<void> open() async {
    final webview = await WebviewWindow.create(
      configuration: CreateConfiguration(
        windowWidth: 1100,
        windowHeight: 760,
        title: title,
        titleBarHeight: 36,
      ),
    );
    _webview = webview;
    if (userAgent.isNotEmpty) {
      // Prefer native UA when possible; also patch navigator for JS checks.
      try {
        await webview.setApplicationNameForUserAgent('');
      } catch (_) {}
      webview.addScriptToExecuteOnDocumentCreated(
        "Object.defineProperty(navigator, 'userAgent', {get: function() { return ${jsonEncode(userAgent)}; }});"
        "Object.defineProperty(navigator, 'platform', {get: function() { return 'Linux x86_64'; }});"
        "Object.defineProperty(navigator, 'webdriver', {get: function() { return undefined; }});",
      );
    }
    for (final assignment in _cookieJar.documentCookieAssignments()) {
      webview.addScriptToExecuteOnDocumentCreated(assignment);
    }
    // Default allow-all navigation callback so DecidePolicy always gets a
    // fast true even if no caller set a blocker (login windows).
    webview.setOnUrlRequestCallback((url) => true);
    webview.launch(initialUrl);
  }

  Future<String> exportCookies() async {
    final webview = _webview;
    if (webview != null) {
      await _cookieJar.mergeFromWebview(webview);
      // Some hosts store cookies only as document.cookie (not fully mirrored
      // by WebKitCookieManager at export time). Pull JS cookie jar too.
      await _mergeDocumentCookies(webview);
    }
    return _cookieJar.exportCookieHeader(
      allowedHostSuffixes: allowedHostSuffixes.isEmpty
          ? null
          : allowedHostSuffixes,
    );
  }

  Future<void> _mergeDocumentCookies(Webview webview) async {
    try {
      final raw = await webview.evaluateJavaScript('document.cookie');
      final header = raw?.toString().trim() ?? '';
      if (header.isEmpty) return;
      final href = await webview.evaluateJavaScript('location.href');
      final pageUrl = href?.toString().trim().isNotEmpty == true
          ? href!.toString()
          : initialUrl;
      final uri = Uri.tryParse(pageUrl);
      final domain = uri?.host ?? '';
      if (domain.isEmpty) return;
      for (final part in header.split(';')) {
        final trimmed = part.trim();
        if (trimmed.isEmpty) continue;
        final eq = trimmed.indexOf('=');
        if (eq <= 0) continue;
        final name = trimmed.substring(0, eq).trim();
        final value = trimmed.substring(eq + 1).trim();
        if (name.isEmpty) continue;
        await _cookieJar.setCookie(
          url: pageUrl,
          name: name,
          value: value,
          domain: domain,
          path: '/',
          isSecure: uri?.scheme == 'https',
        );
      }
    } catch (error, stackTrace) {
      AppLog.instance.warn(
        'linux/webview',
        'document.cookie merge failed: $error',
      );
      AppLog.instance.error(
        'linux/webview',
        'document.cookie merge stack',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> navigate(String url) async {
    _webview?.launch(url);
  }

  /// Evaluate JS in the visible login WebView (used by login save + tests).
  Future<String?> evaluateJavaScript(String javaScript) async {
    final webview = _webview;
    if (webview == null) return null;
    final result = await webview.evaluateJavaScript(javaScript);
    return result?.toString();
  }

  Future<void> close() async {
    final webview = _webview;
    _webview = null;
    if (webview == null) {
      return;
    }
    // Hide first so the user never sees a "stuck" orphan chrome, then close.
    // Native close is deferred to the GTK idle loop; a short yield reduces
    // races with in-flight evaluateJavaScript (cookie poll).
    try {
      await webview.setWebviewWindowVisibility(false);
    } catch (_) {
      // Best-effort; window may already be closing.
    }
    try {
      webview.close();
    } catch (error) {
      AppLog.instance.warn('linux/webview', 'login webview close failed: $error');
    }
    await Future<void>.delayed(const Duration(milliseconds: 80));
  }
}
