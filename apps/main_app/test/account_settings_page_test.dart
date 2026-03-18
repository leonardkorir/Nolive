import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nolive_app/src/app/bootstrap/bootstrap.dart';
import 'package:nolive_app/src/features/settings/presentation/account_settings_page.dart';

void main() {
  testWidgets(
      'account settings page shows flat provider list and account actions', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AccountSettingsPage(
          bootstrap: createAppBootstrap(mode: AppRuntimeMode.preview),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('账号管理'), findsWidgets);
    expect(find.textContaining('仅在需要凭据的平台提供登录管理'), findsNothing);
    expect(find.textContaining('账号仅在平台需要额外鉴权时才配置'), findsNothing);
    expect(find.textContaining('当前平台播放链路不依赖账号登录'), findsNothing);
    expect(find.text('哔哩哔哩'), findsOneWidget);
    expect(find.text('斗鱼直播'), findsOneWidget);
    expect(find.text('虎牙直播'), findsOneWidget);
    expect(find.text('Chaturbate'), findsOneWidget);
    expect(find.text('抖音直播'), findsOneWidget);
    expect(find.text('扫码登录'), findsOneWidget);
    expect(find.text('网页登录'), findsNWidgets(2));
    expect(find.text('编辑 Cookie'), findsNWidgets(3));
    expect(find.text('校验状态'), findsNWidgets(2));
    expect(find.text('刷新状态'), findsNWidgets(2));
    expect(find.text('无需登录'), findsNWidgets(2));
  });
}
