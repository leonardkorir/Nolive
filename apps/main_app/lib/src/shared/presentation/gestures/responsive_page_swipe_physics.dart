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
    ScrollDirection.idle => _resolveIdlePageTarget(
      basePage: basePage,
      fractionalPage: fractionalPage,
      settlePageThresholdFraction: settlePageThresholdFraction,
    ),
  };
}

double _resolveIdlePageTarget({
  required double basePage,
  required double fractionalPage,
  required double settlePageThresholdFraction,
}) {
  if (settlePageThresholdFraction >= 0.5) {
    return fractionalPage >= 0.5 ? basePage + 1.0 : basePage;
  }
  if (fractionalPage < settlePageThresholdFraction) {
    return basePage;
  }
  if (fractionalPage > 1 - settlePageThresholdFraction) {
    return basePage + 1.0;
  }
  if (fractionalPage < 0.5) {
    return basePage + 1.0;
  }
  if (fractionalPage > 0.5) {
    return basePage;
  }
  return basePage + 1.0;
}

class ResponsivePageSwipePhysics extends PageScrollPhysics {
  const ResponsivePageSwipePhysics({
    super.parent,
    this.dragStartThreshold = 3,
    this.flingDistanceThreshold = 12,
    this.flingVelocityThreshold = 240,
    this.settlePageThresholdFraction = 0.5,
    this.resolveUserScrollDirection,
  });

  const ResponsivePageSwipePhysics.topLevel({
    super.parent,
    this.resolveUserScrollDirection,
  }) : dragStartThreshold = 1,
       flingDistanceThreshold = 4,
       flingVelocityThreshold = 80,
       settlePageThresholdFraction = 0.12;

  final double dragStartThreshold;
  final double flingDistanceThreshold;
  final double flingVelocityThreshold;
  final double settlePageThresholdFraction;
  final ScrollDirection Function()? resolveUserScrollDirection;

  @override
  ResponsivePageSwipePhysics applyTo(ScrollPhysics? ancestor) {
    return ResponsivePageSwipePhysics(
      parent: buildParent(ancestor),
      dragStartThreshold: dragStartThreshold,
      flingDistanceThreshold: flingDistanceThreshold,
      flingVelocityThreshold: flingVelocityThreshold,
      settlePageThresholdFraction: settlePageThresholdFraction,
      resolveUserScrollDirection: resolveUserScrollDirection,
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

  ScrollDirection _resolveScrollDirection(ScrollMetrics position) {
    final positionDirection = position is ScrollPosition
        ? position.userScrollDirection
        : ScrollDirection.idle;
    if (positionDirection != ScrollDirection.idle) {
      return positionDirection;
    }
    return resolveUserScrollDirection?.call() ?? ScrollDirection.idle;
  }

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
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
      direction: _resolveScrollDirection(position),
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
