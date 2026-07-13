import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_providers/live_providers.dart';
import 'package:live_storage/live_storage.dart';
import 'package:nolive_app/src/features/settings/application/manage_provider_accounts_use_case.dart';
import 'package:nolive_app/src/features/settings/application/sensitive_setting_keys.dart';
import 'package:nolive_app/src/shared/application/secure_credential_store.dart';

void main() {
  test(
    'updating provider account settings clears registry cache so next create is fresh',
    () async {
      final settingsRepository = InMemorySettingsRepository();
      final secureStore = InMemorySecureCredentialStore();
      final registry = ProviderRegistry()
        ..register(
          ProviderRegistration(
            descriptor: const ProviderDescriptor(
              id: ProviderId.bilibili,
              displayName: 'Bilibili',
              capabilities: {ProviderCapability.roomDetail},
              supportedPlatforms: {ProviderPlatform.android},
              maturity: ProviderMaturity.ready,
            ),
            builder: () => _CountingProvider(),
          ),
        );

      final first = registry.create(ProviderId.bilibili) as _CountingProvider;
      final second = registry.create(ProviderId.bilibili) as _CountingProvider;
      expect(identical(first, second), isTrue);
      expect(_CountingProvider.builds, 1);

      final revision = ValueNotifier<int>(0);
      await UpdateProviderAccountSettingsUseCase(
        settingsRepository,
        secureStore,
        providerRegistry: registry,
        providerCatalogRevision: revision,
      )(
        const ProviderAccountSettings(
          bilibiliCookie: 'SESSDATA=new-cookie',
          bilibiliUserId: 1,
          chaturbateCookie: '',
          douyinCookie: '',
          twitchCookie: '',
          youtubeCookie: '',
        ),
      );

      expect(revision.value, 1);
      expect(
        await secureStore.read(SensitiveSettingKeys.accountBilibiliCookie),
        'SESSDATA=new-cookie',
      );

      final third = registry.create(ProviderId.bilibili) as _CountingProvider;
      expect(identical(first, third), isFalse);
      expect(_CountingProvider.builds, 2);
      expect(first.disposed, isTrue);
    },
  );
}

class _CountingProvider extends LiveProvider {
  _CountingProvider() {
    builds += 1;
  }

  static int builds = 0;
  bool disposed = false;

  @override
  ProviderDescriptor get descriptor => const ProviderDescriptor(
    id: ProviderId.bilibili,
    displayName: 'Bilibili',
    capabilities: {ProviderCapability.roomDetail},
    supportedPlatforms: {ProviderPlatform.android},
    maturity: ProviderMaturity.ready,
  );

  @override
  void dispose() {
    disposed = true;
  }
}
