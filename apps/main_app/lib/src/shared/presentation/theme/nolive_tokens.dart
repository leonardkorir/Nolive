import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

/// Semantic status colors for live / offline / watching / warning.
@immutable
class NoliveStatusColors extends ThemeExtension<NoliveStatusColors> {
  const NoliveStatusColors({
    required this.liveForeground,
    required this.liveBackground,
    required this.offlineForeground,
    required this.offlineBackground,
    required this.watchingForeground,
    required this.watchingBackground,
    required this.warningForeground,
    required this.warningBackground,
    required this.overlayWarningForeground,
    required this.overlayMetaForeground,
  });

  final Color liveForeground;
  final Color liveBackground;
  final Color offlineForeground;
  final Color offlineBackground;
  final Color watchingForeground;
  final Color watchingBackground;
  final Color warningForeground;
  final Color warningBackground;
  final Color overlayWarningForeground;
  final Color overlayMetaForeground;

  static NoliveStatusColors light() {
    return const NoliveStatusColors(
      liveForeground: Color(0xFFD14343),
      liveBackground: Color(0xFFFCEBEC),
      offlineForeground: Color(0xFF667085),
      offlineBackground: Color(0xFFF1F4F8),
      watchingForeground: Color(0xFF15803D),
      watchingBackground: Color(0xFFEAF8EE),
      warningForeground: Color(0xFFB7791F),
      warningBackground: Color(0xFFFFF4DE),
      overlayWarningForeground: Color(0xFFFFC978),
      overlayMetaForeground: Color(0xFFD5DAE1),
    );
  }

  static NoliveStatusColors dark() {
    return const NoliveStatusColors(
      liveForeground: Color(0xFFFF8B7E),
      liveBackground: Color(0xFF351819),
      offlineForeground: Color(0xFFAFB7C5),
      offlineBackground: Color(0xFF1B212B),
      watchingForeground: Color(0xFF7BE495),
      watchingBackground: Color(0xFF12261A),
      warningForeground: Color(0xFFF5C46B),
      warningBackground: Color(0xFF3A2A0F),
      overlayWarningForeground: Color(0xFFFFC978),
      overlayMetaForeground: Color(0xFFD5DAE1),
    );
  }

  /// Pure entry for tests / non-widget callers.
  @visibleForTesting
  static NoliveStatusColors forBrightness(Brightness brightness) {
    return brightness == Brightness.dark ? dark() : light();
  }

  static NoliveStatusColors of(BuildContext context) {
    return Theme.of(context).extension<NoliveStatusColors>() ??
        forBrightness(Theme.of(context).brightness);
  }

  @override
  NoliveStatusColors copyWith({
    Color? liveForeground,
    Color? liveBackground,
    Color? offlineForeground,
    Color? offlineBackground,
    Color? watchingForeground,
    Color? watchingBackground,
    Color? warningForeground,
    Color? warningBackground,
    Color? overlayWarningForeground,
    Color? overlayMetaForeground,
  }) {
    return NoliveStatusColors(
      liveForeground: liveForeground ?? this.liveForeground,
      liveBackground: liveBackground ?? this.liveBackground,
      offlineForeground: offlineForeground ?? this.offlineForeground,
      offlineBackground: offlineBackground ?? this.offlineBackground,
      watchingForeground: watchingForeground ?? this.watchingForeground,
      watchingBackground: watchingBackground ?? this.watchingBackground,
      warningForeground: warningForeground ?? this.warningForeground,
      warningBackground: warningBackground ?? this.warningBackground,
      overlayWarningForeground:
          overlayWarningForeground ?? this.overlayWarningForeground,
      overlayMetaForeground:
          overlayMetaForeground ?? this.overlayMetaForeground,
    );
  }

  @override
  NoliveStatusColors lerp(ThemeExtension<NoliveStatusColors>? other, double t) {
    if (other is! NoliveStatusColors) {
      return this;
    }
    return NoliveStatusColors(
      liveForeground: Color.lerp(liveForeground, other.liveForeground, t)!,
      liveBackground: Color.lerp(liveBackground, other.liveBackground, t)!,
      offlineForeground: Color.lerp(
        offlineForeground,
        other.offlineForeground,
        t,
      )!,
      offlineBackground: Color.lerp(
        offlineBackground,
        other.offlineBackground,
        t,
      )!,
      watchingForeground: Color.lerp(
        watchingForeground,
        other.watchingForeground,
        t,
      )!,
      watchingBackground: Color.lerp(
        watchingBackground,
        other.watchingBackground,
        t,
      )!,
      warningForeground: Color.lerp(
        warningForeground,
        other.warningForeground,
        t,
      )!,
      warningBackground: Color.lerp(
        warningBackground,
        other.warningBackground,
        t,
      )!,
      overlayWarningForeground: Color.lerp(
        overlayWarningForeground,
        other.overlayWarningForeground,
        t,
      )!,
      overlayMetaForeground: Color.lerp(
        overlayMetaForeground,
        other.overlayMetaForeground,
        t,
      )!,
    );
  }
}

/// Shared corner radii: sm (row), md (grid card), lg (surface card).
@immutable
class NoliveRadii extends ThemeExtension<NoliveRadii> {
  const NoliveRadii({required this.sm, required this.md, required this.lg});

  final double sm;
  final double md;
  final double lg;

  static const NoliveRadii standard = NoliveRadii(sm: 10, md: 12, lg: 18);

  static NoliveRadii of(BuildContext context) {
    return Theme.of(context).extension<NoliveRadii>() ?? standard;
  }

  @override
  NoliveRadii copyWith({double? sm, double? md, double? lg}) {
    return NoliveRadii(sm: sm ?? this.sm, md: md ?? this.md, lg: lg ?? this.lg);
  }

  @override
  NoliveRadii lerp(ThemeExtension<NoliveRadii>? other, double t) {
    if (other is! NoliveRadii) {
      return this;
    }
    return NoliveRadii(
      sm: lerpDouble(sm, other.sm, t) ?? sm,
      md: lerpDouble(md, other.md, t) ?? md,
      lg: lerpDouble(lg, other.lg, t) ?? lg,
    );
  }
}

// Provider-tab keep-alive policy lives in provider_tab_keep_alive.dart
// (LRU cache of recently visited tabs — not instant dispose).
