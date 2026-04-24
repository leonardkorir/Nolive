import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:live_providers/live_providers.dart';
import 'package:live_providers/src/danmaku/provider_unavailable_danmaku_session.dart';
import 'package:live_providers/src/providers/bilibili/bilibili_auth_context.dart';
import 'package:live_providers/src/providers/bilibili/bilibili_live_data_source.dart';
import 'package:live_providers/src/providers/bilibili/bilibili_sign_service.dart';
import 'package:live_providers/src/providers/bilibili/bilibili_transport.dart';
import 'package:test/test.dart';

void main() {
  test('live bilibili runtime maps signed search/detail/play flow', () async {
    final transport = _FakeBilibiliTransport();
    final authContext =
        BilibiliAuthContext(cookie: 'SESSDATA=test', userId: 42);
    final signService = BilibiliSignService(
      transport: transport,
      authContext: authContext,
    );
    final provider = BilibiliProvider(
      dataSource: BilibiliLiveDataSource(
        transport: transport,
        signService: signService,
        authContext: authContext,
      ),
    );

    final rooms = await provider.searchRooms('测试');
    expect(rooms.items, hasLength(1));
    expect(rooms.items.single.areaName, '测试区');
    expect(rooms.items.single.streamerAvatarUrl, startsWith('https://'));

    final detail = await provider.fetchRoomDetail(rooms.items.single.roomId);
    expect(detail.roomId, '32558935');
    expect(detail.areaName, '测试区');
    expect(detail.sourceUrl, 'https://live.bilibili.com/32558935');
    expect(detail.startedAt, isNotNull);
    expect(
      (detail.danmakuToken! as Map<String, Object?>)['serverHost'],
      'broadcastlv.chat.bilibili.com',
    );

    final qualities = await provider.fetchPlayQualities(detail);
    expect(qualities, isNotEmpty);
    expect(qualities.any((item) => item.isDefault), isTrue);

    final urls = await provider.fetchPlayUrls(
      detail: detail,
      quality: qualities.firstWhere((item) => item.isDefault),
    );
    expect(urls, isNotEmpty);
    expect(urls.first.url, startsWith('https://'));
    expect(urls.first.headers['referer'], 'https://live.bilibili.com');
    expect(
      transport.requestedUrls.where((item) => item.contains('w_rid=')).length,
      greaterThanOrEqualTo(2),
    );
  });

  test('live bilibili runtime degrades danmaku when danmu info fails',
      () async {
    final transport = _FakeBilibiliDanmakuUnavailableTransport();
    final authContext =
        BilibiliAuthContext(cookie: 'SESSDATA=test; DedeUserID=42', userId: 7);
    final provider = BilibiliProvider(
      dataSource: BilibiliLiveDataSource(
        transport: transport,
        signService: BilibiliSignService(
          transport: transport,
          authContext: authContext,
        ),
        authContext: authContext,
      ),
    );

    final detail = await provider.fetchRoomDetail('32558935');
    final token = detail.danmakuToken! as Map<String, Object?>;

    expect(detail.roomId, '32558935');
    expect(token['mode'], 'unavailable');

    final session = await provider.createDanmakuSession(detail);
    expect(session, isA<ProviderUnavailableDanmakuSession>());
  });

  test('live bilibili runtime throws on room detail business failure',
      () async {
    final transport = _FakeBilibiliRoomInfoFailureTransport();
    final authContext =
        BilibiliAuthContext(cookie: 'SESSDATA=test', userId: 42);
    final provider = BilibiliProvider(
      dataSource: BilibiliLiveDataSource(
        transport: transport,
        signService: BilibiliSignService(
          transport: transport,
          authContext: authContext,
        ),
        authContext: authContext,
      ),
    );

    expect(
      () => provider.fetchRoomDetail('32558935'),
      throwsA(isA<ProviderParseException>()),
    );
  });

  test(
      'live bilibili runtime falls back to anonymous public API when cookie is expired',
      () async {
    final transport = _FakeBilibiliExpiredCookieTransport();
    final authContext = BilibiliAuthContext(
      cookie: 'SESSDATA=expired-session; DedeUserID=42',
      userId: 42,
    );
    final provider = BilibiliProvider(
      dataSource: BilibiliLiveDataSource(
        transport: transport,
        signService: BilibiliSignService(
          transport: transport,
          authContext: authContext,
        ),
        authContext: authContext,
      ),
    );

    final recommend = await provider.fetchRecommendRooms();
    expect(recommend.items, hasLength(1));

    final detail = await provider.fetchRoomDetail('32558935');
    final token = detail.danmakuToken! as Map<String, Object?>;

    expect(detail.roomId, '32558935');
    expect(token['roomId'], 32558935);
    expect(transport.unauthorizedAuthedRequests, 2);
    expect(transport.navAnonymousRequests, 1);
    expect(transport.publicApiRequestsWithExpiredCookie, isEmpty);
  });

  test('live bilibili runtime normalizes malformed display text', () async {
    final transport = _FakeBilibiliMalformedTextTransport();
    final authContext = BilibiliAuthContext(cookie: '', userId: 0);
    final provider = BilibiliProvider(
      dataSource: BilibiliLiveDataSource(
        transport: transport,
        signService: BilibiliSignService(
          transport: transport,
          authContext: authContext,
        ),
        authContext: authContext,
      ),
    );

    final rooms = await provider.fetchRecommendRooms();
    final detail = await provider.fetchRoomDetail('32558935');

    expect(rooms.items.single.title, '游戏厅');
    expect(rooms.items.single.streamerName, '热门主播');
    expect(rooms.items.single.areaName, '热门游戏');
    expect(detail.title, '游戏厅');
    expect(detail.streamerName, '热门主播');
    expect(detail.areaName, '热门游戏');
    expect(detail.description, '主播简介');
  });

  test(
      'live bilibili runtime normalizes missing DedeUserID from stored user id',
      () async {
    final authContext = BilibiliAuthContext(
      cookie: 'SESSDATA=test-session; bili_jct=test-jct',
      userId: 42,
    );

    expect(authContext.cookie, contains('SESSDATA=test-session'));
    expect(authContext.cookie, contains('DedeUserID=42'));
  });

  test(
      'live bilibili runtime falls back to search-based recommend rooms when WBI key loading keeps failing',
      () async {
    final transport = _FakeBilibiliRecommendFallbackTransport();
    final authContext = BilibiliAuthContext(
      cookie: 'SESSDATA=expired-session; DedeUserID=42',
      userId: 42,
    );
    final provider = BilibiliProvider(
      dataSource: BilibiliLiveDataSource(
        transport: transport,
        signService: BilibiliSignService(
          transport: transport,
          authContext: authContext,
        ),
        authContext: authContext,
      ),
    );

    final recommend = await provider.fetchRecommendRooms();

    expect(recommend.items, hasLength(1));
    expect(recommend.items.single.title, '推荐回退房间');
    expect(recommend.items.single.streamerName, '回退主播');
    expect(transport.navRequests, greaterThanOrEqualTo(2));
    expect(transport.searchRequests, greaterThanOrEqualTo(1));
  });

  test(
      'live bilibili runtime keeps public browse anonymous while using account cookie for WBI keys, play info and danmaku auth',
      () async {
    final transport = _FakeBilibiliAnonymousPublicTransport();
    final authContext = BilibiliAuthContext(
      cookie: 'SESSDATA=test-session; bili_jct=test-jct',
      userId: 42,
    );
    final provider = BilibiliProvider(
      dataSource: BilibiliLiveDataSource(
        transport: transport,
        signService: BilibiliSignService(
          transport: transport,
          authContext: authContext,
        ),
        authContext: authContext,
      ),
    );

    final recommend = await provider.fetchRecommendRooms();
    final detail = await provider.fetchRoomDetail('32558935');
    final qualities = await provider.fetchPlayQualities(detail);
    await provider.fetchPlayUrls(
      detail: detail,
      quality: qualities.first,
    );
    final token = detail.danmakuToken! as Map<String, Object?>;

    expect(recommend.items, hasLength(1));
    expect(transport.authedNavRequests, 1);
    expect(transport.authedOtherPublicRequests, isEmpty);
    expect(transport.authedDanmakuInfoRequests, hasLength(1));
    expect(transport.authedPlayInfoRequests, hasLength(2));
    expect(token['cookie'], contains('SESSDATA=test-session'));
    expect(token['cookie'], contains('DedeUserID=42'));
    expect(token['uid'], 42);
  });

  test(
      'live bilibili runtime falls back to anonymous play info when account cookie is expired',
      () async {
    final transport = _FakeBilibiliPlayInfoAuthFallbackTransport();
    final authContext = BilibiliAuthContext(
      cookie: 'SESSDATA=expired-session; DedeUserID=42',
      userId: 42,
    );
    final provider = BilibiliProvider(
      dataSource: BilibiliLiveDataSource(
        transport: transport,
        signService: BilibiliSignService(
          transport: transport,
          authContext: authContext,
        ),
        authContext: authContext,
      ),
    );

    final detail = await provider.fetchRoomDetail('32558935');
    final qualities = await provider.fetchPlayQualities(detail);
    final urls = await provider.fetchPlayUrls(
      detail: detail,
      quality: qualities.first,
    );

    expect(qualities, isNotEmpty);
    expect(urls, isNotEmpty);
    expect(transport.authedPlayInfoRequests, 2);
    expect(transport.anonymousPlayInfoRequests, 2);
  });
}

