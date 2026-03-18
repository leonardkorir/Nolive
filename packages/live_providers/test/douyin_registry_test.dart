import 'package:live_core/live_core.dart';
import 'package:live_providers/live_providers.dart';
import 'package:test/test.dart';

void main() {
  test('default catalog exposes douyin provider builder', () {
    final registry = ReferenceProviderCatalog.buildDefaultRegistry();

    expect(registry.hasImplementation(ProviderId.douyin), isTrue);
    expect(
      registry
          .findDescriptor(ProviderId.douyin)
          ?.supports(ProviderCapability.login),
      isFalse,
    );

    final provider = registry.create(ProviderId.douyin);
    expect(provider, isA<DouyinProvider>());
  });
}
