import 'package:live_core/live_core.dart';

class ProviderRegistry {
  final Map<String, ProviderRegistration> _registrations = {};
  final Map<String, LiveProvider> _instances = {};

  Iterable<ProviderRegistration> get registrations => _registrations.values;

  Iterable<ProviderDescriptor> get descriptors {
    return _registrations.values.map((item) => item.descriptor);
  }

  void register(ProviderRegistration registration) {
    final providerId = registration.descriptor.id.value;
    _registrations[providerId] = registration;
    _instances.remove(providerId);
  }

  ProviderRegistration? findRegistration(ProviderId providerId) {
    return _registrations[providerId.value];
  }

  ProviderDescriptor? findDescriptor(ProviderId providerId) {
    return findRegistration(providerId)?.descriptor;
  }

  ProviderDescriptor? findDescriptorById(String providerId) {
    return _registrations[providerId]?.descriptor;
  }

  bool hasImplementation(ProviderId providerId) {
    return findRegistration(providerId)?.hasImplementation ?? false;
  }

  LiveProvider create(ProviderId providerId) {
    final cached = _instances[providerId.value];
    if (cached != null) {
      return cached;
    }
    final registration = findRegistration(providerId);
    if (registration == null) {
      throw ProviderNotImplementedException.migration(
        providerId: providerId,
        feature: 'provider registration',
      );
    }
    final provider = registration.create();
    _instances[providerId.value] = provider;
    return provider;
  }

  void invalidate(ProviderId providerId) {
    _instances.remove(providerId.value);
  }

  void clearCache() {
    _instances.clear();
  }
}