class _FakeBilibiliTransport implements BilibiliTransport {
  final List<String> requestedUrls = [];

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
    final uri = Uri.parse(url).replace(
      queryParameters: queryParameters.isEmpty ? null : queryParameters,
    );
    requestedUrls.add(uri.toString());

    if (uri
        .toString()
        .startsWith('https://api.bilibili.com/x/frontend/finger/spi')) {
      return jsonEncode({
        'code': 0,
        'data': {'b_3': 'mock-buvid3', 'b_4': 'mock-buvid4'},
      });
    }
    if (uri
        .toString()
        .startsWith('https://api.bilibili.com/x/web-interface/nav')) {
      return jsonEncode({
        'code': 0,
        'data': {
          'wbi_img': {
            'img_url':
                'https://i0.hdslb.com/bfs/wbi/7cd084941338484aae1ad9425b84077c.png',
            'sub_url':
                'https://i0.hdslb.com/bfs/wbi/4932caff0ff746eab6f01bf08b70ac45.png',
          },
        },
      });
    }
    if (uri
        .toString()
        .startsWith('https://api.bilibili.com/x/web-interface/search/type')) {
      return jsonEncode({
        'code': 0,
        'data': {
          'pageinfo': {
            'live_room': {'numPages': 1},
          },
          'result': {
            'live_room': [
              {
                'roomid': 32558935,
                'title': '直播<em class="keyword">测试</em>',
                'user_cover': '//i0.hdslb.com/bfs/live/new_room_cover/demo.jpg',
                'cover': '//i0.hdslb.com/bfs/live-key-frame/demo.webp',
                'uname': '凌霄sama_ow',
                'uface': '//i1.hdslb.com/bfs/face/demo.jpg',
                'online': 153,
                'cate_name': '测试区',
                'live_status': 1,
              },
            ],
          },
        },
      });
    }
    if (uri.toString().startsWith(
          'https://api.live.bilibili.com/xlive/web-room/v1/index/getInfoByRoom',
        )) {
      expect(uri.queryParameters['w_rid'], isNotNull);
      expect(uri.queryParameters['wts'], isNotNull);
      return jsonEncode({
        'code': 0,
        'data': {
          'room_info': {
            'room_id': 32558935,
            'short_id': 0,
            'title': '直播测试',
            'cover': 'https://i0.hdslb.com/bfs/live/demo-cover.jpg',
            'keyframe': 'https://i0.hdslb.com/bfs/live/demo-keyframe.webp',
            'area_name': '测试区',
            'description': '测试简介',
            'online': 153,
            'live_status': 1,
            'live_start_time': 1773085886,
          },
          'anchor_info': {
            'base_info': {
              'uname': '凌霄sama_ow',
              'face': '//i1.hdslb.com/bfs/face/demo.jpg',
            },
          },
        },
      });
    }
    if (uri.toString().startsWith(
          'https://api.live.bilibili.com/xlive/web-room/v1/index/getDanmuInfo',
        )) {
      expect(uri.queryParameters['w_rid'], isNotNull);
      expect(uri.queryParameters['wts'], isNotNull);
      return jsonEncode({
        'code': 0,
        'data': {
          'token': 'mock-danmaku-token',
          'host_list': [
            {'host': 'broadcastlv.chat.bilibili.com'},
          ],
        },
      });
    }
    if (uri.toString().startsWith(
          'https://api.live.bilibili.com/xlive/web-room/v2/index/getRoomPlayInfo',
        )) {
      return jsonEncode({
        'code': 0,
        'data': {
          'playurl_info': {
            'playurl': {
              'current_qn': 150,
              'g_qn_desc': [
                {'qn': 80, 'desc': '流畅'},
                {'qn': 150, 'desc': '高清'},
              ],
              'stream': [
                {
                  'format': [
                    {
                      'codec': [
                        {
                          'accept_qn': [80, 150],
                          'base_url': '/live-bvc/32558935/index.m3u8',
                          'url_info': [
                            {
                              'host': 'https://cn-bj-live-comet-01.example.com',
                              'extra': '?qn=150&token=abc',
                            },
                            {
                              'host': 'https://mcdn-live.example.com',
                              'extra': '?qn=150&token=def',
                            },
                          ],
                        },
                      ],
                    },
                  ],
                },
              ],
            },
          },
        },
      });
    }

