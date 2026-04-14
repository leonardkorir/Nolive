import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nolive_app/src/shared/presentation/gestures/responsive_page_swipe_physics.dart';

void main() {
  group('resolveResponsivePageTarget', () {
    test('keeps default half-page settle behavior for regular pages', () {
      expect(
        resolveResponsivePageTarget(
          page: 0.49,
          velocity: 0,
          velocityThreshold: 240,
          settlePageThresholdFraction: 0.5,
        ),
        0,
      );
      expect(
        resolveResponsivePageTarget(
          page: 0.50,
          velocity: 0,
          velocityThreshold: 240,
          settlePageThresholdFraction: 0.5,
        ),
        1,
      );
    });

    test('top-level pages settle after a shorter drag distance', () {
      expect(
        resolveResponsivePageTarget(
          page: 0.17,
          velocity: 0,
          velocityThreshold: 80,
          settlePageThresholdFraction: 0.18,
          direction: ScrollDirection.reverse,
        ),
        0,
      );
      expect(
        resolveResponsivePageTarget(
          page: 0.18,
          velocity: 0,
          velocityThreshold: 80,
          settlePageThresholdFraction: 0.18,
          direction: ScrollDirection.reverse,
        ),
        1,
      );
    });

    test('top-level pages use the same shorter threshold when returning', () {
      expect(
        resolveResponsivePageTarget(
          page: 0.83,
          velocity: 0,
          velocityThreshold: 80,
          settlePageThresholdFraction: 0.18,
          direction: ScrollDirection.forward,
        ),
        1,
      );
      expect(
        resolveResponsivePageTarget(
          page: 0.82,
          velocity: 0,
          velocityThreshold: 80,
          settlePageThresholdFraction: 0.18,
          direction: ScrollDirection.forward,
        ),
        0,
      );
    });

    test('fling direction still wins even with very small drag offset', () {
      expect(
        resolveResponsivePageTarget(
          page: 0.05,
          velocity: 120,
          velocityThreshold: 80,
          settlePageThresholdFraction: 0.18,
          direction: ScrollDirection.reverse,
        ),
        1,
      );
      expect(
        resolveResponsivePageTarget(
          page: 0.95,
          velocity: -120,
          velocityThreshold: 80,
          settlePageThresholdFraction: 0.18,
          direction: ScrollDirection.forward,
        ),
        0,
      );
    });
  });
}
