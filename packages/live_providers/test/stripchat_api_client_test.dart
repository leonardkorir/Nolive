import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:live_core/live_core.dart';
import 'package:live_providers/src/providers/provider_runtime_support.dart';
import 'package:live_providers/src/providers/stripchat/stripchat_api_client.dart';
import 'package:test/test.dart';

class _RedirectHttpClient extends http.BaseClient {
  _RedirectHttpClient(this.port);
  final int port;
  final http.Client _inner = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    final localUri = request.url.replace(
      scheme: 'http',
      host: 'localhost',
      port: port,
    );
    final newRequest = http.Request(request.method, localUri);
    newRequest.headers.addAll(request.headers);
    if (request is http.Request) {
      newRequest.bodyBytes = request.bodyBytes;
    }
    return _inner.send(newRequest);
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}

class _MockHttpClient extends http.BaseClient {
  final Map<String, List<http.Response>> _responses = {};
  final List<http.BaseRequest> requests = [];

  void respond(String urlPattern, {int statusCode = 200, String body = '{}'}) {
    _responses[urlPattern] = <http.Response>[
      http.Response(
        body,
        statusCode,
        request: http.Request('GET', Uri.parse(urlPattern)),
      ),
    ];
  }

  void respondSequence(
    String urlPattern,
    List<String> bodies, {
    int statusCode = 200,
  }) {
    _responses[urlPattern] = bodies
        .map(
          (body) => http.Response(
            body,
            statusCode,
            request: http.Request('GET', Uri.parse(urlPattern)),
          ),
        )
        .toList(growable: true);
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    final url = request.url.toString();
    for (final entry in _responses.entries) {
      if (url.contains(entry.key)) {
        final queuedResponses = entry.value;
        final response = queuedResponses.length > 1
            ? queuedResponses.removeAt(0)
            : queuedResponses.first;
        return http.StreamedResponse(
          Stream.value(utf8.encode(response.body)),
          response.statusCode,
          request: request,
          headers: response.headers,
        );
      }
    }
    return http.StreamedResponse(
      Stream.value(utf8.encode('{}')),
      200,
      request: request,
    );
  }
}

