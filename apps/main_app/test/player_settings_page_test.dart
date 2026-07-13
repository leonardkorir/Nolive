import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nolive_app/src/app/bootstrap/bootstrap.dart';
import 'package:nolive_app/src/features/settings/presentation/player_settings_page.dart';
import 'test_feature_dependencies.dart';

void main() {
  testWidgets('player settings page exposes android playback controls', (
    tester,
  ) async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerSettingsPage(
          dependencies: buildPlayerSettingsDependencies(bootstrap),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('播放器设置'), findsWidgets);
    expect(find.text('观看与播放'), findsOneWidget);
    expect(find.text('默认清晰度（Wi‑Fi）'), findsOneWidget);
    expect(
      find.byKey(const Key('player-prefer-highest-quality-switch')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('player-wifi-quality-highest')), findsOneWidget);
    expect(find.byKey(const Key('player-force-https-switch')), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('直播间与小窗'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('直播间与小窗'), findsOneWidget);
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

    await tester.scrollUntilVisible(
      find.byKey(const Key('player-mpv-custom-output-switch')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('player-mpv-custom-output-switch')));
    await tester.pump();
    final customSwitch = tester.widget<SwitchListTile>(
      find.byKey(const Key('player-mpv-custom-output-switch')),
    );
    expect(customSwitch.value, isTrue);
    await tester.pumpAndSettle();
    final saved = await bootstrap.loadPlayerPreferences();
    expect(saved.mpvCustomOutputEnabled, isTrue);

    await tester.scrollUntilVisible(
      find.byKey(const Key('player-auto-fullscreen-switch')),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('player-auto-fullscreen-switch')));
    await tester.pumpAndSettle();

    final preferences = await bootstrap.loadPlayerPreferences();
    expect(preferences.androidAutoFullscreenEnabled, isFalse);
    expect(preferences.androidBackgroundAutoPauseEnabled, isTrue);
    expect(preferences.androidPipHideDanmakuEnabled, isTrue);
  });
}
