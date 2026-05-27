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
  });

  factory AppPlatformCapabilities.current() {
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

  bool get isMobile => isAndroid || isIOS;
  bool get isDesktop => isWindows || isLinux || isMacOS;
}
