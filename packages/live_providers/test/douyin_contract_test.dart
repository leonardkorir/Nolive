import 'package:live_core/live_core.dart';
import 'package:live_providers/live_providers.dart';
import 'package:test/test.dart';

void main() {
  test('douyin registration stays aligned with declared capabilities', () {
    final registry = ReferenceProviderCatalog.buildDefaultRegistry();
    final provider = registry.create(ProviderId.douyin);
    final descriptor = provider.descriptor;

    expect(descriptor.validate(), isEmpty);
    expect(
        provider.requireContract<SupportsRecommendRooms>(
            ProviderCapability.recommendRooms),
        isA<SupportsRecommendRooms>());
    expect(
        provider.requireContract<SupportsRoomSearch>(
            ProviderCapability.searchRooms),
        isA<SupportsRoomSearch>());
    expect(
        provider
            .requireContract<SupportsRoomDetail>(ProviderCapability.roomDetail),
        isA<SupportsRoomDetail>());
    expect(
        provider.requireContract<SupportsPlayQualities>(
            ProviderCapability.playQualities),
        isA<SupportsPlayQualities>());
    expect(
        provider.requireContract<SupportsPlayUrls>(ProviderCapability.playUrls),
        isA<SupportsPlayUrls>());
  });
}
