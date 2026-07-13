import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:nolive_app/src/app/bootstrap/bootstrap.dart';
import 'package:nolive_app/src/features/search/presentation/search_page.dart';
import 'test_feature_dependencies.dart';

void main() {
  testWidgets(
    'search page uses initial provider id to select the matching tab',
    (tester) async {
      final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
      final expectedIndex = _sortedSearchProviders(
        bootstrap,
      ).indexWhere((item) => item.id == ProviderId.douyu);

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
    },
  );

  testWidgets('search page falls back to the first searchable provider', (
    tester,
  ) async {
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

  testWidgets('clearing the search field resets tabs back to waiting state', (
    tester,
  ) async {
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

  testWidgets('search page retries failures and dedupes load-more results', (
    tester,
  ) async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    final provider = _ScriptedSearchProvider();
    bootstrap.providerRegistry.register(
      ProviderRegistration(
        descriptor: _ScriptedSearchProvider.providerDescriptor,
        builder: () => provider,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SearchPage(
          dependencies: buildSearchFeatureDependencies(bootstrap),
          initialProviderId: ProviderId.twitch,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '主播');
    await tester.tap(find.byKey(const Key('search-submit-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('搜索失败'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '重试'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      find.byKey(const Key('search-room-card-twitch-room-1')),
      findsOneWidget,
    );
    expect(find.widgetWithText(FilledButton, '加载更多'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '加载更多'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      find.byKey(const Key('search-room-card-twitch-room-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('search-room-card-twitch-room-2')),
      findsOneWidget,
    );
    expect(find.widgetWithText(FilledButton, '加载更多'), findsNothing);
    expect(find.text('已经到底了'), findsOneWidget);
    expect(provider.searchCallCount, 3);
  });

  testWidgets('new searches reset stale load-more progress', (tester) async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    final provider = _BlockingSearchProvider();
    bootstrap.providerRegistry.register(
      ProviderRegistration(
        descriptor: _BlockingSearchProvider.providerDescriptor,
        builder: () => provider,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SearchPage(
          dependencies: buildSearchFeatureDependencies(bootstrap),
          initialProviderId: ProviderId.twitch,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'alpha');
    await tester.tap(find.byKey(const Key('search-submit-button')));
    await tester.pump();

    provider.completeRequest(
      query: 'alpha',
      page: 1,
      response: const PagedResponse<LiveRoom>(
        items: [
          LiveRoom(
            providerId: ProviderId.twitch,
            roomId: 'alpha-1',
            title: 'Alpha 房间',
            streamerName: 'Alpha',
          ),
        ],
        hasMore: true,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, '加载更多'));
    await tester.pump();
    expect(provider.hasPendingRequest(query: 'alpha', page: 2), isTrue);

    await tester.enterText(find.byType(TextField).first, 'beta');
    await tester.tap(find.byKey(const Key('search-submit-button')));
    await tester.pump();

    provider.completeRequest(
      query: 'beta',
      page: 1,
      response: const PagedResponse<LiveRoom>(
        items: [
          LiveRoom(
            providerId: ProviderId.twitch,
            roomId: 'beta-1',
            title: 'Beta 房间',
            streamerName: 'Beta',
          ),
        ],
        hasMore: true,
      ),
    );
    await tester.pumpAndSettle();

    provider.completeRequest(
      query: 'alpha',
      page: 2,
      response: const PagedResponse<LiveRoom>(
        items: [
          LiveRoom(
            providerId: ProviderId.twitch,
            roomId: 'alpha-2',
            title: 'Stale Alpha 房间',
            streamerName: 'Alpha',
          ),
        ],
        hasMore: false,
        page: 2,
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('search-room-card-twitch-beta-1')),
      findsOneWidget,
    );
    expect(find.widgetWithText(FilledButton, '加载更多'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '加载更多'));
    await tester.pump();

    expect(provider.hasPendingRequest(query: 'beta', page: 2), isTrue);
  });
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

class _ScriptedSearchProvider extends LiveProvider
    implements SupportsRoomSearch {
  static const providerDescriptor = ProviderDescriptor(
    id: ProviderId.twitch,
    displayName: 'Twitch',
    capabilities: {ProviderCapability.searchRooms},
    supportedPlatforms: {ProviderPlatform.android},
    maturity: ProviderMaturity.ready,
  );

  int searchCallCount = 0;

  @override
  ProviderDescriptor get descriptor => providerDescriptor;

  @override
  Future<PagedResponse<LiveRoom>> searchRooms(
    String query, {
    int page = 1,
  }) async {
    searchCallCount += 1;
    if (searchCallCount == 1) {
      throw StateError('search offline');
    }
    if (page == 1) {
      return const PagedResponse<LiveRoom>(
        items: [
          LiveRoom(
            providerId: ProviderId.twitch,
            roomId: 'room-1',
            title: 'Alpha 房间',
            streamerName: 'Alpha',
          ),
        ],
        hasMore: true,
      );
    }
    return const PagedResponse<LiveRoom>(
      items: [
        LiveRoom(
          providerId: ProviderId.twitch,
          roomId: 'room-1',
          title: 'Alpha 房间',
          streamerName: 'Alpha',
        ),
        LiveRoom(
          providerId: ProviderId.twitch,
          roomId: 'room-2',
          title: 'Beta 房间',
          streamerName: 'Beta',
        ),
      ],
      hasMore: false,
      page: 2,
    );
  }
}

class _BlockingSearchProvider extends LiveProvider
    implements SupportsRoomSearch {
  static const providerDescriptor = ProviderDescriptor(
    id: ProviderId.twitch,
    displayName: 'Twitch',
    capabilities: {ProviderCapability.searchRooms},
    supportedPlatforms: {ProviderPlatform.android},
    maturity: ProviderMaturity.ready,
  );

  final List<_PendingSearchRequest> _requests = [];

  @override
  ProviderDescriptor get descriptor => providerDescriptor;

  @override
  Future<PagedResponse<LiveRoom>> searchRooms(String query, {int page = 1}) {
    final request = _PendingSearchRequest(query: query, page: page);
    _requests.add(request);
    return request.completer.future;
  }

  bool hasPendingRequest({required String query, required int page}) {
    return _requests.any(
      (request) =>
          request.query == query &&
          request.page == page &&
          !request.completer.isCompleted,
    );
  }

  void completeRequest({
    required String query,
    required int page,
    required PagedResponse<LiveRoom> response,
  }) {
    final request = _requests.singleWhere(
      (item) =>
          item.query == query &&
          item.page == page &&
          !item.completer.isCompleted,
    );
    request.completer.complete(response);
  }
}

class _PendingSearchRequest {
  _PendingSearchRequest({required this.query, required this.page});

  final String query;
  final int page;
  final Completer<PagedResponse<LiveRoom>> completer =
      Completer<PagedResponse<LiveRoom>>();
}
