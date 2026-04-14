import 'package:flutter_test/flutter_test.dart';
import 'package:nolive_app/src/features/room/presentation/room_view_ui_state.dart';

void main() {
  test('room view ui state exposes stable defaults', () {
    const state = RoomViewUiState();

    expect(state.isFullscreen, isFalse);
    expect(state.fullscreenBootstrapPending, isFalse);
    expect(state.desktopMiniWindowActive, isFalse);
    expect(state.showInlinePlayerChrome, isTrue);
    expect(state.showFullscreenChrome, isTrue);
    expect(state.lockFullscreenControls, isFalse);
    expect(state.pipSupported, isFalse);
    expect(state.enteringPictureInPicture, isFalse);
    expect(state.danmakuVisibleBeforePip, isTrue);
  });

  test('room view ui state copyWith updates selected flags only', () {
    const state = RoomViewUiState();

    final next = state.copyWith(
      isFullscreen: true,
      desktopMiniWindowActive: true,
      showInlinePlayerChrome: false,
      enteringPictureInPicture: true,
    );

    expect(next.isFullscreen, isTrue);
    expect(next.desktopMiniWindowActive, isTrue);
    expect(next.showInlinePlayerChrome, isFalse);
    expect(next.enteringPictureInPicture, isTrue);
    expect(next.showFullscreenChrome, isTrue);
    expect(next.lockFullscreenControls, isFalse);
  });
}
