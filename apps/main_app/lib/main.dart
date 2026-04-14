import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nolive_app/src/app/bootstrap/bootstrap_host_app.dart';
import 'package:nolive_app/src/shared/application/app_log.dart';
import 'package:window_manager/window_manager.dart';

typedef ImageCacheBudget = ({int maximumSize, int maximumSizeBytes});

@visibleForTesting
ImageCacheBudget resolveImageCacheBudget({
  required bool mobilePlatform,
}) {
  if (mobilePlatform) {
    return (
      maximumSize: 100,
      maximumSizeBytes: 48 << 20,
    );
  }
  return (
    maximumSize: 200,
    maximumSizeBytes: 96 << 20,
  );
}

@visibleForTesting
void configureImageCacheBudget(ImageCache imageCache) {
  if (kIsWeb) {
    return;
  }
  final budget = resolveImageCacheBudget(
    mobilePlatform: Platform.isAndroid || Platform.isIOS,
  );
  imageCache.maximumSize = budget.maximumSize;
  imageCache.maximumSizeBytes = budget.maximumSizeBytes;
}

Future<void> main() async {
  await runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    configureImageCacheBudget(PaintingBinding.instance.imageCache);
    await AppLog.instance.ensureInitialized();
    FlutterError.onError = (details) {
      AppLog.instance.error(
        'flutter',
        details.exceptionAsString(),
        stackTrace: details.stack,
      );
      FlutterError.presentError(details);
    };
    PlatformDispatcher.instance.onError = (error, stackTrace) {
      AppLog.instance.error(
        'platform',
        'Unhandled platform error',
        error: error,
        stackTrace: stackTrace,
      );
      return true;
    };
    AppLog.instance.info(
      'app',
      'startup platform=${Platform.operatingSystem} '
          'version=${Platform.operatingSystemVersion} '
          'debug=$kDebugMode',
    );
    if (!kIsWeb &&
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      await windowManager.ensureInitialized();
      const options = WindowOptions(
        size: Size(1280, 720),
        minimumSize: Size(960, 540),
        center: true,
        title: 'Nolive',
        backgroundColor: Colors.transparent,
      );
      await windowManager.waitUntilReadyToShow(options, () async {
        await windowManager.show();
        await windowManager.focus();
      });
    }
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
    );
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    runApp(const BootstrapHostApp());
  }, (error, stackTrace) {
    AppLog.instance.error(
      'zone',
      'Uncaught zone error',
      error: error,
      stackTrace: stackTrace,
    );
  });
}
