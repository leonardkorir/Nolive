import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nolive_app/src/shared/presentation/app_feedback.dart';
import 'package:nolive_app/src/shared/presentation/theme/nolive_theme.dart';

void main() {
  testWidgets('showAppSnackBar uses floating themed snackbar', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: NoliveTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return FilledButton(
                onPressed: () => showAppSnackBar(context, '操作成功'),
                child: const Text('go'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('go'));
    await tester.pump(); // start snackbar
    expect(find.text('操作成功'), findsOneWidget);
    // Behavior comes from ThemeData.snackBarTheme (null on widget = use theme).
    final theme = tester.widget<MaterialApp>(find.byType(MaterialApp)).theme!;
    expect(theme.snackBarTheme.behavior, SnackBarBehavior.floating);
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('showAppErrorSnackBar avoids raw Exception dumps', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: NoliveTheme.dark(),
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return FilledButton(
                onPressed: () => showAppErrorSnackBar(
                  context,
                  Exception('SocketException: failed host lookup'),
                ),
                child: const Text('err'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('err'));
    await tester.pump();
    expect(find.textContaining('网络'), findsOneWidget);
    expect(find.textContaining('SocketException'), findsNothing);
  });
}
