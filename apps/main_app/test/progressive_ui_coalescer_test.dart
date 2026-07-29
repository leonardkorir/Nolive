import 'package:flutter_test/flutter_test.dart';
import 'package:nolive_app/src/shared/presentation/progressive_ui_coalescer.dart';

void main() {
  test(
    'ProgressiveUiCoalescer merges multiple schedules into one flush',
    () async {
      var flushes = 0;
      final coalescer = ProgressiveUiCoalescer(
        interval: const Duration(milliseconds: 40),
        onFlush: () => flushes += 1,
      );

      coalescer.schedule();
      coalescer.schedule();
      coalescer.schedule();
      expect(flushes, 0);
      expect(coalescer.hasPendingFlush, isTrue);

      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(flushes, 1);

      coalescer.schedule();
      coalescer.flushNow();
      expect(flushes, 2);

      coalescer.dispose();
      coalescer.schedule();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(flushes, 2);
    },
  );

  test('cancel drops scheduled flush without invoking onFlush', () async {
    var flushes = 0;
    final coalescer = ProgressiveUiCoalescer(
      interval: const Duration(milliseconds: 40),
      onFlush: () => flushes += 1,
    );
    coalescer.schedule();
    expect(coalescer.hasPendingFlush, isTrue);
    coalescer.cancel();
    expect(coalescer.hasPendingFlush, isFalse);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(flushes, 0);
    coalescer.dispose();
  });
}
