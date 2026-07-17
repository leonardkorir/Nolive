import 'dart:io';

import 'package:flutter/foundation.dart';

class AppPlatformCapabilities {
  const AppPlatformCapabilities({
    required this.isWeb,
    required this.isAndroid,
    required this.isIOS,
    required this.isLinux,
    required this.isMacOS,
    required this.isWindows,
    required this.targetPlatform,
    required this.operatingSystem,
    required this.operatingSystemVersion,
    this.linuxWebViewAvailable = true,
  });

  factory AppPlatformCapabilities.current({bool? linuxWebViewAvailable}) {
    return AppPlatformCapabilities(
      isWeb: kIsWeb,
      isAndroid: !kIsWeb && Platform.isAndroid,
      isIOS: !kIsWeb && Platform.isIOS,
      isLinux: !kIsWeb && Platform.isLinux,
      isMacOS: !kIsWeb && Platform.isMacOS,
      isWindows: !kIsWeb && Platform.isWindows,
      targetPlatform: defaultTargetPlatform,
      operatingSystem: kIsWeb ? 'web' : Platform.operatingSystem,
      operatingSystemVersion: kIsWeb ? '' : Platform.operatingSystemVersion,
      linuxWebViewAvailable: linuxWebViewAvailable ?? true,
    );
  }

  final bool isWeb;
  final bool isAndroid;
  final bool isIOS;
  final bool isLinux;
  final bool isMacOS;
  final bool isWindows;
  final TargetPlatform targetPlatform;
  final String operatingSystem;
  final String operatingSystemVersion;

  /// Whether a Linux WebView implementation is wired for this build.
  /// Defaults to true once the desktop WebView adapter ships; tests may
  /// override to exercise "bridge disabled: no webview" logging.
  final bool linuxWebViewAvailable;

  bool get isMobile => isAndroid || isIOS;
  bool get isDesktop => isWindows || isLinux || isMacOS;

  /// Headless WebView available for HLS bridges / nsig solvers.
  ///
  /// Android/iOS/macOS/Windows: flutter_inappwebview.
  /// Linux: desktop WebKitGTK adapter (scheme B) when [linuxWebViewAvailable].
  bool get supportsHeadlessWebView {
    if (isWeb) return false;
    if (isMobile || isMacOS || isWindows) return true;
    if (isLinux) return linuxWebViewAvailable;
    return false;
  }

  /// Visible embedded / desktop web login that can export cookies.
  bool get supportsEmbeddedWebLogin => supportsHeadlessWebView && !isWeb;
}
