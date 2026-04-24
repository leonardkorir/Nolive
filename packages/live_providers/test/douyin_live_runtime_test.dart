import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:live_providers/live_providers.dart';
import 'package:live_providers/src/providers/douyin/douyin_mapper.dart';
import 'package:live_providers/src/providers/douyin/douyin_live_data_source.dart';
import 'package:live_providers/src/providers/douyin/douyin_sign_service.dart';
import 'package:live_providers/src/providers/douyin/douyin_transport.dart';
import 'package:test/test.dart';

void main() {
  test('live douyin runtime maps search/detail/play flow', () async {
    final transport = _FakeDouyinTransport();
    final signService = HttpDouyinSignService(cookie: 'ttwid=test-cookie');
    final provider = DouyinProvider(
      dataSource: DouyinLiveDataSource(
        transport: transport,
        signService: signService,
      ),
    );

    final rooms = await provider.searchRooms('测试');
    expect(rooms.items, hasLength(1));
    expect(rooms.items.single.roomId, '416144012050');

    final detail = await provider.fetchRoomDetail(rooms.items.single.roomId);
    expect(detail.roomId, '416144012050');
    expect(detail.areaName, '知识');
    expect(detail.isLive, isTrue);

    final qualities = await provider.fetchPlayQualities(detail);
    expect(qualities, isNotEmpty);
    final selected = qualities.firstWhere((item) => item.isDefault);

    final urls =
        await provider.fetchPlayUrls(detail: detail, quality: selected);
    expect(urls, isNotEmpty);
    expect(urls.first.url, contains('/origin.'));
  });

  test(
      'douyin search fallback paginates filtered feed instead of returning hot rooms',
      () async {
    final provider = DouyinProvider(
      dataSource: DouyinLiveDataSource(
        transport: _FallbackDouyinTransport(),
        signService: HttpDouyinSignService(cookie: 'ttwid=test-cookie'),
      ),
    );

    final page1 = await provider.searchRooms('关键', page: 1);
    expect(page1.items, hasLength(10));
    expect(page1.hasMore, isTrue);
    expect(page1.items.first.roomId, 'match-0');

    final page2 = await provider.searchRooms('关键', page: 2);
    expect(page2.items, hasLength(2));
    expect(page2.hasMore, isFalse);
    expect(page2.items.first.roomId, 'match-10');

    final empty = await provider.searchRooms('不存在', page: 1);
    expect(empty.items, isEmpty);
    expect(empty.hasMore, isFalse);
  });

  test('douyin categories surface parse failures instead of silent fallback',
      () async {
    final provider = DouyinProvider(
      dataSource: DouyinLiveDataSource(
        transport: _BrokenDouyinCategoryTransport(),
        signService: HttpDouyinSignService(cookie: 'ttwid=test-cookie'),
      ),
    );

    expect(
      provider.fetchCategories,
      throwsA(isA<ProviderParseException>()),
    );
  });

  test('douyin categories extract nested icon url payloads', () async {
    final provider = DouyinProvider(
      dataSource: DouyinLiveDataSource(
        transport: _CategoryIconDouyinTransport(),
        signService: HttpDouyinSignService(cookie: 'ttwid=test-cookie'),
      ),
    );

    final categories = await provider.fetchCategories();
    expect(categories, hasLength(1));
    expect(categories.single.children, isNotEmpty);
    expect(
      categories.single.children.first.pic,
      'https://douyin.test/category-icon.png',
    );
  });

  test('douyin category rooms skip sparse empty pages by advancing offset',
      () async {
    final provider = DouyinProvider(
      dataSource: DouyinLiveDataSource(
        transport: _SparseDouyinCategoryTransport(),
        signService: HttpDouyinSignService(cookie: 'ttwid=test-cookie'),
      ),
    );

    final page = await provider.fetchCategoryRooms(
      const LiveSubCategory(
        id: '1010026,1',
        parentId: '1000000,1',
        name: '绝地求生',
      ),
      page: 2,
    );

    expect(page.page, 3);
    expect(page.items, hasLength(15));
    expect(page.items.first.roomId, 'room-30-0');
    expect(page.hasMore, isTrue);
  });

  test('legacy douyin quality mapping keeps origin playable', () {
    const detail = LiveRoomDetail(
      providerId: 'douyin',
      roomId: '1',
      title: 'legacy',
      streamerName: 'tester',
      isLive: true,
      sourceUrl: 'https://live.douyin.com/1',
      metadata: {
        'streamUrl': {
          'live_core_sdk_data': {
            'pull_data': {
              'options': {
                'qualities': [
                  {'name': '标清', 'level': 2},
                  {'name': '高清', 'level': 1},
                  {'name': '原画', 'level': 0},
                ],
              },
              'stream_data': '',
            },
          },
          'flv_pull_url': {
            'sd': 'https://douyin.test/sd.flv',
            'hd': 'https://douyin.test/hd.flv',
            'origin': 'https://douyin.test/origin.flv',
          },
          'hls_pull_url_map': {
            'sd': 'https://douyin.test/sd.m3u8',
            'hd': 'https://douyin.test/hd.m3u8',
            'origin': 'https://douyin.test/origin.m3u8',
          },
        },
      },
    );

    final qualities = DouyinMapper.mapPlayQualities(detail);
    final origin = qualities.firstWhere((item) => item.isDefault);
    final urls = DouyinMapper.mapPlayUrls(origin);

    expect(urls, isNotEmpty);
    expect(urls.first.url, contains('/origin.'));
  });

  test('live douyin runtime normalizes malformed display text', () async {
    final transport = _MalformedTextDouyinTransport();
    final signService = HttpDouyinSignService(cookie: 'ttwid=test-cookie');
    final provider = DouyinProvider(
      dataSource: DouyinLiveDataSource(
        transport: transport,
        signService: signService,
      ),
    );

    final rooms = await provider.searchRooms('测试');
    final detail = await provider.fetchRoomDetail(rooms.items.single.roomId);

    expect(rooms.items.single.title, '抖音游戏厅');
    expect(rooms.items.single.streamerName, '抖音热门主播');
    expect(detail.title, '抖音游戏厅');
    expect(detail.streamerName, '抖音热门主播');
    expect(detail.areaName, '热门游戏');
    expect(detail.description, '主播简介');
  });

  test('douyin room detail falls back to html when web enter stalls', () async {
    final provider = DouyinProvider(
      dataSource: DouyinLiveDataSource(
        transport: _TimeoutThenHtmlDouyinTransport(),
        signService: HttpDouyinSignService(cookie: 'ttwid=test-cookie'),
        roomDetailApiTimeout: const Duration(milliseconds: 20),
        roomDetailHtmlTimeout: const Duration(milliseconds: 200),
      ),
    );

    final detail = await provider.fetchRoomDetail('416144012050');
    final qualities = await provider.fetchPlayQualities(detail);
    final urls = await provider.fetchPlayUrls(
      detail: detail,
      quality: qualities.firstWhere((item) => item.isDefault),
    );

    expect(detail.title, '抖音 HTML 直播间');
    expect(detail.streamerName, '抖音 HTML 主播');
    expect(detail.isLive, isTrue);
    expect(qualities, isNotEmpty);
    expect(urls, isNotEmpty);
    expect(urls.first.url, contains('/origin.'));
  });
}

