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
      tester.view.physicalSize = const Size(600, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final completer = Completer<AppBootstrap>();

      await tester.pumpWidget(
        BootstrapHostApp(bootstrapLoader: () => completer.future),
      );
      await tester.pump();

      expect(find.byKey(const Key('bootstrap-status-title')), findsOneWidget);
      expect(find.text('正在启动 Nolive'), findsOneWidget);
      expect(
        find.byKey(const Key('bootstrap-status-progress')),
        findsOneWidget,
      );
      final loadingApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(loadingApp.locale, kZhHansCnLocale);

      completer.complete(createAppBootstrap(mode: AppRuntimeMode.preview));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('bootstrap-status-title')), findsNothing);
      expect(find.byKey(const Key('shell-tab-library')), findsOneWidget);
    },
  );

  test('app bootstrap runs injected dispose cleanup', () async {
    var disposeCalls = 0;

    final bootstrap = createAppBootstrap(
      mode: AppRuntimeMode.preview,
      onDispose: () async {
        disposeCalls += 1;
      },
    );

    await bootstrap.dispose();

    expect(disposeCalls, 1);
  });

  testWidgets('bootstrap host app shows retry shell on bootstrap failure', (
    tester,
  ) async {
    await tester.pumpWidget(
      BootstrapHostApp(
        bootstrapLoader: () async {
          throw StateError('boom');
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Nolive 启动失败'), findsOneWidget);
    expect(find.textContaining('boom'), findsOneWidget);
    expect(find.byKey(const Key('bootstrap-status-retry')), findsOneWidget);
  });
}
