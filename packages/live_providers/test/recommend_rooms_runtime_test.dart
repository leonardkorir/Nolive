import 'dart:convert';

import 'package:live_providers/live_providers.dart';
import 'package:live_providers/src/providers/bilibili/bilibili_auth_context.dart';
import 'package:live_providers/src/providers/bilibili/bilibili_live_data_source.dart';
import 'package:live_providers/src/providers/bilibili/bilibili_sign_service.dart';
import 'package:live_providers/src/providers/bilibili/bilibili_transport.dart';
import 'package:live_providers/src/providers/douyin/douyin_live_data_source.dart';
import 'package:live_providers/src/providers/douyin/douyin_sign_service.dart';
import 'package:live_providers/src/providers/douyin/douyin_transport.dart';
import 'package:live_providers/src/providers/douyu/douyu_live_data_source.dart';
import 'package:live_providers/src/providers/douyu/douyu_sign_service.dart';
import 'package:live_providers/src/providers/douyu/douyu_transport.dart';
import 'package:live_providers/src/providers/huya/huya_live_data_source.dart';
import 'package:live_providers/src/providers/huya/huya_sign_service.dart';
import 'package:live_providers/src/providers/huya/huya_transport.dart';
import 'package:test/test.dart';

void main() {
  test('douyin recommend categories flatten to concrete games', () async {
    final provider = DouyinProvider(
      dataSource: DouyinLiveDataSource(
        transport: _FakeDouyinRecommendTransport(),
        signService: HttpDouyinSignService(cookie: 'ttwid=test-cookie'),
      ),
    );

    final categories = await provider.fetchCategories();
    final game = categories.firstWhere((item) => item.name == '游戏');
    final names =
        game.children.map((item) => item.name).toList(growable: false);

    expect(names.first, '游戏');
    expect(names, contains('绝地求生'));
    expect(names, contains('三角洲行动'));
    expect(names, isNot(contains('射击游戏')));

    final recommend = await provider.fetchRecommendRooms();
    expect(recommend.items, hasLength(1));
    expect(recommend.items.single.roomId, '88990011');
    expect(recommend.items.single.viewerCount, 45678);
  });

  test('douyu recommend rooms maps hot list', () async {
    final provider = DouyuProvider(
      dataSource: DouyuLiveDataSource(
        transport: _FakeDouyuRecommendTransport(),
        signService: _FakeDouyuRecommendSignService(),
      ),
    );

    final recommend = await provider.fetchRecommendRooms();
    expect(recommend.items, hasLength(1));
    expect(recommend.items.single.roomId, '312212');
    expect(recommend.items.single.viewerCount, 125000);
  });

  test('douyu recommend rooms keeps paging when pgcnt is missing', () async {
    final provider = DouyuProvider(
      dataSource: DouyuLiveDataSource(
        transport: _FakeDouyuMissingPageCountTransport(),
        signService: _FakeDouyuRecommendSignService(),
      ),
    );

    final firstPage = await provider.fetchRecommendRooms(page: 1);
    expect(firstPage.items, hasLength(40));
    expect(firstPage.hasMore, isTrue);

    final secondPage = await provider.fetchRecommendRooms(page: 2);
    expect(secondPage.items, hasLength(1));
    expect(secondPage.hasMore, isFalse);
  });

  test('huya recommend rooms maps homepage list', () async {
    final provider = HuyaProvider(
      dataSource: HuyaLiveDataSource(
        transport: _FakeHuyaRecommendTransport(),
        signService: HttpHuyaSignService(),
      ),
    );

    final recommend = await provider.fetchRecommendRooms();
    expect(recommend.items, hasLength(1));
    expect(recommend.items.single.roomId, 'yy/123456');
    expect(recommend.items.single.viewerCount, 98765);
  });

  test('bilibili recommend rooms maps online-sorted list', () async {
    final transport = _FakeBilibiliRecommendTransport();
    final authContext = BilibiliAuthContext(cookie: 'SESSDATA=test', userId: 1);
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
    expect(recommend.items.single.roomId, '32558935');
    expect(recommend.items.single.viewerCount, 54321);
  });

  test(
      'bilibili recommend rooms fall back when homepage API is risk-controlled',
      () async {
    final transport = _FakeBilibiliRecommendFallbackTransport();
    final authContext = BilibiliAuthContext(cookie: 'SESSDATA=test', userId: 1);
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
    expect(recommend.items.single.roomId, '987654');
    expect(recommend.items.single.viewerCount, 77777);
  });
}

