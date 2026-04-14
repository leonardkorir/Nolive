import 'package:flutter_test/flutter_test.dart';
import 'package:nolive_app/src/features/room/presentation/room_gesture_ui_state.dart';

void main() {
  test('room gesture ui state exposes stable defaults', () {
    const state = RoomGestureUiState();

    expect(state.tracking, isFalse);
    expect(state.adjustingBrightness, isFalse);
    expect(state.startY, 0);
    expect(state.startVolume, 1);
    expect(state.startBrightness, 0.5);
    expect(state.tipText, isNull);
  });

  test('room gesture ui state copyWith can update and clear tip text', () {
    const state = RoomGestureUiState();

    final updated = state.copyWith(
      tracking: true,
      adjustingBrightness: true,
      startY: 42,
      startVolume: 0.6,
      startBrightness: 0.7,
      tipText: '亮度 70%',
    );
    final cleared = updated.copyWith(clearTipText: true);

    expect(updated.tracking, isTrue);
    expect(updated.adjustingBrightness, isTrue);
    expect(updated.startY, 42);
    expect(updated.startVolume, 0.6);
    expect(updated.startBrightness, 0.7);
    expect(updated.tipText, '亮度 70%');
    expect(cleared.tipText, isNull);
    expect(cleared.tracking, isTrue);
  });
}
