/// Embedded web-login path: open Linux desktop WebView session, set a cookie
/// **inside the WebView**, then export via the same [exportCookies] path the
/// settings login page uses. No pre-seeded jar values for the asserted name.
///
/// Run:
///   flutter test integration_test/linux_web_login_cookie_test.dart -d linux
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nolive_app/src/app/platform/app_platform_capabilities.dart';
import 'package:nolive_app/src/app/runtime_bridges/linux_desktop_webview_adapter.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Linux web-login exports WebView-set cookie',
    (tester) async {
      if (!Platform.isLinux) return;
      final caps = AppPlatformCapabilities.current();
      expect(caps.supportsEmbeddedWebLogin, isTrue);

      // Empty jar — do not pre-seed the cookie name under assertion.
      final jar = LinuxDesktopCookieJar();
      const cookieName = 'nolive_linux_login';
      const cookieValue = 'from_webview_ok';

      final session = LinuxDesktopWebLoginSession(
        initialUrl: 'https://example.com/',
        title: 'nolive-web-login-smoke',
        userAgent:
            'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/146.0.0.0 Safari/537.36',
        cookieJar: jar,
        allowedHostSuffixes: const ['example.com'],
      );

      debugPrint('WEB_LOGIN_OPEN_START');
      await session.open().timeout(const Duration(seconds: 30));
      debugPrint('WEB_LOGIN_OPEN_OK');
      await Future<void>.delayed(const Duration(seconds: 2));

      // Set cookie **inside** the WebView (same surface a login flow uses).
      final setResult = await session
          .evaluateJavaScript(
            "document.cookie='$cookieName=$cookieValue; path=/; max-age=3600'; document.cookie;",
          )
          .timeout(const Duration(seconds: 10));
      debugPrint('WEB_LOGIN_JS_SET_RESULT=$setResult');

      // Confirm WebView document.cookie sees the value before export.
      final jsCookie = await session
          .evaluateJavaScript('document.cookie')
          .timeout(const Duration(seconds: 10));
      debugPrint('WEB_LOGIN_JS_COOKIE=$jsCookie');
      expect(
        (jsCookie ?? '').toLowerCase().contains(cookieName.toLowerCase()),
        isTrue,
        reason:
            'WebView document.cookie must contain $cookieName, got $jsCookie',
      );

      final header = await session.exportCookies().timeout(
        const Duration(seconds: 15),
      );
      debugPrint(
        'WEB_LOGIN_COOKIE_HEADER_LEN=${header.length} PREVIEW='
        '${header.length > 160 ? header.substring(0, 160) : header}',
      );

      expect(
        header.toLowerCase().contains(cookieName.toLowerCase()),
        isTrue,
        reason:
            'exportCookies must surface WebView-set $cookieName '
            '(login save path). got: $header',
      );
      expect(
        header.contains(cookieValue),
        isTrue,
        reason: 'export must include the WebView-written value. got: $header',
      );
      debugPrint('WEB_LOGIN_COOKIE_OK name=$cookieName');
      debugPrint('WEB_LOGIN_SMOKE_DONE');
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