    fail('Unexpected bilibili request: $uri');
  }
}

class _FakeBilibiliDanmakuUnavailableTransport extends _FakeBilibiliTransport {
  @override
  Future<String> getText(
    String url, {
    Map<String, String> queryParameters = const {},
    Map<String, String> headers = const {},
  }) async {
    final uri = Uri.parse(url).replace(
      queryParameters: queryParameters.isEmpty ? null : queryParameters,
    );
    if (uri.toString().startsWith(
          'https://api.live.bilibili.com/xlive/web-room/v1/index/getDanmuInfo',
        )) {
      return jsonEncode({
        'code': -352,
        'message': 'risk control',
        'data': const {},
      });
    }
    return super.getText(
      url,
      queryParameters: queryParameters,
      headers: headers,
    );
  }
}

class _FakeBilibiliRoomInfoFailureTransport extends _FakeBilibiliTransport {
  @override
  Future<String> getText(
    String url, {
    Map<String, String> queryParameters = const {},
    Map<String, String> headers = const {},
  }) async {
    final uri = Uri.parse(url).replace(
      queryParameters: queryParameters.isEmpty ? null : queryParameters,
    );
    if (uri.toString().startsWith(
          'https://api.live.bilibili.com/xlive/web-room/v1/index/getInfoByRoom',
        )) {
      return jsonEncode({
        'code': -400,
        'message': 'room detail blocked',
      });
    }
    return super.getText(
      url,
      queryParameters: queryParameters,
      headers: headers,
    );
  }
}

