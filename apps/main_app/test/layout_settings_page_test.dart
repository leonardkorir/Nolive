import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nolive_app/src/app/bootstrap/bootstrap.dart';
import 'package:nolive_app/src/features/settings/presentation/layout_settings_page.dart';

void main() {
  testWidgets('layout settings page shows shell and provider ordering tools', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LayoutSettingsPage(
          bootstrap: createAppBootstrap(mode: AppRuntimeMode.preview),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('主页设置'), findsWidgets);
    expect(find.text('导航顺序'), findsOneWidget);
    expect(find.text('平台顺序'), findsOneWidget);
    expect(find.text('恢复默认'), findsOneWidget);
    expect(find.text('首页'), findsOneWidget);
    expect(find.text('哔哩哔哩'), findsOneWidget);
    expect(find.byType(CircleAvatar), findsNothing);
  });
}
