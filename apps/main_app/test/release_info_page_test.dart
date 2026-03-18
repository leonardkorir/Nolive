import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nolive_app/src/features/settings/presentation/release_info_page.dart';

void main() {
  testWidgets('release info page shows placeholder only', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ReleaseInfoPage(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('应用信息'), findsOneWidget);
    expect(find.text('Nolive'), findsOneWidget);
    expect(find.text('当前版本不展示发布信息。'), findsOneWidget);
    expect(find.text('发布检查'), findsNothing);
  });
}
