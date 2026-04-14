import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nolive_app/src/shared/presentation/adaptive/app_adaptive_layout.dart';

void main() {
  test('adaptive layout uses compact medium and expanded breakpoints', () {
    expect(
      AppAdaptiveLayoutSpec.fromSize(const Size(599, 900)).size,
      AppAdaptiveSize.compact,
    );
    expect(
      AppAdaptiveLayoutSpec.fromSize(const Size(600, 900)).size,
      AppAdaptiveSize.medium,
    );
    expect(
      AppAdaptiveLayoutSpec.fromSize(const Size(839, 1200)).size,
      AppAdaptiveSize.medium,
    );
    expect(
      AppAdaptiveLayoutSpec.fromSize(const Size(840, 1200)).size,
      AppAdaptiveSize.expanded,
    );
  });

  test('adaptive category grid count clamps to a safe range', () {
    const spec = AppAdaptiveLayoutSpec(
      size: AppAdaptiveSize.expanded,
      pageHorizontalPadding: 24,
      providerTabLogoSize: 26,
      providerTabLabelPadding: EdgeInsets.symmetric(horizontal: 24),
      sectionGap: 20,
      categoryTileVisualExtent: 76,
      categoryTileTextSize: 12.6,
      categoryTileChildAspectRatio: 0.84,
      categoryTileTargetWidth: 152,
      categorySearchMaxWidth: 420,
    );

    expect(spec.browseCategoryCrossAxisCount(200), 4);
    expect(spec.browseCategoryCrossAxisCount(900), 5);
    expect(spec.browseCategoryCrossAxisCount(4000), 8);
  });

  test('compact category grid keeps five columns on phone widths', () {
    const spec = AppAdaptiveLayoutSpec(
      size: AppAdaptiveSize.compact,
      pageHorizontalPadding: 16,
      providerTabLogoSize: 22,
      providerTabLabelPadding: EdgeInsets.symmetric(horizontal: 18),
      sectionGap: 16,
      categoryTileVisualExtent: 56,
      categoryTileTextSize: 10.8,
      categoryTileChildAspectRatio: 0.86,
      categoryTileTargetWidth: 72,
      categorySearchMaxWidth: 320,
    );

    expect(spec.browseCategoryCrossAxisCount(200), 5);
    expect(spec.browseCategoryCrossAxisCount(379), 5);
    expect(spec.browseCategoryCrossAxisCount(520), 7);
  });
}