class _FakeDouyinTransport extends DouyinTransport {
  @override
  Future<DouyinHttpResponse> getResponse(
    String url, {
    Map<String, String> queryParameters = const {},
    Map<String, String> headers = const {},
  }) async {
    final uri = Uri.parse(url).replace(
      queryParameters: queryParameters.isEmpty ? null : queryParameters,
    );
    if (uri
        .toString()
        .startsWith('https://www.douyin.com/aweme/v1/web/live/search/')) {
      return DouyinHttpResponse(
        body: jsonEncode({
          'status_code': 0,
          'data': [
            {
              'lives': {
                'rawdata': jsonEncode({
                  'title': '抖音测试直播间',
                  'owner': {
                    'web_rid': '416144012050',
                    'nickname': '抖音主播',
                    'avatar_medium': {
                      'url_list': ['https://douyin.test/avatar.jpg']
                    },
                  },
                  'cover': {
                    'url_list': ['https://douyin.test/cover.jpg']
                  },
                  'stats': {'total_user': 12345},
                  'room': {'title': '抖音测试直播间'},
                }),
              },
            },
          ],
        }),
        headers: const {},
      );
    }
    if (uri
        .toString()
        .startsWith('https://live.douyin.com/webcast/room/web/enter/')) {
      return DouyinHttpResponse(
        body: jsonEncode({
          'data': {
            'data': [
              {
                'id_str': '7376429659866598196',
                'title': '抖音测试直播间',
                'status': 2,
                'cover': {
                  'url_list': ['https://douyin.test/cover.jpg']
                },
                'owner': {
                  'nickname': '抖音主播',
                  'signature': '签名',
                  'avatar_thumb': {
                    'url_list': ['https://douyin.test/avatar.jpg']
                  },
                },
                'room_view_stats': {'display_value': 54321},
                'stream_url': {
                  'live_core_sdk_data': {
                    'pull_data': {
                      'options': {
                        'qualities': [
                          {'name': '高清', 'level': 1, 'sdk_key': 'hd'},
                          {'name': '原画', 'level': 0, 'sdk_key': 'origin'},
                        ],
                      },
                      'stream_data':
                          '{"data":{"hd":{"main":{"flv":"https://douyin.test/hd.flv","hls":"https://douyin.test/hd.m3u8"}},"origin":{"main":{"flv":"https://douyin.test/origin.flv","hls":"https://douyin.test/origin.m3u8"}}}}',
                    },
                  },
                },
              },
            ],
            'user': {
              'nickname': '抖音主播',
              'avatar_thumb': {
                'url_list': ['https://douyin.test/avatar.jpg']
              },
            },
            'partition_road_map': {
              'partition': {'title': '知识'},
              'sub_partition': {
                'partition': {'title': '技术'}
              },
            },
          },
        }),
        headers: const {},
      );
    }
    fail('Unexpected douyin request: $uri');
  }
}