class _FakeBilibiliExpiredCookieTransport extends BilibiliTransport {
  int unauthorizedAuthedRequests = 0;
  int navAnonymousRequests = 0;
  final List<String> publicApiRequestsWithExpiredCookie = <String>[];

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
    final uri = Uri.parse(url).replace(
      queryParameters: queryParameters.isEmpty ? null : queryParameters,
    );
    final cookie = headers['cookie'] ?? '';
    final hasExpiredSession = cookie.contains('SESSDATA=expired-session');
    final hasBuvid = cookie.contains('buvid3=');

    if (uri
        .toString()
        .startsWith('https://api.bilibili.com/x/frontend/finger/spi')) {
      if (hasExpiredSession) {
        unauthorizedAuthedRequests += 1;
        return jsonEncode({
          'code': -101,
          'message': '账号未登录',
        });
      }
      return jsonEncode({
        'code': 0,
        'data': {'b_3': 'mock-buvid3', 'b_4': 'mock-buvid4'},
      });
    }
    if (uri
        .toString()
        .startsWith('https://api.bilibili.com/x/web-interface/nav')) {
      if (hasExpiredSession) {
        unauthorizedAuthedRequests += 1;
        return jsonEncode({
          'code': -101,
          'message': '账号未登录',
        });
      }
      navAnonymousRequests += 1;
      expect(hasBuvid, isTrue);
      return jsonEncode({
        'code': 0,
        'data': {
          'wbi_img': {
            'img_url':
                'https://i0.hdslb.com/bfs/wbi/7cd084941338484aae1ad9425b84077c.png',
            'sub_url':
                'https://i0.hdslb.com/bfs/wbi/4932caff0ff746eab6f01bf08b70ac45.png',
          },
        },
      });
    }
    if (hasExpiredSession &&
        (uri.toString().contains('getListByArea') ||
            uri.toString().contains('getInfoByRoom'))) {
      publicApiRequestsWithExpiredCookie.add(uri.toString());
    }
    if (uri.toString().startsWith(
          'https://api.live.bilibili.com/xlive/web-interface/v1/second/getListByArea',
        )) {
      expect(uri.queryParameters['w_rid'], isNotNull);
      expect(uri.queryParameters['wts'], isNotNull);
      expect(hasExpiredSession, isFalse);
      expect(hasBuvid, isTrue);
      return jsonEncode({
        'code': 0,
        'data': {
          'list': [
            {
              'roomid': 32558935,
              'title': 'B站热门房间',
              'cover': 'https://bilibili.test/cover.jpg',
              'system_cover': 'https://bilibili.test/keyframe.webp',
              'area_name': '测试区',
              'uname': 'B站热榜主播',
              'face': 'https://bilibili.test/avatar.jpg',
              'online': 54321,
              'live_status': 1,
            },
          ],
        },
      });
    }
    if (uri.toString().startsWith(
          'https://api.live.bilibili.com/xlive/web-room/v1/index/getInfoByRoom',
        )) {
      expect(uri.queryParameters['w_rid'], isNotNull);
      expect(uri.queryParameters['wts'], isNotNull);
      expect(hasExpiredSession, isFalse);
      return jsonEncode({
        'code': 0,
        'data': {
          'room_info': {
            'room_id': 32558935,
            'short_id': 0,
            'title': '直播测试',
            'cover': 'https://i0.hdslb.com/bfs/live/demo-cover.jpg',
            'keyframe': 'https://i0.hdslb.com/bfs/live/demo-keyframe.webp',
            'area_name': '测试区',
            'description': '测试简介',
            'online': 153,
            'live_status': 1,
            'live_start_time': 1773085886,
          },
          'anchor_info': {
            'base_info': {
              'uname': '凌霄sama_ow',
              'face': '//i1.hdslb.com/bfs/face/demo.jpg',
            },
          },
        },
      });
    }
    if (uri.toString().startsWith(
          'https://api.live.bilibili.com/xlive/web-room/v1/index/getDanmuInfo',
        )) {
      if (hasExpiredSession) {
        unauthorizedAuthedRequests += 1;
        return jsonEncode({
          'code': -101,
          'message': '账号未登录',
        });
      }
      expect(uri.queryParameters['w_rid'], isNotNull);
      expect(uri.queryParameters['wts'], isNotNull);
      expect(hasExpiredSession, isFalse);
      return jsonEncode({
        'code': 0,
        'data': {
          'token': 'mock-danmaku-token',
          'host_list': [
            {'host': 'broadcastlv.chat.bilibili.com'},
          ],
        },
      });
    }

