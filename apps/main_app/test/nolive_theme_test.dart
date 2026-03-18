import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nolive_app/src/shared/presentation/theme/nolive_theme.dart';
import 'package:nolive_app/src/shared/presentation/theme/zh_text.dart';

void main() {
  const removedFontFamilies = <String>{'NotoSansCJKSC'};

  test('light and dark theme use lightweight zh font and locale', () {
    for (final theme in <ThemeData>[
      NoliveTheme.light(),
      NoliveTheme.dark(),
    ]) {
      final bodyMedium = theme.textTheme.bodyMedium;
      expect(bodyMedium, isNotNull);
      expect(removedFontFamilies, isNot(contains(bodyMedium?.fontFamily)));
      expect(bodyMedium?.fontFamily, kZhFontFamily);
      expect(bodyMedium?.locale, kZhHansCnLocale);

      expect(
        removedFontFamilies,
        isNot(contains(theme.chipTheme.labelStyle?.fontFamily)),
      );
      expect(theme.chipTheme.labelStyle?.fontFamily, kZhFontFamily);
      expect(theme.chipTheme.labelStyle?.locale, kZhHansCnLocale);

      expect(
        removedFontFamilies,
        isNot(contains(theme.tabBarTheme.labelStyle?.fontFamily)),
      );
      expect(theme.tabBarTheme.labelStyle?.fontFamily, kZhFontFamily);
      expect(theme.tabBarTheme.labelStyle?.locale, kZhHansCnLocale);

      expect(
        removedFontFamilies,
        isNot(contains(theme.tabBarTheme.unselectedLabelStyle?.fontFamily)),
      );
      expect(theme.tabBarTheme.unselectedLabelStyle?.fontFamily, kZhFontFamily);
      expect(theme.tabBarTheme.unselectedLabelStyle?.locale, kZhHansCnLocale);

      final navigationLabelStyle =
          theme.navigationBarTheme.labelTextStyle?.resolve(<WidgetState>{});
      expect(
        removedFontFamilies,
        isNot(contains(navigationLabelStyle?.fontFamily)),
      );
      expect(navigationLabelStyle?.fontFamily, kZhFontFamily);
      expect(navigationLabelStyle?.locale, kZhHansCnLocale);

      expect(theme.appBarTheme.titleTextStyle?.fontFamily, kZhFontFamily);
      expect(theme.appBarTheme.titleTextStyle?.locale, kZhHansCnLocale);
      expect(theme.inputDecorationTheme.hintStyle?.fontFamily, kZhFontFamily);
      expect(theme.inputDecorationTheme.hintStyle?.locale, kZhHansCnLocale);
      expect(theme.snackBarTheme.contentTextStyle?.fontFamily, kZhFontFamily);
      expect(theme.snackBarTheme.contentTextStyle?.locale, kZhHansCnLocale);
    }
  });

  test('helper applies zh font, locale, and even leading', () {
    final style = applyZhTextStyle(const TextStyle(fontSize: 14));

    expect(style.fontFamily, kZhFontFamily);
    expect(style.fontFamilyFallback, const <String>['sans-serif']);
    expect(style.locale, kZhHansCnLocale);
    expect(style.leadingDistribution, TextLeadingDistribution.even);
    expect(style.fontSize, 14);
  });
}
