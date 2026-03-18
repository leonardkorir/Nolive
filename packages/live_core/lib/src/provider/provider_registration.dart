import '../error/nolive_exception.dart';
import 'live_provider.dart';
import 'provider_descriptor.dart';

typedef LiveProviderBuilder = LiveProvider Function();

class ProviderRegistration {
  const ProviderRegistration({required this.descriptor, this.builder});

  final ProviderDescriptor descriptor;
  final LiveProviderBuilder? builder;

  bool get hasImplementation => builder != null;

  LiveProvider create() {
    final instanceBuilder = builder;
    if (instanceBuilder == null) {
      throw ProviderNotImplementedException.migration(
        providerId: descriptor.id,
        feature: 'provider runtime implementation',
      );
    }
    return instanceBuilder();
  }
}
