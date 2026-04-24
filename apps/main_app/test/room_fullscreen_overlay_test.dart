import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nolive_app/src/features/room/presentation/widgets/room_fullscreen_overlay.dart';

void main() {
  void configureTestViewport(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

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

  testWidgets(
      'fullscreen overlay adapts compact chrome and sanitizes malformed labels',
      (tester) async {
    configureTestViewport(tester, const Size(640, 360));
    final badLabel =
        '游${String.fromCharCode(0xD800)}戏${String.fromCharCode(0xDC00)}厅';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RoomFullscreenOverlay(
            player: const SizedBox.expand(),
            followDrawer: const SizedBox.shrink(),
            showChrome: true,
            showLockButton: true,
            lockControls: false,
            gestureTipText: badLabel,
            pipSupported: true,
            supportsDesktopMiniWindow: true,
            desktopMiniWindowActive: false,
            supportsPlayerCapture: true,
            showDanmakuOverlay: true,
            title: badLabel,
            liveDuration: '00:10:00',
            qualityLabel: badLabel,
            lineLabel: badLabel,
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
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('游戏厅'), findsWidgets);
  });

  testWidgets('fullscreen overlay avoids overflow on ultra compact widths',
      (tester) async {
    configureTestViewport(tester, const Size(480, 320));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RoomFullscreenOverlay(
            player: const SizedBox.expand(),
            followDrawer: const SizedBox.shrink(),
            showChrome: true,
            showLockButton: true,
            lockControls: false,
            gestureTipText: null,
            pipSupported: true,
            supportsDesktopMiniWindow: true,
            desktopMiniWindowActive: false,
            supportsPlayerCapture: true,
            showDanmakuOverlay: true,
            title: 'A very long room title for compact fullscreen overlay',
            liveDuration: '00:10:00',
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
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(
        find.byKey(const Key('room-fullscreen-more-button')), findsOneWidget);
    expect(
      find.byKey(const Key('room-fullscreen-capture-button')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('room-fullscreen-desktop-mini-window-button')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('room-fullscreen-debug-button')),
      findsNothing,
    );
  });

  testWidgets('fullscreen overlay keeps chrome stable on compact landscape',
      (tester) async {
    configureTestViewport(tester, const Size(640, 280));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RoomFullscreenOverlay(
            player: const SizedBox.expand(),
            followDrawer: const SizedBox.shrink(),
            showChrome: true,
            showLockButton: true,
            lockControls: false,
            gestureTipText: null,
            pipSupported: true,
            supportsDesktopMiniWindow: true,
            desktopMiniWindowActive: false,
            supportsPlayerCapture: true,
            showDanmakuOverlay: true,
            title: 'A very long room title for compact fullscreen overlay',
            liveDuration: '00:10:00',
            qualityLabel: '超清蓝光线路',
            lineLabel: '超长线路标签',
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
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(
        find.byKey(const Key('room-fullscreen-more-button')), findsOneWidget);
    expect(find.byKey(const Key('room-fullscreen-quality-button')),
        findsOneWidget);
    expect(
      find.byKey(const Key('room-fullscreen-line-button')),
      findsOneWidget,
    );
  });

  testWidgets('fullscreen overlay avoids overflow on typical phone landscape',
      (tester) async {
    configureTestViewport(tester, const Size(844, 390));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RoomFullscreenOverlay(
            player: const SizedBox.expand(),
            followDrawer: const SizedBox.shrink(),
            showChrome: true,
            showLockButton: true,
            lockControls: false,
            gestureTipText: null,
            pipSupported: true,
            supportsDesktopMiniWindow: true,
            desktopMiniWindowActive: false,
            supportsPlayerCapture: true,
            showDanmakuOverlay: true,
            title:
                'A very long room title for a real device landscape viewport',
            liveDuration: '00:10:00',
            qualityLabel: '超清蓝光原画',
            lineLabel: '超长线路标签-主站回源',
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
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(
        find.byKey(const Key('room-fullscreen-more-button')), findsOneWidget);
    expect(
      find.byKey(const Key('room-fullscreen-quality-button')),
      findsOneWidget,
    );
  });

  testWidgets('fullscreen overlay avoids overflow on narrow phone fullscreen',
      (tester) async {
    configureTestViewport(tester, const Size(412, 220));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RoomFullscreenOverlay(
            player: const SizedBox.expand(),
            followDrawer: const SizedBox.shrink(),
            showChrome: true,
            showLockButton: true,
            lockControls: false,
            gestureTipText: null,
            pipSupported: true,
            supportsDesktopMiniWindow: true,
            desktopMiniWindowActive: false,
            supportsPlayerCapture: true,
            showDanmakuOverlay: true,
            title: 'A very long room title for a narrow device fullscreen',
            liveDuration: '12:34:56',
            qualityLabel: '1080p',
            lineLabel: '主线路-回源',
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
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const Key('room-fullscreen-exit-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('room-fullscreen-quality-button')),
      findsOneWidget,
    );
  });

  testWidgets(
      'fullscreen overlay avoids overflow on compact xperia landscape viewport',
      (tester) async {
    configureTestViewport(tester, const Size(384, 220));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RoomFullscreenOverlay(
            player: const SizedBox.expand(),
            followDrawer: const SizedBox.shrink(),
            showChrome: true,
            showLockButton: true,
            lockControls: false,
            gestureTipText: null,
            pipSupported: true,
            supportsDesktopMiniWindow: true,
            desktopMiniWindowActive: false,
            supportsPlayerCapture: true,
            showDanmakuOverlay: true,
            title: 'queen_kitty1818 live room title for compact landscape',
            liveDuration: '12:34:56',
            qualityLabel: '1080p 原画',
            lineLabel: '主线路-回源',
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
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const Key('room-fullscreen-exit-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('room-fullscreen-quality-button')),
      findsOneWidget,
    );
  });

  testWidgets('fullscreen overlay avoids overflow on wide phone landscape',
      (tester) async {
    configureTestViewport(tester, const Size(932, 412));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RoomFullscreenOverlay(
            player: const SizedBox.expand(),
            followDrawer: const SizedBox.shrink(),
            showChrome: true,
            showLockButton: true,
            lockControls: false,
            gestureTipText: null,
            pipSupported: true,
            supportsDesktopMiniWindow: true,
            desktopMiniWindowActive: false,
            supportsPlayerCapture: true,
            showDanmakuOverlay: true,
            title: 'Live room title',
            liveDuration: '12:34:56',
            qualityLabel: '1080p',
            lineLabel: '主线路',
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
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const Key('room-fullscreen-more-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('room-fullscreen-quality-button')),
      findsOneWidget,
    );
  });

  testWidgets('fullscreen overlay avoids overflow on xperia landscape width',
      (tester) async {
    configureTestViewport(tester, const Size(896, 411));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RoomFullscreenOverlay(
            player: const SizedBox.expand(),
            followDrawer: const SizedBox.shrink(),
            showChrome: true,
            showLockButton: true,
            lockControls: false,
            gestureTipText: null,
            pipSupported: true,
            supportsDesktopMiniWindow: true,
            desktopMiniWindowActive: false,
            supportsPlayerCapture: true,
            showDanmakuOverlay: true,
            title: 'Long fullscreen title for Xperia landscape viewport',
            liveDuration: '12:34:56',
            qualityLabel: '1080p 原画',
            lineLabel: '主线路-回源',
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
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(
        find.byKey(const Key('room-fullscreen-more-button')), findsOneWidget);
  });
}
