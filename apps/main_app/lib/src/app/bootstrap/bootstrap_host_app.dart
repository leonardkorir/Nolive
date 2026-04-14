import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:nolive_app/src/app/app.dart';
import 'package:nolive_app/src/app/bootstrap/bootstrap.dart';
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

  @override
  void initState() {
    super.initState();
    _bootstrapFuture = widget.bootstrapLoader();
  }

  void _retry() {
    setState(() {
      _bootstrapFuture = widget.bootstrapLoader();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppBootstrap>(
      future: _bootstrapFuture,
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          return NoliveApp(appBootstrap: snapshot.data!);
        }
        return MaterialApp(
          title: 'Nolive',
          locale: kZhHansCnLocale,
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
              data: mediaQuery.copyWith(textScaler: TextScaler.noScaling),
              child: DefaultTextStyle.merge(
                style: applyZhTextStyle(),
                child: child ?? const SizedBox.shrink(),
              ),
            );
          },
          theme: NoliveTheme.light(),
          home: _BootstrapStatusPage(
            loading: !snapshot.hasError,
            error: snapshot.error,
            onRetry: _retry,
          ),
        );
      },
    );
  }
}

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
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const FlutterLogo(size: 64),
                  const SizedBox(height: 20),
                  Text(
                    loading ? '正在启动 Nolive' : 'Nolive 启动失败',
                    key: const Key('bootstrap-status-title'),
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    loading ? '正在初始化本地数据和运行时环境，请稍候。' : '${error ?? '未知错误'}',
                    key: const Key('bootstrap-status-message'),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  if (loading)
                    const CircularProgressIndicator.adaptive(
                      key: Key('bootstrap-status-progress'),
                    )
                  else
                    FilledButton.icon(
                      key: const Key('bootstrap-status-retry'),
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('重试'),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
