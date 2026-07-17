import 'package:live_core/live_core.dart';
import 'package:live_providers/src/tooling/provider_smoke.dart';
import 'package:test/test.dart';

const _kSmokeDescriptor = ProviderDescriptor(
  id: ProviderId.bilibili,
  displayName: 'Smoke Fixture',
  capabilities: {
    ProviderCapability.recommendRooms,
    ProviderCapability.searchRooms,
    ProviderCapability.roomDetail,
    ProviderCapability.playQualities,
    ProviderCapability.playUrls,
  },
  supportedPlatforms: {ProviderPlatform.android},
  maturity: ProviderMaturity.ready,
);

void main() {
  test(
    'provider smoke succeeds when the full read-only chain resolves',
    () async {
      final result = await runProviderSmokeCase(
        ProviderSmokeCase(
          name: 'fixture',
          provider: _FakeSmokeProvider(
            rooms: [
              const LiveRoom(
                providerId: ProviderId.bilibili,
                roomId: '6',
                title: 'fixture room',
                streamerName: 'fixture streamer',
                isLive: true,
              ),
            ],
            detail: const LiveRoomDetail(
              providerId: ProviderId.bilibili,
              roomId: '6',
              title: 'fixture room',
              streamerName: 'fixture streamer',
              isLive: true,
            ),
            qualities: [
              LivePlayQuality(id: 'auto', label: 'Auto', isDefault: true),
            ],
            urls: const [LivePlayUrl(url: 'https://example.com/live.m3u8')],
          ),
          query: 'fixture',
        ),
      );

      expect(validateProviderSmokeResult(result), isNull);
      expect(result.urls.single.url, contains('live.m3u8'));
    },
  );

  test('provider smoke fails fast when search returns no rooms', () async {
    final provider = _FakeSmokeProvider(
      rooms: const [],
      detail: const LiveRoomDetail(
        providerId: ProviderId.bilibili,
        roomId: 'unused',
        title: 'unused',
        streamerName: 'unused',
      ),
      qualities: const [],
      urls: const [],
    );

    final result = await runProviderSmokeCase(
      ProviderSmokeCase(name: 'fixture', provider: provider, query: 'missing'),
    );

    expect(
      validateProviderSmokeResult(result),
      contains('search returned 0 rooms'),
    );
    expect(provider.fetchRoomDetailCalls, 0);
  });

  test(
    'provider smoke uses recommend rooms when query is empty',
    () async {
      final provider = _FakeSmokeProvider(
        rooms: [
          const LiveRoom(
            providerId: ProviderId.douyin,
            roomId: 'hot-1',
            title: 'hot room',
            streamerName: 'hot streamer',
            isLive: true,
          ),
        ],
        detail: const LiveRoomDetail(
          providerId: ProviderId.douyin,
          roomId: 'hot-1',
          title: 'hot room',
          streamerName: 'hot streamer',
          isLive: true,
        ),
        qualities: [
          LivePlayQuality(id: 'origin', label: '原画', isDefault: true),
        ],
        urls: const [LivePlayUrl(url: 'https://example.com/douyin.flv')],
      );

      final result = await runProviderSmokeCase(
        ProviderSmokeCase(name: 'douyin', provider: provider, query: ''),
      );

      expect(validateProviderSmokeResult(result), isNull);
      expect(provider.searchCalls, 0);
      expect(provider.fetchRecommendRoomsCalls, 1);
      expect(result.urls.single.url, contains('douyin.flv'));
    },
  );

  test('provider smoke fails when qualities are missing', () async {
    final result = await runProviderSmokeCase(
      ProviderSmokeCase(
        name: 'fixture',
        provider: _FakeSmokeProvider(
          rooms: [
            const LiveRoom(
              providerId: ProviderId.bilibili,
              roomId: '6',
              title: 'fixture room',
              streamerName: 'fixture streamer',
            ),
          ],
          detail: const LiveRoomDetail(
            providerId: ProviderId.bilibili,
            roomId: '6',
            title: 'fixture room',
            streamerName: 'fixture streamer',
          ),
          qualities: const [],
          urls: const [],
        ),
        query: 'fixture',
      ),
    );

    expect(
      validateProviderSmokeResult(result),
      contains('no playable qualities'),
    );
  });

  test('provider smoke fails when play urls are missing', () async {
    final result = await runProviderSmokeCase(
      ProviderSmokeCase(
        name: 'fixture',
        provider: _FakeSmokeProvider(
          rooms: [
            const LiveRoom(
              providerId: ProviderId.bilibili,
              roomId: '6',
              title: 'fixture room',
              streamerName: 'fixture streamer',
            ),
          ],
          detail: const LiveRoomDetail(
            providerId: ProviderId.bilibili,
            roomId: '6',
            title: 'fixture room',
            streamerName: 'fixture streamer',
          ),
          qualities: [
            LivePlayQuality(id: 'auto', label: 'Auto', isDefault: true),
          ],
          urls: const [],
        ),
        query: 'fixture',
      ),
    );

    expect(validateProviderSmokeResult(result), contains('no playable urls'));
  });

  test(
    'provider smoke falls back to recommend rooms on transient douyu kw error',
    () async {
      final provider = _FakeSmokeProvider(
        descriptor: const ProviderDescriptor(
          id: ProviderId.douyu,
          displayName: 'Smoke Fixture',
          capabilities: {
            ProviderCapability.recommendRooms,
            ProviderCapability.searchRooms,
            ProviderCapability.roomDetail,
            ProviderCapability.playQualities,
            ProviderCapability.playUrls,
          },
          supportedPlatforms: {ProviderPlatform.android},
          maturity: ProviderMaturity.ready,
        ),
        rooms: const [
          LiveRoom(
            providerId: ProviderId.douyu,
            roomId: '66',
            title: 'recommend room',
            streamerName: 'fixture streamer',
            isLive: true,
          ),
        ],
        detail: const LiveRoomDetail(
          providerId: ProviderId.douyu,
          roomId: '66',
          title: 'recommend room',
          streamerName: 'fixture streamer',
          isLive: true,
        ),
        qualities: [
          LivePlayQuality(id: 'auto', label: 'Auto', isDefault: true),
        ],
        urls: const [LivePlayUrl(url: 'https://example.com/live.m3u8')],
        searchErrors: [
          ProviderParseException(
            providerId: ProviderId.douyu,
            message: '【kw】kw不能为空',
          ),
          ProviderParseException(
            providerId: ProviderId.douyu,
            message: '【kw】kw不能为空',
          ),
        ],
      );

      final result = await runProviderSmokeCase(
        ProviderSmokeCase(name: 'fixture', provider: provider, query: '王者荣耀'),
      );

      expect(validateProviderSmokeResult(result), isNull);
      expect(provider.searchCalls, 2);
      expect(provider.fetchRecommendRoomsCalls, 1);
    },
  );

  test(
    'provider smoke classifies bilibili login-required failures as auth skips',
    () {
      final bilibiliCase = ProviderSmokeCase(
        name: 'bilibili',
        provider: _FakeSmokeProvider(
          rooms: const [],
          detail: const LiveRoomDetail(
            providerId: ProviderId.bilibili,
            roomId: 'unused',
            title: 'unused',
            streamerName: 'unused',
          ),
          qualities: const [],
          urls: const [],
        ),
        query: '聊天',
      );
      final douyuCase = ProviderSmokeCase(
        name: 'douyu',
        provider: _FakeSmokeProvider(
          descriptor: const ProviderDescriptor(
            id: ProviderId.douyu,
            displayName: 'Douyu Fixture',
            capabilities: {
              ProviderCapability.searchRooms,
              ProviderCapability.roomDetail,
              ProviderCapability.playQualities,
              ProviderCapability.playUrls,
            },
            supportedPlatforms: {ProviderPlatform.android},
            maturity: ProviderMaturity.ready,
          ),
          rooms: const [],
          detail: const LiveRoomDetail(
            providerId: ProviderId.douyu,
            roomId: 'unused',
            title: 'unused',
            streamerName: 'unused',
          ),
          qualities: const [],
          urls: const [],
        ),
        query: '王者荣耀',
      );
      final error = ProviderParseException(
        providerId: ProviderId.bilibili,
        message: 'Bilibili load WBI keys failed with code -101: 账号未登录',
      );

      expect(
        isKnownProviderSmokeAuthPreconditionFailure(bilibiliCase, error),
        isTrue,
      );
      expect(
        isKnownProviderSmokeAuthPreconditionFailure(douyuCase, error),
        isFalse,
      );
      expect(providerSmokeStrictAuthEnabled(const {}), isFalse);
      expect(
        providerSmokeStrictAuthEnabled(const {
          'NOLIVE_PROVIDER_SMOKE_STRICT_AUTH': '1',
        }),
        isTrue,
      );
      expect(
        providerSmokeStrictAuthEnabled(const {
          'NOLIVE_PROVIDER_SMOKE_STRICT_AUTH': 'true',
        }),
        isTrue,
      );
    },
  );
}

