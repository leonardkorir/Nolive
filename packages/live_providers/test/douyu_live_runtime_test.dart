import 'dart:convert';

import 'package:live_providers/live_providers.dart';
import 'package:live_providers/src/providers/douyu/douyu_live_data_source.dart';
import 'package:live_providers/src/providers/douyu/douyu_sign_service.dart';
import 'package:live_providers/src/providers/douyu/douyu_transport.dart';
import 'package:test/test.dart';

void main() {
  test('live douyu runtime prefers square category icon when available',
      () async {
    final transport = _FakeDouyuTransport();
    final signService = _FakeDouyuSignService();
    final provider = DouyuProvider(
      dataSource: DouyuLiveDataSource(
        transport: transport,
        signService: signService,
      ),
    );

    final categories = await provider.fetchCategories();
    final gaming = categories.firstWhere((item) => item.id == '1');
    final lol = gaming.children.firstWhere((item) => item.id == '1');

    expect(lol.name, '英雄联盟');
    expect(
      lol.pic,
      'https://sta-op.douyucdn.cn/dycatr/1de1ea5215b513cf4f5b3c326f5f9657.png',
    );
  });

  test('live douyu runtime maps search/detail/play flow', () async {
    final transport = _FakeDouyuTransport();
    final signService = _FakeDouyuSignService();
    final provider = DouyuProvider(
      dataSource: DouyuLiveDataSource(
        transport: transport,
        signService: signService,
      ),
    );

    final rooms = await provider.searchRooms('测试');
    expect(rooms.items, hasLength(1));
    expect(rooms.hasMore, isFalse);
    expect(rooms.items.single.areaName, '网游竞技');
    expect(rooms.items.single.viewerCount, 125000);
    expect(rooms.items.single.streamerAvatarUrl, startsWith('https://'));

    final detail = await provider.fetchRoomDetail(rooms.items.single.roomId);
    expect(detail.roomId, '312212');
    expect(detail.areaName, '网游竞技');
    expect(detail.sourceUrl, 'https://www.douyu.com/312212');
    expect(detail.isLive, isTrue);
    expect(detail.viewerCount, 132000);
    expect((detail.metadata?['deviceId']), 'test-device-id');

    final qualities = await provider.fetchPlayQualities(detail);
    expect(qualities, isNotEmpty);
    expect(qualities.map((item) => item.label), ['原画1080P60', '蓝光4M', '高清']);
    expect(qualities.first.sortOrder, greaterThan(qualities[1].sortOrder));
    expect(qualities.firstWhere((item) => item.isDefault).label, '蓝光4M');
    expect(
      qualities.firstWhere((item) => item.isDefault).metadata?['cdns'],
      ['tct-h5', 'hw-h5', 'scdn'],
    );

    final urls = await provider.fetchPlayUrls(
      detail: detail,
      quality: qualities.firstWhere((item) => item.isDefault),
    );
    expect(urls, hasLength(3));
    expect(urls.first.url, startsWith('https://stream.douyu.test/'));
    expect(urls.first.headers['referer'], 'https://www.douyu.com/312212');
    expect(urls.first.metadata?['rate'], 4);
    expect(
      transport.postBodies.where((item) => item.contains('rate=4')).length,
      3,
    );
    expect(
      transport.postBodies.where((item) => item.contains('cdn=tct-h5')).length,
      1,
    );
  });
}

class _FakeDouyuSignService implements DouyuSignService {
  @override
  Map<String, String> buildPlayHeaders(String roomId, {String? deviceId}) {
    final resolvedDeviceId = deviceId ?? 'test-device-id';
    return {
      'user-agent': 'test-agent',
      'referer': 'https://www.douyu.com/$roomId',
      'cookie': 'dy_did=$resolvedDeviceId;acf_did=$resolvedDeviceId',
      'content-type': 'application/x-www-form-urlencoded',
    };
  }

  @override
  Future<DouyuSignedPlayContext> buildPlayContext(String roomId) async {
    return const DouyuSignedPlayContext(
      body: 'rid=312212&did=test-device-id&tt=1700000000&sign=test-sign',
      deviceId: 'test-device-id',
      timestamp: 1700000000,
      script: 'function ub98484234() {}',
    );
  }

  @override
  Map<String, String> buildRoomHeaders(String roomId) {
    return {
      'user-agent': 'test-agent',
      'referer': 'https://www.douyu.com/$roomId',
    };
  }

  @override
  Map<String, String> buildSearchHeaders() {
    return {
      'user-agent': 'test-agent',
      'referer': 'https://www.douyu.com/search/',
      'cookie': 'dy_did=test-device-id;acf_did=test-device-id',
    };
  }

  @override
  String extendPlayBody(
    String baseBody, {
    required String cdn,
    required String rate,
  }) {
    return '$baseBody&cdn=$cdn&rate=$rate&ver=Douyu_223061205&iar=0&ive=0&hevc=0&fa=0';
  }
}

