import 'package:live_core/live_core.dart';
import 'package:live_providers/live_providers.dart';
import 'package:test/test.dart';

void main() {
  test('twitch registration stays aligned with declared capabilities', () {
    final registry = ReferenceProviderCatalog.buildDefaultRegistry();
    final provider = registry.create(ProviderId.twitch);
    final descriptor = provider.descriptor;

    expect(descriptor.validate(), isEmpty);
    expect(
      descriptor.capabilities,
      equals({
        ProviderCapability.categories,
        ProviderCapability.recommendRooms,
        ProviderCapability.searchRooms,
        ProviderCapability.roomDetail,
        ProviderCapability.playQualities,
        ProviderCapability.playUrls,
        ProviderCapability.danmaku,
      }),
    );
    expect(
      provider.requireContract<SupportsCategories>(
        ProviderCapability.categories,
      ),
      isA<SupportsCategories>(),
    );
    expect(
      provider.requireContract<SupportsCategoryRooms>(
        ProviderCapability.categories,
      ),
      isA<SupportsCategoryRooms>(),
    );
    expect(
      provider.requireContract<SupportsRecommendRooms>(
        ProviderCapability.recommendRooms,
      ),
      isA<SupportsRecommendRooms>(),
    );
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
    expect(
      provider.requireContract<SupportsDanmaku>(
        ProviderCapability.danmaku,
      ),
      isA<SupportsDanmaku>(),
    );
  });
}
