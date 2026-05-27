import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:live_providers/src/providers/huya/huya_transport.dart';
import 'package:test/test.dart';

void main() {
  test('huya transport retries transient failures once', () async {
    var requestCount = 0;
    final transport = HttpHuyaTransport(
      client: MockClient((request) async {
        requestCount += 1;
        if (requestCount == 1) {
          return http.Response('busy', 503);
        }
        return http.Response(jsonEncode(const {'status': 'ok'}), 200);
      }),
    );

    final response = await transport.getJson('https://www.huya.com/test');

    expect(response['status'], 'ok');
    expect(requestCount, 2);
  });
}
