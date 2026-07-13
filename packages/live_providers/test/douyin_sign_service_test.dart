import 'package:http/http.dart' as http;
import 'package:live_providers/src/providers/douyin/douyin_sign_service.dart';
import 'package:test/test.dart';

void main() {
  test(
    'douyin sign service preserves expires cookies when parsing set-cookie',
    () async {
      final client = _FakeHttpClient((request) async {
        expect(request.method, 'HEAD');
        return http.Response(
          '',
          200,
          headers: const {
            'set-cookie':
                'ttwid=from-head; Expires=Thu, 01 Jan 1970 00:00:00 GMT; Path=/, msToken=token-value; Path=/',
          },
        );
      });
      final service = HttpDouyinSignService(client: client);

      final headers = await service.buildHeaders();

      expect(headers['cookie'], 'ttwid=from-head;msToken=token-value');
    },
  );

  test(
    'forceRefreshCookie bypasses injected cookie and fetches a fresh value',
    () async {
      var headRequests = 0;
      final client = _FakeHttpClient((request) async {
        headRequests += 1;
        return http.Response(
          '',
          200,
          headers: const {'set-cookie': 'ttwid=refreshed-cookie; Path=/'},
        );
      });
      final service = HttpDouyinSignService(
        cookie: 'ttwid=injected-cookie',
        client: client,
      );

      final cached = await service.buildHeaders();
      final refreshed = await service.buildHeaders(forceRefreshCookie: true);

      expect(cached['cookie'], 'ttwid=injected-cookie');
      expect(refreshed['cookie'], 'ttwid=refreshed-cookie');
      expect(headRequests, 1);
    },
  );

  test(
    'douyin sign service falls back to default cookie on refresh failure',
    () async {
      final service = HttpDouyinSignService(
        client: _FakeHttpClient((request) async {
          throw http.ClientException('network down');
        }),
      );

      final headers = await service.buildHeaders(forceRefreshCookie: true);

      expect(headers['cookie'], HttpDouyinSignService.defaultCookie);
    },
  );
}

class _FakeHttpClient extends http.BaseClient {
  _FakeHttpClient(this._handler);

  final Future<http.Response> Function(http.BaseRequest request) _handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await _handler(request);
    return http.StreamedResponse(
      Stream<List<int>>.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      request: request,
      reasonPhrase: response.reasonPhrase,
    );
  }
}
