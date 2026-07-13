import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nolive_app/src/features/profile/presentation/profile_page.dart';
import 'package:nolive_app/src/features/settings/application/github_app_update_service.dart';
import 'package:nolive_app/src/app/routing/app_routes.dart';
import 'package:nolive_app/src/shared/presentation/app_settings_entries.dart';

void main() {
  testWidgets('profile page shows disclaimer, homepage, and update entries', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProfilePage(
            versionLoader: () async => '0.3.5',
            updateService: GithubAppUpdateService(
              releaseResolver: () async => GithubReleaseInfo(
                version: '0.3.5',
                releaseUri: Uri(
                  scheme: 'https',
                  host: 'github.com',
                  path: '/leonardkorir/Nolive/releases/tag/v0.3.5',
                ),
              ),
            ),
            urlLauncher: (_) async => true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('观看记录'), findsOneWidget);
    expect(find.text('账号管理'), findsOneWidget);
    expect(find.text('应用信息'), findsNothing);

    await tester.scrollUntilVisible(
      find.text('免责声明'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('免责声明'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('检查更新'),
      300,
      scrollable: find.byType(Scrollable).last,
    );

    expect(find.text('开源主页'), findsOneWidget);
    expect(find.text('检查更新'), findsOneWidget);
    expect(find.text('Ver 0.3.5'), findsOneWidget);
    // Profile uses product menu, not Settings dump.
    expect(
      kProfileMenuEntries.any((e) => e.routeName == AppRoutes.releaseInfo),
      isFalse,
    );
  });

  testWidgets('profile page shows update dialog when newer release exists', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProfilePage(
            versionLoader: () async => '0.3.5',
            updateService: GithubAppUpdateService(
              releaseResolver: () async => GithubReleaseInfo(
                version: '0.3.6',
                releaseUri: Uri(
                  scheme: 'https',
                  host: 'github.com',
                  path: '/leonardkorir/Nolive/releases/tag/v0.3.6',
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

    expect(find.text('发现新版本 v0.3.6'), findsOneWidget);
    expect(find.text('前往更新'), findsOneWidget);
  });

  testWidgets('profile page shows snackbar when homepage launch fails', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProfilePage(
            versionLoader: () async => '0.3.5',
            updateService: GithubAppUpdateService(
              releaseResolver: () async => GithubReleaseInfo(
                version: '0.3.5',
                releaseUri: Uri(
                  scheme: 'https',
                  host: 'github.com',
                  path: '/leonardkorir/Nolive/releases/tag/v0.3.5',
                ),
              ),
            ),
            urlLauncher: (_) async => false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('开源主页'),
      300,
      scrollable: find.byType(Scrollable).last,
    );

    await tester.tap(find.text('开源主页'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('无法打开开源主页。'), findsOneWidget);
  });

  testWidgets('profile page surfaces update check failures', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProfilePage(
            versionLoader: () async => '0.3.5',
            updateService: GithubAppUpdateService(
              releaseResolver: () async {
                throw StateError('network down');
              },
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

    expect(find.textContaining('检查更新失败'), findsOneWidget);
    // Friendly copy — no raw StateError dump on the snackbar.
    expect(find.textContaining('Bad state: network down'), findsNothing);
  });
}