class _FallbackDouyinTransport extends DouyinTransport {
  @override
  Future<DouyinHttpResponse> getResponse(
    String url, {
    Map<String, String> queryParameters = const {},
    Map<String, String> headers = const {},
  }) async {
    final uri = Uri.parse(url).replace(
      queryParameters: queryParameters.isEmpty ? null : queryParameters,
    );
    if (uri
        .toString()
        .startsWith('https://www.douyin.com/aweme/v1/web/live/search/')) {
      return DouyinHttpResponse(
        body: jsonEncode({
          'status_code': 0,
          'data': const [],
        }),
        headers: const {},
      );
    }
    if (uri.toString() ==
        'https://live.douyin.com/webcast/feed/?aid=6383&app_name=douyin_web&need_map=1&is_draw=1&inner_from_drawer=0&enter_source=web_homepage_hot_web_live_card&source_key=web_homepage_hot_web_live_card&count=50') {
      return DouyinHttpResponse(
        body: jsonEncode({
          'data': [
            for (var index = 0; index < 18; index += 1)
              {
                'data': {
                  'title': index < 12 ? '关键房间$index' : '无关房间$index',
                  'cover': {
                    'url_list': ['https://douyin.test/cover-$index.jpg']
                  },
                  'owner': {
                    'web_rid': index < 12 ? 'match-$index' : 'other-$index',
                    'nickname': index < 12 ? '关键主播$index' : '其他主播$index',
                    'avatar_thumb': {
                      'url_list': ['https://douyin.test/avatar-$index.jpg']
                    },
                  },
                  'room_view_stats': {'display_value': 1000 + index},
                },
              },
          ],
        }),
        headers: const {},
      );
    }
    fail('Unexpected douyin fallback request: $uri');
  }
}

