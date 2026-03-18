import 'package:flutter/material.dart';

const Locale kZhHansCnLocale = Locale.fromSubtags(
  languageCode: 'zh',
  scriptCode: 'Hans',
  countryCode: 'CN',
);

const String kZhFontFamily = 'DroidSansFallback';
const TextLeadingDistribution kZhTextLeadingDistribution =
    TextLeadingDistribution.even;

TextStyle applyZhTextStyle([TextStyle style = const TextStyle()]) {
  return style.copyWith(
    fontFamily: kZhFontFamily,
    fontFamilyFallback: const ['sans-serif'],
    locale: kZhHansCnLocale,
    leadingDistribution:
        style.leadingDistribution ?? kZhTextLeadingDistribution,
  );
}

TextStyle? applyZhTextStyleOrNull(TextStyle? style) {
  if (style == null) {
    return null;
  }
  return applyZhTextStyle(style);
}

TextTheme applyZhTextTheme(TextTheme textTheme) {
  return textTheme.copyWith(
    displayLarge: applyZhTextStyleOrNull(textTheme.displayLarge),
    displayMedium: applyZhTextStyleOrNull(textTheme.displayMedium),
    displaySmall: applyZhTextStyleOrNull(textTheme.displaySmall),
    headlineLarge: applyZhTextStyleOrNull(textTheme.headlineLarge),
    headlineMedium: applyZhTextStyleOrNull(textTheme.headlineMedium),
    headlineSmall: applyZhTextStyleOrNull(textTheme.headlineSmall),
    titleLarge: applyZhTextStyleOrNull(textTheme.titleLarge),
    titleMedium: applyZhTextStyleOrNull(textTheme.titleMedium),
    titleSmall: applyZhTextStyleOrNull(textTheme.titleSmall),
    bodyLarge: applyZhTextStyleOrNull(textTheme.bodyLarge),
    bodyMedium: applyZhTextStyleOrNull(textTheme.bodyMedium),
    bodySmall: applyZhTextStyleOrNull(textTheme.bodySmall),
    labelLarge: applyZhTextStyleOrNull(textTheme.labelLarge),
    labelMedium: applyZhTextStyleOrNull(textTheme.labelMedium),
    labelSmall: applyZhTextStyleOrNull(textTheme.labelSmall),
  );
}
