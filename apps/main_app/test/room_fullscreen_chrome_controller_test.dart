import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nolive_app/src/features/room/presentation/room_fullscreen_chrome_controller.dart';
import 'package:nolive_app/src/features/room/presentation/room_gesture_ui_state.dart';
import 'package:nolive_app/src/features/room/presentation/room_view_ui_state.dart';

import 'room_fullscreen_test_fakes.dart';

void main() {
  testWidgets('fullscreen chrome auto hides after delay', (tester) async {
    final harness = _ChromeHarness();
    addTearDown(harness.dispose);
    harness.viewUiState = const RoomViewUiState(
      isFullscreen: true,
      showFullscreenChrome: true,
    );

    harness.controller.scheduleFullscreenChromeAutoHide();
    await tester.pump(const Duration(seconds: 2));

    expect(harness.viewUiState.showFullscreenChrome, isFalse);
  });

  testWidgets('inline chrome auto hides after delay', (tester) async {
    final harness = _ChromeHarness();
    addTearDown(harness.dispose);
    harness.viewUiState = const RoomViewUiState(
      showInlinePlayerChrome: true,
    );

    harness.controller.scheduleInlineChromeAutoHide();
    await tester.pump(const Duration(seconds: 2));

    expect(harness.viewUiState.showInlinePlayerChrome, isFalse);
  });

  testWidgets('follow drawer open keeps fullscreen chrome visible state stable',
      (tester) async {
    final harness = _ChromeHarness();
    addTearDown(harness.dispose);
    harness.viewUiState = const RoomViewUiState(
      isFullscreen: true,
      showFullscreenChrome: true,
    );

    harness.controller.openFullscreenFollowDrawer();
    harness.controller.scheduleFullscreenChromeAutoHide();
    await tester.pump(const Duration(seconds: 2));

    expect(harness.viewUiState.showFullscreenFollowDrawer, isTrue);
    expect(harness.viewUiState.showFullscreenChrome, isFalse);
    expect(harness.followWatchlistLoadCount, 1);
  });

  testWidgets('gesture tip pauses auto hide and reschedules after clear', (
    tester,
  ) async {
    final harness = _ChromeHarness();
    addTearDown(harness.dispose);
    harness.viewUiState = const RoomViewUiState(
      isFullscreen: true,
      showFullscreenChrome: true,
    );

    harness.controller.showGestureTip('音量 70%');
    await tester.pump(const Duration(milliseconds: 899));
    expect(harness.gestureUiState.tipText, '音量 70%');
    expect(harness.viewUiState.showFullscreenChrome, isTrue);

    await tester.pump(const Duration(milliseconds: 1));
    expect(harness.gestureUiState.tipText, isNull);

    await tester.pump(const Duration(seconds: 2));
    expect(harness.viewUiState.showFullscreenChrome, isFalse);
  });

  testWidgets('vertical drag adjusts volume only while fullscreen unlocked', (
    tester,
  ) async {
    final harness = _ChromeHarness();
    addTearDown(harness.dispose);
    harness.viewUiState = const RoomViewUiState(
      isFullscreen: true,
      lockFullscreenControls: false,
    );

    harness.gestureUiState = const RoomGestureUiState(
      tracking: true,
      adjustingBrightness: false,
      startY: 1200,
      startVolume: 0.6,
    );
    await harness.controller.handleVerticalDragUpdate(
      DragUpdateDetails(globalPosition: const Offset(900, 900)),
    );
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump(const Duration(seconds: 2));

    expect(harness.android.events, contains('setMediaVolume'));

    harness.android.events.clear();
    harness.viewUiState = const RoomViewUiState(
      isFullscreen: true,
      lockFullscreenControls: true,
    );
    harness.gestureUiState = const RoomGestureUiState(
      tracking: true,
      adjustingBrightness: false,
      startY: 1200,
      startVolume: 0.6,
    );
    await harness.controller.handleVerticalDragUpdate(
      DragUpdateDetails(globalPosition: const Offset(900, 900)),
    );

    expect(harness.android.events, isNot(contains('setMediaVolume')));
  });
}

class _ChromeHarness {
  _ChromeHarness() {
    controller = RoomFullscreenChromeController(
      context: RoomFullscreenChromeContext(
        androidPlaybackBridge: android,
        ensureFollowWatchlistLoaded: () async {
          followWatchlistLoadCount += 1;
        },
        resolveScreenSize: () => const Size(1080, 1920),
        resolveVolume: () => volume,
        updateVolume: (value) {
          volume = value;
        },
        readViewUiState: () => viewUiState,
        updateViewUiState: (updater) {
          viewUiState = updater(viewUiState);
        },
        readGestureUiState: () => gestureUiState,
        updateGestureUiState: (updater) {
          gestureUiState = updater(gestureUiState);
        },
        isDisposed: () => disposed,
      ),
    );
  }

  final TestRoomAndroidPlaybackBridgeFacade android =
      TestRoomAndroidPlaybackBridgeFacade();
  late final RoomFullscreenChromeController controller;
  RoomViewUiState viewUiState = const RoomViewUiState();
  RoomGestureUiState gestureUiState = const RoomGestureUiState();
  bool disposed = false;
  double volume = 0.6;
  int followWatchlistLoadCount = 0;

  void dispose() {
    disposed = true;
    controller.dispose();
  }
}
