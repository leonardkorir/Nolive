import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_providers/live_providers.dart';
import 'package:nolive_app/src/app/bootstrap/bootstrap.dart';
import 'package:nolive_app/src/features/settings/application/settings_feature_dependencies.dart';
import 'package:nolive_app/src/features/settings/presentation/account_settings_page.dart';

void main() {
  testWidgets(
    'account settings page shows flat provider list and account actions',
    (tester) async {
      final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
      await tester.pumpWidget(
        MaterialApp(
          home: AccountSettingsPage(
            dependencies: SettingsFeatureDependencies.fromBootstrap(bootstrap),
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
      expect(find.text('Twitch'), findsOneWidget);
      expect(find.text('YouTube'), findsOneWidget);
      expect(find.text('扫码登录'), findsOneWidget);
      expect(find.text('网页登录'), findsNWidgets(3));
      expect(find.text('手动导入密钥'), findsOneWidget);
      expect(find.text('编辑 Cookie'), findsNWidgets(5));
      expect(find.text('校验状态'), findsNWidgets(2));
      expect(find.text('刷新状态'), findsNWidgets(5));
      expect(find.text('未配置'), findsWidgets);
      expect(find.text('无需登录'), findsNWidgets(4));
      expect(find.textContaining('Cookie/WebView 路径已封存'), findsNothing);
      expect(find.textContaining('默认播放使用本地 MOUFLON 解码'), findsOneWidget);
    },
  );

  testWidgets(
    'account settings can edit bilibili cookies, reload dashboard, and clear credentials',
    (tester) async {
      final bilibiliClient = _FakeBilibiliAccountClient();
      final bootstrap = createAppBootstrap(
        mode: AppRuntimeMode.preview,
        bilibiliAccountClient: bilibiliClient,
        douyinAccountClient: _FakeDouyinAccountClient(),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: AccountSettingsPage(
            dependencies: SettingsFeatureDependencies.fromBootstrap(bootstrap),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(OutlinedButton, '编辑 Cookie').first);
      await tester.pumpAndSettle();

      final dialogFields = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(dialogFields.at(0), 'SESSDATA=preview');
      await tester.enterText(dialogFields.at(1), '');
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();

      expect(find.text('测试哔哩用户 · UID 10086'), findsOneWidget);
      final reloadCountAfterSave = bilibiliClient.loadProfileCallCount;
      expect(reloadCountAfterSave, greaterThan(0));

      await tester.tap(find.byTooltip('刷新状态').first);
      await tester.pumpAndSettle();

      expect(
        bilibiliClient.loadProfileCallCount,
        greaterThan(reloadCountAfterSave),
      );

      await tester.tap(find.widgetWithText(OutlinedButton, '清除凭据').first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '清除'));
      await tester.pumpAndSettle();

      expect(find.text('测试哔哩用户 · UID 10086'), findsNothing);
      expect(find.text('可扫码登录或手动填写 Cookie'), findsOneWidget);
    },
  );
}

class _FakeBilibiliAccountClient implements BilibiliAccountClient {
  int loadProfileCallCount = 0;

  @override
  Future<BilibiliQrLoginSession> createQrLoginSession() async {
    return const BilibiliQrLoginSession(
      qrcodeKey: 'preview-key',
      qrcodeUrl: 'https://example.com/qr-login',
    );
  }

  @override
  Future<BilibiliAccountProfile> loadProfile({required String cookie}) async {
    loadProfileCallCount += 1;
    if (cookie.trim().isEmpty) {
      throw StateError('missing cookie');
    }
    return const BilibiliAccountProfile(
      userId: 10086,
      displayName: '测试哔哩用户',
      avatarUrl: 'https://example.com/avatar.png',
    );
  }

  @override
  Future<BilibiliQrLoginPollResult> pollQrLogin({
    required String qrcodeKey,
  }) async {
    return const BilibiliQrLoginPollResult(
      status: BilibiliQrLoginStatus.pending,
    );
  }
}

class _FakeDouyinAccountClient implements DouyinAccountClient {
  @override
  Future<DouyinAccountProfile> loadProfile({required String cookie}) async {
    return const DouyinAccountProfile(
      displayName: '测试抖音用户',
      secUid: 'sec-preview',
      avatarUrl: 'https://example.com/avatar.png',
    );
  }
}