class _FakeDouyuTransport implements DouyuTransport {
  final List<String> requestedUrls = [];
  final List<String> postBodies = [];

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

    if (uri.toString().startsWith(
          'https://m.douyu.com/api/cate/list',
        )) {
      return jsonEncode({
        'data': {
          'cate1Info': [
            {
              'cate1Id': 1,
              'cate1Name': '网游竞技',
            },
          ],
          'cate2Info': [
            {
              'cate1Id': 1,
              'cate2Id': 1,
              'cate2Name': '英雄联盟',
              'pic':
                  'https://sta-op.douyucdn.cn/dycatr/f72ebc4febe52280ef460494e3026459.png',
              'icon':
                  'https://sta-op.douyucdn.cn/dycatr/1de1ea5215b513cf4f5b3c326f5f9657.png',
              'smallIcon':
                  'https://sta-op.douyucdn.cn/dycatr/e2c1b85bdc1082e534a1f70001d69249.png',
            },
          ],
        },
      });
    }
    if (uri.toString().startsWith(
          'https://www.douyu.com/japi/search/api/searchShow',
        )) {
      return jsonEncode({
        'error': 0,
        'data': {
          'relateShow': [
            {
              'rid': 312212,
              'roomName': '斗鱼<em>测试</em>直播间',
              'roomSrc': '//staticlive.douyucdn.cn/upload/demo-cover.jpg',
              'nickName': '小鱼主播',
              'avatar': '//apic.douyucdn.cn/upload/demo-avatar.jpg',
              'hot': '12.5万',
              'cateName': '网游竞技',
            },
          ],
        },
      });
    }
    if (uri.toString().startsWith('https://www.douyu.com/betard/')) {
      return jsonEncode({
        'room': {
          'room_id': 312212,
          'room_name': '斗鱼测试直播间',
          'owner_name': '小鱼主播',
          'owner_avatar': '//apic.douyucdn.cn/upload/demo-avatar-full.jpg',
          'room_pic': 'https://staticlive.douyucdn.cn/upload/demo-room-pic.jpg',
          'second_lvl_name': '网游竞技',
          'show_details': '这是一个用于 provider 迁移测试的直播间。',
          'show_status': 1,
          'videoLoop': 0,
          'room_biz_all': {
            'hot': '13.2万',
          },
        },
      });
    }
    if (uri.toString().startsWith(
          'https://www.douyu.com/swf_api/homeH5Enc',
        )) {
      expect(uri.queryParameters['rids'], '312212');
      return jsonEncode({
        'data': {
          'room312212': 'function ub98484234() {}',
        },
      });
    }

    fail('Unexpected douyu request: $uri');
  }

  @override
  Future<Map<String, dynamic>> postJson(
    String url, {
    String body = '',
    Map<String, String> queryParameters = const {},
    Map<String, String> headers = const {},
  }) async {
    final text = await postText(
      url,
      body: body,
      queryParameters: queryParameters,
      headers: headers,
    );
    return (jsonDecode(text) as Map).cast<String, dynamic>();
  }

  @override
  Future<String> postText(
    String url, {
    String body = '',
    Map<String, String> queryParameters = const {},
    Map<String, String> headers = const {},
  }) async {
    final uri = Uri.parse(url).replace(
      queryParameters: queryParameters.isEmpty ? null : queryParameters,
    );
    requestedUrls.add(uri.toString());
    postBodies.add(body);
    expect(headers['content-type'], 'application/x-www-form-urlencoded');

    if (uri.toString().startsWith(
          'https://www.douyu.com/lapi/live/getH5Play/312212',
        )) {
      if (body.contains('rate=-1')) {
        return jsonEncode({
          'error': 0,
          'data': {
            'rate': 4,
            'cdnsWithName': [
              {'cdn': 'tct-h5'},
              {'cdn': 'scdn'},
              {'cdn': 'hw-h5'},
            ],
            'multirates': [
              {'rate': 0, 'name': '原画1080P60', 'bit': 15436},
              {'rate': 4, 'name': '蓝光4M', 'bit': 4000},
              {'rate': 2, 'name': '高清', 'bit': 900},
            ],
          },
        });
      }

      if (!body.contains('rate=-1')) {
        expect(body.contains('ver=Douyu_223061205'), isTrue);
        expect(body.contains('iar=0'), isTrue);
        expect(body.contains('ive=0'), isTrue);
      }

      final line = body.contains('cdn=tct-h5')
          ? 'tct-h5'
          : body.contains('cdn=hw-h5')
              ? 'hw-h5'
              : 'scdn';
      return jsonEncode({
        'error': 0,
        'data': {
          'cdn': line,
          'rate': 4,
          'rtmp_url': 'https://stream.douyu.test/$line',
          'rtmp_live': 'live_312212.m3u8?rate=4&amp;token=${line}Token',
        },
      });
    }

    fail('Unexpected douyu post request: $uri');
  }
}
