import 'package:live_core/live_core.dart';
import 'package:live_providers/live_providers.dart';

class SearchProviderRoomsUseCase {
  const SearchProviderRoomsUseCase(this.registry);

  final ProviderRegistry registry;

  Future<PagedResponse<LiveRoom>> call({
    required ProviderId providerId,
    required String query,
    int page = 1,
  }) async {
    final provider = registry.create(providerId);
    final roomSearch = provider.requireContract<SupportsRoomSearch>(
      ProviderCapability.searchRooms,
    );
    return roomSearch.searchRooms(query, page: page);
  }
}
