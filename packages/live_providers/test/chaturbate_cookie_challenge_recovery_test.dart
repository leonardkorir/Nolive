import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:live_providers/live_providers.dart';
import 'package:live_providers/src/providers/chaturbate/chaturbate_api_client.dart';
import 'package:live_providers/src/providers/chaturbate/chaturbate_live_data_source.dart';
import 'package:test/test.dart';

const String _roomId = 'roomy';

/// Room page shell carrying the realtime bootstrap the danmaku session needs.
const String _bootstrapHtml = '''
<html><script>
window["tsInstance"] = new TS({
  push_services: JSON.parse('[{"backend":"a","host":"realtime.pa.highwebmedia.com"}]'),
  csrftoken: 'csrf-from-page'
});
</script></html>
''';

/// What Cloudflare serves instead of the room when it wants a challenge solved.
const String _cloudflareChallengeBody = '''
<html><head><title>Just a moment...</title></head>
<body><script>window._cf_chl_opt = {};</script></body></html>
''';

/// A 200 response whose shell simply carries no realtime bootstrap.
const String _emptyShellHtml = '<html>anonymous shell</html>';

void main() {
  group('chaturbate room page cookie / challenge handling', () {
    test('a configured cookie is used on the very first request', () async {
      final pageCookies = <String>[];
      final source = _dataSource(
        cookie: 'cf_clearance=live',
        onRoomPage: (cookie) {
          pageCookies.add(cookie);
          return http.Response(_bootstrapHtml, 200);
        },
      );

      final detail = await source.fetchRoomDetail(_roomId);

      expect(
        pageCookies.single,
        contains('cf_clearance=live'),
        reason: 'anonymous-first doubles traffic and provokes CF/429',
      );
      expect(
        (detail.danmakuToken as ChaturbateDanmakuToken).csrfToken,
        'csrf-from-page',
      );
    });

    test(
      'a cookie that is itself challenged falls back to one anonymous retry',
      () async {
        final pageCookies = <String>[];
        final source = _dataSource(
          cookie: 'cf_clearance=stale',
          onRoomPage: (cookie) {
            pageCookies.add(cookie);
            if (pageCookies.length == 1) {
              return http.Response(_cloudflareChallengeBody, 403);
            }
            return http.Response(_bootstrapHtml, 200);
          },
        );

        final detail = await source.fetchRoomDetail(_roomId);

        expect(pageCookies, hasLength(2));
        expect(pageCookies.first, contains('cf_clearance=stale'));
        expect(
          pageCookies[1],
          isNot(contains('cf_clearance')),
          reason:
              'a stale cf_clearance can itself provoke the interstitial, so '
              'the retry has to drop it',
        );
        expect(
          (detail.danmakuToken as ChaturbateDanmakuToken).csrfToken,
          'csrf-from-page',
          reason: 'the anonymous retry has to actually feed the danmaku token',
        );
      },
    );

    test('the anonymous retry is attempted at most once', () async {
      var pageRequests = 0;
      final source = _dataSource(
        cookie: 'cf_clearance=stale',
        onRoomPage: (_) {
          pageRequests += 1;
          return http.Response(_cloudflareChallengeBody, 403);
        },
      );

      await source.fetchRoomDetail(_roomId);

      expect(pageRequests, 2);
    });

    test('without a cookie there is nothing to retry with', () async {
      var pageRequests = 0;
      final source = _dataSource(
        cookie: '',
        onRoomPage: (_) {
          pageRequests += 1;
          return http.Response(_cloudflareChallengeBody, 403);
        },
      );

      await source.fetchRoomDetail(_roomId);

      expect(
        pageRequests,
        1,
        reason: 'retrying anonymously after an anonymous request is a no-op',
      );
    });

    test(
      'a 200 shell without bootstrap does not burn a second request',
      () async {
        var pageRequests = 0;
        final source = _dataSource(
          cookie: 'cf_clearance=live',
          onRoomPage: (_) {
            pageRequests += 1;
            return http.Response(_emptyShellHtml, 200);
          },
        );

        await source.fetchRoomDetail(_roomId);

        expect(
          pageRequests,
          1,
          reason:
              'no second request would produce a csrf the first one lacked, so '
              'the failure kind is recorded instead of retried',
        );
      },
    );
  });

  group('chaturbate failure diagnostics', () {
    test('a skipped retry says why it was skipped', () async {
      final diagnostics = <String>[];
      final source = _dataSource(
        cookie: '',
        onRoomPage: (_) => http.Response(_cloudflareChallengeBody, 403),
        diagnostics: diagnostics.add,
      );

      await source.fetchRoomDetail(_roomId);

      expect(
        diagnostics.where((line) => line.contains('retry=skipped')),
        isNotEmpty,
        reason: 'the log must not leave "was a cookie sent?" to deduction',
      );
      expect(
        diagnostics.firstWhere((line) => line.contains('retry=skipped')),
        allOf(contains('hasCookie=false'), contains('challenge=true')),
      );
    });

    test('a retry that also fails is recorded', () async {
      final diagnostics = <String>[];
      final source = _dataSource(
        cookie: 'cf_clearance=stale',
        onRoomPage: (_) => http.Response(_cloudflareChallengeBody, 403),
        diagnostics: diagnostics.add,
      );

      await source.fetchRoomDetail(_roomId);

      expect(
        diagnostics.where((line) => line.contains('retrying anonymously')),
        isNotEmpty,
      );
      expect(
        diagnostics.where(
          (line) => line.contains('anonymous retry also failed'),
        ),
        isNotEmpty,
      );
    });

    test('a retry that succeeds is recorded', () async {
      final diagnostics = <String>[];
      var calls = 0;
      final source = _dataSource(
        cookie: 'cf_clearance=stale',
        onRoomPage: (_) {
          calls += 1;
          return calls == 1
              ? http.Response(_cloudflareChallengeBody, 403)
              : http.Response(_bootstrapHtml, 200);
        },
        diagnostics: diagnostics.add,
      );

      await source.fetchRoomDetail(_roomId);

      expect(
        diagnostics.where((line) => line.contains('anonymous retry succeeded')),
        isNotEmpty,
      );
    });
  });

  group('chaturbate danmaku unavailable reason', () {
    final diagnostics = <String>[];

    Future<String?> reasonFor({required String cookie}) async {
      final client = _apiClient(
        cookie: cookie,
        onRoomPage: (_) => http.Response(_cloudflareChallengeBody, 403),
      );
      final provider = ChaturbateProvider(
        dataSource: ChaturbateLiveDataSource(apiClient: client),
        danmakuApiClient: client,
        diagnostics: diagnostics.add,
      );
      final detail = await provider.fetchRoomDetail(_roomId);
      final session = await provider.createDanmakuSession(detail);
      return session.unavailableReason;
    }

    test('tells an unconfigured user to add a cookie', () async {
      final reason = await reasonFor(cookie: '');

      expect(reason, isNotNull);
      expect(reason, contains('未配置'));
      expect(
        reason,
        isNot(contains('更新')),
        reason: 'telling users to update a cookie they never added misleads',
      );
      expect(
        diagnostics.where((line) => line.contains('advice=add-cookie')),
        isNotEmpty,
        reason: 'the log must record which advice the user was shown',
      );
    });

    test('tells a configured user their cookie may have expired', () async {
      final reason = await reasonFor(cookie: 'cf_clearance=stale');

      expect(reason, isNotNull);
      expect(reason, contains('更新'));
      expect(reason, isNot(contains('未配置')));
      expect(
        diagnostics.where((line) => line.contains('advice=update-cookie')),
        isNotEmpty,
      );
    });
  });
}

HttpChaturbateApiClient _apiClient({
  required String cookie,
  required http.Response Function(String cookie) onRoomPage,
}) {
  return HttpChaturbateApiClient(
    cookie: cookie,
    requestScheduler: ChaturbateRequestScheduler(
      minSpacing: Duration.zero,
      maxConcurrent: 8,
    ),
    client: MockClient((request) async {
      if (request.url.path == '/api/chatvideocontext/$_roomId/') {
        return http.Response(
          jsonEncode({
            'broadcaster_username': _roomId,
            'broadcaster_uid': '100',
            'room_uid': '200',
            'room_status': 'public',
            'hls_source': 'https://edge.example/live.m3u8',
          }),
          200,
        );
      }
      if (request.url.path == '/$_roomId/') {
        return onRoomPage(request.headers['cookie'] ?? '');
      }
      fail('Unexpected request: ${request.url}');
    }),
  );
}

ChaturbateLiveDataSource _dataSource({
  required String cookie,
  required http.Response Function(String cookie) onRoomPage,
  void Function(String message)? diagnostics,
}) {
  return ChaturbateLiveDataSource(
    apiClient: _apiClient(cookie: cookie, onRoomPage: onRoomPage),
    diagnostics: diagnostics,
  );
}