class _FakeDouyinRecommendTransport extends DouyinTransport {
  @override
  Future<DouyinHttpResponse> getResponse(
    String url, {
    Map<String, String> queryParameters = const {},
    Map<String, String> headers = const {},
  }) async {
    final uri = Uri.parse(url).replace(
      queryParameters: queryParameters.isEmpty ? null : queryParameters,
    );
    if (uri.toString() == 'https://live.douyin.com/') {
      return DouyinHttpResponse(
        body:
            r'{\"pathname\":\"/\",\"categoryData\":[{\"partition\":{\"id_str\":\"101\",\"type\":4,\"title\":\"聊天\"},\"sub_partition\":[]},{\"partition\":{\"id_str\":\"103\",\"type\":4,\"title\":\"游戏\"},\"sub_partition\":[{\"partition\":{\"id_str\":\"1\",\"type\":1,\"title\":\"射击游戏\"},\"sub_partition\":[{\"partition\":{\"id_str\":\"1010026\",\"type\":1,\"title\":\"绝地求生\"},\"sub_partition\":[]},{\"partition\":{\"id_str\":\"1011032\",\"type\":1,\"title\":\"三角洲行动\"},\"sub_partition\":[]}]}]}]}],',
        headers: const {},
      );
    }
    if (uri.toString().startsWith(
          'https://live.douyin.com/webcast/web/partition/detail/room/v2/',
        )) {
      return DouyinHttpResponse(
        body: jsonEncode({
          'data': {
            'data': [
              {
                'web_rid': '88990011',
                'tag_name': '热门',
                'room': {
                  'title': '抖音热门测试房间',
                  'cover': {
                    'url_list': ['https://douyin.test/cover.jpg']
                  },
                  'owner': {
                    'web_rid': '88990011',
                    'nickname': '抖音热榜主播',
                    'avatar_medium': {
                      'url_list': ['https://douyin.test/avatar.jpg']
                    },
                  },
                  'room_view_stats': {'display_value': 45678},
                },
              },
            ],
          },
        }),
        headers: const {},
      );
    }
    fail('Unexpected douyin recommend request: $uri');
  }
}

class _FakeDouyuRecommendSignService implements DouyuSignService {
  @override
  Map<String, String> buildPlayHeaders(String roomId, {String? deviceId}) =>
      const {};

  @override
  Future<DouyuSignedPlayContext> buildPlayContext(String roomId) {
    throw UnimplementedError();
  }

  @override
  Map<String, String> buildRoomHeaders(String roomId) => const {};

  @override
  Map<String, String> buildSearchHeaders() => const {};

  @override
  String extendPlayBody(
    String baseBody, {
    required String cdn,
    required String rate,
  }) {
    throw UnimplementedError();
  }
}

class _FakeDouyuRecommendTransport extends DouyuTransport {
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
          'https://www.douyu.com/japi/weblist/apinc/allpage/6/',
        )) {
      return jsonEncode({
        'data': {
          'pgcnt': 3,
          'rl': [
            {
              'type': 1,
              'rid': 312212,
              'rn': '斗鱼热门房间',
              'nn': '斗鱼热榜主播',
              'rs16': 'https://douyu.test/cover.jpg',
              'c2name_display': '网游竞技',
              'av': 'demo-avatar',
              'ol': '12.5万',
            },
          ],
        },
      });
    }
    fail('Unexpected douyu recommend request: $uri');
  }

  @override
  Future<String> postText(
    String url, {
    String body = '',
    Map<String, String> queryParameters = const {},
    Map<String, String> headers = const {},
  }) {
    throw UnimplementedError();
  }
}

