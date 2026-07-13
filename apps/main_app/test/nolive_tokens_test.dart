import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nolive_app/src/shared/presentation/provider_tab_keep_alive.dart';
import 'package:nolive_app/src/shared/presentation/theme/nolive_theme.dart';
import 'package:nolive_app/src/shared/presentation/theme/nolive_tokens.dart';

void main() {
  test('status tokens distinguish live / offline / warning by brightness', () {
    final light = NoliveStatusColors.forBrightness(Brightness.light);
    final dark = NoliveStatusColors.forBrightness(Brightness.dark);

    expect(light.liveForeground, isNot(light.offlineForeground));
    expect(light.warningForeground, isNot(light.liveForeground));
    expect(dark.liveForeground, isNot(dark.offlineForeground));
  });

  test('theme exposes NoliveStatusColors and NoliveRadii extensions', () {
    final light = NoliveTheme.light();
    final dark = NoliveTheme.dark();
    expect(light.extension<NoliveStatusColors>(), isNotNull);
    expect(dark.extension<NoliveStatusColors>(), isNotNull);
    expect(light.extension<NoliveRadii>()?.md, NoliveRadii.standard.md);
    expect(dark.extension<NoliveRadii>()?.lg, NoliveRadii.standard.lg);
  });

  test('provider tab keep-alive uses LRU recent tabs not only selected', () {
    final store = ProviderTabKeepAliveStore(capacity: 3);
    expect(store.shouldKeep(0), isTrue); // empty = keep all
    store.select(0);
    store.select(1);
    store.select(2);
    expect(store.shouldKeep(0), isTrue);
    expect(store.shouldKeep(1), isTrue);
    expect(store.shouldKeep(2), isTrue);
    // Visiting a 4th tab drops the oldest (0).
    store.select(3);
    expect(store.shouldKeep(3), isTrue);
    expect(store.shouldKeep(2), isTrue);
    expect(store.shouldKeep(1), isTrue);
    expect(store.shouldKeep(0), isFalse);

    expect(
      shouldKeepProviderTabAlive(
        tabIndex: 1,
        selectedIndex: 3,
        recentTabIndices: store.recentTabIndices,
        capacity: 3,
      ),
      isTrue,
    );
    expect(
      shouldKeepProviderTabAlive(
        tabIndex: 0,
        selectedIndex: 3,
        recentTabIndices: store.recentTabIndices,
        capacity: 3,
      ),
      isFalse,
    );
  });
}
