import 'package:live_core/live_core.dart';
import 'package:test/test.dart';

void main() {
  test('LiveProvider.requireCapability throws typed exception', () {
    final provider = _FakeProvider();

    expect(
      () => provider.requireCapability(ProviderCapability.playUrls),
      throwsA(isA<ProviderCapabilityException>()),
    );
  });

  test('LiveProvider.requireContract throws contract exception', () {
    final provider = _FakeProvider();

    expect(
      () => provider.requireContract<SupportsRoomDetail>(
        ProviderCapability.searchRooms,
      ),
      throwsA(isA<ProviderContractException>()),
    );
  });
}

class _FakeProvider extends LiveProvider implements SupportsRoomSearch {
  @override
  ProviderDescriptor get descriptor => const ProviderDescriptor(
        id: ProviderId('fake'),
        displayName: 'Fake',
        capabilities: {
          ProviderCapability.searchRooms,
        },
        supportedPlatforms: {
          ProviderPlatform.linux,
        },
      );

  @override
  Future<PagedResponse<LiveRoom>> searchRooms(String query, {int page = 1}) {
    return Future.value(const PagedResponse(items: [], hasMore: false));
  }
}