class _FakeDouyuMissingPageCountTransport extends DouyuTransport {
  @override
  Future<String> getText(
    String url, {
    Map<String, String> queryParameters = const {},
    Map<String, String> headers = const {},
  }) async {
    final uri = Uri.parse(url).replace(
      queryParameters: queryParameters.isEmpty ? null : queryParameters,
    );
    if (uri.toString().endsWith('/1')) {
      return jsonEncode({
        'data': {
          'pgcnt': 0,
          'rl': List.generate(
            40,
            (index) => {
              'type': 1,
              'rid': 600000 + index,
              'rn': '斗鱼推荐房间$index',
              'nn': '斗鱼主播$index',
              'rs16': 'https://douyu.test/cover-$index.jpg',
              'c2name_display': '网游竞技',
              'av': 'demo-avatar-$index',
              'ol': '1.2万',
            },
          ),
        },
      });
    }
    if (uri.toString().endsWith('/2')) {
      return jsonEncode({
        'data': {
          'pgcnt': 0,
          'rl': [
            {
              'type': 1,
              'rid': 700001,
              'rn': '斗鱼末页房间',
              'nn': '斗鱼末页主播',
              'rs16': 'https://douyu.test/cover-last.jpg',
              'c2name_display': '网游竞技',
              'av': 'demo-avatar-last',
              'ol': '9800',
            },
          ],
        },
      });
    }
    fail('Unexpected douyu recommend request: $uri');
  }

  @override
  Future<String> postText(
    String url, {
    String body = '',
    Map<String, String> queryParameters = const {},
    Map<String, String> headers = const {},
  }) {
    throw UnimplementedError();
  }
}

class _FakeHuyaRecommendTransport extends HuyaTransport {
  @override
  Future<String> getText(
    String url, {
    Map<String, String> queryParameters = const {},
    Map<String, String> headers = const {},
  }) async {
    final uri = Uri.parse(url).replace(
      queryParameters: queryParameters.isEmpty ? null : queryParameters,
    );
    if (uri.toString().startsWith('https://www.huya.com/cache.php')) {
      return jsonEncode({
        'data': {
          'page': 1,
          'totalPage': 4,
          'datas': [
            {
              'profileRoom': 'yy/123456',
              'introduction': '虎牙热门房间',
              'screenshot': 'https://huya.test/cover.jpg',
              'gameFullName': '英雄联盟',
              'nick': '虎牙热榜主播',
              'avatar180': 'https://huya.test/avatar.jpg',
              'totalCount': '98765',
            },
          ],
        },
      });
    }
    fail('Unexpected huya recommend request: $uri');
  }
}

class _FakeBilibiliRecommendTransport extends BilibiliTransport {
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
          'https://api.bilibili.com/x/frontend/finger/spi',
        )) {
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
      expect(uri.queryParameters['w_rid'], isNotNull);
      expect(uri.queryParameters['wts'], isNotNull);
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
    fail('Unexpected bilibili recommend request: $uri');
  }
}

class _FakeBilibiliRecommendFallbackTransport extends BilibiliTransport {
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
          'https://api.bilibili.com/x/frontend/finger/spi',
        )) {
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
    if (uri.toString() == 'https://live.bilibili.com/lol') {
      return r'{"access_id":"fallback-access"}';
    }
    if (uri.toString().startsWith(
          'https://api.live.bilibili.com/xlive/web-interface/v1/second/getListByArea',
        )) {
      expect(uri.queryParameters['w_rid'], isNotNull);
      expect(uri.queryParameters['wts'], isNotNull);
      return jsonEncode({
        'code': -352,
        'message': 'risk control',
        'data': {'list': const []},
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
            'name': '网游',
            'list': [
              {
                'id': 101,
                'parent_id': 1,
                'name': '英雄联盟',
              },
            ],
          },
        ],
      });
    }
    if (uri.toString().startsWith(
          'https://api.live.bilibili.com/xlive/web-interface/v1/second/getList',
        )) {
      expect(uri.queryParameters['w_rid'], isNotNull);
      expect(uri.queryParameters['wts'], isNotNull);
      return jsonEncode({
        'code': 0,
        'data': {
          'has_more': 0,
          'list': [
            {
              'roomid': 987654,
              'title': '分类兜底房间',
              'cover': 'https://bilibili.test/fallback-cover.jpg',
              'system_cover': 'https://bilibili.test/fallback-keyframe.webp',
              'area_name': '英雄联盟',
              'uname': '分类兜底主播',
              'face': 'https://bilibili.test/fallback-avatar.jpg',
              'online': 77777,
              'live_status': 1,
            },
          ],
        },
      });
    }
    fail('Unexpected bilibili fallback recommend request: $uri');
  }
}
