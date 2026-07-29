import 'package:live_core/live_core.dart';
import 'package:live_providers/live_providers.dart';
import 'package:nolive_app/src/shared/application/provider_request_retry.dart';

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
  }) {
    return retryProviderRequestWithRebuild<List<LiveCategory>>(
      registry: registry,
      providerId: providerId,
      operation: 'categories',
      maxAttempts: providerId == ProviderId.bilibili ? bilibiliMaxAttempts : 1,
      retryDelay: bilibiliRetryDelay,
      action: (provider) => provider
          .requireContract<SupportsCategories>(ProviderCapability.categories)
          .fetchCategories(),
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
