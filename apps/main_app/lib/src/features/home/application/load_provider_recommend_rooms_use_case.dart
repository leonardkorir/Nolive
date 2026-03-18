import 'package:live_core/live_core.dart';
import 'package:live_providers/live_providers.dart';

class LoadProviderRecommendRoomsUseCase {
  const LoadProviderRecommendRoomsUseCase(this.registry);

  final ProviderRegistry registry;

  Future<PagedResponse<LiveRoom>> call({
    required ProviderId providerId,
    int page = 1,
  }) async {
    final provider = registry.create(providerId);
    final recommendRooms = provider.requireContract<SupportsRecommendRooms>(
      ProviderCapability.recommendRooms,
    );
    return recommendRooms.fetchRecommendRooms(page: page);
  }
}
