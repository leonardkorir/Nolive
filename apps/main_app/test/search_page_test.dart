import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:nolive_app/src/app/bootstrap/bootstrap.dart';
import 'package:nolive_app/src/features/search/presentation/search_page.dart';
import 'test_feature_dependencies.dart';

void main() {
  testWidgets('search page uses initial provider id to select the matching tab',
      (tester) async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    final expectedIndex = _sortedSearchProviders(bootstrap)
        .indexWhere((item) => item.id == ProviderId.douyu);

    expect(expectedIndex, greaterThan(0));

    await tester.pumpWidget(
      MaterialApp(
        home: SearchPage(
          dependencies: buildSearchFeatureDependencies(bootstrap),
          initialProviderId: ProviderId.douyu,
        ),
      ),
    );

    expect(
      tester
          .widget<DefaultTabController>(find.byType(DefaultTabController))
          .initialIndex,
      expectedIndex,
    );
  });

  testWidgets('search page falls back to the first searchable provider',
      (tester) async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);

    await tester.pumpWidget(
      MaterialApp(
        home: SearchPage(
          dependencies: buildSearchFeatureDependencies(bootstrap),
          initialProviderId: const ProviderId('missing-provider'),
        ),
      ),
    );

    expect(
      tester
          .widget<DefaultTabController>(find.byType(DefaultTabController))
          .initialIndex,
      0,
    );
  });

  testWidgets('clearing the search field resets tabs back to waiting state',
      (tester) async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);

    await tester.pumpWidget(
      MaterialApp(
        home: SearchPage(
          dependencies: buildSearchFeatureDependencies(bootstrap),
          initialProviderId: ProviderId.douyu,
        ),
      ),
    );

    expect(find.text('等待搜索'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'test');
    await tester.tap(find.byKey(const Key('search-submit-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('等待搜索'), findsNothing);

    await tester.tap(find.byTooltip('清空'));
    await tester.pump();

    expect(find.text('等待搜索'), findsOneWidget);
  });
}

List<ProviderDescriptor> _sortedSearchProviders(AppBootstrap bootstrap) {
  final preferences = bootstrap.layoutPreferences.value;
  return bootstrap
      .listAvailableProviders()
      .where((item) => item.supports(ProviderCapability.searchRooms))
      .toList(growable: false)
    ..sort((a, b) => preferences
        .providerSortIndex(a.id.value)
        .compareTo(preferences.providerSortIndex(b.id.value)));
}
