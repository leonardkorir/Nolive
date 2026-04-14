import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nolive_app/src/features/room/presentation/widgets/room_fullscreen_overlay.dart';

void main() {
  testWidgets('locked fullscreen keeps only lock button visible', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RoomFullscreenOverlay(
            player: const SizedBox.expand(),
            followDrawer: const SizedBox.shrink(),
            showChrome: false,
            showLockButton: true,
            lockControls: true,
            gestureTipText: null,
            pipSupported: true,
            supportsDesktopMiniWindow: false,
            desktopMiniWindowActive: false,
            supportsPlayerCapture: true,
            showDanmakuOverlay: true,
            title: 'title',
            liveDuration: '01:00',
            qualityLabel: '原画',
            lineLabel: '线路1',
            onToggleChrome: () {},
            onOpenFollowDrawer: () {},
            onToggleFullscreen: () {},
            onVerticalDragStart: (_) {},
            onVerticalDragUpdate: (_) {},
            onVerticalDragEnd: (_) {},
            onExitFullscreen: () {},
            onEnterPictureInPicture: () {},
            onToggleDesktopMiniWindow: () {},
            onCapture: () {},
            onShowDebug: () {},
            onShowMore: () {},
            onToggleFullscreenLock: () {},
            onRefresh: () {},
            onToggleDanmakuOverlay: () {},
            onOpenDanmakuSettings: () {},
            onShowQuality: () {},
            onShowLine: () {},
          ),
        ),
      ),
    );

    expect(
        find.byKey(const Key('room-fullscreen-lock-button')), findsOneWidget);
    expect(find.byKey(const Key('room-exit-fullscreen-button')), findsNothing);
    expect(
        find.byKey(const Key('room-fullscreen-refresh-button')), findsNothing);
  });

  testWidgets('locked fullscreen can hide lock button independently', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RoomFullscreenOverlay(
            player: const SizedBox.expand(),
            followDrawer: const SizedBox.shrink(),
            showChrome: false,
            showLockButton: false,
            lockControls: true,
            gestureTipText: null,
            pipSupported: true,
            supportsDesktopMiniWindow: false,
            desktopMiniWindowActive: false,
            supportsPlayerCapture: true,
            showDanmakuOverlay: true,
            title: 'title',
            liveDuration: '01:00',
            qualityLabel: '原画',
            lineLabel: '线路1',
            onToggleChrome: () {},
            onOpenFollowDrawer: () {},
            onToggleFullscreen: () {},
            onVerticalDragStart: (_) {},
            onVerticalDragUpdate: (_) {},
            onVerticalDragEnd: (_) {},
            onExitFullscreen: () {},
            onEnterPictureInPicture: () {},
            onToggleDesktopMiniWindow: () {},
            onCapture: () {},
            onShowDebug: () {},
            onShowMore: () {},
            onToggleFullscreenLock: () {},
            onRefresh: () {},
            onToggleDanmakuOverlay: () {},
            onOpenDanmakuSettings: () {},
            onShowQuality: () {},
            onShowLine: () {},
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('room-fullscreen-lock-button')), findsNothing);
  });
}