    fail('Unexpected bilibili request: $uri');
  }
}

class _FakeBilibiliAnonymousPublicTransport extends _FakeBilibiliTransport {
  int authedNavRequests = 0;
  final List<String> authedOtherPublicRequests = <String>[];
  final List<String> authedPlayInfoRequests = <String>[];
  final List<String> authedDanmakuInfoRequests = <String>[];

  @override
  Future<String> getText(
    String url, {
    Map<String, String> queryParameters = const {},
    Map<String, String> headers = const {},
  }) async {
    final uri = Uri.parse(url).replace(
      queryParameters: queryParameters.isEmpty ? null : queryParameters,
    );
    final cookie = headers['cookie'] ?? '';
    final hasAuthCookie = cookie.contains('SESSDATA=');
    final isNavRequest = uri
        .toString()
        .startsWith('https://api.bilibili.com/x/web-interface/nav');
    final isPlayInfoRequest = uri.toString().startsWith(
          'https://api.live.bilibili.com/xlive/web-room/v2/index/getRoomPlayInfo',
        );
    final isDanmakuInfoRequest = uri.toString().startsWith(
          'https://api.live.bilibili.com/xlive/web-room/v1/index/getDanmuInfo',
        );
    final isOtherPublicRequest = uri
            .toString()
            .startsWith('https://api.bilibili.com/x/frontend/finger/spi') ||
        uri.toString().startsWith(
              'https://api.live.bilibili.com/xlive/web-interface/v1/second/getListByArea',
            ) ||
        uri.toString().startsWith(
              'https://api.live.bilibili.com/xlive/web-room/v1/index/getInfoByRoom',
            );
    if (isNavRequest && hasAuthCookie) {
      authedNavRequests += 1;
    } else if (isPlayInfoRequest && hasAuthCookie) {
      authedPlayInfoRequests.add(uri.toString());
    } else if (isDanmakuInfoRequest && hasAuthCookie) {
      authedDanmakuInfoRequests.add(uri.toString());
    } else if (isOtherPublicRequest && hasAuthCookie) {
      authedOtherPublicRequests.add(uri.toString());
    }
    if (uri.toString().startsWith(
          'https://api.live.bilibili.com/xlive/web-interface/v1/second/getListByArea',
        )) {
      return jsonEncode({
        'code': 0,
        'data': {
          'list': [
            {
              'roomid': 32558935,
              'title': 'B站热门房间',
              'cover': 'https://bilibili.test/cover.jpg',
              'system_cover': 'https://bilibili.test/keyframe.webp',
              'area_name': '测试区',
              'uname': 'B站热榜主播',
              'face': 'https://bilibili.test/avatar.jpg',
              'online': 54321,
              'live_status': 1,
            },
          ],
        },
      });
    }
    return super.getText(
      url,
      queryParameters: queryParameters,
      headers: headers,
    );
  }
}

