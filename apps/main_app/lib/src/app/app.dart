import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:nolive_app/src/app/bootstrap/bootstrap.dart';
import 'package:nolive_app/src/app/routing/app_router.dart';
import 'package:nolive_app/src/app/routing/app_routes.dart';
import 'package:nolive_app/src/shared/presentation/theme/nolive_theme.dart';
import 'package:nolive_app/src/shared/presentation/theme/zh_text.dart';

class NoliveApp extends StatelessWidget {
  const NoliveApp({required this.appBootstrap, super.key});

  final AppBootstrap appBootstrap;

  @override
  Widget build(BuildContext context) {
    final router = AppRouter(appBootstrap);
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: appBootstrap.themeMode,
      builder: (context, themeMode, _) {
        return MaterialApp(
          title: 'Nolive',
          theme: NoliveTheme.light(),
          darkTheme: NoliveTheme.dark(),
          themeMode: themeMode,
          locale: kZhHansCnLocale,
          supportedLocales: const [
            Locale.fromSubtags(
                languageCode: 'zh', scriptCode: 'Hans', countryCode: 'CN'),
            Locale.fromSubtags(
                languageCode: 'zh', scriptCode: 'Hant', countryCode: 'TW'),
            Locale('en'),
            Locale('ja', 'JP'),
          ],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          builder: (context, child) {
            final mediaQuery = MediaQuery.of(context);
            final isDark = Theme.of(context).brightness == Brightness.dark;
            final overlayStyle = (isDark
                    ? SystemUiOverlayStyle.light
                    : SystemUiOverlayStyle.dark)
                .copyWith(
              statusBarColor: Colors.transparent,
              systemNavigationBarColor: Colors.transparent,
            );
            return AnnotatedRegion<SystemUiOverlayStyle>(
              value: overlayStyle,
              child: MediaQuery(
                data: mediaQuery.copyWith(textScaler: TextScaler.noScaling),
                child: DefaultTextStyle.merge(
                  style: applyZhTextStyle(),
                  child: child ?? const SizedBox.shrink(),
                ),
              ),
            );
          },
          initialRoute: AppRoutes.home,
          onGenerateRoute: router.onGenerateRoute,
        );
      },
    );
  }
}
