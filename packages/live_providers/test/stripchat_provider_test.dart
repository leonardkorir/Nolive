import 'package:live_core/live_core.dart';
import 'package:live_providers/live_providers.dart';
import 'package:live_providers/src/danmaku/stripchat_danmaku_session.dart';
import 'package:live_providers/src/danmaku/provider_unavailable_danmaku_session.dart';
import 'package:live_providers/src/providers/stripchat/stripchat_api_client.dart';
import 'package:test/test.dart';

void main() {
  late StripchatProvider provider;

  setUp(() {
    provider = StripchatProvider.preview();
  });

  tearDown(() {
    provider.dispose();
  });

  test('descriptor has correct fields', () {
    final descriptor = provider.descriptor;
    expect(descriptor.id, ProviderId.stripchat);
    expect(descriptor.displayName, 'Stripchat');
    expect(descriptor.maturity, ProviderMaturity.inMigration);
    expect(descriptor.validate(), isEmpty);
    expect(descriptor.capabilities, contains(ProviderCapability.categories));
    expect(descriptor.capabilities, contains(ProviderCapability.danmaku));
    expect(descriptor.roomIdPatterns, contains(r'^[A-Za-z0-9_-]+$'));
    expect(descriptor.roomIdPatterns, contains(r'^\d+$'));
    expect(descriptor.supportedPlatforms, contains(ProviderPlatform.android));
    expect(
      descriptor.supportedPlatforms,
      isNot(contains(ProviderPlatform.web)),
    );
  });

  test(
    'fetchCategories returns non-empty list and matches structure',
    () async {
      final categories = await provider.fetchCategories();
      expect(categories, isNotEmpty);
      expect(categories.length, greaterThanOrEqualTo(2));
      for (final category in categories) {
        expect(category.id, isNotEmpty);
        expect(category.name, isNotEmpty);
        expect(category.children, isNotEmpty);
        for (final subCategory in category.children) {
          expect(subCategory.id, isNotEmpty);
          expect(subCategory.name, isNotEmpty);
          expect(subCategory.parentId, category.id);
        }
      }
    },
  );

  test('fetchCategoryRooms returns paged response', () async {
    final categories = await provider.fetchCategories();
    final subCategory = categories.first.children.first;
    final response = await provider.fetchCategoryRooms(subCategory);
    expect(response.items, isNotEmpty);
    expect(response.page, 1);
    expect(response.hasMore, false);
  });

  test('fetchRecommendRooms returns sorted rooms', () async {
    final response = await provider.fetchRecommendRooms();
    expect(response.items.length, greaterThanOrEqualTo(4));
    expect(response.page, 1);
    expect(response.hasMore, false);
    for (final room in response.items) {
      expect(room.providerId, ProviderId.stripchat);
      expect(room.roomId, isNotEmpty);
      expect(room.streamerName, isNotEmpty);
    }
  });

  test('searchRooms matches username and streamerName', () async {
    final response = await provider.searchRooms('alice');
    expect(response.items, isNotEmpty);
    expect(
      response.items.any((room) => room.roomId.toLowerCase().contains('alice')),
      isTrue,
    );

    final emptyResponse = await provider.searchRooms('');
    expect(
      emptyResponse.items.length,
      greaterThanOrEqualTo(response.items.length),
    );
  });

  test('fetchRoomDetail returns detail for known room', () async {
    final detail = await provider.fetchRoomDetail('alice_demo');
    expect(detail.providerId, ProviderId.stripchat);
    expect(detail.roomId, 'alice_demo');
    expect(detail.title, isNotEmpty);
    expect(detail.danmakuToken, isA<PreviewDanmakuToken>());
    expect(detail.metadata, isNotNull);
    expect(detail.metadata?['streamName'], isNotNull);
    expect(detail.sourceUrl, 'https://zh.stripchat.com/alice_demo');
  });

  test('fetchPlayQualities includes auto and specific qualities', () async {
    final detail = await provider.fetchRoomDetail('alice_demo');
    final qualities = await provider.fetchPlayQualities(detail);
    expect(qualities, isNotEmpty);
    expect(qualities.any((q) => q.id == 'auto'), isTrue);
    expect(qualities.any((q) => q.isDefault), isTrue);
  });

  test('fetchPlayUrls returns HLS URL', () async {
    final detail = await provider.fetchRoomDetail('alice_demo');
    final qualities = await provider.fetchPlayQualities(detail);
    final autoQuality = qualities.firstWhere((q) => q.id == 'auto');
    final urls = await provider.fetchPlayUrls(
      detail: detail,
      quality: autoQuality,
    );
    expect(urls, isNotEmpty);
    expect(urls.first.url, contains('.m3u8'));
    expect(urls.first.url, contains('auto'));
    expect(urls.first.headers, isNotEmpty);
  });

  test('createDanmakuSession returns ticker for preview token', () async {
    final detail = await provider.fetchRoomDetail('alice_demo');
    final session = await provider.createDanmakuSession(detail);
    expect(session, isNotNull);
    expect(session.messages, isNotNull);
    await session.disconnect();
  });

  group('createDanmakuSession with various tokens', () {
    test(
      'returns ProviderUnavailableDanmakuSession with reason for UnavailableDanmakuToken',
      () async {
        final detail = LiveRoomDetail(
          providerId: ProviderId.stripchat,
          roomId: 'test',
          title: 'test',
          streamerName: 'test',
          isLive: true,
          danmakuToken: const UnavailableDanmakuToken(
            reason: 'Specific rejection reason',
          ),
        );
        final session = await provider.createDanmakuSession(detail);
        expect(session, isA<ProviderUnavailableDanmakuSession>());
        expect(
          (session as ProviderUnavailableDanmakuSession).reason,
          'Specific rejection reason',
        );
      },
    );

    test(
      'returns ProviderUnavailableDanmakuSession for empty modelId StripchatDanmakuToken',
      () async {
        final detail = LiveRoomDetail(
          providerId: ProviderId.stripchat,
          roomId: 'test',
          title: 'test',
          streamerName: 'test',
          isLive: true,
          danmakuToken: const StripchatDanmakuToken(
            modelId: '',
            websocketUrl: 'wss://test',
            jwt: 'some_jwt',
          ),
        );
        final session = await provider.createDanmakuSession(detail);
        expect(session, isA<ProviderUnavailableDanmakuSession>());
        expect(
          (session as ProviderUnavailableDanmakuSession).reason,
          contains('弹幕Token缺少modelId'),
        );
      },
    );

    test(
      'returns ProviderUnavailableDanmakuSession for empty jwt StripchatDanmakuToken',
      () async {
        final detail = LiveRoomDetail(
          providerId: ProviderId.stripchat,
          roomId: 'test',
          title: 'test',
          streamerName: 'test',
          isLive: true,
          danmakuToken: const StripchatDanmakuToken(
            modelId: '123',
            websocketUrl: 'wss://test',
            jwt: ' ',
          ),
        );
        final session = await provider.createDanmakuSession(detail);
        expect(session, isA<ProviderUnavailableDanmakuSession>());
        expect(
          (session as ProviderUnavailableDanmakuSession).reason,
          contains('弹幕Token JWT为空'),
        );
      },
    );

    test(
      'returns StripchatDanmakuSession for valid StripchatDanmakuToken',
      () async {
        final detail = LiveRoomDetail(
          providerId: ProviderId.stripchat,
          roomId: 'test',
          title: 'test',
          streamerName: 'test',
          isLive: true,
          danmakuToken: const StripchatDanmakuToken(
            modelId: '123',
            websocketUrl: 'wss://test',
            jwt: 'some_jwt',
          ),
        );
        final session = await provider.createDanmakuSession(detail);
        expect(session, isA<StripchatDanmakuSession>());
        await session.disconnect();
      },
    );
  });

  group('StripchatProvider.live', () {
    late StripchatProvider liveProvider;
    late _MockStripchatApiClient mockApiClient;

    setUp(() {
      mockApiClient = _MockStripchatApiClient();
      liveProvider = StripchatProvider.live(apiClient: mockApiClient);
    });

    tearDown(() {
      liveProvider.dispose();
    });

    test('fetchCategories returns parsed live categories', () async {
      final categories = await liveProvider.fetchCategories();
      expect(categories, isNotEmpty);
      expect(categories[0].id, 'country-asia_pacific');
    });

    test('fetchCategoryRooms returns mapped response', () async {
      final response = await liveProvider.fetchCategoryRooms(
        const LiveSubCategory(
          id: 'tagLanguageChinese',
          parentId: 'country-asia_pacific',
          name: 'Chinese',
        ),
      );
      expect(response.items, isNotEmpty);
      expect(response.items.first.roomId, 'alice_demo');
    });

    test('fetchRecommendRooms returns mapped response', () async {
      final response = await liveProvider.fetchRecommendRooms();
      expect(response.items, isNotEmpty);
      expect(response.items.first.roomId, 'alice_demo');
    });

    test('searchRooms returns mapped response', () async {
      final response = await liveProvider.searchRooms('alice');
      expect(response.items, isNotEmpty);
      expect(response.items.first.roomId, 'alice_demo');
    });

    test(
      'fetchRoomDetail returns detail for modelId and maps settings',
      () async {
        // numeric ID test
        final detail = await liveProvider.fetchRoomDetail('12345');
        expect(detail.roomId, '12345');
        expect(detail.streamerName, 'alice_demo');
        expect(detail.viewerCount, 665); // 200 + 300 + 100 + 50 + 10 + 5
        expect(detail.danmakuToken, isA<StripchatDanmakuToken>());
        final token = detail.danmakuToken as StripchatDanmakuToken;
        expect(token.modelId, '12345');
        expect(token.jwt, 'mock-jwt');
      },
    );

    test('fetchPlayQualities returns resolved qualities', () async {
      final detail = await liveProvider.fetchRoomDetail('alice_demo');
      final qualities = await liveProvider.fetchPlayQualities(detail);
      expect(qualities, isNotEmpty);
      expect(qualities.any((q) => q.id == '720p'), isTrue);
    });

    test('fetchPlayUrls returns probed master playlist URL', () async {
      final detail = await liveProvider.fetchRoomDetail('alice_demo');
      final qualities = await liveProvider.fetchPlayQualities(detail);
      final quality720 = qualities.firstWhere((q) => q.id == '720p');
      final urls = await liveProvider.fetchPlayUrls(
        detail: detail,
        quality: quality720,
      );
      expect(urls, isNotEmpty);
      expect(urls.first.url.toString(), contains('doppiocdn.net'));
    });
  });
}

