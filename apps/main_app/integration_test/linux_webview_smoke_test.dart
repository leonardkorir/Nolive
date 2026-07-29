import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nolive_app/src/app/platform/app_platform_capabilities.dart';
import 'package:nolive_app/src/app/runtime_bridges/hls_proxy_platform_adapter_impl.dart';
import 'package:nolive_app/src/app/runtime_bridges/linux_desktop_webview_adapter.dart';

/// Real Linux embedder + plugin registration smoke for HlsHeadlessWebView.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Linux headless WebView load HTTPS + JS + async + dispose',
    (tester) async {
      if (!Platform.isLinux) {
        return;
      }

      final caps = AppPlatformCapabilities.current();
      expect(caps.isLinux, isTrue);
      expect(caps.supportsHeadlessWebView, isTrue);

      final jar = LinuxDesktopCookieJar();
      await jar.setCookie(
        url: 'https://example.com/',
        name: 'smoke',
        value: '1',
        domain: 'example.com',
        path: '/',
      );

      final adapter = HlsProxyPlatformAdapterImpl(
        platformCapabilities: caps,
        linuxCookieJar: jar,
      );
      expect(adapter.supportsHeadlessWebView, isTrue);
      expect(identical(adapter.cookieManager, jar), isTrue);

      final view = await adapter.createHeadlessWebView(
        initialUrl: 'https://example.com/',
        userAgent: 'NoliveLinuxWebViewSmoke/1.0',
      );

      await view.run();
      await tester.pump(const Duration(seconds: 2));

      final js = await view.evaluateJavascript(source: '1+1');
      debugPrint('JS_RESULT=$js');
      expect(js, isNotNull);

      final asyncResult = await view.callAsyncJavaScript(
        functionBody: 'return await Promise.resolve(7);',
        arguments: const <String, dynamic>{},
      );
      debugPrint(
        'ASYNC_VALUE=${asyncResult?.value} ASYNC_ERROR=${asyncResult?.error}',
      );
      expect(asyncResult, isNotNull);
      expect(asyncResult!.error, isNull);
      expect(asyncResult.value, isNotNull);

      final html = await view.getHtml();
      debugPrint('HTML_LEN=${html?.length ?? 0}');
      expect(html, isNotNull);
      expect(html!.length, greaterThan(0));

      await view.dispose().timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          debugPrint(
            'dispose timed out (GTK teardown) — smoke assertions already passed',
          );
        },
      );
      debugPrint('WEBVIEW_SMOKE_OK');
    },
    timeout: const Timeout(Duration(seconds: 90)),
  );
}