void main() {
  late _MockHttpClient mockHttp;
  late HttpStripchatApiClient client;

  setUp(() {
    mockHttp = _MockHttpClient();
    client = HttpStripchatApiClient(client: mockHttp);
  });

  tearDown(() {
    client.close();
  });

  group('fetchInitialDynamic', () {
    test('constructs correct URI with path and query params', () async {
      mockHttp.respond('initial-dynamic');

      await client.fetchInitialDynamic();

      final request = mockHttp.requests.last;
      expect(request.url.path, '/api/front/v3/config/initial-dynamic');
      expect(request.url.queryParameters['requestPath'], '/');
    });

    test('parses initialDynamic from wrapped response', () async {
      mockHttp.respond(
        'initial-dynamic',
        body: jsonEncode({
          'initialDynamic': {
            'userHash': 'test-hash',
            'csrfToken': 'test-csrf',
            'guestId': -999,
            'websocket': {'url': 'wss://test.ws', 'token': 'test-jwt'},
          },
        }),
      );

      final result = await client.fetchInitialDynamic();

      expect(result['userHash'], 'test-hash');
      expect(result['csrfToken'], 'test-csrf');
    });

    test('throws ProviderParseException for invalid JSON', () async {
      mockHttp.respond('initial-dynamic', body: 'not-json');

      expect(
        () => client.fetchInitialDynamic(),
        throwsA(isA<ProviderParseException>()),
      );
    });

    test('caches initialDynamic after first call', () async {
      mockHttp.respond(
        'initial-dynamic',
        body: jsonEncode({
          'initialDynamic': {'userHash': 'cached'},
        }),
      );

      await client.fetchInitialDynamic();
      final result = await client.fetchInitialDynamic();

      expect(result['userHash'], 'cached');
      expect(mockHttp.requests.length, 1);
    });

    test(
      'refreshes initialDynamic when cached websocket jwt is expired',
      () async {
        final expiredJwt = _buildJwt(
          exp: DateTime.now().toUtc().subtract(const Duration(minutes: 5)),
        );
        final freshJwt = _buildJwt(
          exp: DateTime.now().toUtc().add(const Duration(hours: 1)),
        );
        mockHttp.respondSequence('initial-dynamic', [
          jsonEncode({
            'initialDynamic': {
              'userHash': 'expired-cache',
              'websocket': {'url': 'wss://test.ws', 'token': expiredJwt},
            },
          }),
          jsonEncode({
            'initialDynamic': {
              'userHash': 'fresh-cache',
              'websocket': {'url': 'wss://test.ws', 'token': freshJwt},
            },
          }),
        ]);

        final first = await client.fetchInitialDynamic();
        final second = await client.fetchInitialDynamic();

        expect(first['userHash'], 'expired-cache');
        expect(second['userHash'], 'fresh-cache');
        expect(mockHttp.requests.length, 2);
      },
    );

    test('deduplicates concurrent fetchInitialDynamic calls', () async {
      mockHttp.respond(
        'initial-dynamic',
        body: jsonEncode({
          'initialDynamic': {
            'userHash': 'dedup-hash',
            'websocket': {
              'url': 'wss://test.ws',
              'token': _buildJwt(
                exp: DateTime.now().add(const Duration(hours: 1)),
              ),
            },
          },
        }),
      );

      final futures = [
        client.fetchInitialDynamic(),
        client.fetchInitialDynamic(),
      ];
      final results = await Future.wait(futures);

      expect(results[0]['userHash'], 'dedup-hash');
      expect(results[1]['userHash'], 'dedup-hash');
      expect(mockHttp.requests.length, 1);
    });
  });

  group('fetchRecommendModels', () {
    test('includes configured cookie in request headers', () async {
      final cookieClient = HttpStripchatApiClient(
        client: mockHttp,
        cookie: 'stripchat_com_guestId=123; __cf_bm=test',
      );
      addTearDown(cookieClient.close);
      mockHttp.respond('v2/models');

      await cookieClient.fetchRecommendModels();

      final request = mockHttp.requests.last;
      expect(
        request.headers['cookie'],
        'stripchat_com_guestId=123; __cf_bm=test',
      );
    });

    test('includes guestHash in query params', () async {
      mockHttp.respond('v2/models');

      await client.fetchRecommendModels(guestHash: 'my-hash');

      final request = mockHttp.requests.last;
      expect(request.url.queryParameters['guestHash'], 'my-hash');
      expect(request.url.queryParameters['primaryTag'], 'girls');
      expect(request.url.queryParameters['limit'], '24');
    });

    test('omits guestHash when null', () async {
      mockHttp.respond('v2/models');

      await client.fetchRecommendModels();

      final request = mockHttp.requests.last;
      expect(request.url.queryParameters.containsKey('guestHash'), isFalse);
    });
  });

  group('fetchCategoryModels', () {
    test('includes parentTag, filterGroupTags, guestHash', () async {
      mockHttp.respond('models');
      const filterGroupTags = '[["tagLanguageChinese"]]';

      await client.fetchCategoryModels(
        filterGroupTags: filterGroupTags,
        parentTag: 'tagLanguageChinese',
        guestHash: 'cat-hash',
      );

      final request = mockHttp.requests.last;
      expect(request.url.queryParameters['filterGroupTags'], filterGroupTags);
      expect(request.url.queryParameters['parentTag'], 'tagLanguageChinese');
      expect(request.url.queryParameters['guestHash'], 'cat-hash');
    });
  });

  group('searchModels', () {
    test('decodes plain JSON search response', () async {
      mockHttp.respond(
        'search/group/all',
        body: jsonEncode({
          'groups': {
            'username': {
              'models': [
                {
                  'username': 'found_user',
                  'id': 100,
                  'status': 'public',
                  'isLive': true,
                  'streamName': '001',
                },
              ],
            },
          },
        }),
      );

      final result = await client.searchModels(query: 'test');

      expect(result['groups'], isNotNull);
    });

    test('decodes base64 encoded search response', () async {
      final payload = jsonEncode({
        'groups': {
          'username': {
            'models': [
              {
                'username': 'base64_user',
                'id': 200,
                'status': 'public',
                'isLive': true,
                'streamName': '002',
              },
            ],
          },
        },
      });
      final base64Body = base64Encode(utf8.encode(payload));
      mockHttp.respond('search/group/all', body: base64Body);

      final result = await client.searchModels(query: 'test');

      expect(result['groups'], isNotNull);
    });

    test('throws ProviderParseException for invalid search response', () async {
      mockHttp.respond('search/group/all', body: '!!!not-valid!!!');

      expect(
        () => client.searchModels(query: 'test'),
        throwsA(isA<ProviderParseException>()),
      );
    });

    test('throws ProviderParseException for JSON array response', () async {
      mockHttp.respond('search/group/all', body: '[1,2,3]');

      expect(
        () => client.searchModels(query: 'test'),
        throwsA(isA<ProviderParseException>()),
      );
    });
  });

  group('listModels', () {
    test(
      'handles multiple modelIds correctly without overriding keys',
      () async {
        mockHttp.respond('models/list');

        await client.listModels(modelIds: [123, 456]);

        final request = mockHttp.requests.last;
        expect(request.url.path, '/api/front/models/list');
        expect(request.url.queryParametersAll['modelIds[]'], ['123', '456']);
      },
    );
  });

  group('network error handling / retries', () {
    test('throws ProviderParseException for non-2xx status', () async {
      mockHttp.respond('v2/models', statusCode: 404, body: 'not found');

      expect(
        () => client.fetchRecommendModels(),
        throwsA(isA<ProviderParseException>()),
      );
    });

    test('retries on 403 Forbidden', () async {
      mockHttp.respondSequence('v2/models', [
        'forbidden',
        jsonEncode({'models': []}),
      ], statusCode: 403);

      final clientWithRetry = HttpStripchatApiClient(
        client: mockHttp,
        retryPolicy: const ProviderRetryPolicy(maxAttempts: 2),
      );
      addTearDown(clientWithRetry.close);

      await expectLater(
        clientWithRetry.fetchRecommendModels(),
        throwsA(isA<ProviderParseException>()),
      );
      expect(mockHttp.requests.length, 2);
    });

    test('wraps SocketException in ProviderRetryableException', () async {
      var attempts = 0;
      final failingHttp = _FailingHttpClient(() {
        attempts++;
        throw const SocketException('Connection failed');
      });
      final clientWithSocketError = HttpStripchatApiClient(
        client: failingHttp,
        retryPolicy: const ProviderRetryPolicy(maxAttempts: 3),
      );
      addTearDown(clientWithSocketError.close);

      await expectLater(
        clientWithSocketError.fetchRecommendModels(),
        throwsA(isA<SocketException>()),
      );
      expect(attempts, 3);
    });
  });

  group('probePlaybackPlaylist', () {
    test(
      'rejects advertisement child playlist behind master playlist',
      () async {
        mockHttp.respond(
          'master/12345_auto.m3u8',
          body:
              '#EXTM3U\n'
              '#EXT-X-STREAM-INF:BANDWIDTH=1200000\n'
              'https://media-hls.doppiocdn.net/b-hls-09/12345/12345_720p.m3u8\n',
        );
        mockHttp.respond(
          '12345_720p.m3u8',
          body: '#EXTM3U\n#EXT-X-MOUFLON-ADVERT\n#EXT-X-PLAYLIST-TYPE:VOD\n',
        );

        final result = await client.probePlaybackPlaylist(
          'https://edge-hls.doppiocdn.net/hls/12345/master/12345_auto.m3u8',
        );

        expect(result.isPlayable, isFalse);
        expect(result.reason, 'stripchat_advertisement_playlist');
      },
    );

    test(
      'prefers requested quality variant when master playlist offers it',
      () async {
        mockHttp.respond(
          'master/12345_auto.m3u8',
          body:
              '#EXTM3U\n'
              '#EXT-X-MOUFLON:PSCH:v2:test-key\n'
              '#EXT-X-STREAM-INF:BANDWIDTH=800000\n'
              'https://media-hls.doppiocdn.net/b-hls-09/12345/12345_480p.m3u8\n'
              '#EXT-X-STREAM-INF:BANDWIDTH=1600000\n'
              'https://media-hls.doppiocdn.net/b-hls-09/12345/12345_1080p.m3u8\n',
        );
        mockHttp.respond(
          '12345_480p.m3u8',
          body: '#EXTM3U\n#EXT-X-TARGETDURATION:1\n',
        );
        mockHttp.respond(
          '12345_1080p.m3u8',
          body: '#EXTM3U\n#EXT-X-TARGETDURATION:1\n',
        );

        final result = await client.probePlaybackPlaylist(
          'https://edge-hls.doppiocdn.net/hls/12345/master/12345_auto.m3u8',
          preferredVariantId: '480p',
        );

        expect(result.isPlayable, isTrue);
        expect(result.finalUrl.toString(), contains('12345_480p.m3u8'));
        expect(result.finalUrl.queryParameters['psch'], 'v2');
        expect(result.finalUrl.queryParameters['pkey'], 'test-key');
      },
    );

    test('appends master mouflon auth to child playlist requests', () async {
      mockHttp.respond(
        'master/12345_auto.m3u8',
        body:
            '#EXTM3U\n'
            '#EXT-X-MOUFLON:PSCH:v2:abc123\n'
            '#EXT-X-STREAM-INF:BANDWIDTH=1600000\n'
            'https://media-hls.doppiocdn.net/b-hls-09/12345/12345_1080p.m3u8?minHeight=240&playlistType=lowLatency\n',
      );
      mockHttp.respond(
        '12345_1080p.m3u8?minHeight=240&playlistType=lowLatency&psch=v2&pkey=abc123',
        body: '#EXTM3U\n#EXT-X-TARGETDURATION:1\n',
      );

      final result = await client.probePlaybackPlaylist(
        'https://edge-hls.doppiocdn.net/hls/12345/master/12345_auto.m3u8',
      );

      expect(result.isPlayable, isTrue);
      expect(
        mockHttp.requests.last.url.toString(),
        contains('psch=v2&pkey=abc123'),
      );
      expect(result.finalUrl.queryParameters['psch'], 'v2');
      expect(result.finalUrl.queryParameters['pkey'], 'abc123');
    });
  });

  group('fetchPlaybackVariants', () {
    test('extracts source and fixed qualities from master playlist', () async {
      mockHttp.respond(
        'master/12345_auto.m3u8',
        body:
            '#EXTM3U\n'
            '#EXT-X-MOUFLON:PSCH:v2:test-key\n'
            '#EXT-X-STREAM-INF:BANDWIDTH=1200000\n'
            'https://media-hls.doppiocdn.net/b-hls-09/12345/12345.m3u8\n'
            '#EXT-X-STREAM-INF:BANDWIDTH=400000\n'
            'https://media-hls.doppiocdn.net/b-hls-09/12345/12345_240p.m3u8\n'
            '#EXT-X-STREAM-INF:BANDWIDTH=800000\n'
            'https://media-hls.doppiocdn.net/b-hls-09/12345/12345_480p.m3u8\n',
      );

      final variants = await client.fetchPlaybackVariants(
        'https://edge-hls.doppiocdn.net/hls/12345/master/12345_auto.m3u8',
      );

      expect(variants.map((variant) => variant.qualityId), [
        'source',
        '240p',
        '480p',
      ]);
      expect(variants.first.url.queryParameters['psch'], 'v2');
      expect(variants.first.url.queryParameters['pkey'], 'test-key');
    });

    test('returns empty variants for non-master playlist response', () async {
      mockHttp.respond(
        'master/12345_auto.m3u8',
        body: '#EXTM3U\n#EXT-X-TARGETDURATION:1\n',
      );

      final variants = await client.fetchPlaybackVariants(
        'https://edge-hls.doppiocdn.net/hls/12345/master/12345_auto.m3u8',
      );

      expect(variants, isEmpty);
    });
  });

  group('HttpStripchatApiClient Loopback', () {
    late HttpServer server;
    late _RedirectHttpClient redirectClient;
    late HttpStripchatApiClient loopbackClient;

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      redirectClient = _RedirectHttpClient(server.port);
      loopbackClient = HttpStripchatApiClient(
        client: redirectClient,
        retryPolicy: const ProviderRetryPolicy(maxAttempts: 1),
      );
    });

    tearDown(() async {
      loopbackClient.close();
      await server.close(force: true);
    });

    test(
      'real loopback server handles fetchInitialDynamic correctly',
      () async {
        final mockResponseData = {
          'initialDynamic': {
            'userHash': 'loopback-hash',
            'csrfToken': 'loopback-csrf',
            'guestId': 12345,
            'websocket': {
              'url': 'wss://loopback.ws',
              'token': _buildJwt(
                exp: DateTime.now().add(const Duration(hours: 1)),
              ),
            },
          },
        };

        // Set up the listener on the loopback server
        server.listen((HttpRequest request) {
          try {
            expect(request.uri.path, '/api/front/v3/config/initial-dynamic');
            expect(request.uri.queryParameters['requestPath'], '/');
            expect(request.headers.value('user-agent'), contains('Mozilla'));

            request.response
              ..statusCode = HttpStatus.ok
              ..headers.contentType = ContentType.json
              ..write(jsonEncode(mockResponseData))
              ..close();
          } catch (e) {
            // Send error response to not block the client infinitely
            request.response
              ..statusCode = HttpStatus.internalServerError
              ..write(e.toString())
              ..close();
          }
        });

        final result = await loopbackClient.fetchInitialDynamic();
        expect(result['userHash'], 'loopback-hash');
        expect(result['csrfToken'], 'loopback-csrf');
      },
    );
  });
}

String _buildJwt({required DateTime exp}) {
  final header = base64Url.encode(utf8.encode(jsonEncode({'alg': 'none'})));
  final payload = base64Url.encode(
    utf8.encode(
      jsonEncode({'exp': exp.toUtc().millisecondsSinceEpoch ~/ 1000}),
    ),
  );
  return '$header.$payload.signature';
}

class _FailingHttpClient extends http.BaseClient {
  _FailingHttpClient(this.onSend);
  final void Function() onSend;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    onSend();
    return http.StreamedResponse(const Stream.empty(), 200);
  }
}
