import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:nolive_app/src/app/bootstrap/bootstrap.dart';
import 'package:nolive_app/src/features/browse/presentation/browse_page.dart';
import 'package:nolive_app/src/features/search/presentation/search_page.dart';
import 'package:nolive_app/src/shared/presentation/gestures/responsive_tab_swipe_switcher.dart';
import 'package:nolive_app/src/shared/presentation/widgets/persisted_network_image.dart';
import 'test_feature_dependencies.dart';

void main() {
  testWidgets('browse page uses shared swipe switcher for provider tabs', (
    tester,
  ) async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);

    await tester.pumpWidget(
      MaterialApp(
        home: BrowsePage(
          dependencies: buildBrowseFeatureDependencies(bootstrap),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ResponsiveTabSwipeSwitcher), findsOneWidget);
    expect(
      tester.widget<TabBarView>(find.byType(TabBarView)).physics,
      isA<NeverScrollableScrollPhysics>(),
    );
  });

  testWidgets('browse page sanitizes malformed utf16 category labels', (
    tester,
  ) async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    bootstrap.providerRegistry.register(
      ProviderRegistration(
        descriptor: _MalformedBrowseCategoryProvider.providerDescriptor,
        builder: () => _MalformedBrowseCategoryProvider(),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: BrowsePage(
          dependencies: buildBrowseFeatureDependencies(bootstrap),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final providerTab = find.byKey(const Key('browse-provider-tab-twitch'));
    await tester.ensureVisible(providerTab);
    await tester.tap(providerTab);
    await tester.pumpAndSettle();

    expect(find.text('热门'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('browse category artwork uses contain fit', (tester) async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    bootstrap.providerRegistry.register(
      ProviderRegistration(
        descriptor: _MalformedBrowseCategoryProvider.providerDescriptor,
        builder: () => _MalformedBrowseCategoryProvider(),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: BrowsePage(
          dependencies: buildBrowseFeatureDependencies(bootstrap),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final providerTab = find.byKey(const Key('browse-provider-tab-twitch'));
    await tester.ensureVisible(providerTab);
    await tester.tap(providerTab);
    await tester.pumpAndSettle();

    final imageFinder = find.descendant(
      of: find.byKey(const Key('browse-category-twitch-leaf')),
      matching: find.byType(PersistedNetworkImage),
    );

    expect(imageFinder, findsOneWidget);
    expect(
      tester.widget<PersistedNetworkImage>(imageFinder).fit,
      BoxFit.contain,
    );
  });

  testWidgets('browse category artwork uses a square visual slot', (
    tester,
  ) async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    bootstrap.providerRegistry.register(
      ProviderRegistration(
        descriptor: _MalformedBrowseCategoryProvider.providerDescriptor,
        builder: () => _MalformedBrowseCategoryProvider(),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: BrowsePage(
          dependencies: buildBrowseFeatureDependencies(bootstrap),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final providerTab = find.byKey(const Key('browse-provider-tab-twitch'));
    await tester.ensureVisible(providerTab);
    await tester.tap(providerTab);
    await tester.pumpAndSettle();

    final visualFinder = find.byKey(
      const Key('browse-category-visual-twitch-leaf'),
    );
    expect(visualFinder, findsOneWidget);

    final size = tester.getSize(visualFinder);
    expect(size.width, closeTo(size.height, 0.1));
  });

  testWidgets(
    'browse search action opens standalone search seeded with the selected provider',
    (tester) async {
      final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
      final expectedIndex = _sortedSearchProviders(
        bootstrap,
      ).indexWhere((item) => item.id == ProviderId.douyu);

      expect(expectedIndex, greaterThanOrEqualTo(0));

      await tester.pumpWidget(
        MaterialApp(
          home: BrowsePage(
            dependencies: buildBrowseFeatureDependencies(bootstrap),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final douyuTab = find.byKey(const Key('browse-provider-tab-douyu'));
      await tester.ensureVisible(douyuTab);
      await tester.tap(douyuTab, warnIfMissed: false);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('browse-appbar-search-button')));
      await tester.pumpAndSettle();

      expect(find.byType(SearchPage), findsOneWidget);
      expect(
        tester
            .widget<DefaultTabController>(
              find.descendant(
                of: find.byType(SearchPage),
                matching: find.byType(DefaultTabController),
              ),
            )
            .initialIndex,
        expectedIndex,
      );
    },
  );
}

List<ProviderDescriptor> _sortedSearchProviders(AppBootstrap bootstrap) {
  final preferences = bootstrap.layoutPreferences.value;
  return bootstrap
      .listAvailableProviders()
      .where((item) => item.supports(ProviderCapability.searchRooms))
      .toList(growable: false)
    ..sort(
      (a, b) => preferences
          .providerSortIndex(a.id.value)
          .compareTo(preferences.providerSortIndex(b.id.value)),
    );
}

class _MalformedBrowseCategoryProvider extends LiveProvider
    implements SupportsCategories {
  static const providerDescriptor = ProviderDescriptor(
    id: ProviderId.twitch,
    displayName: 'Twitch',
    capabilities: {ProviderCapability.categories},
    supportedPlatforms: {ProviderPlatform.android},
  );

  @override
  ProviderDescriptor get descriptor =>
      _MalformedBrowseCategoryProvider.providerDescriptor;

  @override
  Future<List<LiveCategory>> fetchCategories() async {
    final malformed = '热门${String.fromCharCode(0xD800)}';
    return [
      LiveCategory(
        id: 'group',
        name: '游戏${String.fromCharCode(0xD800)}',
        children: [
          LiveSubCategory(
            id: 'leaf',
            parentId: 'group',
            name: malformed,
            pic: 'https://example.com/category.png',
          ),
        ],
      ),
    ];
  }
}
