import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nolive_app/src/shared/presentation/theme/nolive_tokens.dart';
import 'package:nolive_app/src/shared/presentation/theme/zh_text.dart';

class NoliveTheme {
  const NoliveTheme._();

  static const Color _lightBackground = Color(0xFFF4F7FB);
  static const Color _lightSurface = Color(0xFFFFFFFF);
  static const Color _lightSurfaceAlt = Color(0xFFEAF1F7);
  static const Color _lightPrimary = Color(0xFF1778D4);
  static const Color _lightSecondary = Color(0xFF0F9D92);
  static const Color _lightOutline = Color(0xFFD7E1EB);

  static const Color _darkBackground = Color(0xFF060A10);
  static const Color _darkSurface = Color(0xFF101720);
  static const Color _darkSurfaceAlt = Color(0xFF182331);
  static const Color _darkPrimary = Color(0xFF5DAEFF);
  static const Color _darkSecondary = Color(0xFF4FD1C5);
  static const Color _darkOutline = Color(0xFF253243);
  static const Color _green = Color(0xFF22C55E);
  static ThemeData light() {
    const colorScheme = ColorScheme(
      brightness: Brightness.light,
      primary: _lightPrimary,
      onPrimary: Colors.white,
      secondary: _lightSecondary,
      onSecondary: Colors.white,
      error: Color(0xFFDC2626),
      onError: Colors.white,
      surface: _lightSurface,
      onSurface: Color(0xFF111827),
      tertiary: _green,
      onTertiary: Colors.white,
      primaryContainer: Color(0xFFDCEEFF),
      onPrimaryContainer: Color(0xFF0A2744),
      secondaryContainer: Color(0xFFD8F5F1),
      onSecondaryContainer: Color(0xFF063B38),
      surfaceContainerHighest: _lightSurfaceAlt,
      onSurfaceVariant: Color(0xFF667085),
      outline: _lightOutline,
      outlineVariant: Color(0xFFE4E7EC),
      shadow: Color(0x14000000),
      scrim: Colors.black54,
      inverseSurface: Color(0xFF0F172A),
      onInverseSurface: Colors.white,
      inversePrimary: Color(0xFF8CC6FF),
      surfaceTint: _lightPrimary,
    );

    return _buildTheme(
      colorScheme: colorScheme,
      scaffoldBackgroundColor: _lightBackground,
      cardColor: _lightSurface,
      inputFillColor: _lightSurface,
      navigationBackgroundColor: const Color(0xFFF9FAFB),
      navigationIndicatorColor: const Color(0xFFE5F1FC),
      dividerColor: const Color(0xFFE5E7EB),
    );
  }

  static ThemeData dark() {
    const colorScheme = ColorScheme(
      brightness: Brightness.dark,
      primary: _darkPrimary,
      onPrimary: Colors.white,
      secondary: _darkSecondary,
      onSecondary: Colors.white,
      error: Color(0xFFF87171),
      onError: Colors.white,
      surface: _darkSurface,
      onSurface: Color(0xFFF8FAFC),
      tertiary: _green,
      onTertiary: Colors.white,
      primaryContainer: Color(0xFF113761),
      onPrimaryContainer: Color(0xFFD8EDFF),
      secondaryContainer: Color(0xFF0B403B),
      onSecondaryContainer: Color(0xFFD9FFFB),
      surfaceContainerHighest: _darkSurfaceAlt,
      onSurfaceVariant: Color(0xFF98A2B3),
      outline: _darkOutline,
      outlineVariant: Color(0xFF1D2330),
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: Color(0xFFF8FAFC),
      onInverseSurface: Color(0xFF0F172A),
      inversePrimary: Color(0xFF1D7FE0),
      surfaceTint: _darkPrimary,
    );

    return _buildTheme(
      colorScheme: colorScheme,
      scaffoldBackgroundColor: _darkBackground,
      cardColor: _darkSurface,
      inputFillColor: _darkSurfaceAlt,
      navigationBackgroundColor: const Color(0xFF0A0D12),
      navigationIndicatorColor: const Color(0xFF132235),
      dividerColor: const Color(0xFF1D2432),
    );
  }