class _BrokenDouyinCategoryTransport extends DouyinTransport {
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
      return const DouyinHttpResponse(body: '<html></html>', headers: {});
    }
    fail('Unexpected douyin category request: $uri');
  }
}

class _SparseDouyinCategoryTransport extends DouyinTransport {
  @override
  Future<DouyinHttpResponse> getResponse(
    String url, {
    Map<String, String> queryParameters = const {},
    Map<String, String> headers = const {},
  }) async {
    final uri = Uri.parse(url).replace(
      queryParameters: queryParameters.isEmpty ? null : queryParameters,
    );
    if (!uri.toString().startsWith(
        'https://live.douyin.com/webcast/web/partition/detail/room/v2/')) {
      fail('Unexpected douyin sparse category request: $uri');
    }

    final offset = int.parse(uri.queryParameters['offset'] ?? '0');
    final responseOffset = offset + 15;
    final items = offset == 15
        ? const <Map<String, dynamic>>[]
        : List.generate(15, (index) {
            return {
              'web_rid': 'room-$offset-$index',
              'tag_name': '绝地求生',
              'room': {
                'title': '房间$index',
                'cover': {
                  'url_list': ['https://douyin.test/cover-$offset-$index.jpg']
                },
                'owner': {
                  'nickname': '主播$index',
                  'avatar_medium': {
                    'url_list': [
                      'https://douyin.test/avatar-$offset-$index.jpg'
                    ]
                  },
                },
                'room_view_stats': {'display_value': 1000 + index},
              },
            };
          });

    return DouyinHttpResponse(
      body: jsonEncode({
        'data': {
          'count': 15,
          'offset': responseOffset,
          'data': items,
        },
      }),
      headers: const {},
    );
  }
}

class _CategoryIconDouyinTransport extends DouyinTransport {
  @override
  Future<DouyinHttpResponse> getResponse(
    String url, {
    Map<String, String> queryParameters = const {},
    Map<String, String> headers = const {},
  }) async {
    final uri = Uri.parse(url).replace(
      queryParameters: queryParameters.isEmpty ? null : queryParameters,
    );
    if (uri.toString() != 'https://live.douyin.com/') {
      fail('Unexpected douyin category icon request: $uri');
    }
    return DouyinHttpResponse(
      body:
          r'{\"pathname\":\"/\",\"categoryData\":[{\"partition\":{\"id_str\":\"720\",\"type\":1,\"title\":\"游戏\",\"icon\":{\"url\":\"https://douyin.test/category-icon.png\"}},\"sub_partition\":[]}]}],',
      headers: const {},
    );
  }
}

class _MalformedTextDouyinTransport extends _FakeDouyinTransport {
  static final String _badTitle =
      '抖音游${String.fromCharCode(0xD800)}戏${String.fromCharCode(0xDC00)}厅';
  static final String _badName = '抖音熱${String.fromCharCode(0xD800)}門主播';
  static final String _badArea = '熱門遊${String.fromCharCode(0xDC00)}戲';
  static final String _badDescription = '主播簡${String.fromCharCode(0xD800)}介';

