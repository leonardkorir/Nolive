import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nolive_app/src/features/settings/application/release_info_manifest.dart';
import 'package:nolive_app/src/features/settings/presentation/release_info_page.dart';

void main() {
  testWidgets('release info page shows current release metadata and checks', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ReleaseInfoPage(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('应用信息'), findsOneWidget);
    expect(find.text('Nolive'), findsOneWidget);
    expect(find.text(ReleaseInfoManifest.fallbackVersion), findsOneWidget);
    expect(find.text(ReleaseInfoManifest.primaryPlatform), findsOneWidget);

    await tester.scrollUntilVisible(find.text('发布检查'), 240);
    await tester.pumpAndSettle();

    expect(find.text('发布检查'), findsOneWidget);
    expect(find.text(ReleaseInfoManifest.releaseChecks.first), findsOneWidget);
  });
}
