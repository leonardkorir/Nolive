import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:live_providers/live_providers.dart';
import 'package:live_providers/src/providers/douyu/douyu_live_data_source.dart';
import 'package:live_providers/src/providers/douyu/douyu_sign_service.dart';
import 'package:live_providers/src/providers/douyu/douyu_transport.dart';
import 'package:test/test.dart';

void main() {
  test(
    'live douyu runtime prefers square category icon when available',
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
    },
  );

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
    // Room detail no longer pre-signs (SlotSun signs at play time).
    expect(detail.metadata?['deviceId'], HttpDouyuSignService.kDefaultDeviceId);

    final qualities = await provider.fetchPlayQualities(detail);
    expect(qualities, isNotEmpty);
    expect(qualities.map((item) => item.label), ['原画1080P60', '蓝光4M', '高清']);
    expect(qualities.first.sortOrder, greaterThan(qualities[1].sortOrder));
    expect(qualities.firstWhere((item) => item.isDefault).label, '蓝光4M');
    expect(qualities.firstWhere((item) => item.isDefault).metadata?['cdns'], [
      'tct-h5',
      'hw-h5',
      'scdn',
    ]);

    final urls = await provider.fetchPlayUrls(
      detail: detail,
      quality: qualities.firstWhere((item) => item.isDefault),
    );
    expect(urls, hasLength(3));
    // Host preference: hw1a first, then tct, scdn last.
    expect(urls.first.url, contains('hw1a.douyu.test'));
    expect(urls.map((item) => Uri.parse(item.url).host).toList(), [
      'hw1a.douyu.test',
      'tct.douyu.test',
      'scdn.douyu.test',
    ]);
    // SlotSun bare URL: no stream headers on Douyu FLV.
    expect(urls.first.headers, isEmpty);
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

  test(
    'live douyu runtime retries transient play request failures once',
    () async {
      final transport = _FakeDouyuTransport()..failPlayPostCount = 1;
      final signService = _FakeDouyuSignService();
      final provider = DouyuProvider(
        dataSource: DouyuLiveDataSource(
          transport: transport,
          signService: signService,
        ),
      );

      final detail = await provider.fetchRoomDetail('312212');
      final qualities = await provider.fetchPlayQualities(detail);

      expect(qualities, isNotEmpty);
      expect(
        transport.postBodies.where((item) => item.contains('rate=-1')).length,
        2,
      );
    },
  );

  test('betard offline still attempts getH5Play (stale show_status)', () async {
    // betard show_status=0 but getH5Play can still return ladder/URLs.
    final transport = _FakeDouyuTransport()..offlineRoom = true;
    final signService = _FakeDouyuSignService();
    final provider = DouyuProvider(
      dataSource: DouyuLiveDataSource(
        transport: transport,
        signService: signService,
      ),
    );

    final detail = await provider.fetchRoomDetail('312212');
    expect(detail.isLive, isFalse);
    final qualities = await provider.fetchPlayQualities(detail);
    expect(qualities, isNotEmpty);
    expect(
      transport.postBodies.where((item) => item.contains('rate=-1')),
      isNotEmpty,
    );
  });

  test('getH5Play error -5 yields empty qualities without throw', () async {
    final transport = _FakeDouyuTransport()..playErrorCode = -5;
    final signService = _FakeDouyuSignService();
    final provider = DouyuProvider(
      dataSource: DouyuLiveDataSource(
        transport: transport,
        signService: signService,
      ),
    );

    final detail = await provider.fetchRoomDetail('312212');
    expect(detail.isLive, isTrue);
    final qualities = await provider.fetchPlayQualities(detail);
    expect(qualities, isEmpty);
  });

  test('getH5Play non-offline error throws typed failure', () async {
    final transport = _FakeDouyuTransport()
      ..playErrorCode = 1
      ..playErrorMsg = '请求过于频繁';
    final signService = _FakeDouyuSignService();
    final provider = DouyuProvider(
      dataSource: DouyuLiveDataSource(
        transport: transport,
        signService: signService,
      ),
    );

    final detail = await provider.fetchRoomDetail('312212');
    await expectLater(
      provider.fetchPlayQualities(detail),
      throwsA(
        isA<ProviderParseException>().having(
          (e) => e.message,
          'message',
          contains('rateLimited'),
        ),
      ),
    );
  });

  test('classifyDouyuH5PlayError maps offline and auth', () {
    expect(classifyDouyuH5PlayError(-5, null), DouyuH5PlayErrorKind.offline);
    expect(classifyDouyuH5PlayError(1, '房间未开播'), DouyuH5PlayErrorKind.offline);
    expect(
      classifyDouyuH5PlayError(1, '签名错误'),
      DouyuH5PlayErrorKind.authFailed,
    );
    expect(
      classifyDouyuH5PlayError(1, '请求过于频繁'),
      DouyuH5PlayErrorKind.rateLimited,
    );
  });
}