  @override
  Future<DouyinHttpResponse> getResponse(
    String url, {
    Map<String, String> queryParameters = const {},
    Map<String, String> headers = const {},
  }) async {
    final uri = Uri.parse(url).replace(
      queryParameters: queryParameters.isEmpty ? null : queryParameters,
    );
    if (uri
        .toString()
        .startsWith('https://www.douyin.com/aweme/v1/web/live/search/')) {
      return DouyinHttpResponse(
        body: jsonEncode({
          'status_code': 0,
          'data': [
            {
              'lives': {
                'rawdata': jsonEncode({
                  'title': _badTitle,
                  'owner': {
                    'web_rid': '416144012050',
                    'nickname': _badName,
                    'avatar_medium': {
                      'url_list': ['https://douyin.test/avatar.jpg']
                    },
                  },
                  'cover': {
                    'url_list': ['https://douyin.test/cover.jpg']
                  },
                  'stats': {'total_user': 12345},
                  'room': {'title': _badTitle},
                }),
              },
            },
          ],
        }),
        headers: const {},
      );
    }
    if (uri
        .toString()
        .startsWith('https://live.douyin.com/webcast/room/web/enter/')) {
      return DouyinHttpResponse(
        body: jsonEncode({
          'data': {
            'data': [
              {
                'id_str': '7376429659866598196',
                'title': _badTitle,
                'status': 2,
                'cover': {
                  'url_list': ['https://douyin.test/cover.jpg']
                },
                'owner': {
                  'nickname': _badName,
                  'avatar_thumb': {
                    'url_list': ['https://douyin.test/avatar.jpg']
                  },
                  'signature': _badDescription,
                },
                'room_view_stats': {'display_value': 12345},
                'stream_url': {
                  'flv_pull_url': {
                    'FULL_HD1': 'https://douyin.test/origin.flv',
                  },
                  'hls_pull_url_map': {
                    'FULL_HD1': 'https://douyin.test/origin.m3u8',
                  },
                  'live_core_sdk_data': {
                    'pull_data': {
                      'options': {
                        'qualities': [
                          {'sdk_key': 'FULL_HD1', 'name': '原画', 'level': 0},
                        ],
                      },
                      'stream_data': '',
                    },
                  },
                },
              },
            ],
            'user': {
              'nickname': _badName,
            },
            'partition_road_map': {
              'partition': {'title': _badArea},
            },
          },
        }),
        headers: const {},
      );
    }
    return super.getResponse(
      url,
      queryParameters: queryParameters,
      headers: headers,
    );
  }
}

class _TimeoutThenHtmlDouyinTransport extends DouyinTransport {
  @override
  Future<DouyinHttpResponse> getResponse(
    String url, {
    Map<String, String> queryParameters = const {},
    Map<String, String> headers = const {},
  }) async {
    final uri = Uri.parse(url).replace(
      queryParameters: queryParameters.isEmpty ? null : queryParameters,
    );
    if (uri
        .toString()
        .startsWith('https://live.douyin.com/webcast/room/web/enter/')) {
      await Future<void>.delayed(const Duration(milliseconds: 80));
      return const DouyinHttpResponse(body: '{}', headers: {});
    }
    if (uri.toString() == 'https://live.douyin.com/416144012050') {
      final payload = jsonEncode({
        'state': {
          'appStore': {},
          'roomStore': {
            'roomInfo': {
              'room': {
                'id_str': '7376429659866598196',
                'title': '抖音 HTML 直播间',
                'status': 2,
                'cover': {
                  'url_list': ['https://douyin.test/cover.jpg'],
                },
                'owner': {
                  'nickname': '抖音 HTML 主播',
                  'signature': 'HTML 签名',
                  'avatar_thumb': {
                    'url_list': ['https://douyin.test/avatar.jpg'],
                  },
                },
                'room_view_stats': {
                  'display_value': 54321,
                },
                'stream_url': {
                  'live_core_sdk_data': {
                    'pull_data': {
                      'options': {
                        'qualities': [
                          {
                            'name': '原画',
                            'level': 0,
                            'sdk_key': 'origin',
                          },
                        ],
                      },
                      'stream_data': jsonEncode({
                        'data': {
                          'origin': {
                            'main': {
                              'flv': 'https://douyin.test/origin.flv',
                              'hls': 'https://douyin.test/origin.m3u8',
                            },
                          },
                        },
                      }),
                    },
                  },
                },
              },
              'anchor': {
                'nickname': '抖音 HTML 主播',
                'avatar_thumb': {
                  'url_list': ['https://douyin.test/avatar.jpg'],
                },
              },
            },
          },
          'userStore': {
            'odin': {
              'user_unique_id': '123456789012',
            },
          },
        },
      }).replaceAll('"', r'\"');
      return DouyinHttpResponse(
        body: '$payload]\\n',
        headers: const {},
      );
    }
    fail('Unexpected douyin timeout/html request: $uri');
  }
}