class _FakeBilibiliPlayInfoAuthFallbackTransport
    extends _FakeBilibiliTransport {
  int authedPlayInfoRequests = 0;
  int anonymousPlayInfoRequests = 0;

  @override
  Future<String> getText(
    String url, {
    Map<String, String> queryParameters = const {},
    Map<String, String> headers = const {},
  }) async {
    final uri = Uri.parse(url).replace(
      queryParameters: queryParameters.isEmpty ? null : queryParameters,
    );
    final isPlayInfoRequest = uri.toString().startsWith(
          'https://api.live.bilibili.com/xlive/web-room/v2/index/getRoomPlayInfo',
        );
    if (!isPlayInfoRequest) {
      return super.getText(
        url,
        queryParameters: queryParameters,
        headers: headers,
      );
    }

    final hasAuthCookie = (headers['cookie'] ?? '').contains('SESSDATA=');
    if (hasAuthCookie) {
      authedPlayInfoRequests += 1;
      return jsonEncode({
        'code': -101,
        'message': '账号未登录',
      });
    }

    anonymousPlayInfoRequests += 1;
    return super.getText(
      url,
      queryParameters: queryParameters,
      headers: headers,
    );
  }
}

class _FakeBilibiliMalformedTextTransport extends _FakeBilibiliTransport {
  static final String _badTitle =
      '游${String.fromCharCode(0xD800)}戏${String.fromCharCode(0xDC00)}厅';
  static final String _badName = '熱${String.fromCharCode(0xD800)}門主播';
  static final String _badArea = '熱門遊${String.fromCharCode(0xDC00)}戲';
  static final String _badDescription = '主播簡${String.fromCharCode(0xD800)}介';

