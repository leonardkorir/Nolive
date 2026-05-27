import 'package:live_core/live_core.dart';
import 'package:live_providers/src/providers/stripchat/stripchat_api_client.dart';
import 'package:live_providers/src/providers/stripchat/stripchat_data_source.dart';
import 'package:live_providers/src/providers/stripchat/stripchat_live_data_source.dart';
import 'package:test/test.dart';

import 'support/stripchat_fixture_loader.dart';

class _MockStripchatApiClient implements StripchatApiClient {
  _MockStripchatApiClient({
    this.probeFinalUrl,
    this.broadcastDelay = Duration.zero,
    this.playbackVariants = const <StripchatPlaybackVariant>[],
  });

  final String? probeFinalUrl;
  final Duration broadcastDelay;
  final List<StripchatPlaybackVariant> playbackVariants;

  @override
  String get cookie => 'stripchat_com_guestId=1; __cf_bm=test';

  @override
  Future<Map<String, dynamic>> fetchInitialDynamic() async {
    return {
      'userHash': 'mock-hash-123',
      'csrfToken': 'mock-csrf-456',
      'guestId': -999,
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
  Future<Map<String, dynamic>> fetchRecommendModels({
    int limit = 24,
    int offset = 0,
    String? guestHash,
  }) async {
    return {
      'blocks': [
        {
          'models': [
            {
              'id': 100001,
              'username': 'alice_mock',
              'status': 'public',
              'isLive': true,
              'streamName': '100001',
              'viewersCount': 500,
              'snapshotTimestamp': 1777920990,
              'previewUrlThumbSmall': 'https://img.test/alice.jpg',
              'country': 'China',
            },
          ],
        },
      ],
      'totalCount': 10,
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
          'username': 'tag_user',
          'status': 'public',
          'isLive': true,
          'streamName': '200001',
          'viewersCount': 300,
        },
      ],
      'totalCount': 1,
      'filteredCount': 1,
    };
  }

