import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nolive_app/src/app/bootstrap/bootstrap.dart';
import 'package:nolive_app/src/features/sync/presentation/sync_local_page.dart';
import 'package:nolive_app/src/features/sync/presentation/sync_webdav_page.dart';

void main() {
  testWidgets('sync webdav page shows configure, test and upload actions', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SyncWebDavPage(
          bootstrap: createAppBootstrap(mode: AppRuntimeMode.preview),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('WebDAV 同步'), findsWidgets);
    expect(
        find.byKey(const Key('sync-webdav-configure-button')), findsOneWidget);
    expect(find.byKey(const Key('sync-webdav-test-button')), findsOneWidget);
    expect(find.byKey(const Key('sync-webdav-upload-button')), findsOneWidget);
  });

  testWidgets('sync local page shows local actions', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SyncLocalPage(
          bootstrap: createAppBootstrap(mode: AppRuntimeMode.preview),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('局域网数据同步'), findsWidgets);
    expect(find.byKey(const Key('sync-local-toggle-button')), findsOneWidget);
    expect(find.byKey(const Key('sync-local-edit-button')), findsOneWidget);
    expect(find.byKey(const Key('sync-local-test-button')), findsOneWidget);
    expect(find.byKey(const Key('sync-local-push-button')), findsOneWidget);
  });
}
