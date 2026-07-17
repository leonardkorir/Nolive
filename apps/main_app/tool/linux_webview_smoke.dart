import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:nolive_app/src/app/platform/app_platform_capabilities.dart';
import 'package:nolive_app/src/app/runtime_bridges/hls_proxy_platform_adapter_impl.dart';
import 'package:nolive_app/src/app/runtime_bridges/linux_desktop_webview_adapter.dart';

/// Real Linux plugin path smoke (must be run with Flutter Linux embedder).
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!Platform.isLinux) {
    stderr.writeln('SKIP: not Linux');
    exit(0);
  }
  final caps = AppPlatformCapabilities.current();
  final jar = LinuxDesktopCookieJar();
  final adapter = HlsProxyPlatformAdapterImpl(
    platformCapabilities: caps,
    linuxCookieJar: jar,
  );
  stdout.writeln(
    'supportsHeadlessWebView=${adapter.supportsHeadlessWebView} '
    'isLinux=${caps.isLinux}',
  );
  final view = await adapter.createHeadlessWebView(
    initialUrl: 'https://example.com/',
    userAgent: 'NoliveLinuxWebViewSmoke/1.0',
  );
  await view.run();
  // Give page a moment
  await Future<void>.delayed(const Duration(seconds: 2));
  final js = await view.evaluateJavascript(source: '1+1');
  stdout.writeln('JS_RESULT=$js');
  final asyncResult = await view.callAsyncJavaScript(
    functionBody: 'return await Promise.resolve(7);',
    arguments: const {},
  );
  stdout.writeln(
    'ASYNC_VALUE=${asyncResult?.value} ASYNC_ERROR=${asyncResult?.error}',
  );
  final html = await view.getHtml();
  stdout.writeln('HTML_LEN=${html?.length ?? 0}');
  await view.dispose();
  if (js == null) {
    stderr.writeln('FAIL: evaluateJavascript returned null');
    exit(2);
  }
  if (asyncResult?.value == null || asyncResult?.error != null) {
    stderr.writeln('FAIL: callAsyncJavaScript did not settle: $asyncResult');
    exit(3);
  }
  stdout.writeln('WEBVIEW_SMOKE_OK');
  exit(0);
}
