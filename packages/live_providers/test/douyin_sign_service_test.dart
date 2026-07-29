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
    'no user cookie and HEAD failure uses pure_live-style legal default ttwid',
    () async {
      final service = HttpDouyinSignService(
        client: _FakeHttpClient((request) async {
          throw http.ClientException('network down');
        }),
      );

      final headers = await service.buildHeaders();

      final cookie = headers['cookie']!;
      expect(cookie, isNot(contains('local-fallback')));
      expect(cookie, HttpDouyinSignService.defaultCookie);
      expect(cookie, startsWith('ttwid=1%7C'));
      // Morphologically valid pure_live-style shape: multi-segment ttwid.
      expect(cookie.split('%7C').length, greaterThanOrEqualTo(3));
    },
  );

  test(
    'forceRefresh on HEAD failure also uses static legal default, never local-fallback',
    () async {
      final service = HttpDouyinSignService(
        cookie: 'ttwid=injected-cookie',
        client: _FakeHttpClient((request) async {
          throw http.ClientException('network down');
        }),
      );

      final headers = await service.buildHeaders(forceRefreshCookie: true);

      expect(headers['cookie'], isNot(contains('local-fallback')));
      expect(headers['cookie'], HttpDouyinSignService.defaultCookie);
    },
  );

  test(
    'injected account cookie with ttwid is preferred without HEAD',
    () async {
      var headRequests = 0;
      final service = HttpDouyinSignService(
        cookie: 'ttwid=account-guest-ttwid; msToken=abc',
        client: _FakeHttpClient((request) async {
          headRequests += 1;
          return http.Response('', 500);
        }),
      );

      final headers = await service.buildHeaders();

      expect(headers['cookie'], 'ttwid=account-guest-ttwid; msToken=abc');
      expect(headRequests, 0);
    },
  );

  test('defaultCookie is a fixed legal constant, not timestamped fake', () {
    expect(
      HttpDouyinSignService.defaultCookie,
      isNot(contains('local-fallback')),
    );
    expect(
      HttpDouyinSignService.defaultCookie,
      'ttwid=1%7CB1qls3GdnZhUov9o2NxOMxxYS2ff6OSvEWbv0ytbES4%7C1680522049%7C280d802d6d478e3e78d0c807f7c487e7ffec0ae4e5fdd6a0fe74c3c6af149511',
    );
    // Two reads must be identical (no DateTime.now in default).
    expect(
      HttpDouyinSignService.defaultCookie,
      HttpDouyinSignService.defaultCookie,
    );
  });
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
