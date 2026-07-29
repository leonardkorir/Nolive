import 'package:live_core/live_core.dart';
import 'package:live_providers/live_providers.dart';
import 'package:nolive_app/src/shared/application/provider_request_retry.dart';

class LoadProviderRecommendRoomsUseCase {
  const LoadProviderRecommendRoomsUseCase(
    this.registry, {
    this.bilibiliRetryDelay = const Duration(milliseconds: 350),
    this.bilibiliMaxAttempts = 3,
  });

  final ProviderRegistry registry;
  final Duration bilibiliRetryDelay;
  final int bilibiliMaxAttempts;

  Future<PagedResponse<LiveRoom>> call({
    required ProviderId providerId,
    int page = 1,
  }) {
    return retryProviderRequestWithRebuild<PagedResponse<LiveRoom>>(
      registry: registry,
      providerId: providerId,
      operation: 'recommend rooms',
      maxAttempts: providerId == ProviderId.bilibili && page == 1
          ? bilibiliMaxAttempts
          : 1,
      retryDelay: bilibiliRetryDelay,
      shouldRetryResult: (response) => response.items.isEmpty,
      action: (provider) => provider
          .requireContract<SupportsRecommendRooms>(
            ProviderCapability.recommendRooms,
          )
          .fetchRecommendRooms(page: page),
    );
  }
}
