import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

double resolveResponsivePageTarget({
  required double page,
  required double velocity,
  required double velocityThreshold,
  required double settlePageThresholdFraction,
  ScrollDirection direction = ScrollDirection.idle,
}) {
  assert(settlePageThresholdFraction > 0 && settlePageThresholdFraction <= 0.5);
  if (velocity <= -velocityThreshold) {
    return (page - 0.5).roundToDouble();
  }
  if (velocity >= velocityThreshold) {
    return (page + 0.5).roundToDouble();
  }
  final basePage = page.floorToDouble();
  final fractionalPage = page - basePage;
  return switch (direction) {
    ScrollDirection.reverse =>
      fractionalPage >= settlePageThresholdFraction ? basePage + 1.0 : basePage,
    ScrollDirection.forward =>
      fractionalPage <= (1 - settlePageThresholdFraction)
          ? basePage
          : basePage + 1.0,
    ScrollDirection.idle => fractionalPage >= 0.5 ? basePage + 1.0 : basePage,
  };
}

class ResponsivePageSwipePhysics extends PageScrollPhysics {
  const ResponsivePageSwipePhysics({
    super.parent,
    this.dragStartThreshold = 3,
    this.flingDistanceThreshold = 12,
    this.flingVelocityThreshold = 240,
    this.settlePageThresholdFraction = 0.5,
  });

  const ResponsivePageSwipePhysics.topLevel({super.parent})
      : dragStartThreshold = 1,
        flingDistanceThreshold = 4,
        flingVelocityThreshold = 80,
        settlePageThresholdFraction = 0.18;

  final double dragStartThreshold;
  final double flingDistanceThreshold;
  final double flingVelocityThreshold;
  final double settlePageThresholdFraction;

  @override
  ResponsivePageSwipePhysics applyTo(ScrollPhysics? ancestor) {
    return ResponsivePageSwipePhysics(
      parent: buildParent(ancestor),
      dragStartThreshold: dragStartThreshold,
      flingDistanceThreshold: flingDistanceThreshold,
      flingVelocityThreshold: flingVelocityThreshold,
      settlePageThresholdFraction: settlePageThresholdFraction,
    );
  }

  @override
  double get dragStartDistanceMotionThreshold => dragStartThreshold;

  @override
  double get minFlingDistance => flingDistanceThreshold;

  @override
  double get minFlingVelocity => flingVelocityThreshold;

  double _getPage(ScrollMetrics position) {
    if (position is PageMetrics) {
      return position.page!;
    }
    return position.pixels / position.viewportDimension;
  }

  double _getPixels(ScrollMetrics position, double page) {
    if (position is PageMetrics) {
      return page * position.viewportDimension * position.viewportFraction;
    }
    return page * position.viewportDimension;
  }

  @override
  Simulation? createBallisticSimulation(
      ScrollMetrics position, double velocity) {
    if ((velocity <= 0.0 && position.pixels <= position.minScrollExtent) ||
        (velocity >= 0.0 && position.pixels >= position.maxScrollExtent)) {
      return super.createBallisticSimulation(position, velocity);
    }
    final tolerance = toleranceFor(position);
    final effectiveVelocityThreshold = velocity == 0
        ? flingVelocityThreshold
        : flingVelocityThreshold > tolerance.velocity
            ? flingVelocityThreshold
            : tolerance.velocity;
    final targetPage = resolveResponsivePageTarget(
      page: _getPage(position),
      velocity: velocity,
      velocityThreshold: effectiveVelocityThreshold,
      settlePageThresholdFraction: settlePageThresholdFraction,
      direction: position is ScrollPosition
          ? position.userScrollDirection
          : ScrollDirection.idle,
    );
    final unclampedTarget = _getPixels(position, targetPage);
    final target = unclampedTarget
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    if (target != position.pixels) {
      return ScrollSpringSimulation(
        spring,
        position.pixels,
        target,
        velocity,
        tolerance: tolerance,
      );
    }
    return null;
  }
}
