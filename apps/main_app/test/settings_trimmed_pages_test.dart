import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nolive_app/src/app/bootstrap/bootstrap.dart';
import 'package:nolive_app/src/features/settings/presentation/appearance_settings_page.dart';
import 'package:nolive_app/src/features/settings/presentation/danmaku_settings_page.dart';
import 'package:nolive_app/src/features/settings/presentation/disclaimer_page.dart';
import 'test_feature_dependencies.dart';

void main() {
  testWidgets('appearance settings page hides runtime overview block', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AppearanceSettingsPage(
          dependencies: buildAppearanceSettingsDependencies(
            createAppBootstrap(mode: AppRuntimeMode.preview),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('运行态概览'), findsNothing);
  });

  testWidgets('disclaimer page hides intro subtitle', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: DisclaimerPage()),
    );
    await tester.pumpAndSettle();

    expect(find.text('免责声明'), findsWidgets);
  });

  testWidgets('danmaku settings preview text stays on the new copy set', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DanmakuSettingsPage(
          dependencies: buildDanmakuSettingsDependencies(
            createAppBootstrap(mode: AppRuntimeMode.preview),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('预览效果'),
      300,
      scrollable: find.byType(Scrollable).last,
    );

    expect(find.text('午后记得起来活动一下，顺手喝两口水。'), findsNWidgets(2));
  });
}
