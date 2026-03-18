import 'package:live_core/live_core.dart';
import 'package:live_providers/live_providers.dart';
import 'package:test/test.dart';

void main() {
  test('default catalog exposes huya migrated runtime', () {
    final registry = ReferenceProviderCatalog.buildDefaultRegistry();

    expect(registry.hasImplementation(ProviderId.huya), isTrue);

    final provider = registry.create(ProviderId.huya);

    expect(provider, isA<HuyaProvider>());
    expect(provider.descriptor.validate(), isEmpty);
    expect(provider.supports(ProviderCapability.danmaku), isTrue);
    expect(
      provider.requireContract<SupportsRoomSearch>(
        ProviderCapability.searchRooms,
      ),
      isA<SupportsRoomSearch>(),
    );
    expect(
      provider.requireContract<SupportsRoomDetail>(
        ProviderCapability.roomDetail,
      ),
      isA<SupportsRoomDetail>(),
    );
    expect(
      provider.requireContract<SupportsPlayQualities>(
        ProviderCapability.playQualities,
      ),
      isA<SupportsPlayQualities>(),
    );
    expect(
      provider.requireContract<SupportsPlayUrls>(
        ProviderCapability.playUrls,
      ),
      isA<SupportsPlayUrls>(),
    );
  });
}
