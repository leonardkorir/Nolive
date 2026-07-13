import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:live_providers/src/providers/provider_runtime_support.dart';
import 'package:live_providers/src/providers/twitch/twitch_api_client.dart';
import 'package:test/test.dart';

void main() {
  test('twitch api client allows overriding client-id for rotation', () async {
    late http.Request capturedRequest;
    final client = HttpTwitchApiClient(
      clientId: 'custom-client-id',
      client: MockClient((request) async {
        capturedRequest = request;
        return http.Response(jsonEncode(const {'data': {}}), 200);
      }),
    );

    await client.postGraphQl(const {'operationName': 'Test'});

    expect(capturedRequest.headers['client-id'], 'custom-client-id');
  });

  test('twitch api client retries transient GraphQL failures once', () async {
    var requestCount = 0;
    final client = HttpTwitchApiClient(
      browserProfile: const ProviderBrowserProfile(
        userAgent: 'SimpleLive-TW-UA',
        acceptLanguage: 'ja-JP',
        browserName: 'Chrome',
        browserVersion: '146.0.0.0',
        osName: 'Linux',
        osVersion: '',
      ),
      client: MockClient((request) async {
        requestCount += 1;
        expect(request.headers['user-agent'], 'SimpleLive-TW-UA');
        expect(request.headers['accept-language'], 'ja-JP');
        if (requestCount == 1) {
          return http.Response('busy', 503);
        }
        return http.Response(
          jsonEncode(const {
            'data': {'ok': true},
          }),
          200,
        );
      }),
    );

    final payload = await client.postGraphQl(const {'operationName': 'Retry'});

    expect((payload as Map<String, dynamic>)['data']['ok'], isTrue);
    expect(requestCount, 2);
  });
}
