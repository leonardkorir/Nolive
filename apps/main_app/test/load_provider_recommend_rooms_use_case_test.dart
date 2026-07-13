import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_providers/live_providers.dart';
import 'package:nolive_app/src/features/home/application/load_provider_recommend_rooms_use_case.dart';

void main() {
  test(
    'load provider recommend rooms retries bilibili empty first page with fresh provider instances',
    () async {
      var createdProviders = 0;
      final state = _RetryRecommendState();
      final registry = ProviderRegistry()
        ..register(
          ProviderRegistration(
            descriptor: _RetryBilibiliRecommendProvider.descriptorValue,
            builder: () {
              createdProviders += 1;
              return _RetryBilibiliRecommendProvider(state: state);
            },
          ),
        );
      final useCase = LoadProviderRecommendRoomsUseCase(
        registry,
        bilibiliRetryDelay: Duration.zero,
        bilibiliMaxAttempts: 3,
      );

      final payload = await useCase(providerId: ProviderId.bilibili, page: 1);

      expect(createdProviders, 2);
      expect(state.fetchAttempts, 2);
      expect(payload.items, hasLength(1));
      expect(payload.items.single.roomId, 'room-1');
    },
  );

  test(
    'load provider recommend rooms does not retry non-bilibili empty pages',
    () async {
      final provider = _EmptyRecommendProvider();
      final registry = ProviderRegistry()
        ..register(
          ProviderRegistration(
            descriptor: _EmptyRecommendProvider.descriptorValue,
            builder: () => provider,
          ),
        );
      final useCase = LoadProviderRecommendRoomsUseCase(
        registry,
        bilibiliRetryDelay: Duration.zero,
      );

      final payload = await useCase(providerId: ProviderId.douyu, page: 1);

      expect(provider.fetchRecommendCalls, 1);
      expect(payload.items, isEmpty);
    },
  );
}

class _RetryRecommendState {
  int fetchAttempts = 0;
}

class _RetryBilibiliRecommendProvider extends LiveProvider
    implements SupportsRecommendRooms {
  _RetryBilibiliRecommendProvider({required this.state});

  static const descriptorValue = ProviderDescriptor(
    id: ProviderId.bilibili,
    displayName: '哔哩哔哩',
    capabilities: {ProviderCapability.recommendRooms},
    supportedPlatforms: {ProviderPlatform.android},
    maturity: ProviderMaturity.ready,
  );

  final _RetryRecommendState state;

  @override
  ProviderDescriptor get descriptor => descriptorValue;

  @override
  Future<PagedResponse<LiveRoom>> fetchRecommendRooms({int page = 1}) async {
    state.fetchAttempts += 1;
    if (state.fetchAttempts == 1) {
      return const PagedResponse(items: [], hasMore: false, page: 1);
    }
    return const PagedResponse(
      items: [
        LiveRoom(
          providerId: ProviderId.bilibili,
          roomId: 'room-1',
          title: '第一页',
          streamerName: '主播一',
          coverUrl: 'https://example.com/cover.png',
          streamerAvatarUrl: 'https://example.com/avatar.png',
          viewerCount: 100,
          isLive: true,
        ),
      ],
      hasMore: false,
      page: 1,
    );
  }
}

class _EmptyRecommendProvider extends LiveProvider
    implements SupportsRecommendRooms {
  static const descriptorValue = ProviderDescriptor(
    id: ProviderId.douyu,
    displayName: '斗鱼',
    capabilities: {ProviderCapability.recommendRooms},
    supportedPlatforms: {ProviderPlatform.android},
    maturity: ProviderMaturity.ready,
  );

  int fetchRecommendCalls = 0;

  @override
  ProviderDescriptor get descriptor => descriptorValue;

  @override
  Future<PagedResponse<LiveRoom>> fetchRecommendRooms({int page = 1}) async {
    fetchRecommendCalls += 1;
    return const PagedResponse(items: [], hasMore: false, page: 1);
  }
}
