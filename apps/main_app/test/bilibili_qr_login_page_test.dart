import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_providers/live_providers.dart';
import 'package:nolive_app/src/app/bootstrap/bootstrap.dart';
import 'package:nolive_app/src/features/settings/presentation/bilibili_qr_login_page.dart';

class _FakeBilibiliAccountClient implements BilibiliAccountClient {
  @override
  Future<BilibiliQrLoginSession> createQrLoginSession() async {
    return const BilibiliQrLoginSession(
      qrcodeKey: 'preview-key',
      qrcodeUrl: 'https://example.com/qr-login',
    );
  }

  @override
  Future<BilibiliAccountProfile> loadProfile({required String cookie}) async {
    return const BilibiliAccountProfile(
      userId: 10086,
      displayName: 'preview-user',
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
      displayName: 'preview-douyin',
      secUid: 'sec-preview',
      avatarUrl: 'https://example.com/avatar.png',
    );
  }
}

void main() {
  testWidgets('bilibili qr login page shows qr session and pending status', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BilibiliQrLoginPage(
          bootstrap: createAppBootstrap(
            mode: AppRuntimeMode.preview,
            bilibiliAccountClient: _FakeBilibiliAccountClient(),
            douyinAccountClient: _FakeDouyinAccountClient(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('哔哩哔哩扫码登录'), findsOneWidget);
    expect(find.text('扫码登录'), findsOneWidget);
    expect(find.text('请使用哔哩哔哩客户端扫码确认'), findsOneWidget);
    expect(find.text('刷新二维码'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    expect(find.text('等待扫码…'), findsOneWidget);
  });
}
