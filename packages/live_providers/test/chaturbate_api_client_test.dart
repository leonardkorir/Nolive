import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:live_core/live_core.dart';
import 'package:live_providers/src/providers/chaturbate/chaturbate_api_client.dart';
import 'package:test/test.dart';

void main() {
  test('chaturbate api client forwards configured cookie header', () async {
    final client = HttpChaturbateApiClient(
      cookie: 'cf_clearance=test-clearance; __cf_bm=test-bm',
      client: MockClient((request) async {
        expect(request.headers['cookie'],
            'cf_clearance=test-clearance; __cf_bm=test-bm');
        expect(request.url.path, '/kittengirlxo/');
        expect(
          request.headers['user-agent'],
          HttpChaturbateApiClient.browserUserAgent,
        );
        expect(
          request.headers['sec-fetch-mode'],
          'navigate',
        );
        expect(
          request.headers['sec-fetch-dest'],
          'document',
        );
        expect(
          request.headers['upgrade-insecure-requests'],
          '1',
        );
        expect(
          request.headers['referer'],
          'https://chaturbate.com/',
        );
        return http.Response('<html></html>', 200);
      }),
    );

    final page = await client.fetchRoomPage('kittengirlxo');
    expect(page, '<html></html>');
  });

  test('chaturbate api client surfaces cloudflare challenge guidance',
      () async {
    final client = HttpChaturbateApiClient(
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
          allOf(contains('Cloudflare challenge'), contains('浏览器完整 Cookie')),
        ),
      ),
    );
  });

  test('chaturbate discover request carries browser-like cors headers',
      () async {
    final client = HttpChaturbateApiClient(
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
      client: MockClient((request) async {
        expect(
          request.headers['referer'],
          'https://chaturbate.com/realcest/',
        );
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

  test('chaturbate room context can suppress configured cookie header',
      () async {
    final client = HttpChaturbateApiClient(
      cookie: 'cf_clearance=test-clearance; __cf_bm=test-bm',
      client: MockClient((request) async {
        expect(request.url.path, '/api/chatvideocontext/kittengirlxo/');
        expect(request.headers.containsKey('cookie'), isFalse);
        return http.Response('{}', 200);
      }),
    );

    await client.fetchRoomContext(
      'kittengirlxo',
      cookie: '',
    );
  });

  test('chaturbate hls playlist can suppress configured cookie header',
      () async {
    final client = HttpChaturbateApiClient(
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
}