class _MockStripchatApiClient implements StripchatApiClient {
  @override
  String get cookie => 'mock_cookie';

  @override
  Future<Map<String, dynamic>> fetchInitialDynamic() async {
    return {
      'userHash': 'mock-hash',
      'csrfToken': 'mock-csrf',
      'guestId': 12345,
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
  }

  @override
  Future<Map<String, dynamic>> fetchLiveTags() async {
    return {
      'liveTagDetails': {'tagLanguageChinese': {}, 'tagLanguageUSModels': {}},
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
  }

  @override
  Future<Map<String, dynamic>> fetchCategoryModels({
    required String filterGroupTags,
    int limit = 60,
    int offset = 0,
    String? parentTag,
    String? guestHash,
  }) async {
    return {
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
      ],
      'totalCount': 1,
    };
  }

  @override
  Future<Map<String, dynamic>> fetchRecommendModels({
    int limit = 24,
    int offset = 0,
    String? guestHash,
  }) async {
    return {
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
          ],
        },
      ],
      'totalCount': 1,
    };
  }

  @override
  Future<Map<String, dynamic>> searchModels({
    required String query,
    int limit = 24,
    String? guestHash,
  }) async {
    return {
      'groups': {
        'username': {
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
          ],
        },
      },
    };
  }

  @override
  Future<Map<String, dynamic>> listModels({
    required List<int> modelIds,
    String? csrfToken,
    String? guestHash,
  }) async {
    return {
      'models': [
        {
          'id': modelIds.first,
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
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> fetchCam(String username) async {
    return {
      'cam': {
        'topic': 'Welcome to my room',
        'streamName': '12345',
        'isCamAvailable': true,
      },
      'user': {
        'user': {
          'id': 12345,
          'username': username,
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
  }

  @override
  Future<Map<String, dynamic>> fetchBroadcast(String username) async {
    return {
      'item': {
        'modelId': 12345,
        'username': username,
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
  }

  @override
  Future<Map<String, dynamic>> fetchMembers(String username) async {
    return {
      'guests': 200,
      'regulars': 300,
      'greens': 100,
      'golds': 50,
      'invisibles': 10,
      'spies': 5,
    };
  }

  @override
  Future<Map<String, dynamic>> fetchChatHistory(String modelId) async {
    return {};
  }

  @override
  Future<List<StripchatPlaybackVariant>> fetchPlaybackVariants(
    String url, {
    Map<String, String> headers = const <String, String>{},
  }) async {
    return [
      StripchatPlaybackVariant(
        qualityId: '720p',
        url: Uri.parse(url),
        bandwidth: 2000000,
      ),
    ];
  }

  @override
  Future<StripchatPlaybackProbeResult> probePlaybackPlaylist(
    String url, {
    Map<String, String> headers = const <String, String>{},
    String? preferredVariantId,
  }) async {
    return StripchatPlaybackProbeResult(
      isPlayable: true,
      finalUrl: Uri.parse(url),
      body: '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=2000000\n720p.m3u8',
    );
  }

  @override
  void close() {}
}
