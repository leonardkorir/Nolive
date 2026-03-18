import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nolive_app/src/app/bootstrap/bootstrap.dart';
import 'package:nolive_app/src/features/sync/presentation/sync_center_page.dart';

void main() {
  testWidgets('sync center page shows landing entries', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SyncCenterPage(
          bootstrap: createAppBootstrap(mode: AppRuntimeMode.preview),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('数据同步'), findsWidgets);
    expect(find.textContaining('当前提供 WebDAV 备份与局域网推送'), findsNothing);
    expect(find.text('WebDAV 同步'), findsOneWidget);
    expect(find.text('局域网数据同步'), findsOneWidget);
    expect(find.text('导入 / 导出'), findsOneWidget);
    expect(find.byKey(const Key('sync-entry-webdav')), findsOneWidget);
    expect(find.byKey(const Key('sync-entry-local')), findsOneWidget);
  });
}
