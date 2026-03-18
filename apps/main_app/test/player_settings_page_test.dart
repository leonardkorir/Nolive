import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nolive_app/src/app/bootstrap/bootstrap.dart';
import 'package:nolive_app/src/features/settings/presentation/player_settings_page.dart';

void main() {
  testWidgets('player settings page exposes android playback controls', (
    tester,
  ) async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerSettingsPage(
          bootstrap: bootstrap,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('播放器设置'), findsWidgets);
    expect(find.text('直播间与小窗'), findsOneWidget);
    expect(find.byKey(const Key('player-force-https-switch')), findsOneWidget);
    expect(
      find.byKey(const Key('player-auto-fullscreen-switch')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('player-background-auto-pause-switch')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('player-pip-hide-danmaku-switch')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('player-scale-mode-contain')), findsOneWidget);

    await tester.tap(find.byKey(const Key('player-auto-fullscreen-switch')));
    await tester.pumpAndSettle();

    final preferences = await bootstrap.loadPlayerPreferences();
    expect(preferences.androidAutoFullscreenEnabled, isFalse);
    expect(preferences.androidBackgroundAutoPauseEnabled, isTrue);
    expect(preferences.androidPipHideDanmakuEnabled, isTrue);
  });
}
