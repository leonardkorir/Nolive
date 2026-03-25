import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_providers/live_providers.dart';
import 'package:live_storage/live_storage.dart';
import 'package:live_sync/live_sync.dart';
import 'package:nolive_app/src/features/settings/application/manage_layout_preferences_use_case.dart';
import 'package:nolive_app/src/features/settings/application/manage_provider_accounts_use_case.dart';
import 'package:nolive_app/src/features/settings/application/manage_snapshot_data_use_case.dart';

void main() {
  test('updating provider accounts invalidates cached live providers',
      () async {
    var created = 0;
    final registry = ProviderRegistry()
      ..register(
        ProviderRegistration(
          descriptor: DouyinProvider.kDescriptor,
          builder: () {
            created += 1;
            return DouyinProvider.preview();
          },
        ),
      );
    final settingsRepository = InMemorySettingsRepository();
    final useCase = UpdateProviderAccountSettingsUseCase(
      settingsRepository,
      providerRegistry: registry,
    );

    final first = registry.create(ProviderId.douyin);
    await useCase(
      const ProviderAccountSettings(
        bilibiliCookie: '',
        bilibiliUserId: 0,
        chaturbateCookie: '',
        douyinCookie: 'fresh-cookie',
        twitchCookie: '',
      ),
    );
    final second = registry.create(ProviderId.douyin);

    expect(created, 2);
    expect(identical(first, second), isFalse);
  });

  test('importing snapshot clears cached provider instances', () async {
    var created = 0;
    final registry = ProviderRegistry()
      ..register(
        ProviderRegistration(
          descriptor: DouyinProvider.kDescriptor,
          builder: () {
            created += 1;
            return DouyinProvider.preview();
          },
        ),
      );
    final settingsRepository = InMemorySettingsRepository();
    final historyRepository = InMemoryHistoryRepository();
    final followRepository = InMemoryFollowRepository();
    final tagRepository = InMemoryTagRepository();
    final snapshotService = RepositorySyncSnapshotService(
      settingsRepository: settingsRepository,
      historyRepository: historyRepository,
      followRepository: followRepository,
      tagRepository: tagRepository,
    );
    final themeMode = ValueNotifier<ThemeMode>(ThemeMode.system);
    final layoutPreferences = ValueNotifier(LayoutPreferences.defaults());
    final importUseCase = ImportSyncSnapshotJsonUseCase(
      snapshotService: snapshotService,
      settingsRepository: settingsRepository,
      followRepository: followRepository,
      tagRepository: tagRepository,
      themeModeNotifier: themeMode,
      layoutPreferencesNotifier: layoutPreferences,
      providerRegistry: registry,
    );

    final first = registry.create(ProviderId.douyin);
    await importUseCase(
      '{"settings":{"account_douyin_cookie":"new-cookie"},"blocked_keywords":[],"tags":[],"history":[],"follows":[]}',
    );
    final second = registry.create(ProviderId.douyin);

    expect(created, 2);
    expect(identical(first, second), isFalse);
  });
}
