import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nolive_app/src/features/profile/presentation/profile_page.dart';
import 'package:nolive_app/src/features/settings/application/github_app_update_service.dart';

void main() {
  testWidgets('profile page shows disclaimer, homepage, and update entries', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProfilePage(
            versionLoader: () async => '0.3.2',
            updateService: GithubAppUpdateService(
              releaseResolver: () async => GithubReleaseInfo(
                version: '0.3.2',
                releaseUri: Uri(
                  scheme: 'https',
                  host: 'github.com',
                  path: '/leonardkorir/Nolive/releases/tag/v0.3.2',
                ),
              ),
            ),
            urlLauncher: (_) async => true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('免责声明'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.scrollUntilVisible(
      find.text('检查更新'),
      300,
      scrollable: find.byType(Scrollable).last,
    );

    expect(find.text('免责声明'), findsOneWidget);
    expect(find.text('开源主页'), findsOneWidget);
    expect(find.text('检查更新'), findsOneWidget);
    expect(find.text('Ver 0.3.2'), findsOneWidget);
  });

  testWidgets('profile page shows update dialog when newer release exists', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProfilePage(
            versionLoader: () async => '0.3.2',
            updateService: GithubAppUpdateService(
              releaseResolver: () async => GithubReleaseInfo(
                version: '0.3.3',
                releaseUri: Uri(
                  scheme: 'https',
                  host: 'github.com',
                  path: '/leonardkorir/Nolive/releases/tag/v0.3.3',
                ),
              ),
            ),
            urlLauncher: (_) async => true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('检查更新'),
      300,
      scrollable: find.byType(Scrollable).last,
    );

    await tester.tap(find.text('检查更新'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('发现新版本 v0.3.3'), findsOneWidget);
    expect(find.text('前往更新'), findsOneWidget);
  });
}