class _FakeDouyuSignService implements DouyuSignService {
  @override
  Map<String, String> buildPlayHeaders(String roomId, {String? deviceId}) {
    return {
      'user-agent': 'test-agent',
      'content-type': 'application/x-www-form-urlencoded',
      'accept':
          'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'accept-language': 'zh-CN,zh;q=0.8,en-US;q=0.5,en;q=0.3',
    };
  }

  @override
  Map<String, String> buildStreamHeaders(String roomId, {String? deviceId}) {
    // SlotSun Douyu: bare URL.
    return const {};
  }

  @override
  Future<String> buildSignedPlayBody(
    String roomId, {
    String cdn = '',
    String rate = '-1',
  }) async {
    return 'enc_data=test&tt=1700000000&did=test-device-id&auth=test-auth'
        '&cdn=$cdn&rate=$rate&hevc=0&fa=0&ive=0&ver=Douyu_new&iar=0';
  }

  @override
  Future<DouyuSignedPlayContext> buildPlayContext(String roomId) async {
    final body = await buildSignedPlayBody(roomId);
    return DouyuSignedPlayContext(
      body: body,
      deviceId: 'test-device-id',
      timestamp: 1700000000,
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
    return '$baseBody&cdn=$cdn&rate=$rate&hevc=0&fa=0&ive=0&ver=Douyu_new&iar=0';
  }
}

class _FakeDouyuTransport implements DouyuTransport {
  final List<String> requestedUrls = [];
  final List<String> postBodies = [];
  int failPlayPostCount = 0;
  bool offlineRoom = false;
  int playErrorCode = 0;
  String playErrorMsg = '房间未开播';

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

    if (uri.toString().startsWith('https://m.douyu.com/api/cate/list')) {
      return jsonEncode({
        'data': {
          'cate1Info': [
            {'cate1Id': 1, 'cate1Name': '网游竞技'},
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
          'show_status': offlineRoom ? 0 : 1,
          'videoLoop': 0,
          'room_biz_all': {'hot': '13.2万'},
        },
      });
    }
    if (uri.toString().startsWith(
      'https://www.douyu.com/wgapi/livenc/liveweb/websec/getEncryption',
    )) {
      return jsonEncode({
        'data': {
          'rand_str': 'rand',
          'enc_time': 1,
          'is_special': 0,
          'key': 'key',
          'enc_data': 'enc',
        },
      });
    }
    if (uri.toString().startsWith('https://www.douyu.com/swf_api/homeH5Enc')) {
      expect(uri.queryParameters['rids'], '312212');
      return jsonEncode({
        'data': {'room312212': 'function ub98484234() {}'},
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
      'https://www.douyu.com/lapi/live/getH5PlayV1/312212',
    )) {
      if (failPlayPostCount > 0) {
        failPlayPostCount -= 1;
        throw ProviderParseException(
          providerId: ProviderId.douyu,
          message: 'fixture transient play failure',
        );
      }
      if (body.contains('rate=-1')) {
        if (playErrorCode != 0) {
          return jsonEncode({
            'error': playErrorCode,
            'msg': playErrorMsg,
            'data': '',
          });
        }
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
        expect(body.contains('ver=Douyu_new'), isTrue);
        expect(body.contains('iar=0'), isTrue);
        expect(body.contains('ive=0'), isTrue);
      }

      final line = body.contains('cdn=tct-h5')
          ? 'tct-h5'
          : body.contains('cdn=hw-h5')
          ? 'hw-h5'
          : 'scdn';
      // Distinct hosts so preferReliableDouyuPlayUrls does not collapse lines.
      final host = switch (line) {
        'tct-h5' => 'tct.douyu.test',
        'hw-h5' => 'hw1a.douyu.test',
        _ => 'scdn.douyu.test',
      };
      return jsonEncode({
        'error': 0,
        'data': {
          'cdn': line,
          'rate': 4,
          'rtmp_url': 'https://$host/live',
          'rtmp_live': 'live_312212.m3u8?rate=4&amp;token=${line}Token',
        },
      });
    }

    fail('Unexpected douyu post request: $uri');
  }
}
