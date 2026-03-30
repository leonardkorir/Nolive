import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:nolive_app/src/app/bootstrap/bootstrap.dart';
import 'package:nolive_app/src/app/home/presentation/home_page.dart';
import 'package:nolive_app/src/features/browse/presentation/browse_page.dart';
import 'package:nolive_app/src/features/category/presentation/provider_categories_page.dart';
import 'package:nolive_app/src/features/search/presentation/search_page.dart';

void main() {
  testWidgets('home page search button inherits the current provider',
      (tester) async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);

    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(bootstrap: bootstrap),
      ),
    );
    await tester.pumpAndSettle();

    final douyuTabLabel = find.text('斗鱼').first;
    await tester.ensureVisible(douyuTabLabel);
    await tester.tap(douyuTabLabel);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('home-appbar-search-button')));
    await tester.pumpAndSettle();

    expect(
      tester.widget<SearchPage>(find.byType(SearchPage)).initialProviderId,
      ProviderId.douyu,
    );
  });

  testWidgets('browse page search button inherits the current provider',
      (tester) async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);

    await tester.pumpWidget(
      MaterialApp(
        home: BrowsePage(bootstrap: bootstrap),
      ),
    );
    await tester.pumpAndSettle();

    final douyuTabLabel = find.text('斗鱼').first;
    await tester.ensureVisible(douyuTabLabel);
    await tester.tap(douyuTabLabel);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('browse-appbar-search-button')));
    await tester.pumpAndSettle();

    expect(
      tester.widget<SearchPage>(find.byType(SearchPage)).initialProviderId,
      ProviderId.douyu,
    );
  });

  testWidgets('provider category page search button inherits the page provider',
      (tester) async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);

    await tester.pumpWidget(
      MaterialApp(
        home: ProviderCategoriesPage(
          bootstrap: bootstrap,
          providerId: ProviderId.douyu,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('provider-category-search-button')));
    await tester.pumpAndSettle();

    expect(
      tester.widget<SearchPage>(find.byType(SearchPage)).initialProviderId,
      ProviderId.douyu,
    );
  });
}
