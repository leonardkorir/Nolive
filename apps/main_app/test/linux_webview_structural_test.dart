import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:nolive_app/src/app/platform/app_platform_capabilities.dart';
import 'package:nolive_app/src/app/runtime_bridges/hls_proxy_platform_adapter_impl.dart';
import 'package:nolive_app/src/app/runtime_bridges/linux_desktop_webview_adapter.dart';

void main() {
  test('Linux plugin registration lists desktop_webview_window', () {
    // Structural: shipped Linux runner must register WebView plugin.
    final cmake = File(
      'linux/flutter/generated_plugins.cmake',
    );
    expect(cmake.existsSync(), isTrue, reason: 'run from apps/main_app');
    final text = cmake.readAsStringSync();
    expect(text, contains('desktop_webview_window'));
    expect(text, contains('flutter_secure_storage_linux'));
  });

  test('Linux adapter implementation files exist', () {
    expect(
      File('lib/src/app/runtime_bridges/linux_desktop_webview_adapter.dart')
          .existsSync(),
      isTrue,
    );
    expect(
      File(
        'lib/src/features/settings/presentation/linux_desktop_web_login_page.dart',
      ).existsSync(),
      isTrue,
    );
  });

  test('adapter selects Linux cookie jar when on Linux with webview', () {
    // Only meaningful when the test process itself is Linux.
    if (!Platform.isLinux) {
      return;
    }
    final caps = AppPlatformCapabilities(
      isWeb: false,
      isAndroid: false,
      isIOS: false,
      isLinux: true,
      isMacOS: false,
      isWindows: false,
      targetPlatform: TargetPlatform.linux,
      operatingSystem: 'linux',
      operatingSystemVersion: 'test',
      linuxWebViewAvailable: true,
    );
    final jar = LinuxDesktopCookieJar();
    final adapter = HlsProxyPlatformAdapterImpl(
      platformCapabilities: caps,
      linuxCookieJar: jar,
    );
    expect(adapter.supportsHeadlessWebView, isTrue);
    expect(identical(adapter.cookieManager, jar), isTrue);
  });
}
