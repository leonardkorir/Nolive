import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:live_providers/src/providers/bilibili/bilibili_transport.dart';
import 'package:test/test.dart';

void main() {
  test('bilibili transport retries transient failures once', () async {
    var requestCount = 0;
    final transport = HttpBilibiliTransport(
      client: MockClient((request) async {
        requestCount += 1;
        if (requestCount == 1) {
          return http.Response('busy', 503);
        }
        return http.Response(jsonEncode(const {'code': 0}), 200);
      }),
    );

    final response = await transport.getJson('https://api.bilibili.com/test');

    expect(response['code'], 0);
    expect(requestCount, 2);
  });
}
