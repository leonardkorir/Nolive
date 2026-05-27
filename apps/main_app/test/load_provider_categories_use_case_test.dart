import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_providers/live_providers.dart';
import 'package:nolive_app/src/features/category/application/load_provider_categories_use_case.dart';

void main() {
  test(
    'load provider categories retries bilibili with fresh provider instances',
    () async {
      var createdProviders = 0;
      final state = _RetryState();
      final registry = ProviderRegistry()
        ..register(
          ProviderRegistration(
            descriptor: _RetryBilibiliCategoriesProvider.descriptorValue,
            builder: () {
              createdProviders += 1;
              return _RetryBilibiliCategoriesProvider(state: state);
            },
          ),
        );
      final useCase = LoadProviderCategoriesUseCase(
        registry,
        bilibiliRetryDelay: Duration.zero,
        bilibiliMaxAttempts: 3,
      );

      final payload = await useCase(ProviderId.bilibili);

      expect(createdProviders, 2);
      expect(state.fetchAttempts, 2);
      expect(payload.descriptor.id, ProviderId.bilibili);
      expect(payload.categories, hasLength(1));
      expect(payload.categories.single.children.single.name, '网游');
    },
  );

  test(
    'load provider categories does not retry non-bilibili failures',
    () async {
      final provider = _FailingCategoriesProvider();
      final registry = ProviderRegistry()
        ..register(
          ProviderRegistration(
            descriptor: _FailingCategoriesProvider.descriptorValue,
            builder: () => provider,
          ),
        );
      final useCase = LoadProviderCategoriesUseCase(
        registry,
        bilibiliRetryDelay: Duration.zero,
      );

      await expectLater(
        () => useCase(ProviderId.douyu),
        throwsA(isA<ProviderParseException>()),
      );
      expect(provider.fetchCategoriesCalls, 1);
    },
  );
}

class _RetryBilibiliCategoriesProvider extends LiveProvider
    implements SupportsCategories {
  _RetryBilibiliCategoriesProvider({required this.state});

  static const descriptorValue = ProviderDescriptor(
    id: ProviderId.bilibili,
    displayName: '哔哩哔哩',
    capabilities: {ProviderCapability.categories},
    supportedPlatforms: {ProviderPlatform.android},
    maturity: ProviderMaturity.ready,
  );

  final _RetryState state;

  @override
  ProviderDescriptor get descriptor => descriptorValue;

  @override
  Future<List<LiveCategory>> fetchCategories() async {
    state.fetchAttempts += 1;
    if (state.fetchAttempts == 1) {
      throw ProviderParseException(
        providerId: ProviderId.bilibili,
        message: 'Bilibili request failed before response: categories',
      );
    }
    return const [
      LiveCategory(
        id: '1',
        name: '游戏',
        children: [LiveSubCategory(id: '11', parentId: '1', name: '网游')],
      ),
    ];
  }
}

class _RetryState {
  int fetchAttempts = 0;
}

class _FailingCategoriesProvider extends LiveProvider
    implements SupportsCategories {
  static const descriptorValue = ProviderDescriptor(
    id: ProviderId.douyu,
    displayName: '斗鱼',
    capabilities: {ProviderCapability.categories},
    supportedPlatforms: {ProviderPlatform.android},
    maturity: ProviderMaturity.ready,
  );

  int fetchCategoriesCalls = 0;

  @override
  ProviderDescriptor get descriptor => descriptorValue;

  @override
  Future<List<LiveCategory>> fetchCategories() async {
    fetchCategoriesCalls += 1;
    throw ProviderParseException(
      providerId: ProviderId.douyu,
      message: 'Douyu request failed before response: categories',
    );
  }
}
