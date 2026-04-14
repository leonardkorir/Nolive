import 'package:flutter/foundation.dart';

@immutable
class RoomGestureUiState {
  const RoomGestureUiState({
    this.tracking = false,
    this.adjustingBrightness = false,
    this.startY = 0,
    this.startVolume = 1,
    this.startBrightness = 0.5,
    this.tipText,
  });

  final bool tracking;
  final bool adjustingBrightness;
  final double startY;
  final double startVolume;
  final double startBrightness;
  final String? tipText;

  RoomGestureUiState copyWith({
    bool? tracking,
    bool? adjustingBrightness,
    double? startY,
    double? startVolume,
    double? startBrightness,
    String? tipText,
    bool clearTipText = false,
  }) {
    return RoomGestureUiState(
      tracking: tracking ?? this.tracking,
      adjustingBrightness: adjustingBrightness ?? this.adjustingBrightness,
      startY: startY ?? this.startY,
      startVolume: startVolume ?? this.startVolume,
      startBrightness: startBrightness ?? this.startBrightness,
      tipText: clearTipText ? null : (tipText ?? this.tipText),
    );
  }
}
