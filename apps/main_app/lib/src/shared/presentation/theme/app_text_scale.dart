import 'package:flutter/material.dart';

/// Clamps the platform [TextScaler] so system font size is respected within
/// a layout-safe range (never fully ignored via [TextScaler.noScaling]).
@visibleForTesting
TextScaler resolveAppTextScaler(
  TextScaler platform, {
  double minScale = 1.0,
  double maxScale = 1.3,
}) {
  // Sample against a typical body size so non-linear scalers still clamp.
  const sampleFontSize = 14.0;
  final scaled = platform.scale(sampleFontSize);
  final factor = (scaled / sampleFontSize).clamp(minScale, maxScale);
  if ((factor - 1.0).abs() < 0.001) {
    return TextScaler.noScaling;
  }
  return TextScaler.linear(factor);
}

/// Applies [resolveAppTextScaler] onto a [MediaQueryData] copy.
MediaQueryData applyAppTextScaler(MediaQueryData data) {
  return data.copyWith(textScaler: resolveAppTextScaler(data.textScaler));
}
