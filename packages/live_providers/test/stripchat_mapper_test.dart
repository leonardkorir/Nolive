import 'package:live_core/live_core.dart';
import 'package:live_providers/src/providers/stripchat/stripchat_mapper.dart';
import 'package:test/test.dart';

void main() {
  group('mapCategories', () {
    test('builds region categories from liveTagDetails and ethnicity from '
        'liveTagGroups', () {
      final payload = {
        'liveTagDetails': {
          'tagLanguageChinese': {},
          'tagLanguageUSModels': {},
          'tagLanguageIndian': {},
          'tagLanguageFilipino': {},
          'tagLanguageAfrican': {},
          'tagLanguageTurkish': {},
        },
        'liveTagGroups': [
          {
            'alias': 'ethnicity',
            'tags': [
              {'tag': 'ethnicityAsian'},
              {'tag': 'ethnicityWhite'},
            ],
          },
        ],
      };

      final categories = StripchatMapper.mapCategories(payload);

      expect(categories[0].id, 'country-asia_pacific');
      expect(categories[0].name, '亚洲 & 太平洋');
      expect(categories[0].children, hasLength(3));
      expect(categories[0].children[0].id, 'tagLanguageFilipino');
      expect(categories[0].children[0].name, '菲律宾');
      expect(categories[0].children[1].id, 'tagLanguageIndian');
      expect(categories[0].children[2].id, 'tagLanguageChinese');
      expect(categories[0].children[2].name, '中文');

      expect(categories[1].id, 'country-north_america');
      expect(categories[1].name, '北美');
      expect(categories[1].children[0].id, 'tagLanguageUSModels');

      expect(categories[2].id, 'country-africa');
      expect(categories[2].children[0].id, 'tagLanguageAfrican');

      expect(categories[3].id, 'country-middle_east');
      expect(categories[3].children[0].id, 'tagLanguageTurkish');

      final ethnicity = categories.firstWhere((c) => c.id == 'ethnicity');
      expect(ethnicity.name, '种族');
      expect(ethnicity.children[0].name, '亚洲人');
    });
  });

  group('mapRecommendResponse', () {
    test('maps v2/models blocks to paged rooms', () {
      final payload = {
        'blocks': [
          {
            'url': 'girls/recommended',
            'models': [
              {
                'id': 100001,
                'username': 'alice_demo',
                'status': 'public',
                'isLive': true,
                'streamName': '100001',
                'viewersCount': 1200,
                'snapshotTimestamp': 1777920990,
                'previewUrlThumbSmall': 'https://img.test/alice.jpg',
                'country': 'China',
                'avatarUrl': 'https://img.test/alice_avatar.jpg',
              },
              {
                'id': 100002,
                'username': 'bob_live',
                'status': 'public',
                'isLive': true,
                'streamName': '100002',
                'viewersCount': 800,
                'previewUrlThumbSmall': 'https://img.test/bob.jpg',
                'country': 'USA',
              },
            ],
          },
        ],
        'totalCount': 2,
      };

      final response = StripchatMapper.mapRecommendResponse(
        payload,
        page: 1,
        limit: 24,
      );

      expect(response.items, hasLength(2));
      expect(response.page, 1);
      expect(response.hasMore, isFalse);
      expect(response.items[0].roomId, 'alice_demo');
      expect(response.items[0].streamerName, 'alice_demo');
      expect(response.items[0].areaName, 'China');
      expect(response.items[0].viewerCount, 1200);
      expect(response.items[0].coverUrl, contains('alice.jpg'));
      expect(
        response.items[0].keyframeUrl,
        'https://img.doppiocdn.net/snapshot/100001/1777920990',
      );
    });

    test('filters off/idle/private/p2p status rooms', () {
      final payload = {
        'blocks': [
          {
            'models': [
              {
                'username': 'online_a',
                'status': 'public',
                'isLive': true,
                'streamName': '001',
              },
              {
                'username': 'offline_b',
                'status': 'off',
                'isLive': false,
                'streamName': '',
              },
              {
                'username': 'private_c',
                'status': 'private',
                'isLive': true,
                'streamName': '002',
              },
              {
                'username': 'idle_d',
                'status': 'idle',
                'isLive': false,
                'streamName': '',
              },
              {
                'username': 'p2p_e',
                'status': 'p2p',
                'isLive': true,
                'streamName': '003',
              },
            ],
          },
        ],
      };

      final response = StripchatMapper.mapRecommendResponse(
        payload,
        page: 1,
        limit: 24,
      );

      expect(response.items, hasLength(1));
      expect(response.items[0].roomId, 'online_a');
    });

    test('does not filter groupShow before detail check', () {
      final payload = {
        'blocks': [
          {
            'models': [
              {
                'username': 'group_show_user',
                'status': 'groupShow',
                'isLive': true,
                'streamName': '100001',
              },
            ],
          },
        ],
      };

      final response = StripchatMapper.mapRecommendResponse(
        payload,
        page: 1,
        limit: 24,
      );

      expect(response.items, hasLength(1));
    });
  });

  group('mapSearchResponse', () {
    test('merges groups and deduplicates by modelId', () {
      final payload = {
        'groups': {
          'username': {
            'models': [
              {
                'username': 'alice',
                'id': 100,
                'status': 'public',
                'isLive': true,
                'streamName': '001',
              },
            ],
          },
          'topic': {
            'models': [
              {
                'username': 'bob',
                'id': 200,
                'status': 'public',
                'isLive': true,
                'streamName': '002',
              },
            ],
          },
          'tipMenu': {'models': []},
          'activity': {'models': []},
          'interest': {'models': []},
        },
      };

      final response = StripchatMapper.mapSearchResponse(
        payload,
        page: 1,
        limit: 24,
      );

      expect(response.items, hasLength(2));
      expect(response.items[0].roomId, 'alice');
      expect(response.items[1].roomId, 'bob');
    });

    test(
      'merge order follows username->topic->tipMenu->activity->interest',
      () {
        final payload = {
          'groups': {
            'interest': {
              'models': [
                {
                  'username': 'interest_user',
                  'id': 1,
                  'status': 'public',
                  'isLive': true,
                  'streamName': '001',
                },
              ],
            },
            'username': {
              'models': [
                {
                  'username': 'username_user',
                  'id': 2,
                  'status': 'public',
                  'isLive': true,
                  'streamName': '002',
                },
              ],
            },
            'tipMenu': {'models': []},
            'activity': {'models': []},
            'topic': {'models': []},
          },
        };

        final response = StripchatMapper.mapSearchResponse(
          payload,
          page: 1,
          limit: 24,
        );

        expect(response.items, hasLength(2));
        expect(response.items[0].roomId, 'username_user');
        expect(response.items[1].roomId, 'interest_user');
      },
    );
  });

  group('mapPlayQualities', () {
    test('always returns auto as default', () {
      final detail = LiveRoomDetail(
        providerId: ProviderId.stripchat,
        roomId: 'test',
        title: 'Test',
        streamerName: 'tester',
      );

      final qualities = StripchatMapper.mapPlayQualities(detail);

      expect(qualities, isNotEmpty);
      expect(qualities.first.id, 'auto');
      expect(qualities.first.isDefault, isTrue);
    });

    test('generates qualities from presets in metadata', () {
      final detail = LiveRoomDetail(
        providerId: ProviderId.stripchat,
        roomId: 'test',
        title: 'Test',
        streamerName: 'tester',
        metadata: const {
          'presets': ['720p', '480p', '240p', '160p'],
        },
      );

      final qualities = StripchatMapper.mapPlayQualities(detail);

      expect(qualities.length, greaterThanOrEqualTo(2));
      final ids = qualities.map((q) => q.id).toSet();
      expect(ids, contains('auto'));
      expect(ids, contains('720p'));
    });

    test('keeps source above discovered fixed qualities', () {
      final detail = LiveRoomDetail(
        providerId: ProviderId.stripchat,
        roomId: 'test',
        title: 'Test',
        streamerName: 'tester',
      );

      final qualities = StripchatMapper.mapPlayQualities(
        detail,
        discoveredQualityIds: const ['480p', 'source', '240p'],
      );

      expect(qualities.map((quality) => quality.id), [
        'auto',
        'source',
        '480p',
        '240p',
      ]);
      expect(qualities[1].label, 'Source');
      expect(qualities[1].sortOrder, greaterThan(qualities[2].sortOrder));
    });

    test('filters blurred and pixelate presets', () {
      final detail = LiveRoomDetail(
        providerId: ProviderId.stripchat,
        roomId: 'test',
        title: 'Test',
        streamerName: 'tester',
        metadata: const {
          'presets': ['720p', '160p_blurred', '480p'],
        },
      );

      final qualities = StripchatMapper.mapPlayQualities(detail);

      final ids = qualities.map((q) => q.id).toSet();
      expect(ids, contains('720p'));
      expect(ids, contains('480p'));
      expect(ids, isNot(contains('160p_blurred')));
    });
  });

  group('mapPlayUrls', () {
    test('generates HLS URL from streamName and cdnDomain', () async {
      final detail = LiveRoomDetail(
        providerId: ProviderId.stripchat,
        roomId: 'test',
        title: 'Test',
        streamerName: 'tester',
        sourceUrl: 'https://zh.stripchat.com/tester',
        metadata: const {
          'streamName': '12345',
          'cdnDomains': ['doppiocdn.net'],
        },
      );
      final quality = LivePlayQuality(id: 'auto', label: 'Auto');

      final urls = await StripchatMapper.mapPlayUrls(
        detail: detail,
        quality: quality,
      );

      expect(urls, hasLength(1));
      expect(urls[0].url, contains('edge-hls.doppiocdn.net'));
      expect(urls[0].url, contains('/12345/master/12345_auto.m3u8'));
      expect(urls[0].headers['referer'], 'https://zh.stripchat.com/');
      expect(urls[0].headers['user-agent'], isNotEmpty);
      expect(urls[0].headers['sec-ch-ua'], isNotEmpty);
      expect(urls[0].headers['origin'], 'https://zh.stripchat.com');
      expect(urls[0].headers['accept-language'], contains('zh-CN'));
      expect(urls[0].headers['accept'], '*/*');
      expect(urls[0].metadata?['stripchatCdnDomains'], ['doppiocdn.net']);
      expect(
        urls[0].metadata?['stripchatRoomUrl'],
        'https://zh.stripchat.com/tester',
      );
    });

    test(
      'keeps auto master request even for fixed-quality selection and only adds preferred variant hint',
      () async {
        final detail = LiveRoomDetail(
          providerId: ProviderId.stripchat,
          roomId: 'test',
          title: 'Test',
          streamerName: 'tester',
          metadata: const {
            'streamName': '12345',
            'cdnDomains': ['doppiocdn.net'],
          },
        );
        final quality = LivePlayQuality(id: '1080p', label: '1080P');

        final urls = await StripchatMapper.mapPlayUrls(
          detail: detail,
          quality: quality,
        );

        expect(urls, hasLength(1));
        expect(urls[0].url, contains('/12345/master/12345_auto.m3u8'));
        expect(urls[0].metadata?['preferredVariantId'], '1080p');
      },
    );

    test(
      'generates source request from auto master with source hint',
      () async {
        final detail = LiveRoomDetail(
          providerId: ProviderId.stripchat,
          roomId: 'test',
          title: 'Test',
          streamerName: 'tester',
          metadata: const {
            'streamName': '12345',
            'cdnDomains': ['doppiocdn.net'],
          },
        );
        final quality = LivePlayQuality(id: 'source', label: 'Source');

        final urls = await StripchatMapper.mapPlayUrls(
          detail: detail,
          quality: quality,
        );

        expect(urls, hasLength(1));
        expect(urls[0].url, contains('/12345/master/12345_auto.m3u8'));
        expect(urls[0].metadata?['preferredVariantId'], 'source');
      },
    );

    test('returns empty list when streamName is missing', () async {
      final detail = LiveRoomDetail(
        providerId: ProviderId.stripchat,
        roomId: 'test',
        title: 'Test',
        streamerName: 'tester',
      );
      final quality = LivePlayQuality(id: 'auto', label: 'Auto');

      final urls = await StripchatMapper.mapPlayUrls(
        detail: detail,
        quality: quality,
      );

      expect(urls, isEmpty);
    });

    test(
      'returns empty list when room detail already marks playback unavailable',
      () async {
        final detail = LiveRoomDetail(
          providerId: ProviderId.stripchat,
          roomId: 'test',
          title: 'Test',
          streamerName: 'tester',
          metadata: const {
            'streamName': '12345',
            'playbackUnavailableReason': 'blocked',
          },
        );

        final urls = await StripchatMapper.mapPlayUrls(
          detail: detail,
          quality: LivePlayQuality(id: 'auto', label: 'Auto'),
        );

        expect(urls, isEmpty);
      },
    );
  });

  group('mapRoomDetail', () {
    test('maps cam + broadcast to LiveRoomDetail', () async {
      final camPayload = {
        'cam': {
          'topic': 'Welcome to my room',
          'streamName': '12345',
          'isCamAvailable': true,
        },
        'user': {
          'user': {
            'id': 12345,
            'username': 'test_user',
            'status': 'public',
            'isLive': true,
            'snapshotTimestamp': 1777920990,
            'previewUrl': 'https://img.test/preview.jpg',
            'avatarUrl': 'https://img.test/avatar.jpg',
            'description': 'A test room',
            'country': 'China',
          },
        },
      };
      final broadcastPayload = {
        'item': {
          'modelId': 12345,
          'username': 'test_user',
          'streamName': '12345',
          'status': 'public',
          'isLive': true,
          'settings': {
            'presets': ['720p', '480p'],
            'width': 1280,
            'height': 720,
          },
        },
      };
      final initialDynamic = {
        'websocket': {
          'url': 'wss://ws.stripchat.com/connection/websocket',
          'token': 'mock-jwt',
        },
        'players': {
          'cdnConfig': [
            {'domain': 'doppiocdn.net'},
          ],
        },
      };

      final detail = StripchatMapper.mapRoomDetail(
        roomId: 'test_user',
        camPayload: camPayload,
        broadcastPayload: broadcastPayload,
        userHash: 'mock-hash',
        csrfToken: 'mock-csrf',
        guestId: -1,
        initialDynamicPayload: initialDynamic,
        requestCookie: 'stripchat_com_guestId=1; __cf_bm=test',
      );

      expect(detail.roomId, 'test_user');
      expect(detail.title, 'Welcome to my room');
      expect(detail.streamerName, 'test_user');
      expect(detail.coverUrl, contains('preview.jpg'));
      expect(
        detail.keyframeUrl,
        'https://img.doppiocdn.net/snapshot/12345/1777920990',
      );
      expect(detail.streamerAvatarUrl, contains('avatar.jpg'));
      expect(detail.description, 'A test room');
      expect(detail.areaName, 'China');
      expect(detail.isLive, isTrue);
      expect(detail.danmakuToken, isA<StripchatDanmakuToken>());
      final token = detail.danmakuToken as StripchatDanmakuToken;
      expect(token.modelId, '12345');
      expect(token.jwt, 'mock-jwt');
      expect(token.websocketUrl, contains('ws.stripchat.com'));
      expect(token.historyUrl, contains('/api/front/v2/models/12345/chat'));
      expect(token.requestCookie, contains('stripchat_com_guestId=1'));
      expect(token.roomUrl, 'https://zh.stripchat.com/test_user');
      expect(detail.metadata?['modelId'], '12345');
      expect(detail.metadata?['streamName'], '12345');
      expect(detail.metadata?['userHash'], 'mock-hash');
      expect(detail.metadata?['csrfToken'], 'mock-csrf');
      expect(detail.metadata?['guestId'], -1);
      expect(detail.metadata?['presets'], ['720p', '480p']);
      expect(detail.metadata?['requiresLogin'], isFalse);
      expect(
        detail.metadata?['requestCookie'],
        contains('stripchat_com_guestId'),
      );
    });

    test('calculates viewerCount from membersPayload', () {
      final camPayload = {
        'cam': {
          'topic': 'Welcome to my room',
          'streamName': '12345',
          'isCamAvailable': true,
        },
        'user': {
          'user': {
            'id': 12345,
            'username': 'test_user',
            'status': 'public',
            'isLive': true,
            'viewersCount': 100,
          },
        },
      };
      final membersPayload = {
        'guests': 200,
        'regulars': 300,
        'greens': 100,
        'golds': 50,
        'invisibles': 10,
        'spies': 5,
      };

      final detail = StripchatMapper.mapRoomDetail(
        roomId: 'test_user',
        camPayload: camPayload,
        membersPayload: membersPayload,
      );

      expect(detail.viewerCount, 665);
    });

    test(
      'uses unavailable danmaku token when websocket config is missing',
      () async {
        final camPayload = {
          'cam': {'streamName': '12345'},
          'user': {
            'user': {
              'id': 12345,
              'username': 'test_user',
              'status': 'public',
              'isLive': true,
            },
          },
        };

        final detail = StripchatMapper.mapRoomDetail(
          roomId: 'test_user',
          camPayload: camPayload,
        );

        expect(detail.danmakuToken, isA<UnavailableDanmakuToken>());
      },
    );

    test(
      'keeps groupShow rooms playable when stream name and websocket exist',
      () async {
        final detail = StripchatMapper.mapRoomDetail(
          roomId: 'test_user',
          camPayload: {
            'cam': {
              'streamName': '12345',
              'isCamAvailable': true,
              'show': {'mode': 'groupShow'},
            },
            'user': {
              'user': {
                'id': 12345,
                'username': 'test_user',
                'status': 'public',
                'isLive': true,
              },
            },
          },
          initialDynamicPayload: const {
            'websocket': {
              'url': 'wss://ws.stripchat.com/connection/websocket',
              'token': 'mock-jwt',
            },
          },
        );

        expect(detail.metadata?['playbackUnavailableReason'], isNull);
        expect(detail.danmakuToken, isA<StripchatDanmakuToken>());
      },
    );

    test(
      'does not block public broadcast because of stale virtualPrivate show',
      () async {
        final detail = StripchatMapper.mapRoomDetail(
          roomId: 'baeasian',
          camPayload: {
            'cam': {
              'streamName': '',
              'isCamAvailable': true,
              'show': {
                'mode': 'virtualPrivate',
                'endedAt': '2026-03-26T06:53:34Z',
              },
            },
            'user': {
              'user': {
                'id': 112319207,
                'username': 'baeasian',
                'status': 'public',
                'isLive': true,
              },
            },
          },
          broadcastPayload: const {
            'item': {
              'status': 'public',
              'isLive': true,
              'streamName': '112319207',
              'settings': {
                'presets': ['1080p60', '720p60'],
              },
            },
          },
          initialDynamicPayload: const {
            'websocket': {
              'url': 'wss://websocket-sp-v6.stripchat.com/connection/websocket',
              'token': 'mock-jwt',
            },
          },
        );

        expect(detail.metadata?['streamName'], '112319207');
        expect(detail.metadata?['broadcastStatus'], 'public');
        expect(detail.metadata?['playbackUnavailableReason'], isNull);
        expect(detail.danmakuToken, isA<StripchatDanmakuToken>());
      },
    );

    test('does not require cookie to create stripchat danmaku token', () async {
      final detail = StripchatMapper.mapRoomDetail(
        roomId: 'test_user',
        camPayload: {
          'cam': {'streamName': '12345', 'isCamAvailable': false},
          'user': {
            'user': {
              'id': 12345,
              'username': 'test_user',
              'status': 'public',
              'isLive': true,
            },
          },
        },
        initialDynamicPayload: const {
          'websocket': {
            'url': 'wss://ws.stripchat.com/connection/websocket',
            'token': 'mock-jwt',
          },
        },
      );

      expect(detail.metadata?['requiresLogin'], isFalse);
      expect(detail.metadata?['playbackUnavailableReason'], isNull);
      expect(detail.danmakuToken, isA<StripchatDanmakuToken>());
    });

    test('marks offline room with empty stream name as unavailable', () async {
      final detail = StripchatMapper.mapRoomDetail(
        roomId: 'offline_user',
        camPayload: {
          'cam': {'streamName': '', 'isCamAvailable': false},
          'user': {
            'user': {
              'id': 54321,
              'username': 'offline_user',
              'status': 'off',
              'isLive': false,
            },
          },
        },
      );

      expect(detail.metadata?['playbackUnavailableReason'], contains('暂未开播'));
      expect(detail.danmakuToken, isA<UnavailableDanmakuToken>());
    });

    test(
      'handles case-insensitive offline status and dynamic isLive string/int parsing',
      () async {
        final detail = StripchatMapper.mapRoomDetail(
          roomId: 'test_user',
          camPayload: {
            'cam': {
              'streamName': '12345',
              'isCamAvailable': true,
              'viewersCount': 100,
            },
            'user': {
              'user': {
                'id': 12345,
                'username': 'test_user',
                'status': 'Private', // case insensitive restricted status
                'isLive': 'true', // string bool
              },
            },
          },
        );

        expect(detail.isLive, true);
        expect(detail.viewerCount, 100);
        expect(
          detail.metadata?['playbackUnavailableReason'],
          contains('当前房间状态为 "Private"'),
        );
      },
    );
  });
}
