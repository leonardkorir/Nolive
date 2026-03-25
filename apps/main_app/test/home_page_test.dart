import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:nolive_app/src/app/bootstrap/bootstrap.dart';
import 'package:nolive_app/src/app/home/presentation/home_page.dart';

void main() {
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
        home: HomePage(bootstrap: bootstrap),
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