  @override
  Future<String> getText(
    String url, {
    Map<String, String> queryParameters = const {},
    Map<String, String> headers = const {},
  }) async {
    final uri = Uri.parse(url).replace(
      queryParameters: queryParameters.isEmpty ? null : queryParameters,
    );
    requestedUrls.add(uri.toString());

    if (uri
        .toString()
        .startsWith('https://api.bilibili.com/x/frontend/finger/spi')) {
      return jsonEncode({
        'code': 0,
        'data': {'b_3': 'mock-buvid3', 'b_4': 'mock-buvid4'},
      });
    }
    if (uri
        .toString()
        .startsWith('https://api.bilibili.com/x/web-interface/nav')) {
      return jsonEncode({
        'code': 0,
        'data': {
          'wbi_img': {
            'img_url':
                'https://i0.hdslb.com/bfs/wbi/7cd084941338484aae1ad9425b84077c.png',
            'sub_url':
                'https://i0.hdslb.com/bfs/wbi/4932caff0ff746eab6f01bf08b70ac45.png',
          },
        },
      });
    }
    if (uri.toString().startsWith(
          'https://api.live.bilibili.com/xlive/web-interface/v1/second/getListByArea',
        )) {
      return jsonEncode({
        'code': 0,
        'data': {
          'list': [
            {
              'roomid': 32558935,
              'title': _badTitle,
              'cover': 'https://bilibili.test/cover.jpg',
              'system_cover': 'https://bilibili.test/keyframe.webp',
              'area_name': _badArea,
              'uname': _badName,
              'face': 'https://bilibili.test/avatar.jpg',
              'online': 54321,
              'live_status': 1,
            },
          ],
        },
      });
    }
    if (uri.toString().startsWith(
          'https://api.live.bilibili.com/xlive/web-room/v1/index/getInfoByRoom',
        )) {
      return jsonEncode({
        'code': 0,
        'data': {
          'room_info': {
            'room_id': 32558935,
            'short_id': 0,
            'title': _badTitle,
            'cover': 'https://i0.hdslb.com/bfs/live/demo-cover.jpg',
            'keyframe': 'https://i0.hdslb.com/bfs/live/demo-keyframe.webp',
            'area_name': _badArea,
            'description': _badDescription,
            'online': 153,
            'live_status': 1,
            'live_start_time': 1773085886,
          },
          'anchor_info': {
            'base_info': {
              'uname': _badName,
              'face': '//i1.hdslb.com/bfs/face/demo.jpg',
            },
          },
        },
      });
    }
    if (uri.toString().startsWith(
          'https://api.live.bilibili.com/xlive/web-room/v1/index/getDanmuInfo',
        )) {
      return jsonEncode({
        'code': 0,
        'data': {
          'token': 'mock-danmaku-token',
          'host_list': [
            {'host': 'broadcastlv.chat.bilibili.com'},
          ],
        },
      });
    }
    if (uri.toString().startsWith(
          'https://api.live.bilibili.com/xlive/web-room/v2/index/getRoomPlayInfo',
        )) {
      return jsonEncode({
        'code': 0,
        'data': {
          'playurl_info': {
            'playurl': {
              'current_qn': 10000,
              'g_qn_desc': [
                {'qn': 10000, 'desc': '原画'},
              ],
              'stream': [
                {
                  'format': [
                    {
                      'codec': [
                        {
                          'accept_qn': [10000],
                          'base_url': '/live/demo_bluray.flv',
                          'url_info': [
                            {
                              'host': 'https://cn.bilibili.test',
                              'extra': '?token=mock',
                            },
                          ],
                        },
                      ],
                    },
                  ],
                },
              ],
            },
          },
        },
      });
    }

    fail('Unexpected bilibili request: $uri');
  }
}

class _FakeBilibiliRecommendFallbackTransport extends BilibiliTransport {
  int navRequests = 0;
  int searchRequests = 0;

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
    final uri = Uri.parse(url).replace(
      queryParameters: queryParameters.isEmpty ? null : queryParameters,
    );

    if (uri
        .toString()
        .startsWith('https://api.bilibili.com/x/frontend/finger/spi')) {
      return jsonEncode({
        'code': 0,
        'data': {'b_3': 'mock-buvid3', 'b_4': 'mock-buvid4'},
      });
    }
    if (uri
        .toString()
        .startsWith('https://api.bilibili.com/x/web-interface/nav')) {
      navRequests += 1;
      return jsonEncode({
        'code': -101,
        'message': '账号未登录',
      });
    }
    if (uri.toString().startsWith(
          'https://api.live.bilibili.com/room/v1/Area/getList',
        )) {
      return jsonEncode({
        'code': 0,
        'data': [
          {
            'id': 1,
            'name': '热门',
            'list': [
              {
                'id': 101,
                'parent_id': 1,
                'name': '热门推荐',
              },
            ],
          },
        ],
      });
    }
    if (uri
        .toString()
        .startsWith('https://api.bilibili.com/x/web-interface/search/type')) {
      searchRequests += 1;
      return jsonEncode({
        'code': 0,
        'data': {
          'pageinfo': {
            'live_room': {'numPages': 1},
          },
          'result': {
            'live_room': [
              {
                'roomid': 778899,
                'title': '推荐回退房间',
                'user_cover': '//i0.hdslb.com/bfs/live/recommend-cover.jpg',
                'cover': '//i0.hdslb.com/bfs/live/recommend-keyframe.webp',
                'uname': '回退主播',
                'uface': '//i1.hdslb.com/bfs/face/recommend-avatar.jpg',
                'online': 3456,
                'cate_name': '热门推荐',
                'live_status': 1,
              },
            ],
          },
        },
      });
    }

    fail('Unexpected bilibili request: $uri');
  }
}
