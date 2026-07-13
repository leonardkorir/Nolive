import 'package:flutter_test/flutter_test.dart';
import 'package:nolive_app/src/app/routing/app_routes.dart';
import 'package:nolive_app/src/shared/presentation/app_settings_entries.dart';

void main() {
  test('settings page catalog has core routes without dumping onto profile', () {
    expect(kAppSettingsEntries, isNotEmpty);
    final titles = kAppSettingsEntries.map((e) => e.title).toSet();
    final routes = kAppSettingsEntries.map((e) => e.routeName).toSet();

    expect(titles, containsAll(<String>['外观设置', '账号设置', '同步中心', '房间解析']));
    expect(titles.contains('应用信息'), isFalse);
    expect(routes, contains(AppRoutes.appearanceSettings));
    expect(routes, contains(AppRoutes.accountSettings));
    expect(routes, contains(AppRoutes.syncCenter));
    expect(routes, contains(AppRoutes.parseRoom));
    expect(routes.contains(AppRoutes.releaseInfo), isFalse);
    expect(routes.length, kAppSettingsEntries.length);
  });

  test('profile menu is the original flat list without 应用信息', () {
    final titles = kProfileMenuEntries.map((e) => e.title).toList();
    expect(titles.first, '观看记录');
    expect(titles, contains('账号管理'));
    expect(titles, contains('免责声明'));
    expect(titles, contains('其他设置'));
    expect(titles.contains('应用信息'), isFalse);
    expect(
      kProfileMenuEntries.map((e) => e.routeName),
      isNot(contains(AppRoutes.releaseInfo)),
    );
  });
}
