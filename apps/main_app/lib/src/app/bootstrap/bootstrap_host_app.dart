import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:nolive_app/src/app/app.dart';
import 'package:nolive_app/src/app/bootstrap/bootstrap.dart';
import 'package:nolive_app/src/shared/application/app_log.dart';
import 'package:nolive_app/src/shared/presentation/theme/app_text_scale.dart';
import 'package:nolive_app/src/shared/presentation/theme/nolive_theme.dart';
import 'package:nolive_app/src/shared/presentation/theme/zh_text.dart';

class BootstrapHostApp extends StatefulWidget {
  const BootstrapHostApp({
    super.key,
    this.bootstrapLoader = _defaultBootstrapLoader,
  });

  final Future<AppBootstrap> Function() bootstrapLoader;

  static Future<AppBootstrap> _defaultBootstrapLoader() {
    return createPersistentAppBootstrap(mode: AppRuntimeMode.live);
  }

  @override
  State<BootstrapHostApp> createState() => _BootstrapHostAppState();
}

class _BootstrapHostAppState extends State<BootstrapHostApp> {
  late Future<AppBootstrap> _bootstrapFuture;
  AppBootstrap? _warmedBootstrap;
  int _bootstrapGeneration = 0;

  @override
  void initState() {
    super.initState();
    _bootstrapFuture = _loadBootstrap();
  }

  void _retry() {
    setState(() {
      _bootstrapFuture = _loadBootstrap();
      _warmedBootstrap = null;
    });
  }

  Future<AppBootstrap> _loadBootstrap() {
    final generation = ++_bootstrapGeneration;
    return widget.bootstrapLoader().then((bootstrap) {
      if (!mounted || generation != _bootstrapGeneration) {
        unawaited(_disposeBootstrap(bootstrap));
      }
      return bootstrap;
    });
  }

  Future<void> _disposeBootstrap(AppBootstrap bootstrap) async {
     try {
       await bootstrap.dispose();
     } catch (error, stackTrace) {
       // Best-effort cleanup for stale bootstrap results.
       AppLog.instance.error(
         'bootstrap',
         'dispose stale bootstrap failed: $error',
         error: error,
         stackTrace: stackTrace,
       );
       debugPrint('dispose stale bootstrap failed error=$error');
     }
   }

  void _ensureSecureCredentialsReady(AppBootstrap bootstrap) {
    if (identical(_warmedBootstrap, bootstrap)) {
      return;
    }
    _warmedBootstrap = bootstrap;
    // Credentials are sequenced in createPersistentAppBootstrap (ensureReady
    // before UI). Re-run warm-up immediately as idempotent insurance — never
    // delay (first CB home/follow would miss cf_clearance).
    if (mounted && identical(_warmedBootstrap, bootstrap)) {
      unawaited(bootstrap.warmUpSecureCredentialStore());
    }
  }

  @override
  void dispose() {
    final bootstrap = _warmedBootstrap;
    _warmedBootstrap = null;
    if (bootstrap != null) {
      unawaited(_disposeBootstrap(bootstrap));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppBootstrap>(
      future: _bootstrapFuture,
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          _ensureSecureCredentialsReady(snapshot.data!);
          // Drop native splash only when the real shell is ready.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            FlutterNativeSplash.remove();
          });
          return NoliveApp(appBootstrap: snapshot.data!);
        }
        if (snapshot.hasError) {
          // Error UI must be visible; drop splash so retry is usable.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            FlutterNativeSplash.remove();
          });
        }
        final isLoading = !snapshot.hasError;
        return MaterialApp(
          title: 'Nolive',
          locale: kZhHansCnLocale,
          // Avoid TextStyle.lerp inherit conflicts when switching splash→error theme.
          themeAnimationDuration: Duration.zero,
          supportedLocales: const [
            Locale.fromSubtags(
              languageCode: 'zh',
              scriptCode: 'Hans',
              countryCode: 'CN',
            ),
            Locale.fromSubtags(
              languageCode: 'zh',
              scriptCode: 'Hant',
              countryCode: 'TW',
            ),
            Locale('en'),
            Locale('ja', 'JP'),
          ],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          builder: (context, child) {
            final mediaQuery = MediaQuery.of(context);
            return MediaQuery(
              data: applyAppTextScaler(mediaQuery),
              child: DefaultTextStyle.merge(
                style: applyZhTextStyle(),
                child: child ?? const SizedBox.shrink(),
              ),
            );
          },
          // Loading theme matches native splash color to avoid a light flash
          // between Android LaunchTheme and the first Flutter frame.
          theme: isLoading
              ? ThemeData(
                  brightness: Brightness.dark,
                  scaffoldBackgroundColor: _kBootstrapSplashColor,
                  canvasColor: _kBootstrapSplashColor,
                  colorScheme: const ColorScheme.dark(
                    surface: _kBootstrapSplashColor,
                  ),
                )
              : NoliveTheme.light(),
          home: _BootstrapStatusPage(
            loading: isLoading,
            error: snapshot.error,
            onRetry: _retry,
          ),
        );
      },
    );
  }
}

/// Matches [flutter_native_splash] / Android LaunchTheme so the first Flutter
/// frame does not flash a different "正在启动" UI over the native splash.
const Color _kBootstrapSplashColor = Color(0xFF101316);

class _BootstrapStatusPage extends StatelessWidget {
  const _BootstrapStatusPage({
    required this.loading,
    required this.error,
    required this.onRetry,
  });

  final bool loading;
  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (loading) {
      // Pure solid field only. Android LaunchTheme already shows the brand
      // mark once; drawing another logo here causes "one large + one small".
      return const Scaffold(
        key: Key('bootstrap-status-splash'),
        backgroundColor: _kBootstrapSplashColor,
        body: ColoredBox(color: _kBootstrapSplashColor),
      );
    }

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Nolive 启动失败',
                      key: const Key('bootstrap-status-title'),
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${error ?? '未知错误'}',
                      key: const Key('bootstrap-status-message'),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      key: const Key('bootstrap-status-retry'),
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('重试'),
                      style: FilledButton.styleFrom(
                        textStyle: theme.textTheme.labelLarge,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
