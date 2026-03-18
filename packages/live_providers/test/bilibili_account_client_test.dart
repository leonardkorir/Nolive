import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:live_providers/live_providers.dart';
import 'package:test/test.dart';

void main() {
  test('bilibili account client loads profile from cookie', () async {
    final client = HttpBilibiliAccountClient(
      client: MockClient((request) async {
        expect(request.headers['cookie'], 'SESSDATA=test');
        return http.Response.bytes(
          utf8.encode(
            '{"code":0,"data":{"mid":42,"uname":"测试用户","face":"https://example.com/avatar.png"}}',
          ),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

    final profile = await client.loadProfile(cookie: 'SESSDATA=test');

    expect(profile.userId, 42);
    expect(profile.displayName, '测试用户');
  });

  test('bilibili account client parses qr login success cookie', () async {
    final client = HttpBilibiliAccountClient(
      client: MockClient((request) async {
        if (request.url.path.contains('poll')) {
          return http.Response(
            '{"code":0,"data":{"code":0}}',
            200,
            headers: {
              'set-cookie':
                  'SESSDATA=test-session; Path=/, DedeUserID=42; Path=/, bili_jct=test-jct; Path=/, sid=test-sid; Path=/',
            },
          );
        }
        return http.Response('{"code":0,"data":{}}', 200);
      }),
    );

    final result = await client.pollQrLogin(qrcodeKey: 'test-key');

    expect(result.status, BilibiliQrLoginStatus.success);
    expect(result.cookie, contains('SESSDATA=test-session'));
    expect(result.cookie, contains('DedeUserID=42'));
  });
}
