import 'package:flutter_test/flutter_test.dart';
import 'package:nolive_app/src/features/room/presentation/room_desktop_mini_window_coordinator.dart';
import 'package:nolive_app/src/features/room/presentation/room_view_ui_state.dart';

import 'room_fullscreen_test_fakes.dart';

void main() {
  test('enter and exit desktop mini-window restores window state', () async {
    final harness = _DesktopMiniHarness();
    harness.desktopWindow.supported = true;
    addTearDown(harness.dispose);

    await harness.coordinator.enterDesktopMiniWindow(
      exitFullscreen: () async {
        harness.exitFullscreenCount += 1;
      },
      scheduleInlineChromeAutoHide: () {
        harness.scheduleInlineChromeAutoHideCount += 1;
      },
    );

    expect(harness.viewUiState.desktopMiniWindowActive, isTrue);
    expect(harness.desktopWindow.events, contains('setAlwaysOnTop:true'));
    expect(harness.scheduleInlineChromeAutoHideCount, 1);

    await harness.coordinator.exitDesktopMiniWindow(
      scheduleInlineChromeAutoHide: () {
        harness.scheduleInlineChromeAutoHideCount += 1;
      },
    );

    expect(harness.viewUiState.desktopMiniWindowActive, isFalse);
    expect(harness.desktopWindow.alwaysOnTop, isFalse);
    expect(harness.desktopWindow.resizable, isTrue);
  });

  test('enter desktop mini-window exits fullscreen first', () async {
    final harness = _DesktopMiniHarness();
    harness.desktopWindow.supported = true;
    harness.viewUiState = const RoomViewUiState(isFullscreen: true);
    addTearDown(harness.dispose);

    await harness.coordinator.enterDesktopMiniWindow(
      exitFullscreen: () async {
        harness.exitFullscreenCount += 1;
        harness.viewUiState = harness.viewUiState.copyWith(isFullscreen: false);
      },
      scheduleInlineChromeAutoHide: () {
        harness.scheduleInlineChromeAutoHideCount += 1;
      },
    );

    expect(harness.exitFullscreenCount, 1);
    expect(harness.viewUiState.desktopMiniWindowActive, isTrue);
  });

  test('failed enter desktop mini-window rolls back window flags', () async {
    final harness = _DesktopMiniHarness();
    harness.desktopWindow.supported = true;
    harness.desktopWindow.setBoundsError = StateError('setBounds failed');
    addTearDown(harness.dispose);

    await expectLater(
      () => harness.coordinator.enterDesktopMiniWindow(
        exitFullscreen: () async {},
        scheduleInlineChromeAutoHide: () {
          harness.scheduleInlineChromeAutoHideCount += 1;
        },
      ),
      throwsStateError,
    );

    expect(harness.viewUiState.desktopMiniWindowActive, isFalse);
    expect(harness.desktopWindow.alwaysOnTop, isFalse);
    expect(harness.desktopWindow.resizable, isTrue);
  });
}

class _DesktopMiniHarness {
  _DesktopMiniHarness() {
    coordinator = RoomDesktopMiniWindowCoordinator(
      context: RoomDesktopMiniWindowContext(
        desktopWindow: desktopWindow,
        readViewUiState: () => viewUiState,
        updateViewUiState: (updater) {
          viewUiState = updater(viewUiState);
        },
        isDisposed: () => disposed,
      ),
    );
  }

  final TestRoomDesktopWindowFacade desktopWindow =
      TestRoomDesktopWindowFacade();
  late final RoomDesktopMiniWindowCoordinator coordinator;
  RoomViewUiState viewUiState = const RoomViewUiState();
  bool disposed = false;
  int exitFullscreenCount = 0;
  int scheduleInlineChromeAutoHideCount = 0;

  void dispose() {
    disposed = true;
  }
}
