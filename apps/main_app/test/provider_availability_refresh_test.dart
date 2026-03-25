import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nolive_app/src/app/bootstrap/bootstrap.dart';
import 'package:nolive_app/src/features/browse/presentation/browse_page.dart';
import 'package:nolive_app/src/features/settings/application/manage_provider_accounts_use_case.dart';

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
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('browse-provider-tab-chaturbate')),
      findsOneWidget,
    );
  });
}
