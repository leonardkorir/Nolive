import 'package:flutter_test/flutter_test.dart';
import 'package:nolive_app/src/shared/presentation/gestures/responsive_tab_swipe_switcher.dart';

void main() {
  group('resolveResponsiveTabIndexDelta', () {
    test('uses symmetric drag distance in both directions', () {
      expect(
        resolveResponsiveTabIndexDelta(
          dragDx: -17,
          velocityX: 0,
          triggerDistance: 18,
          triggerVelocity: 80,
        ),
        0,
      );
      expect(
        resolveResponsiveTabIndexDelta(
          dragDx: -18,
          velocityX: 0,
          triggerDistance: 18,
          triggerVelocity: 80,
        ),
        1,
      );
      expect(
        resolveResponsiveTabIndexDelta(
          dragDx: 17,
          velocityX: 0,
          triggerDistance: 18,
          triggerVelocity: 80,
        ),
        0,
      );
      expect(
        resolveResponsiveTabIndexDelta(
          dragDx: 18,
          velocityX: 0,
          triggerDistance: 18,
          triggerVelocity: 80,
        ),
        -1,
      );
    });

    test('velocity still wins over drag distance', () {
      expect(
        resolveResponsiveTabIndexDelta(
          dragDx: -2,
          velocityX: -100,
          triggerDistance: 18,
          triggerVelocity: 80,
        ),
        1,
      );
      expect(
        resolveResponsiveTabIndexDelta(
          dragDx: 2,
          velocityX: 100,
          triggerDistance: 18,
          triggerVelocity: 80,
        ),
        -1,
      );
    });
  });
}
