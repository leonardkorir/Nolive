import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nolive_app/src/app/bootstrap/bootstrap.dart';
import 'package:nolive_app/src/features/settings/presentation/layout_settings_page.dart';
import 'test_feature_dependencies.dart';

void main() {
  testWidgets('layout settings page shows shell and provider ordering tools', (
    tester,
  ) async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);

    await tester.pumpWidget(
      MaterialApp(
        home: LayoutSettingsPage(
          dependencies: buildLayoutSettingsDependencies(bootstrap),
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
    final youtubeToggle = find.byKey(
      const Key('layout-provider-toggle-youtube'),
    );
    expect(youtubeToggle, findsOneWidget);
    expect(find.byType(CircleAvatar), findsNothing);

    await tester.ensureVisible(youtubeToggle);
    await tester.pumpAndSettle();

    expect(tester.widget<Switch>(youtubeToggle).value, isTrue);

    await tester.tap(youtubeToggle);
    await tester.pumpAndSettle();

    expect(tester.widget<Switch>(youtubeToggle).value, isFalse);
    expect(bootstrap.layoutPreferences.value.isProviderEnabled('youtube'),
        isFalse);
  });
}
