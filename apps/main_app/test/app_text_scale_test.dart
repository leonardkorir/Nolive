import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nolive_app/src/shared/presentation/theme/app_text_scale.dart';

void main() {
  test('resolveAppTextScaler respects system scale within clamp', () {
    final scaled = resolveAppTextScaler(const TextScaler.linear(1.5));
    // Clamped to max 1.3
    expect(scaled.scale(14.0), closeTo(14.0 * 1.3, 0.01));

    final identity = resolveAppTextScaler(TextScaler.noScaling);
    expect(identity.scale(14.0), 14.0);

    final mild = resolveAppTextScaler(const TextScaler.linear(1.15));
    expect(mild.scale(14.0), closeTo(14.0 * 1.15, 0.01));
  });

  test('applyAppTextScaler does not force noScaling for large system fonts', () {
    final data = const MediaQueryData(
      size: Size(400, 800),
      textScaler: TextScaler.linear(1.4),
    );
    final applied = applyAppTextScaler(data);
    expect(applied.textScaler.scale(14.0), closeTo(14.0 * 1.3, 0.01));
    // Must not be fully disabled (scale factor would be 1.0 only when platform is 1).
    expect(applied.textScaler.scale(14.0), greaterThan(14.0));
  });
}