  static ThemeData _buildTheme({
    required ColorScheme colorScheme,
    required Color scaffoldBackgroundColor,
    required Color cardColor,
    required Color inputFillColor,
    required Color navigationBackgroundColor,
    required Color navigationIndicatorColor,
    required Color dividerColor,
  }) {
    final baseTypography = Typography.material2021().black.apply(
          bodyColor: colorScheme.onSurface,
          displayColor: colorScheme.onSurface,
        );
    final textTheme = applyZhTextTheme(baseTypography.copyWith(
      headlineMedium: baseTypography.headlineMedium?.copyWith(
        fontWeight: FontWeight.w500,
        letterSpacing: 0,
        height: 1.12,
      ),
      headlineSmall: baseTypography.headlineSmall?.copyWith(
        fontWeight: FontWeight.w500,
        letterSpacing: 0,
        height: 1.14,
      ),
      titleLarge: baseTypography.titleLarge?.copyWith(
        fontWeight: FontWeight.w500,
        fontSize: 16,
        height: 1.14,
      ),
      titleMedium: baseTypography.titleMedium?.copyWith(
        fontWeight: FontWeight.w500,
        fontSize: 13.5,
        height: 1.18,
      ),
      titleSmall: baseTypography.titleSmall?.copyWith(
        fontWeight: FontWeight.w500,
        fontSize: 12.5,
        height: 1.18,
      ),
      bodyLarge: baseTypography.bodyLarge?.copyWith(fontSize: 14, height: 1.28),
      bodyMedium:
          baseTypography.bodyMedium?.copyWith(fontSize: 13, height: 1.26),
      bodySmall: baseTypography.bodySmall?.copyWith(fontSize: 12, height: 1.24),
      labelLarge: baseTypography.labelLarge?.copyWith(
        fontWeight: FontWeight.w500,
        fontSize: 11.5,
        height: 1.16,
      ),
    ));

    final statusColors = colorScheme.brightness == Brightness.dark
        ? NoliveStatusColors.dark()
        : NoliveStatusColors.light();

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: scaffoldBackgroundColor,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      extensions: <ThemeExtension<dynamic>>[
        statusColors,
        NoliveRadii.standard,
      ],
      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: (colorScheme.brightness == Brightness.dark
                ? SystemUiOverlayStyle.light
                : SystemUiOverlayStyle.dark)
            .copyWith(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: Colors.transparent,
        ),
        titleTextStyle: applyZhTextStyleOrNull(textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w500,
          color: colorScheme.onSurface,
        )),
      ),
      cardTheme: CardThemeData(
        color: cardColor,
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(NoliveRadii.standard.lg + 4),
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: dividerColor,
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: inputFillColor,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        hintStyle: applyZhTextStyle(
          TextStyle(color: colorScheme.onSurfaceVariant),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(NoliveRadii.standard.lg),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(NoliveRadii.standard.lg),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(NoliveRadii.standard.lg),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.4),
        ),
      ),
      // All Filled / tonal / outlined buttons share min height + radius language.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(NoliveRadii.standard.md + 4),
          ),
          textStyle: applyZhTextStyleOrNull(
            textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          side: BorderSide(color: colorScheme.outlineVariant),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(NoliveRadii.standard.md + 4),
          ),
          textStyle: applyZhTextStyleOrNull(
            textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 40),
          foregroundColor: colorScheme.primary,
          textStyle: applyZhTextStyleOrNull(
            textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: cardColor,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(NoliveRadii.standard.lg + 4),
        ),
        titleTextStyle: applyZhTextStyleOrNull(
          textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface,
          ),
        ),
        contentTextStyle: applyZhTextStyleOrNull(
          textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: colorScheme.surfaceContainerHighest,
        selectedColor: colorScheme.primaryContainer,
        labelStyle: applyZhTextStyle(TextStyle(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w500,
        )),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      listTileTheme: ListTileThemeData(
        // Keep padding modest so Profile / settings rows stay density-consistent.
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(NoliveRadii.standard.lg),
        ),
        iconColor: colorScheme.onSurfaceVariant,
        titleTextStyle: applyZhTextStyleOrNull(
          textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w500,
            color: colorScheme.onSurface,
          ),
        ),
        subtitleTextStyle: applyZhTextStyleOrNull(
          textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        backgroundColor: navigationBackgroundColor,
        indicatorColor: navigationIndicatorColor,
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStateProperty.all(
          applyZhTextStyle(TextStyle(
            fontWeight: FontWeight.w500,
            color: colorScheme.onSurface,
          )),
        ),
      ),
      // Desktop rail: Chinese labels (首页/关注/…) need the same fallback font.
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: navigationBackgroundColor,
        indicatorColor: navigationIndicatorColor,
        selectedIconTheme: IconThemeData(color: colorScheme.onSecondaryContainer),
        unselectedIconTheme: IconThemeData(color: colorScheme.onSurfaceVariant),
        selectedLabelTextStyle: applyZhTextStyleOrNull(
          textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface,
          ),
        ),
        unselectedLabelTextStyle: applyZhTextStyleOrNull(
          textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w500,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        dividerColor: Colors.transparent,
        labelStyle: applyZhTextStyleOrNull(
          textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w500),
        ),
        unselectedLabelStyle: applyZhTextStyleOrNull(
          textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w500),
        ),
      ),
      sliderTheme: SliderThemeData(
        trackHeight: 4,
        inactiveTrackColor: colorScheme.surfaceContainerHighest,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        elevation: 4,
        backgroundColor: colorScheme.inverseSurface,
        contentTextStyle: applyZhTextStyle(
          TextStyle(
            color: colorScheme.onInverseSurface,
            fontWeight: FontWeight.w500,
          ),
        ),
        actionTextColor: colorScheme.inversePrimary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(NoliveRadii.standard.lg),
        ),
        insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: cardColor,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(NoliveRadii.standard.lg + 10),
          ),
        ),
      ),
    );

    return base.copyWith(
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
        },
      ),
    );
  }
}
