import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_providers/live_providers.dart';
import 'package:nolive_app/src/app/bootstrap/bootstrap.dart';
import 'package:nolive_app/src/features/home/application/list_available_providers_use_case.dart';
import 'package:nolive_app/src/features/settings/application/manage_layout_preferences_use_case.dart';

void main() {
  test('layout preferences update drops legacy search tab entries', () async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);

    await bootstrap.updateLayoutPreferences(
      const LayoutPreferences(
        shellTabOrder: [
          ShellTabId.search,
          ShellTabId.home,
          ShellTabId.browse,
          ShellTabId.library,
          ShellTabId.profile,
        ],
        providerOrder: ['douyin', 'chaturbate', 'bilibili', 'douyu', 'huya'],
        enabledProviderIds: ['douyin', 'huya'],
      ),
    );

    final reloaded = await bootstrap.loadLayoutPreferences();
    expect(reloaded.shellTabOrder, isNot(contains(ShellTabId.search)));
    expect(reloaded.shellTabOrder.first, ShellTabId.home);
    expect(reloaded.providerOrder.first, 'douyin');
    expect(reloaded.providerOrder, contains('chaturbate'));
    expect(reloaded.enabledProviderIds, ['douyin', 'huya']);

    final orderedProviders = bootstrap
        .listAvailableProviders()
        .map((item) => item.id.value)
        .toList();
    expect(orderedProviders.first, 'douyin');
    expect(orderedProviders, contains('huya'));
    expect(orderedProviders, isNot(contains('bilibili')));
    expect(
      bootstrap.layoutPreferences.value.shellTabOrder,
      isNot(contains(ShellTabId.search)),
    );
  });

  test('layout preferences defaults keep providers enabled by default', () {
    expect(LayoutPreferences.defaultProviderOrder, contains('chaturbate'));
    expect(LayoutPreferences.defaultProviderOrder, contains('stripchat'));
    expect(LayoutPreferences.defaultEnabledProviderIds, contains('youtube'));
    expect(LayoutPreferences.defaultEnabledProviderIds, contains('stripchat'));
    expect(
      LoadLayoutPreferencesUseCase.normalizeProviderOrder(const [
        'douyu',
        'bilibili',
      ]),
      contains('chaturbate'),
    );
    expect(
      LoadLayoutPreferencesUseCase.normalizeEnabledProviderIds(null),
      contains('chaturbate'),
    );
  });

  test(
    'legacy default enabled providers are migrated to include stripchat',
    () {
      final migrated = LoadLayoutPreferencesUseCase.normalizeEnabledProviderIds(
        const [
          'bilibili',
          'chaturbate',
          'douyu',
          'huya',
          'douyin',
          'twitch',
          'youtube',
        ],
      );

      expect(migrated, contains('stripchat'));
    },
  );

  test(
    'custom enabled providers stay unchanged when stripchat is disabled',
    () {
      final normalized =
          LoadLayoutPreferencesUseCase.normalizeEnabledProviderIds(const [
            'douyin',
            'huya',
          ]);

      expect(normalized, ['douyin', 'huya']);
    },
  );

  test('live provider list shows chaturbate without browser cookie', () {
    final useCase = ListAvailableProvidersUseCase(
      ReferenceProviderCatalog.buildLiveRegistry(stringSetting: (key) => ''),
      ValueNotifier(LayoutPreferences.defaults()),
    );

    final providers = useCase();
    expect(providers.map((item) => item.id.value), contains('chaturbate'));
  });

  test('live provider list respects provider enable switches', () {
    final useCase = ListAvailableProvidersUseCase(
      ReferenceProviderCatalog.buildLiveRegistry(
        stringSetting: (key) => 'csrftoken=demo; __cf_bm=demo',
      ),
      ValueNotifier(
        LayoutPreferences.defaults().copyWith(
          enabledProviderIds: const ['chaturbate'],
        ),
      ),
    );

    final providers = useCase().map((item) => item.id.value).toList();
    expect(providers, ['chaturbate']);
  });
}
