import 'package:flutter/material.dart';

enum AppAdaptiveSize { compact, medium, expanded }

@immutable
class AppAdaptiveLayoutSpec {
  const AppAdaptiveLayoutSpec({
    required this.size,
    required this.pageHorizontalPadding,
    required this.providerTabLogoSize,
    required this.providerTabLabelPadding,
    required this.sectionGap,
    required this.categoryTileVisualExtent,
    required this.categoryTileTextSize,
    required this.categoryTileChildAspectRatio,
    required this.categoryTileTargetWidth,
    required this.categorySearchMaxWidth,
  });

  final AppAdaptiveSize size;
  final double pageHorizontalPadding;
  final double providerTabLogoSize;
  final EdgeInsetsGeometry providerTabLabelPadding;
  final double sectionGap;
  final double categoryTileVisualExtent;
  final double categoryTileTextSize;
  final double categoryTileChildAspectRatio;
  final double categoryTileTargetWidth;
  final double categorySearchMaxWidth;

  bool get isTablet => size != AppAdaptiveSize.compact;
  bool get isExpanded => size == AppAdaptiveSize.expanded;

  static AppAdaptiveLayoutSpec of(BuildContext context) {
    return fromSize(MediaQuery.sizeOf(context));
  }

  static AppAdaptiveLayoutSpec fromSize(Size size) {
    final shortestSide = size.shortestSide;
    if (shortestSide >= 840) {
      return const AppAdaptiveLayoutSpec(
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
    }
    if (shortestSide >= 600) {
      return const AppAdaptiveLayoutSpec(
        size: AppAdaptiveSize.medium,
        pageHorizontalPadding: 20,
        providerTabLogoSize: 24,
        providerTabLabelPadding: EdgeInsets.symmetric(horizontal: 20),
        sectionGap: 18,
        categoryTileVisualExtent: 66,
        categoryTileTextSize: 12.0,
        categoryTileChildAspectRatio: 0.9,
        categoryTileTargetWidth: 132,
        categorySearchMaxWidth: 360,
      );
    }
    return const AppAdaptiveLayoutSpec(
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
  }

  int browseCategoryCrossAxisCount(
    double availableWidth, {
    int? min,
    int max = 8,
  }) {
    final resolvedMin = min ?? (size == AppAdaptiveSize.compact ? 5 : 4);
    return (availableWidth / categoryTileTargetWidth)
        .floor()
        .clamp(resolvedMin, max)
        .toInt();
  }
}
