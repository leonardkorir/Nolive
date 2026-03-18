import 'provider_capability.dart';
import 'provider_id.dart';
import 'provider_maturity.dart';
import 'provider_platform.dart';

class ProviderDescriptor {
  const ProviderDescriptor({
    required this.id,
    required this.displayName,
    required this.capabilities,
    required this.supportedPlatforms,
    this.roomIdPatterns = const [],
    this.maturity = ProviderMaturity.planned,
    this.enabled = true,
  });

  final ProviderId id;
  final String displayName;
  final Set<ProviderCapability> capabilities;
  final Set<ProviderPlatform> supportedPlatforms;
  final List<String> roomIdPatterns;
  final ProviderMaturity maturity;
  final bool enabled;

  bool supports(ProviderCapability capability) {
    return capabilities.contains(capability);
  }

  List<String> validate() {
    final issues = <String>[];

    if (displayName.trim().isEmpty) {
      issues.add('displayName must not be empty');
    }
    if (capabilities.isEmpty) {
      issues.add('capabilities must not be empty');
    }
    if (supportedPlatforms.isEmpty) {
      issues.add('supportedPlatforms must not be empty');
    }

    return issues;
  }
}
