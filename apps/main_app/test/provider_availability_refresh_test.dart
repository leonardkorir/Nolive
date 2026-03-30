import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nolive_app/src/app/bootstrap/bootstrap.dart';
import 'package:nolive_app/src/features/browse/presentation/browse_page.dart';
import 'package:nolive_app/src/features/settings/application/manage_provider_accounts_use_case.dart';
import 'package:nolive_app/src/shared/presentation/adaptive/app_adaptive_layout.dart';

void main() {
  testWidgets('browse page shows twitch and youtube native category tabs',
      (tester) async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);

    await tester.pumpWidget(
      MaterialApp(
        home: BrowsePage(bootstrap: bootstrap),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('browse-provider-tab-twitch')), findsOneWidget);
    expect(
        find.byKey(const Key('browse-provider-tab-youtube')), findsOneWidget);

    await tester.tap(find.byKey(const Key('browse-provider-tab-twitch')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('browse-category-twitch-just_chatting')),
      findsOneWidget,
    );
    expect(
        find.byKey(const Key('browse-discover-room-twitch-xqc')), findsNothing);

    await tester.tap(find.byKey(const Key('browse-provider-tab-youtube')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('browse-category-youtube-gaming')),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const Key('browse-discover-room-youtube-@ChinaStreetObserver/live'),
      ),
      findsNothing,
    );
  });

  testWidgets('browse page updates chaturbate availability after account save',
      (tester) async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);

    await tester.pumpWidget(
      MaterialApp(
        home: BrowsePage(bootstrap: bootstrap),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('browse-provider-tab-chaturbate')),
      findsNothing,
    );

    await bootstrap.updateProviderAccountSettings(
      const ProviderAccountSettings(
        bilibiliCookie: '',
        bilibiliUserId: 0,
        chaturbateCookie: 'csrftoken=demo; __cf_bm=demo-bm',
        douyinCookie: '',
        twitchCookie: '',
        youtubeCookie: '',
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('browse-provider-tab-chaturbate')),
      findsOneWidget,
    );
  });

  testWidgets('browse category tile keeps visual area within adaptive cap',
      (tester) async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    const size = Size(390, 844);

    await _pumpAtSize(
      tester,
      size,
      MaterialApp(
        home: BrowsePage(bootstrap: bootstrap),
      ),
    );

    final youtubeTab = find.byKey(const Key('browse-provider-tab-youtube'));
    await tester.ensureVisible(youtubeTab);
    await tester.tap(youtubeTab);
    await tester.pumpAndSettle();

    final tile = find.byKey(const Key('browse-category-youtube-gaming'));
    final visual =
        find.byKey(const Key('browse-category-visual-youtube-gaming'));

    expect(tile, findsOneWidget);
    expect(visual, findsOneWidget);

    final spec = AppAdaptiveLayoutSpec.fromSize(size);
    final tileSize = tester.getSize(tile);
    final visualSize = tester.getSize(visual);

    expect(visualSize.width, greaterThan(tileSize.width * 0.8));
    expect(visualSize.height, lessThanOrEqualTo(spec.categoryTileVisualExtent));
    expect(visualSize.height, greaterThan(spec.categoryTileVisualExtent * 0.7));
  });
}

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
