import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nolive_app/src/app/platform/app_platform_capabilities.dart';

void main() {
  group('AppPlatformCapabilities WebView gates', () {
    test('Android mobile supports headless + embedded login', () {
      const caps = AppPlatformCapabilities(
        isWeb: false,
        isAndroid: true,
        isIOS: false,
        isLinux: false,
        isMacOS: false,
        isWindows: false,
        targetPlatform: TargetPlatform.android,
        operatingSystem: 'android',
        operatingSystemVersion: '14',
      );
      expect(caps.isMobile, isTrue);
      expect(caps.supportsHeadlessWebView, isTrue);
      expect(caps.supportsEmbeddedWebLogin, isTrue);
    });

    test('Linux with webview available enables bridges + login', () {
      const caps = AppPlatformCapabilities(
        isWeb: false,
        isAndroid: false,
        isIOS: false,
        isLinux: true,
        isMacOS: false,
        isWindows: false,
        targetPlatform: TargetPlatform.linux,
        operatingSystem: 'linux',
        operatingSystemVersion: '6.8',
        linuxWebViewAvailable: true,
      );
      expect(caps.isMobile, isFalse);
      expect(caps.supportsHeadlessWebView, isTrue);
      expect(caps.supportsEmbeddedWebLogin, isTrue);
    });

    test('Linux without webview disables bridges and logs path is false', () {
      const caps = AppPlatformCapabilities(
        isWeb: false,
        isAndroid: false,
        isIOS: false,
        isLinux: true,
        isMacOS: false,
        isWindows: false,
        targetPlatform: TargetPlatform.linux,
        operatingSystem: 'linux',
        operatingSystemVersion: '6.8',
        linuxWebViewAvailable: false,
      );
      expect(caps.supportsHeadlessWebView, isFalse);
      expect(caps.supportsEmbeddedWebLogin, isFalse);
    });

    test('Windows / macOS support headless webview (inappwebview)', () {
      const windows = AppPlatformCapabilities(
        isWeb: false,
        isAndroid: false,
        isIOS: false,
        isLinux: false,
        isMacOS: false,
        isWindows: true,
        targetPlatform: TargetPlatform.windows,
        operatingSystem: 'windows',
        operatingSystemVersion: '11',
      );
      const mac = AppPlatformCapabilities(
        isWeb: false,
        isAndroid: false,
        isIOS: false,
        isLinux: false,
        isMacOS: true,
        isWindows: false,
        targetPlatform: TargetPlatform.macOS,
        operatingSystem: 'macos',
        operatingSystemVersion: '14',
      );
      expect(windows.supportsHeadlessWebView, isTrue);
      expect(mac.supportsHeadlessWebView, isTrue);
    });

    test('Web never supports headless webview gates', () {
      const caps = AppPlatformCapabilities(
        isWeb: true,
        isAndroid: false,
        isIOS: false,
        isLinux: false,
        isMacOS: false,
        isWindows: false,
        targetPlatform: TargetPlatform.android,
        operatingSystem: 'web',
        operatingSystemVersion: '',
      );
      expect(caps.supportsHeadlessWebView, isFalse);
      expect(caps.supportsEmbeddedWebLogin, isFalse);
    });

    test('Linux gate is independent of bare isMobile', () {
      // Regression: international bridges must not key solely on isMobile.
      const linux = AppPlatformCapabilities(
        isWeb: false,
        isAndroid: false,
        isIOS: false,
        isLinux: true,
        isMacOS: false,
        isWindows: false,
        targetPlatform: TargetPlatform.linux,
        operatingSystem: 'linux',
        operatingSystemVersion: '6.8',
        linuxWebViewAvailable: true,
      );
      expect(linux.isMobile, isFalse);
      expect(linux.supportsHeadlessWebView, isTrue);
    });
  });
}
