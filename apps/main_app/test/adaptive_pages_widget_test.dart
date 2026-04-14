import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:nolive_app/src/app/bootstrap/bootstrap.dart';
import 'package:nolive_app/src/app/home/presentation/home_page.dart';
import 'package:nolive_app/src/features/browse/presentation/browse_page.dart';
import 'package:nolive_app/src/features/category/presentation/provider_categories_page.dart';
import 'package:nolive_app/src/features/search/presentation/search_page.dart';
import 'test_feature_dependencies.dart';

void main() {
  testWidgets('home and browse pages render at tablet breakpoints',
      (tester) async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);

    for (final size in _tabletBreakpoints) {
      await _pumpAtSize(
        tester,
        size,
        MaterialApp(
          home: HomePage(
            dependencies: buildHomeFeatureDependencies(bootstrap),
          ),
        ),
      );
      expect(
          find.byKey(const Key('home-appbar-search-button')), findsOneWidget);
      expect(tester.takeException(), isNull);

      await _pumpAtSize(
        tester,
        size,
        MaterialApp(
          home: BrowsePage(
            dependencies: buildBrowseFeatureDependencies(bootstrap),
          ),
        ),
      );
      expect(
        find.byKey(const Key('browse-appbar-search-button')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('search and category pages render at tablet breakpoints',
      (tester) async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);

    for (final size in _tabletBreakpoints) {
      await _pumpAtSize(
        tester,
        size,
        MaterialApp(
          home: SearchPage(
            dependencies: buildSearchFeatureDependencies(bootstrap),
            initialProviderId: ProviderId.douyu,
          ),
        ),
      );
      expect(find.byKey(const Key('search-submit-button')), findsOneWidget);
      expect(tester.takeException(), isNull);

      await _pumpAtSize(
        tester,
        size,
        MaterialApp(
          home: ProviderCategoriesPage(
            dependencies: buildCategoryFeatureDependencies(bootstrap),
            providerId: ProviderId.douyu,
          ),
        ),
      );
      expect(
        find.byKey(const Key('provider-category-search-button')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }
  });
}

const _tabletBreakpoints = <Size>[
  Size(600, 1024),
  Size(840, 1280),
  Size(1280, 800),
];

Future<void> _pumpAtSize(WidgetTester tester, Size size, Widget child) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(child);
  await tester.pumpAndSettle();
}
