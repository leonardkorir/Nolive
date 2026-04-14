import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nolive_app/main.dart' as app_main;
import 'package:nolive_app/src/shared/presentation/widgets/persisted_network_image.dart';

void main() {
  group('resolvePersistedImageDecodeSize', () {
    test('clamps large room cover decodes within budget on both axes', () {
      final size = resolvePersistedImageDecodeSize(
        bucket: PersistedImageBucket.roomCover,
        constraints: const BoxConstraints.tightFor(
          width: 2400,
          height: 1080,
        ),
        devicePixelRatio: 1,
      );

      expect(size.cacheWidth, 1920);
      expect(size.cacheHeight, 864);
    });

    test('uses bounded avatar decode size on both axes', () {
      final size = resolvePersistedImageDecodeSize(
        bucket: PersistedImageBucket.avatar,
        constraints: const BoxConstraints.tightFor(
          width: 72,
          height: 72,
        ),
        devicePixelRatio: 3,
      );

      expect(size.cacheWidth, 216);
      expect(size.cacheHeight, 216);
    });

    test('scales both axes when height dominates the layout', () {
      final size = resolvePersistedImageDecodeSize(
        bucket: PersistedImageBucket.categoryIcon,
        constraints: const BoxConstraints.tightFor(
          width: 48,
          height: 120,
        ),
        devicePixelRatio: 2,
      );

      expect(size.cacheWidth, 77);
      expect(size.cacheHeight, 192);
    });

    test('returns null decode size for unbounded layout', () {
      final size = resolvePersistedImageDecodeSize(
        bucket: PersistedImageBucket.roomCover,
        constraints: const BoxConstraints(),
        devicePixelRatio: 3,
      );

      expect(size.cacheWidth, isNull);
      expect(size.cacheHeight, isNull);
    });
  });

  group('resolveImageCacheBudget', () {
    test('uses tighter budget on mobile', () {
      final budget = app_main.resolveImageCacheBudget(mobilePlatform: true);

      expect(budget.maximumSize, 100);
      expect(budget.maximumSizeBytes, 48 << 20);
    });

    test('uses larger budget on desktop', () {
      final budget = app_main.resolveImageCacheBudget(mobilePlatform: false);

      expect(budget.maximumSize, 200);
      expect(budget.maximumSizeBytes, 96 << 20);
    });
  });
}
