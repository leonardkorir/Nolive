import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nolive_app/src/app/bootstrap/bootstrap.dart';
import 'package:nolive_app/src/app/bootstrap/bootstrap_host_app.dart';
import 'package:nolive_app/src/shared/presentation/theme/zh_text.dart';

void main() {
  testWidgets(
      'bootstrap host app shows loading shell before bootstrap resolves',
      (tester) async {
    final completer = Completer<AppBootstrap>();

    await tester.pumpWidget(
      BootstrapHostApp(
        bootstrapLoader: () => completer.future,
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('bootstrap-status-title')), findsOneWidget);
    expect(find.text('正在启动 Nolive'), findsOneWidget);
    expect(find.byKey(const Key('bootstrap-status-progress')), findsOneWidget);
    final loadingApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(loadingApp.locale, kZhHansCnLocale);

    completer.complete(createAppBootstrap(mode: AppRuntimeMode.preview));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('bootstrap-status-title')), findsNothing);
    expect(find.byKey(const Key('shell-tab-library')), findsOneWidget);
  });
}
