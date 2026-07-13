import 'dart:async';
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:live_providers/src/providers/bilibili/bilibili_auth_context.dart';
import 'package:live_providers/src/providers/bilibili/bilibili_sign_service.dart';
import 'package:live_providers/src/providers/bilibili/bilibili_transport.dart';
import 'package:live_providers/src/providers/provider_runtime_support.dart';
import 'package:test/test.dart';

void main() {
  test('bilibili WBI mixin table matches known fixture', () async {
    final service = BilibiliSignService(
      transport: _DelayedBuvidTransport(),
      authContext: BilibiliAuthContext(),
    );

    final signed = await service.signUrl(
      'https://api.bilibili.com/x/web-interface/search/type?keyword=test&page=1',
    );

    expect(signed['wts'], isNotNull);
    expect(signed['w_rid'], hasLength(32));
    expect(signed['keyword'], 'test');
    expect(signed['page'], '1');
  });

  test('bilibili sign service deduplicates concurrent buvid loads', () async {
    final transport = _DelayedBuvidTransport();
    final service = BilibiliSignService(
      transport: transport,
      authContext: BilibiliAuthContext(cookie: '', userId: 0),
    );

    final results = await Future.wait([
      service.buildHeaders(),
      service.buildHeaders(),
    ]);

    expect(transport.spiRequests, 1);
    expect(results.first['cookie'], contains('buvid3=mock-buvid3'));
    expect(results.last['cookie'], contains('buvid3=mock-buvid3'));
    expect(results.first['user-agent'], BilibiliSignService.defaultUserAgent);
    expect(results.first['user-agent'], contains('Windows NT'));
    expect(results.first['user-agent'], contains('Edg/126.0.0.0'));
    expect(results.first.keys, isNot(contains('accept-language')));
    expect(
      service.browserFingerprintDiagnostics,
      'ua_profile=bilibili_legacy_desktop has_accept_language=false',
    );
  });

  test('bilibili sign service honors injected browser profile', () async {
    final transport = _DelayedBuvidTransport();
    final service = BilibiliSignService(
      transport: transport,
      authContext: BilibiliAuthContext(cookie: '', userId: 0),
      browserProfile: const ProviderBrowserProfile(
        userAgent: 'SimpleLive-Test-UA',
        acceptLanguage: 'en-US',
        browserName: 'Chrome',
        browserVersion: '146.0.0.0',
        osName: 'Linux',
        osVersion: '',
      ),
    );

    final headers = await service.buildHeaders();

    expect(headers['user-agent'], 'SimpleLive-Test-UA');
    expect(headers['accept-language'], 'en-US');
    expect(
      service.browserFingerprintDiagnostics,
      'ua_profile=custom has_accept_language=true',
    );
    expect(transport.lastHeaders['user-agent'], 'SimpleLive-Test-UA');
  });

  test(
    'bilibili buildHeaders tolerates spi bootstrap request failure',
    () async {
      final service = BilibiliSignService(
        transport: _SpiFailureTransport(),
        authContext: BilibiliAuthContext(cookie: '', userId: 0),
      );

      final headers = await service.buildHeaders();

      expect(headers['user-agent'], BilibiliSignService.defaultUserAgent);
      expect(headers.containsKey('cookie'), isFalse);
    },
  );

  test(
    'bilibili sign service rewrites nav transport failures as WBI errors',
    () async {
      final service = BilibiliSignService(
        transport: _NavFailureTransport(),
        authContext: BilibiliAuthContext(cookie: '', userId: 0),
      );

      await expectLater(
        () => service.signUrl(
          'https://api.bilibili.com/x/web-interface/search/type?keyword=test&page=1',
        ),
        throwsA(
          isA<ProviderParseException>().having(
            (error) => error.message,
            'message',
            contains('load WBI keys failed'),
          ),
        ),
      );
    },
  );
}

class _DelayedBuvidTransport implements BilibiliTransport {
  int spiRequests = 0;
  Map<String, String> lastHeaders = const {};

  @override
  Future<Map<String, dynamic>> getJson(
    String url, {
    Map<String, String> queryParameters = const {},
    Map<String, String> headers = const {},
  }) async {
    final text = await getText(
      url,
      queryParameters: queryParameters,
      headers: headers,
    );
    return (jsonDecode(text) as Map).cast<String, dynamic>();
  }

  @override
  Future<String> getText(
    String url, {
    Map<String, String> queryParameters = const {},
    Map<String, String> headers = const {},
  }) async {
    lastHeaders = headers;
    if (url.startsWith('https://api.bilibili.com/x/frontend/finger/spi')) {
      spiRequests += 1;
      await Future<void>.delayed(const Duration(milliseconds: 10));
      return jsonEncode({
        'code': 0,
        'data': {'b_3': 'mock-buvid3', 'b_4': 'mock-buvid4'},
      });
    }
    if (url.startsWith('https://api.bilibili.com/x/web-interface/nav')) {
      return jsonEncode({
        'code': 0,
        'data': {
          'wbi_img': {
            'img_url':
                'https://i0.hdslb.com/bfs/wbi/abcdefghijklmnopqrstuvwxyzabcdef.png',
            'sub_url':
                'https://i0.hdslb.com/bfs/wbi/1234567890abcdef1234567890abcdef.png',
          },
        },
      });
    }
    throw UnimplementedError('Unexpected request: $url');
  }
}

class _SpiFailureTransport extends _DelayedBuvidTransport {
  @override
  Future<String> getText(
    String url, {
    Map<String, String> queryParameters = const {},
    Map<String, String> headers = const {},
  }) {
    if (url.startsWith('https://api.bilibili.com/x/frontend/finger/spi')) {
      throw ProviderParseException(
        providerId: ProviderId.bilibili,
        message:
            'Bilibili request failed before response: https://api.bilibili.com/x/frontend/finger/spi',
      );
    }
    return super.getText(
      url,
      queryParameters: queryParameters,
      headers: headers,
    );
  }
}

class _NavFailureTransport extends _DelayedBuvidTransport {
  @override
  Future<String> getText(
    String url, {
    Map<String, String> queryParameters = const {},
    Map<String, String> headers = const {},
  }) {
    if (url.startsWith('https://api.bilibili.com/x/web-interface/nav')) {
      throw ProviderParseException(
        providerId: ProviderId.bilibili,
        message:
            'Bilibili request failed before response: https://api.bilibili.com/x/web-interface/nav',
      );
    }
    return super.getText(
      url,
      queryParameters: queryParameters,
      headers: headers,
    );
  }
}
