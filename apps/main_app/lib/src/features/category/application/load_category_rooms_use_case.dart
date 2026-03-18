import 'package:live_core/live_core.dart';
import 'package:live_providers/live_providers.dart';

class LoadCategoryRoomsUseCase {
  const LoadCategoryRoomsUseCase(this.registry);

  final ProviderRegistry registry;

  Future<PagedResponse<LiveRoom>> call({
    required ProviderId providerId,
    required LiveSubCategory category,
    int page = 1,
  }) async {
    final provider = registry.create(providerId);
    final rooms = provider.requireContract<SupportsCategoryRooms>(
      ProviderCapability.categories,
    );
    return rooms.fetchCategoryRooms(category, page: page);
  }
}
