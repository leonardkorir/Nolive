import 'package:live_core/live_core.dart';
import 'package:live_providers/live_providers.dart';

class LoadProviderCategoriesUseCase {
  const LoadProviderCategoriesUseCase(this.registry);

  final ProviderRegistry registry;

  Future<ProviderCategoriesPayload> call(ProviderId providerId) async {
    final provider = registry.create(providerId);
    final categories = provider
        .requireContract<SupportsCategories>(ProviderCapability.categories);
    final payload = await categories.fetchCategories();
    return ProviderCategoriesPayload(
      descriptor: provider.descriptor,
      categories: payload,
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
