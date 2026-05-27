import 'package:live_core/live_core.dart';
import 'package:live_providers/live_providers.dart';

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
  }) async {
    final maxAttempts = providerId == ProviderId.bilibili && page == 1
        ? bilibiliMaxAttempts
        : 1;
    ProviderParseException? lastError;
    for (var attempt = 0; attempt < maxAttempts; attempt += 1) {
      if (attempt > 0) {
        registry.invalidate(providerId);
        await Future<void>.delayed(bilibiliRetryDelay);
      }
      final provider = registry.create(providerId);
      final recommendRooms = provider.requireContract<SupportsRecommendRooms>(
        ProviderCapability.recommendRooms,
      );
      try {
        final response = await recommendRooms.fetchRecommendRooms(page: page);
        if (response.items.isNotEmpty || attempt + 1 >= maxAttempts) {
          return response;
        }
      } on ProviderParseException catch (error) {
        lastError = error;
        if (attempt + 1 >= maxAttempts) {
          rethrow;
        }
      }
    }
    throw lastError ??
        ProviderParseException(
          providerId: providerId,
          message: '${providerId.value} recommend rooms failed unexpectedly.',
        );
  }
}
