import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_providers/live_providers.dart';
import 'package:nolive_app/src/features/home/application/list_available_providers_use_case.dart';
import 'package:nolive_app/src/features/settings/application/manage_layout_preferences_use_case.dart';

void main() {
  test('catalog hides planned maturity and ranks ready above inMigration', () {
    final registry = ProviderRegistry()
      ..register(
        const ProviderRegistration(
          descriptor: ProviderDescriptor(
            id: ProviderId.bilibili,
            displayName: 'Bilibili',
            capabilities: {ProviderCapability.roomDetail},
            supportedPlatforms: {ProviderPlatform.android},
            maturity: ProviderMaturity.ready,
          ),
          builder: _NoopProvider.new,
        ),
      )
      ..register(
        const ProviderRegistration(
          descriptor: ProviderDescriptor(
            id: ProviderId.twitch,
            displayName: 'Twitch',
            capabilities: {ProviderCapability.roomDetail},
            supportedPlatforms: {ProviderPlatform.android},
            maturity: ProviderMaturity.inMigration,
          ),
          builder: _NoopProvider.new,
        ),
      )
      ..register(
        ProviderRegistration(
          descriptor: ProviderDescriptor(
            id: ProviderId.from('ghost'),
            displayName: 'Ghost',
            capabilities: const {ProviderCapability.roomDetail},
            supportedPlatforms: const {ProviderPlatform.android},
            maturity: ProviderMaturity.planned,
          ),
          builder: _NoopProvider.new,
        ),
      );

    final preferences = ValueNotifier(
      const LayoutPreferences(
        shellTabOrder: LayoutPreferences.defaultShellTabOrder,
        providerOrder: ['bilibili', 'twitch', 'ghost'],
        enabledProviderIds: ['bilibili', 'twitch', 'ghost'],
      ),
    );

    final listed = ListAvailableProvidersUseCase(registry, preferences)();
    expect(listed.map((item) => item.id), contains(ProviderId.bilibili));
    expect(listed.map((item) => item.id), contains(ProviderId.twitch));
    expect(listed.any((item) => item.id.value == 'ghost'), isFalse);
    expect(
      providerMaturityRank(ProviderMaturity.ready),
      greaterThan(providerMaturityRank(ProviderMaturity.inMigration)),
    );
  });
}

class _NoopProvider extends LiveProvider {
  @override
  ProviderDescriptor get descriptor => const ProviderDescriptor(
    id: ProviderId.bilibili,
    displayName: 'noop',
    capabilities: {ProviderCapability.roomDetail},
    supportedPlatforms: {ProviderPlatform.android},
  );
}
