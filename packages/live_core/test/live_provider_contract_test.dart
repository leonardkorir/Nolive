import 'package:live_core/live_core.dart';
import 'package:test/test.dart';

class MockSearchProvider extends LiveProvider implements SupportsRoomSearch {
  @override
  ProviderDescriptor get descriptor => const ProviderDescriptor(
        id: ProviderId('mock'),
        displayName: 'Mock Search Provider',
        capabilities: {
          ProviderCapability.searchRooms,
        },
        supportedPlatforms: {
          ProviderPlatform.android,
        },
      );

  @override
  Future<PagedResponse<LiveRoom>> searchRooms(String query, {int page = 1}) async {
    return const PagedResponse(items: [], hasMore: false);
  }
}

class BrokenMockProvider extends LiveProvider {
  @override
  ProviderDescriptor get descriptor => const ProviderDescriptor(
        id: ProviderId('broken'),
        displayName: 'Broken Provider',
        capabilities: {
          ProviderCapability.searchRooms,
        },
        supportedPlatforms: {
          ProviderPlatform.android,
        },
      );
}

void main() {
  group('LiveProvider Contract and Capability checks', () {
    test('supports reports correct capability status', () {
      final provider = MockSearchProvider();
      expect(provider.supports(ProviderCapability.searchRooms), isTrue);
      expect(provider.supports(ProviderCapability.danmaku), isFalse);
    });

    test('requireCapability throws ProviderCapabilityException if capability is unsupported', () {
      final provider = MockSearchProvider();
      expect(
        () => provider.requireCapability(ProviderCapability.danmaku),
        throwsA(isA<ProviderCapabilityException>()),
      );
      expect(
        () => provider.requireCapability(ProviderCapability.searchRooms),
        returnsNormally,
      );
    });

    test('requireContract returns cast provider if capability and class interface match', () {
      final provider = MockSearchProvider();
      expect(
        provider.requireContract<SupportsRoomSearch>(ProviderCapability.searchRooms),
        same(provider),
      );
    });

    test('requireContract throws ProviderContractException if capability is supported but interface is not implemented', () {
      final provider = BrokenMockProvider();
      expect(
        () => provider.requireContract<SupportsRoomSearch>(ProviderCapability.searchRooms),
        throwsA(isA<ProviderContractException>()),
      );
    });
  });
}
