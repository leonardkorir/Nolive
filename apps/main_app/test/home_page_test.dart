import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:nolive_app/src/app/bootstrap/bootstrap.dart';
import 'package:nolive_app/src/app/home/presentation/home_page.dart';
import 'package:nolive_app/src/shared/presentation/gestures/responsive_tab_swipe_switcher.dart';
import 'test_feature_dependencies.dart';

void main() {
  testWidgets('home page uses shared swipe switcher for provider tabs', (
    tester,
  ) async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);

    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(dependencies: buildHomeFeatureDependencies(bootstrap)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ResponsiveTabSwipeSwitcher), findsOneWidget);
    expect(
      tester.widget<TabBarView>(find.byType(TabBarView)).physics,
      isA<NeverScrollableScrollPhysics>(),
    );
  });

  testWidgets('home page short horizontal swipe switches provider tabs', (
    tester,
  ) async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);

    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(dependencies: buildHomeFeatureDependencies(bootstrap)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('home-provider-tab-douyu')), findsOneWidget);

    await tester.drag(
      find.byKey(const Key('home-provider-tab-swipe-switcher')),
      const Offset(-24, 0),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));

    final tabController = DefaultTabController.of(
      tester.element(find.byType(TabBarView)),
    );
    expect(tabController.index, 1);
  });

  testWidgets('home page auto loads more provider rooms without button',
      (tester) async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    bootstrap.providerRegistry.register(
      ProviderRegistration(
        descriptor: const ProviderDescriptor(
          id: ProviderId.twitch,
          displayName: 'Twitch',
          capabilities: {
            ProviderCapability.recommendRooms,
          },
          supportedPlatforms: {ProviderPlatform.android},
        ),
        builder: () => _PagedTwitchHomeProvider(),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(dependencies: buildHomeFeatureDependencies(bootstrap)),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('home-provider-tab-twitch')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('第一页'), findsOneWidget);
    expect(find.text('第二页'), findsOneWidget);
    expect(find.text('加载更多'), findsNothing);
    expect(find.text('已经到底了'), findsOneWidget);
  });

  testWidgets('home page keeps auto-prefetching sparse providers until full', (
    tester,
  ) async {
    _AutoPrefetchLimitedHomeProvider.requestedPages.clear();
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    bootstrap.providerRegistry.register(
      ProviderRegistration(
        descriptor: const ProviderDescriptor(
          id: ProviderId.youtube,
          displayName: 'YouTube',
          capabilities: {
            ProviderCapability.recommendRooms,
          },
          supportedPlatforms: {ProviderPlatform.android},
        ),
        builder: () => _AutoPrefetchLimitedHomeProvider(),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(dependencies: buildHomeFeatureDependencies(bootstrap)),
      ),
    );
    await tester.pumpAndSettle();

    final providerTab = find.byKey(const Key('home-provider-tab-youtube'));
    await tester.ensureVisible(providerTab);
    await tester.tap(providerTab);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(_AutoPrefetchLimitedHomeProvider.requestedPages, [1, 2, 3]);
    expect(find.text('第一页'), findsOneWidget);
    expect(find.text('第二页'), findsOneWidget);
  });
}

class _PagedTwitchHomeProvider extends LiveProvider
    implements SupportsRecommendRooms {
  static const ProviderDescriptor _descriptor = ProviderDescriptor(
    id: ProviderId.twitch,
    displayName: 'Twitch',
    capabilities: {
      ProviderCapability.recommendRooms,
    },
    supportedPlatforms: {ProviderPlatform.android},
  );

  @override
  ProviderDescriptor get descriptor => _descriptor;

  @override
  Future<PagedResponse<LiveRoom>> fetchRecommendRooms({int page = 1}) async {
    return switch (page) {
      1 => PagedResponse(
          items: const [
            LiveRoom(
              providerId: 'twitch',
              roomId: 'room-1',
              title: '第一页',
              streamerName: '主播一',
              coverUrl: 'https://example.com/cover-1.png',
              streamerAvatarUrl: 'https://example.com/avatar-1.png',
              viewerCount: 100,
              isLive: true,
            ),
          ],
          hasMore: true,
          page: 1,
        ),
      _ => PagedResponse(
          items: const [
            LiveRoom(
              providerId: 'twitch',
              roomId: 'room-2',
              title: '第二页',
              streamerName: '主播二',
              coverUrl: 'https://example.com/cover-2.png',
              streamerAvatarUrl: 'https://example.com/avatar-2.png',
              viewerCount: 90,
              isLive: true,
            ),
          ],
          hasMore: false,
          page: page,
        ),
    };
  }
}

class _AutoPrefetchLimitedHomeProvider extends LiveProvider
    implements SupportsRecommendRooms {
  static final List<int> requestedPages = <int>[];

  static const ProviderDescriptor _descriptor = ProviderDescriptor(
    id: ProviderId.youtube,
    displayName: 'YouTube',
    capabilities: {
      ProviderCapability.recommendRooms,
    },
    supportedPlatforms: {ProviderPlatform.android},
  );

  @override
  ProviderDescriptor get descriptor => _descriptor;

  @override
  Future<PagedResponse<LiveRoom>> fetchRecommendRooms({int page = 1}) async {
    requestedPages.add(page);
    return PagedResponse(
      items: [
        LiveRoom(
          providerId: 'youtube',
          roomId: 'room-$page',
          title: switch (page) {
            1 => '第一页',
            2 => '第二页',
            _ => '第三页',
          },
          streamerName: '主播$page',
          coverUrl: 'https://example.com/cover-$page.png',
          streamerAvatarUrl: 'https://example.com/avatar-$page.png',
          viewerCount: 100 - page,
          isLive: true,
        ),
      ],
      hasMore: page < 3,
      page: page,
    );
  }
}
