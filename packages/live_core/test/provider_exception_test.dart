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

  test('declared capability returns matching Supports contract', () {
    final provider = _FullContractProvider();

    expect(
      provider.requireContract<SupportsLogin>(ProviderCapability.login),
      same(provider),
    );
    expect(
      provider.requireContract<SupportsSuperChat>(ProviderCapability.superChat),
      same(provider),
    );
    expect(
      provider.requireContract<SupportsBackupSync>(
        ProviderCapability.backupSync,
      ),
      same(provider),
    );
  });

  test('declared optional capability without contract is rejected', () {
    final provider = _MisalignedCapabilityProvider();

    expect(
      () => provider.requireContract<SupportsLogin>(ProviderCapability.login),
      throwsA(isA<ProviderContractException>()),
    );
  });
}

class _FakeProvider extends LiveProvider implements SupportsRoomSearch {
  @override
  ProviderDescriptor get descriptor => const ProviderDescriptor(
    id: ProviderId('fake'),
    displayName: 'Fake',
    capabilities: {ProviderCapability.searchRooms},
    supportedPlatforms: {ProviderPlatform.linux},
  );

  @override
  Future<PagedResponse<LiveRoom>> searchRooms(String query, {int page = 1}) {
    return Future.value(const PagedResponse(items: [], hasMore: false));
  }
}

class _FullContractProvider extends LiveProvider
    implements SupportsLogin, SupportsSuperChat, SupportsBackupSync {
  @override
  ProviderDescriptor get descriptor => const ProviderDescriptor(
    id: ProviderId('full-contract'),
    displayName: 'Full Contract',
    capabilities: {
      ProviderCapability.login,
      ProviderCapability.superChat,
      ProviderCapability.backupSync,
    },
    supportedPlatforms: {ProviderPlatform.linux},
  );
}

class _MisalignedCapabilityProvider extends LiveProvider {
  @override
  ProviderDescriptor get descriptor => const ProviderDescriptor(
    id: ProviderId('misaligned'),
    displayName: 'Misaligned',
    capabilities: {ProviderCapability.login},
    supportedPlatforms: {ProviderPlatform.linux},
  );
}
