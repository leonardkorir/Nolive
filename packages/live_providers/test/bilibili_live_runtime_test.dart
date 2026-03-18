import 'dart:convert';

import 'package:live_providers/live_providers.dart';
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
