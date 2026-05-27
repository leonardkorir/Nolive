import 'package:live_core/live_core.dart';
import 'package:live_providers/live_providers.dart';

class LoadProviderCategoriesUseCase {
  const LoadProviderCategoriesUseCase(
    this.registry, {
    this.bilibiliRetryDelay = const Duration(milliseconds: 350),
    this.bilibiliMaxAttempts = 3,
  });

  final ProviderRegistry registry;
  final Duration bilibiliRetryDelay;
  final int bilibiliMaxAttempts;

  Future<ProviderCategoriesPayload> call(ProviderId providerId) async {
    final provider = registry.create(providerId);
    final payload = await _fetchCategoriesWithRetry(providerId: providerId);
    return ProviderCategoriesPayload(
      descriptor: provider.descriptor,
      categories: payload,
    );
  }

  Future<List<LiveCategory>> _fetchCategoriesWithRetry({
    required ProviderId providerId,
  }) async {
    final maxAttempts = providerId == ProviderId.bilibili
        ? bilibiliMaxAttempts
        : 1;
    ProviderParseException? lastError;
    for (var attempt = 0; attempt < maxAttempts; attempt += 1) {
      if (attempt > 0) {
        registry.invalidate(providerId);
        await Future<void>.delayed(bilibiliRetryDelay);
      }
      final provider = registry.create(providerId);
      final categories = provider.requireContract<SupportsCategories>(
        ProviderCapability.categories,
      );
      try {
        return await categories.fetchCategories();
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
          message: '${providerId.value} categories failed unexpectedly.',
        );
  }
}

class ProviderCategoriesPayload {
  const ProviderCategoriesPayload({
    required this.descriptor,
    required this.categories,
  });

  final ProviderDescriptor descriptor;
  final List<LiveCategory> categories;
}
