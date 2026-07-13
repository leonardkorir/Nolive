import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:nolive_app/src/app/bootstrap/bootstrap_host_app.dart';
import 'package:nolive_app/src/app/platform/app_platform_capabilities.dart';
import 'package:nolive_app/src/shared/application/app_log.dart';
import 'package:nolive_app/src/shared/application/nfr_frame_timing_telemetry.dart';
import 'package:window_manager/window_manager.dart';

typedef ImageCacheBudget = ({int maximumSize, int maximumSizeBytes});

@visibleForTesting
ImageCacheBudget resolveImageCacheBudget({required bool mobilePlatform}) {
  if (mobilePlatform) {
    return (maximumSize: 100, maximumSizeBytes: 48 << 20);
  }
  return (maximumSize: 200, maximumSizeBytes: 96 << 20);
}

@visibleForTesting
void configureImageCacheBudget(ImageCache imageCache) {
  configureImageCacheBudgetForPlatform(
    imageCache,
    platform: AppPlatformCapabilities.current(),
  );
}

@visibleForTesting
void configureImageCacheBudgetForPlatform(
  ImageCache imageCache, {
  required AppPlatformCapabilities platform,
}) {
  if (kIsWeb) {
    return;
  }
  final budget = resolveImageCacheBudget(mobilePlatform: platform.isMobile);
  imageCache.maximumSize = budget.maximumSize;
  imageCache.maximumSizeBytes = budget.maximumSizeBytes;
}

Future<void> main() async {
  await runZonedGuarded(
    () async {
      final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
      // Keep the native splash painted until bootstrap finishes — same single
      // avoid a second pure-black Flutter loading page.
      FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
      final platform = AppPlatformCapabilities.current();
      configureImageCacheBudgetForPlatform(
        PaintingBinding.instance.imageCache,
        platform: platform,
      );
      unawaited(
        AppLog.instance.ensureInitialized().catchError((
          Object error,
          StackTrace stackTrace,
        ) {
          debugPrint('AppLog initialization failed: $error');
        }),
      );
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
        'startup platform=${platform.operatingSystem} '
            'version=${platform.operatingSystemVersion} '
            'debug=$kDebugMode',
      );
      NfrFrameTimingTelemetry.instance.start();
      if (!platform.isWeb && platform.isDesktop) {
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
      runApp(const BootstrapHostApp());
    },
    (error, stackTrace) {
      AppLog.instance.error(
        'zone',
        'Uncaught zone error',
        error: error,
        stackTrace: stackTrace,
      );
    },
  );
}
