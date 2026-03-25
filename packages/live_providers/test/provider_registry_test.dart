import 'package:live_core/live_core.dart';
import 'package:live_providers/live_providers.dart';
import 'package:test/test.dart';

void main() {
  test('default catalog exposes migrated provider descriptors', () {
    final registry = ReferenceProviderCatalog.buildDefaultRegistry();
    final ids = registry.descriptors.map((item) => item.id.value).toSet();

    expect(
      ids,
      containsAll({
        'bilibili',
        'chaturbate',
        'douyu',
        'huya',
        'douyin',
        'twitch',
        'youtube',
      }),
    );
    expect(
        registry
            .findDescriptor(ProviderId.bilibili)
            ?.supports(ProviderCapability.playUrls),
        isTrue);
    expect(
      registry
          .findDescriptor(ProviderId.chaturbate)
          ?.supports(ProviderCapability.searchRooms),
      isTrue,
    );
    expect(
      registry
          .findDescriptor(ProviderId.chaturbate)
          ?.supports(ProviderCapability.categories),
      isTrue,
    );
    expect(
      registry
          .findDescriptor(ProviderId.chaturbate)
          ?.supports(ProviderCapability.danmaku),
      isTrue,
    );
    expect(
      registry
          .findDescriptor(ProviderId.youtube)
          ?.supports(ProviderCapability.categories),
      isTrue,
    );
    expect(
      registry
          .findDescriptor(ProviderId.youtube)
          ?.supports(ProviderCapability.recommendRooms),
      isTrue,
    );
    expect(
      registry
          .findDescriptor(ProviderId.twitch)
          ?.supports(ProviderCapability.categories),
      isTrue,
    );
    expect(
      registry
          .findDescriptor(ProviderId.twitch)
          ?.supports(ProviderCapability.recommendRooms),
      isTrue,
    );
    expect(
      registry
          .findDescriptor(ProviderId.youtube)
          ?.supports(ProviderCapability.danmaku),
      isTrue,
    );
    expect(registry.hasImplementation(ProviderId.bilibili), isTrue);
    expect(registry.hasImplementation(ProviderId.chaturbate), isTrue);
    expect(registry.hasImplementation(ProviderId.douyu), isTrue);
    expect(registry.hasImplementation(ProviderId.huya), isTrue);
    expect(registry.hasImplementation(ProviderId.douyin), isTrue);
    expect(registry.hasImplementation(ProviderId.twitch), isTrue);
    expect(registry.hasImplementation(ProviderId.youtube), isTrue);
  });

  test('registry creates chaturbate provider runtime', () {
    final registry = ReferenceProviderCatalog.buildDefaultRegistry();

    final provider = registry.create(ProviderId.chaturbate);

    expect(provider, isA<ChaturbateProvider>());
  });

  test('registry creates bilibili provider runtime', () {
    final registry = ReferenceProviderCatalog.buildDefaultRegistry();

    final provider = registry.create(ProviderId.bilibili);

    expect(provider, isA<BilibiliProvider>());
  });

  test('registry creates douyu provider runtime', () {
    final registry = ReferenceProviderCatalog.buildDefaultRegistry();

    final provider = registry.create(ProviderId.douyu);

    expect(provider, isA<DouyuProvider>());
  });

  test('registry creates huya provider runtime', () {
    final registry = ReferenceProviderCatalog.buildDefaultRegistry();

    final provider = registry.create(ProviderId.huya);

    expect(provider, isA<HuyaProvider>());
  });

  test('registry creates douyin provider runtime', () {
    final registry = ReferenceProviderCatalog.buildDefaultRegistry();

    final provider = registry.create(ProviderId.douyin);

    expect(provider, isA<DouyinProvider>());
  });

  test('registry creates twitch provider runtime', () {
    final registry = ReferenceProviderCatalog.buildDefaultRegistry();

    final provider = registry.create(ProviderId.twitch);

    expect(provider, isA<TwitchProvider>());
  });

  test('registry creates youtube provider runtime', () {
    final registry = ReferenceProviderCatalog.buildDefaultRegistry();

    final provider = registry.create(ProviderId.youtube);

    expect(provider, isA<YouTubeProvider>());
  });

  test('live registry creates chaturbate provider runtime', () {
    final registry = ReferenceProviderCatalog.buildLiveRegistry();

    final provider = registry.create(ProviderId.chaturbate);

    expect(provider, isA<ChaturbateProvider>());
  });

  test('registry reuses provider instance until invalidated', () {
    var created = 0;
    final registry = ProviderRegistry()
      ..register(
        ProviderRegistration(
          descriptor: BilibiliProvider.kDescriptor,
          builder: () {
            created += 1;
            return BilibiliProvider.preview();
          },
        ),
      );

    final first = registry.create(ProviderId.bilibili);
    final second = registry.create(ProviderId.bilibili);

    expect(identical(first, second), isTrue);
    expect(created, 1);

    registry.invalidate(ProviderId.bilibili);

    final third = registry.create(ProviderId.bilibili);
    expect(identical(first, third), isFalse);
    expect(created, 2);
  });
}
