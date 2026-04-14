import 'package:live_core/live_core.dart';
import 'package:live_providers/live_providers.dart';

class ListProviderDescriptorsUseCase {
  const ListProviderDescriptorsUseCase(this.providerRegistry);

  final ProviderRegistry providerRegistry;

  List<ProviderDescriptor> call() {
    return providerRegistry.descriptors.toList(growable: false);
  }
}

class FindProviderDescriptorByIdUseCase {
  const FindProviderDescriptorByIdUseCase(this.providerRegistry);

  final ProviderRegistry providerRegistry;

  ProviderDescriptor? call(String providerId) {
    return providerRegistry.findDescriptorById(providerId);
  }
}
