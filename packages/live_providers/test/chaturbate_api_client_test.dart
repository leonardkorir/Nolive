import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:live_core/live_core.dart';
import 'package:live_providers/src/providers/chaturbate/chaturbate_api_client.dart';
import 'package:live_providers/src/providers/chaturbate/chaturbate_request_scheduler.dart';
import 'package:live_providers/src/providers/provider_runtime_support.dart';
import 'package:test/test.dart';

void main() {
  test('chaturbate api client forwards configured cookie header', () async {
    final client = HttpChaturbateApiClient(
      requestScheduler: ChaturbateRequestScheduler(minSpacing: Duration.zero, maxConcurrent: 8),
      cookie: 'cf_clearance=test-clearance; __cf_bm=test-bm',
      client: MockClient((request) async {
        expect(
          request.headers['cookie'],
          'cf_clearance=test-clearance; __cf_bm=test-bm',
        );
        expect(request.url.path, '/kittengirlxo/');
        expect(
          request.headers['user-agent'],
          HttpChaturbateApiClient.browserUserAgent,
        );
        expect(request.headers['sec-fetch-mode'], 'navigate');
        expect(request.headers['sec-fetch-dest'], 'document');
        expect(request.headers['upgrade-insecure-requests'], '1');
        expect(request.headers['referer'], 'https://chaturbate.com/');
        return http.Response('<html></html>', 200);
      }),
    );

    final page = await client.fetchRoomPage('kittengirlxo');
    expect(page, '<html></html>');
  });

  test(
    'chaturbate room page decoding prefers utf8 bytes over bad charset',
    () async {
      final expected = '<html><body>你好😀</body></html>';
      final client = HttpChaturbateApiClient(
      requestScheduler: ChaturbateRequestScheduler(minSpacing: Duration.zero, maxConcurrent: 8),
        client: MockClient((request) async {
          return http.Response.bytes(
            utf8.encode(expected),
            200,
            headers: {'content-type': 'text/html; charset=latin1'},
          );
        }),
      );

      final page = await client.fetchRoomPage('utf8-room');
      expect(page, expected);
    },
  );

  test(
    'chaturbate api client surfaces cloudflare challenge guidance',
    () async {
      final client = HttpChaturbateApiClient(
      requestScheduler: ChaturbateRequestScheduler(minSpacing: Duration.zero, maxConcurrent: 8),
        client: MockClient((request) async {
          return http.Response(
            '<html><head><title>Just a moment...</title></head></html>',
            403,
            headers: {'cf-mitigated': 'challenge'},
          );
        }),
      );

      await expectLater(
        () => client.fetchDiscoverCarousel('most_popular'),
        throwsA(
          isA<ProviderParseException>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('Cloudflare challenge'),
              contains('If the room still opens, you can ignore this'),
            ),
          ),
        ),
      );
    },
  );

  test('chaturbate discover request carries browser-like cors headers', () async {
    final client = HttpChaturbateApiClient(
      requestScheduler: ChaturbateRequestScheduler(minSpacing: Duration.zero, maxConcurrent: 8),
      client: MockClient((request) async {
        expect(
          request.url.toString(),
          'https://chaturbate.com/api/ts/discover/carousels/most_popular/?genders',
        );
        expect(request.headers['accept'], '*/*');
        expect(request.headers['referer'], 'https://chaturbate.com/discover/');
        expect(request.headers['sec-fetch-mode'], 'cors');
        expect(request.headers['sec-fetch-dest'], 'empty');
        expect(request.headers['x-requested-with'], 'XMLHttpRequest');
        return http.Response('{}', 200);
      }),
    );

    await client.fetchDiscoverCarousel('most_popular');
  });

  test('chaturbate discover request uses gender route as referer', () async {
    final client = HttpChaturbateApiClient(
      requestScheduler: ChaturbateRequestScheduler(minSpacing: Duration.zero, maxConcurrent: 8),
      client: MockClient((request) async {
        expect(
          request.headers['referer'],
          'https://chaturbate.com/discover/female/',
        );
        return http.Response('{}', 200);
      }),
    );

    await client.fetchDiscoverCarousel('most_popular', genders: 'f');
  });

  test('chaturbate danmaku auth/history use room page as referer', () async {
    var authCalls = 0;
    final client = HttpChaturbateApiClient(
      requestScheduler: ChaturbateRequestScheduler(minSpacing: Duration.zero, maxConcurrent: 8),
      client: MockClient((request) async {
        expect(request.headers['referer'], 'https://chaturbate.com/realcest/');
        authCalls += 1;
        return http.Response(authCalls == 1 ? '{}' : '[]', 200);
      }),
    );

    await client.authenticatePushService(
      roomId: 'realcest',
      csrfToken: 'csrf',
      backend: 'a',
      presenceId: '+fixture',
      topics: const {},
    );
    await client.fetchRoomHistory(
      roomId: 'realcest',
      csrfToken: 'csrf',
      topics: const {},
    );
  });

  test(
    'chaturbate room history 403 is typed as non-fatal history absence',
    () async {
      final client = HttpChaturbateApiClient(
      requestScheduler: ChaturbateRequestScheduler(minSpacing: Duration.zero, maxConcurrent: 8),
        client: MockClient((request) async {
          expect(request.url.path, '/push_service/room_history/');
          return http.Response('forbidden', 403);
        }),
      );

      await expectLater(
        () => client.fetchRoomHistory(
          roomId: 'realcest',
          csrfToken: 'csrf',
          topics: const {},
        ),
        throwsA(
          isA<ChaturbateRoomHistoryUnavailableException>()
              .having((error) => error.statusCode, 'statusCode', 403)
              .having(
                (error) => error.message,
                'message',
                contains('realtime danmaku can continue'),
              ),
        ),
      );
    },
  );

  test('chaturbate room history cloudflare 403 remains fatal', () async {
    final client = HttpChaturbateApiClient(
      requestScheduler: ChaturbateRequestScheduler(minSpacing: Duration.zero, maxConcurrent: 8),
      client: MockClient((request) async {
        return http.Response(
          '<html><head><title>Just a moment...</title></head></html>',
          403,
          headers: {'cf-mitigated': 'challenge'},
        );
      }),
    );

    await expectLater(
      () => client.fetchRoomHistory(
        roomId: 'realcest',
        csrfToken: 'csrf',
        topics: const {},
      ),
      throwsA(
        isA<ProviderParseException>().having(
          (error) => error.message,
          'message',
          contains('Cloudflare challenge'),
        ),
      ),
    );
  });

  test(
    'chaturbate room context can suppress configured cookie header',
    () async {
      final client = HttpChaturbateApiClient(
      requestScheduler: ChaturbateRequestScheduler(minSpacing: Duration.zero, maxConcurrent: 8),
        cookie: 'cf_clearance=test-clearance; __cf_bm=test-bm',
        client: MockClient((request) async {
          expect(request.url.path, '/api/chatvideocontext/kittengirlxo/');
          expect(request.headers.containsKey('cookie'), isFalse);
          return http.Response('{}', 200);
        }),
      );

      await client.fetchRoomContext('kittengirlxo', cookie: '');
    },
  );

  test('chaturbate room page can suppress configured cookie header', () async {
    final client = HttpChaturbateApiClient(
      requestScheduler: ChaturbateRequestScheduler(minSpacing: Duration.zero, maxConcurrent: 8),
      cookie: 'cf_clearance=test-clearance; __cf_bm=test-bm',
      client: MockClient((request) async {
        expect(request.url.path, '/kittengirlxo/');
        expect(request.headers.containsKey('cookie'), isFalse);
        return http.Response('<html></html>', 200);
      }),
    );

    await client.fetchRoomPage('kittengirlxo', cookie: '');
  });

  test('chaturbate room list can suppress configured cookie header', () async {
    final client = HttpChaturbateApiClient(
      requestScheduler: ChaturbateRequestScheduler(minSpacing: Duration.zero, maxConcurrent: 8),
      cookie: 'cf_clearance=test-clearance; __cf_bm=test-bm',
      client: MockClient((request) async {
        expect(request.url.path, '/api/ts/roomlist/room-list/');
        expect(request.headers.containsKey('cookie'), isFalse);
        return http.Response(
          jsonEncode({
            'rooms': const <Map<String, Object?>>[],
            'total_count': 0,
          }),
          200,
        );
      }),
    );

    await client.fetchRoomList(query: '', genders: 'f', cookie: '');
  });

  test('chaturbate hls playlist can suppress configured cookie header', () async {
    final client = HttpChaturbateApiClient(
      requestScheduler: ChaturbateRequestScheduler(minSpacing: Duration.zero, maxConcurrent: 8),
      cookie: 'cf_clearance=test-clearance; __cf_bm=test-bm',
      client: MockClient((request) async {
        expect(
          request.url.toString(),
          'https://edge11-lax.live.mmcdn.com/v1/edge/streams/origin.demo/llhls.m3u8?token=test',
        );
        expect(request.headers.containsKey('cookie'), isFalse);
        expect(request.headers['referer'], 'https://chaturbate.com/');
        return http.Response('#EXTM3U', 200);
      }),
    );

    await client.fetchHlsPlaylist(
      'https://edge11-lax.live.mmcdn.com/v1/edge/streams/origin.demo/llhls.m3u8?token=test',
      referer: 'https://chaturbate.com/demo/',
      cookie: '',
    );
  });

  test(
    'chaturbate api client retries transient document failures once',
    () async {
      var requestCount = 0;
      final client = HttpChaturbateApiClient(
        requestScheduler: ChaturbateRequestScheduler(
          minSpacing: Duration.zero,
          maxConcurrent: 8,
        ),
        // Explicit multi-attempt policy for this regression only.
        retryPolicy: const ProviderRetryPolicy(maxAttempts: 2),
        browserProfile: const ProviderBrowserProfile(
          userAgent: 'SimpleLive-CB-UA',
          acceptLanguage: 'de-DE',
          browserName: 'Chrome',
          browserVersion: '146.0.0.0',
          osName: 'Linux',
          osVersion: '',
          secChUa: '"Chromium";v="146"',
          secChUaMobile: '?0',
          secChUaPlatform: '"Linux"',
        ),
        client: MockClient((request) async {
          requestCount += 1;
          expect(request.headers['user-agent'], 'SimpleLive-CB-UA');
          expect(request.headers['accept-language'], 'de-DE');
          if (requestCount == 1) {
            return http.Response('busy', 503);
          }
          return http.Response('<html>retry-ok</html>', 200);
        }),
      );

      final page = await client.fetchRoomPage('retry-room');

      expect(page, '<html>retry-ok</html>');
      expect(requestCount, 2);
    },
  );

  test(
    'chaturbate room list retries without fingerprint when anonymous api rejects it',
    () async {
      var requestCount = 0;
      final client = HttpChaturbateApiClient(
      requestScheduler: ChaturbateRequestScheduler(minSpacing: Duration.zero, maxConcurrent: 8),
        client: MockClient((request) async {
          requestCount += 1;
          if (requestCount == 1) {
            expect(request.url.queryParameters['require_fingerprint'], 'true');
            return http.Response(
              jsonEncode({'code': 'missing_fingerprint'}),
              400,
            );
          }
          expect(
            request.url.queryParameters.containsKey('require_fingerprint'),
            isFalse,
          );
          return http.Response(
            jsonEncode({
              'rooms': const <Map<String, Object?>>[],
              'total_count': 0,
            }),
            200,
          );
        }),
      );

      final response = await client.fetchRoomList(query: 'demo');

      expect(response['rooms'], isEmpty);
      expect(requestCount, 2);
    },
  );

  test('chaturbate empty room list query omits keywords parameter', () async {
    final client = HttpChaturbateApiClient(
      requestScheduler: ChaturbateRequestScheduler(minSpacing: Duration.zero, maxConcurrent: 8),
      client: MockClient((request) async {
        expect(request.url.path, '/api/ts/roomlist/room-list/');
        expect(request.url.queryParameters.containsKey('keywords'), isFalse);
        expect(request.url.queryParameters['genders'], 'f');
        return http.Response(
          jsonEncode({
            'rooms': const <Map<String, Object?>>[],
            'total_count': 0,
          }),
          200,
        );
      }),
    );

    await client.fetchRoomList(query: '', genders: 'f');
  });

  test('chaturbate room list can skip fingerprint requirement', () async {
    final client = HttpChaturbateApiClient(
      requestScheduler: ChaturbateRequestScheduler(minSpacing: Duration.zero, maxConcurrent: 8),
      client: MockClient((request) async {
        expect(request.url.path, '/api/ts/roomlist/room-list/');
        expect(
          request.url.queryParameters.containsKey('require_fingerprint'),
          isFalse,
        );
        return http.Response(
          jsonEncode({
            'rooms': const <Map<String, Object?>>[],
            'total_count': 0,
          }),
          200,
        );
      }),
    );

    await client.fetchRoomList(
      query: '',
      genders: 'f',
      requireFingerprint: false,
    );
  });
}