class _FakeSmokeProvider extends LiveProvider
    implements
        SupportsRecommendRooms,
        SupportsRoomSearch,
        SupportsRoomDetail,
        SupportsPlayQualities,
        SupportsPlayUrls {
  _FakeSmokeProvider({
    ProviderDescriptor? descriptor,
    required this.rooms,
    required this.detail,
    required this.qualities,
    required this.urls,
    this.searchErrors = const [],
  }) : _descriptor = descriptor ?? _kSmokeDescriptor;

  final ProviderDescriptor _descriptor;
  final List<LiveRoom> rooms;
  final LiveRoomDetail detail;
  final List<LivePlayQuality> qualities;
  final List<LivePlayUrl> urls;
  final List<ProviderParseException> searchErrors;

  int fetchRoomDetailCalls = 0;
  int fetchRecommendRoomsCalls = 0;
  int searchCalls = 0;

  @override
  ProviderDescriptor get descriptor => _descriptor;

  @override
  Future<PagedResponse<LiveRoom>> fetchRecommendRooms({int page = 1}) async {
    fetchRecommendRoomsCalls += 1;
    return PagedResponse(items: rooms, hasMore: false, page: page);
  }

  @override
  Future<LiveRoomDetail> fetchRoomDetail(String roomId) async {
    fetchRoomDetailCalls += 1;
    return detail;
  }

  @override
  Future<List<LivePlayQuality>> fetchPlayQualities(
    LiveRoomDetail detail,
  ) async {
    return qualities;
  }

  @override
  Future<List<LivePlayUrl>> fetchPlayUrls({
    required LiveRoomDetail detail,
    required LivePlayQuality quality,
  }) async {
    return urls;
  }

  @override
  Future<PagedResponse<LiveRoom>> searchRooms(
    String query, {
    int page = 1,
  }) async {
    searchCalls += 1;
    if (searchCalls <= searchErrors.length) {
      throw searchErrors[searchCalls - 1];
    }
    return PagedResponse(items: rooms, hasMore: false, page: page);
  }
}