  @override
  Future<Map<String, dynamic>> fetchLiveTags() async {
    return {
      'liveTagDetails': {
        'tagLanguageChinese': {},
        'tagLanguageUSModels': {},
      },
      'liveTagGroups': [
        {
          'alias': 'ethnicity',
          'tags': [
            {'tag': 'ethnicityAsian'},
          ],
        },
      ],
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
              'username': 'search_result',
              'id': 500,
              'status': 'public',
              'isLive': true,
              'streamName': '500001',
            },
          ],
        },
        'topic': {'models': []},
        'tipMenu': {'models': []},
        'activity': {'models': []},
        'interest': {'models': []},
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
          'username': 'numeric_resolved',
          'id': modelIds.first,
          'status': 'public',
          'isLive': true,
          'streamName': modelIds.first.toString(),
        },
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> fetchCam(String username) async {
    return {
      'cam': {
        'topic': 'Cam Topic',
        'streamName': '99999',
        'isCamAvailable': true,
      },
      'user': {
        'user': {
          'id': 99999,
          'username': username,
          'status': 'public',
          'isLive': true,
          'snapshotTimestamp': 1777920990,
          'previewUrl': 'https://img.test/preview.jpg',
          'avatarUrl': 'https://img.test/avatar.jpg',
          'description': 'Description text',
          'country': 'China',
        },
      },
    };
  }

  @override
  Future<Map<String, dynamic>> fetchBroadcast(String username) async {
    if (broadcastDelay > Duration.zero) {
      await Future<void>.delayed(broadcastDelay);
    }
    return {
      'item': {
        'modelId': 99999,
        'username': username,
        'streamName': '99999',
        'status': 'public',
        'isLive': true,
        'settings': {
          'presets': ['720p', '480p'],
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
    return {
      'messages': [],
    };
  }

  @override
  Future<StripchatPlaybackProbeResult> probePlaybackPlaylist(
    String url, {
    Map<String, String> headers = const <String, String>{},
    String? preferredVariantId,
  }) async {
    return StripchatPlaybackProbeResult(
      isPlayable: true,
      finalUrl: Uri.parse(probeFinalUrl ?? url),
      body: '#EXTM3U',
    );
  }

  @override
  Future<List<StripchatPlaybackVariant>> fetchPlaybackVariants(
    String url, {
    Map<String, String> headers = const <String, String>{},
  }) async {
    return playbackVariants;
  }

  @override
  void close() {}
}

void main() {
  late StripchatDataSource dataSource;

  setUp(() {
    dataSource = StripchatLiveDataSource(
      apiClient: _MockStripchatApiClient(),
    );
  });

  test('fetchCategories returns mapped categories', () async {
    final categories = await dataSource.fetchCategories();
    expect(categories, isNotEmpty);
    expect(categories.first.id, 'country-asia_pacific');
  });

  test('fetchRecommendRooms returns paged rooms', () async {
    final response = await dataSource.fetchRecommendRooms();
    expect(response.items, isNotEmpty);
    expect(response.items.first.roomId, 'alice_mock');
    expect(
      response.items.first.keyframeUrl,
      'https://img.doppiocdn.net/snapshot/100001/1777920990',
    );
    expect(response.page, 1);
  });

  test('fetchRecommendRooms respects pagination', () async {
    final response = await dataSource.fetchRecommendRooms(page: 2);
    expect(response.page, 2);
  });

  test('fetchCategoryRooms returns paged rooms with filter', () async {
    final response = await dataSource.fetchCategoryRooms(
      const LiveSubCategory(
          id: 'tagLanguageChinese', parentId: 'country', name: '中文'),
    );
    expect(response.items, isNotEmpty);
    expect(response.items.first.roomId, 'tag_user');
  });

  test('searchRooms returns flattened and deduped results', () async {
    final response = await dataSource.searchRooms('test');
    expect(response.items, isNotEmpty);
    expect(response.items.first.roomId, 'search_result');
  });

  test('fetchRoomDetail works with username', () async {
    final detail = await dataSource.fetchRoomDetail('test_user');
    expect(detail.roomId, 'test_user');
    expect(detail.title, 'Cam Topic');
    expect(
      detail.keyframeUrl,
      'https://img.doppiocdn.net/snapshot/99999/1777920990',
    );
    expect(detail.danmakuToken, isA<StripchatDanmakuToken>());
    expect(detail.metadata?['streamName'], '99999');
    expect(detail.metadata?['presets'], ['720p', '480p']);
  });

  test('fetchRoomDetail works with numeric modelId', () async {
    final detail = await dataSource.fetchRoomDetail('88888');
    expect(detail.roomId, '88888');
    expect(detail.streamerName, 'numeric_resolved');
    expect(detail.danmakuToken, isA<StripchatDanmakuToken>());
  });

  test('fetchPlayUrls keeps master playlist url for auto quality',
      () async {
    final playbackDataSource = StripchatLiveDataSource(
      apiClient: _MockStripchatApiClient(
        probeFinalUrl:
            'https://media-hls.doppiocdn.net/b-hls-12/99999/99999_1080p60.m3u8?minHeight=240&playlistType=lowLatency&psch=v2&pkey=abc123',
      ),
    );
    final detail = await playbackDataSource.fetchRoomDetail('test_user');
    final urls = await playbackDataSource.fetchPlayUrls(
      detail: detail,
      quality: LivePlayQuality(
        id: 'auto',
        label: 'Auto',
        isDefault: true,
      ),
    );

    expect(urls, hasLength(1));
    expect(urls.first.url, contains('/master/99999_auto.m3u8'));
    expect(
      urls.first.metadata?['masterPlaylistUrl'],
      contains('/master/99999_auto.m3u8'),
    );
    expect(
      urls.first.metadata?['resolvedPlaylistUrl'],
      contains('99999_1080p60.m3u8'),
    );
    expect(urls.first.metadata?['masterPlaylistContent'], '#EXTM3U');
  });

  test('fetchPlayQualities returns auto and presets', () async {
    final detail = await dataSource.fetchRoomDetail('test_user');
    final qualities = await dataSource.fetchPlayQualities(detail);
    expect(qualities.any((q) => q.id == 'auto'), isTrue);
    expect(qualities.any((q) => q.id == '720p'), isTrue);
  });

  test('fetchPlayQualities adds source even when presets already exist',
      () async {
    final sourceAwareDataSource = StripchatLiveDataSource(
      apiClient: _MockStripchatApiClient(
        playbackVariants: <StripchatPlaybackVariant>[
          StripchatPlaybackVariant(
            qualityId: 'source',
            url: Uri.parse(
              'https://media-hls.doppiocdn.net/b-hls-09/99999/99999.m3u8',
            ),
            bandwidth: 1500000,
          ),
        ],
      ),
    );
    final detail = await sourceAwareDataSource.fetchRoomDetail('test_user');

    final qualities = await sourceAwareDataSource.fetchPlayQualities(detail);

    expect(
      qualities.map((quality) => quality.id),
      ['auto', 'source', '720p', '480p'],
    );
  });

  test('fetchPlayQualities derives fixed qualities from master variants',
      () async {
    final fallbackDataSource = StripchatLiveDataSource(
      apiClient: _MockStripchatApiClient(
        broadcastDelay: const Duration(milliseconds: 120),
        playbackVariants: <StripchatPlaybackVariant>[
          StripchatPlaybackVariant(
            qualityId: 'source',
            url: Uri.parse(
              'https://media-hls.doppiocdn.net/b-hls-09/99999/99999.m3u8',
            ),
            bandwidth: 1200000,
          ),
          StripchatPlaybackVariant(
            qualityId: '480p',
            url: Uri.parse(
              'https://media-hls.doppiocdn.net/b-hls-09/99999/99999_480p.m3u8',
            ),
            bandwidth: 800000,
          ),
          StripchatPlaybackVariant(
            qualityId: '240p',
            url: Uri.parse(
              'https://media-hls.doppiocdn.net/b-hls-09/99999/99999_240p.m3u8',
            ),
            bandwidth: 400000,
          ),
        ],
      ),
      broadcastFetchTimeout: const Duration(milliseconds: 20),
    );
    final detail = await fallbackDataSource.fetchRoomDetail('test_user');

    final qualities = await fallbackDataSource.fetchPlayQualities(detail);

    expect(
      qualities.map((quality) => quality.id),
      ['auto', 'source', '480p', '240p'],
    );
  });

  test('fetchPlayUrls returns HLS URL', () async {
    final detail = await dataSource.fetchRoomDetail('test_user');
    final quality = LivePlayQuality(id: 'auto', label: 'Auto');
    final urls = await dataSource.fetchPlayUrls(
      detail: detail,
      quality: quality,
    );
    expect(urls, isNotEmpty);
    expect(urls.first.url, contains('/99999_auto.m3u8'));
  });

  test('fetchRoomDetail does not block on slow broadcast endpoint', () async {
    final stopwatch = Stopwatch()..start();
    final timeoutDataSource = StripchatLiveDataSource(
      apiClient: _MockStripchatApiClient(
        broadcastDelay: const Duration(milliseconds: 120),
      ),
      broadcastFetchTimeout: const Duration(milliseconds: 20),
    );

    final detail = await timeoutDataSource.fetchRoomDetail('test_user');
    stopwatch.stop();

    expect(detail.roomId, 'test_user');
    expect(detail.metadata?['streamName'], '99999');
    expect(detail.metadata?['presets'], isNull);
    expect(stopwatch.elapsedMilliseconds, lessThan(100));
  });

  group('fixture-backed stripchat mapper', () {
    final skipReason = StripchatFixtureLoader.skipReason;
    final skip = skipReason != null;

    test('initial-dynamic fixture parses guestHash and CDN config', () {
      final initialDynamic = StripchatFixtureLoader.loadInitialDynamic();
      if (initialDynamic == null) {
        if (skip) return;
        fail('initial-dynamic fixture should be available');
      }
      expect(initialDynamic['userHash']?.toString(), isNotEmpty);
      final players = initialDynamic['players'] as Map<String, dynamic>?;
      expect(players, isNotNull);
      final cdnConfig = players!['cdnConfig'] as List?;
      expect(cdnConfig, isNotEmpty);
    }, skip: skip ? skipReason : false);

    test('recommend response maps to rooms with expected fields', () {
      final response = StripchatFixtureLoader.loadRecommendResponse();
      if (response == null) {
        if (skip) return;
        fail('recommend fixture should be available');
      }
      final blocks = response['blocks'] as List?;
      expect(blocks, isNotEmpty);
      final firstBlock = (blocks!.first as Map<String, dynamic>);
      final models = firstBlock['models'] as List?;
      expect(models, isNotEmpty);
      final model = models!.first as Map<String, dynamic>;
      expect(model['username']?.toString(), isNotEmpty);
      expect(model['status']?.toString(), isNotEmpty);
    }, skip: skip ? skipReason : false);

    test('search response groups contain models', () {
      final response = StripchatFixtureLoader.loadSearchResponse();
      if (response == null) {
        if (skip) return;
        fail('search fixture should be available');
      }
      final groups = response['groups'] as Map<String, dynamic>?;
      expect(groups, isNotNull);
      expect(groups!.containsKey('username'), isTrue);
    }, skip: skip ? skipReason : false);

    test('cam response contains expected fields', () {
      final response = StripchatFixtureLoader.loadCamResponse('Lucky-baby');
      if (response == null) {
        if (skip) return;
        fail('cam fixture for Lucky-baby should be available');
      }
      final cam = response['cam'] as Map<String, dynamic>?;
      final user = response['user'] as Map<String, dynamic>?;
      expect(cam, isNotNull);
      expect(user, isNotNull);
      expect(cam!['streamName']?.toString(), isNotEmpty);
      expect(cam['topic']?.toString(), isNotEmpty);
    }, skip: skip ? skipReason : false);

    test('broadcast response contains presets', () {
      final response =
          StripchatFixtureLoader.loadBroadcastResponse('Lucky-baby');
      if (response == null) {
        if (skip) return;
        fail('broadcast fixture for Lucky-baby should be available');
      }
      final item = response['item'] as Map<String, dynamic>?;
      expect(item, isNotNull);
      final settings = item!['settings'] as Map<String, dynamic>?;
      expect(settings, isNotNull);
      final presets = settings!['presets'] as List?;
      expect(presets, isNotEmpty);
    }, skip: skip ? skipReason : false);
  });
}
