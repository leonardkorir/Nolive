import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:live_core/live_core.dart';
import 'package:live_providers/src/providers/provider_runtime_support.dart';
import 'package:live_providers/src/providers/youtube/youtube_api_client.dart';
import 'package:test/test.dart';

void main() {
  test('youtube api client follows manual redirects and replays cookies',
      () async {
    var requestCount = 0;
    final client = HttpYouTubeApiClient(
      client: _FakeBaseClient((request) async {
        requestCount += 1;
        if (requestCount == 1) {
          expect(request.method, 'GET');
          expect(request.url.path, '/results');
          expect(request.headers['cookie'], isNull);
          return _streamedResponse(
            request,
            302,
            '',
            headers: {
              'location':
                  '/results?search_query=esports+live&google_abuse=fixture',
              'set-cookie':
                  'VISITOR_INFO1_LIVE=abc123; Path=/, CONSENT=YES+cb; '
                      'Expires=Wed, 09 Jun 2027 10:18:14 GMT; Path=/',
            },
          );
        }

        expect(request.method, 'GET');
        expect(
          request.headers['cookie'],
          allOf(contains('VISITOR_INFO1_LIVE=abc123'),
              contains('CONSENT=YES+cb')),
        );
        return _streamedResponse(
          request,
          200,
          '<html>ok</html>',
        );
      }),
    );

    final html = await client.fetchText(
      'https://www.youtube.com/results?search_query=esports+live',
    );

    expect(html, '<html>ok</html>');
    expect(requestCount, 2);
  });

  test('youtube api client times out live chat polling requests', () async {
    final client = HttpYouTubeApiClient(
      client: _FakeBaseClient((request) {
        return Completer<http.StreamedResponse>().future;
      }),
    );

    expect(
      () => client.postLiveChat(
        apiKey: 'AIzaTest',
        continuation: 'continuation',
        visitorData: 'visitor',
        referer: 'https://www.youtube.com/live_chat?continuation=1',
        timeout: const Duration(milliseconds: 50),
      ),
      throwsA(
        isA<ProviderParseException>().having(
          (error) => error.message,
          'message',
          contains('timed out'),
        ),
      ),
    );
  });

  test('youtube api client retries transient document failures once', () async {
    var requestCount = 0;
    final client = HttpYouTubeApiClient(
      browserProfile: const ProviderBrowserProfile(
        userAgent: 'SimpleLive-YT-UA',
        acceptLanguage: 'fr-FR',
        browserName: 'Chrome',
        browserVersion: '146.0.0.0',
        osName: 'Linux',
        osVersion: '',
      ),
      client: _FakeBaseClient((request) async {
        requestCount += 1;
        expect(request.headers['user-agent'], 'SimpleLive-YT-UA');
        expect(request.headers['accept-language'], 'fr-FR');
        if (requestCount == 1) {
          return _streamedResponse(request, 503, 'busy');
        }
        return _streamedResponse(request, 200, '<html>retry-ok</html>');
      }),
    );

    final html = await client.fetchText('https://www.youtube.com/watch?v=test');

    expect(html, '<html>retry-ok</html>');
    expect(requestCount, 2);
  });
}

class _FakeBaseClient extends http.BaseClient {
  _FakeBaseClient(this._handler);

  final Future<http.StreamedResponse> Function(http.BaseRequest request)
      _handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return _handler(request);
  }
}

http.StreamedResponse _streamedResponse(
  http.BaseRequest request,
  int statusCode,
  String body, {
  Map<String, String> headers = const {},
}) {
  return http.StreamedResponse(
    Stream.value(utf8.encode(body)),
    statusCode,
    headers: headers,
    request: request,
  );
}
