import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:live_providers/live_providers.dart';
import 'package:test/test.dart';

void main() {
  test('douyin account client loads profile from cookie', () async {
    final client = HttpDouyinAccountClient(
      client: MockClient((request) async {
        expect(request.url.queryParameters['aid'], '6383');
        expect(request.headers['cookie'], 'ttwid=test');
        return http.Response.bytes(
          utf8.encode(
            '{"status_code":0,"data":{"nickname":"抖音测试号","sec_uid":"sec-1","avatar_thumb":{"url_list":["https://example.com/a.png"]}}}',
          ),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

    final profile = await client.loadProfile(cookie: 'ttwid=test');

    expect(profile.displayName, '抖音测试号');
    expect(profile.secUid, 'sec-1');
  });
}
