import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

int resolveResponsiveTabIndexDelta({
  required double dragDx,
  required double velocityX,
  required double triggerDistance,
  required double triggerVelocity,
}) {
  if (velocityX.abs() >= triggerVelocity) {
    return velocityX < 0 ? 1 : -1;
  }
  if (dragDx.abs() >= triggerDistance) {
    return dragDx < 0 ? 1 : -1;
  }
  return 0;
}

class ResponsiveTabSwipeSwitcher extends StatefulWidget {
  const ResponsiveTabSwipeSwitcher({
    required this.child,
    this.triggerDistance = 18,
    this.triggerVelocity = 80,
    this.animationDuration = const Duration(milliseconds: 180),
    this.animationCurve = Curves.easeOutCubic,
    super.key,
  });

  final Widget child;
  final double triggerDistance;
  final double triggerVelocity;
  final Duration animationDuration;
  final Curve animationCurve;

  @override
  State<ResponsiveTabSwipeSwitcher> createState() =>
      _ResponsiveTabSwipeSwitcherState();
}

class _ResponsiveTabSwipeSwitcherState
    extends State<ResponsiveTabSwipeSwitcher> {
  double _dragDx = 0;
  bool _handled = false;

  void _reset() {
    _dragDx = 0;
    _handled = false;
  }

  void _maybeSwitch({double velocityX = 0}) {
    if (_handled) {
      return;
    }
    final controller = DefaultTabController.maybeOf(context);
    if (controller == null ||
        controller.length <= 1 ||
        controller.indexIsChanging) {
      return;
    }
    final delta = resolveResponsiveTabIndexDelta(
      dragDx: _dragDx,
      velocityX: velocityX,
      triggerDistance: widget.triggerDistance,
      triggerVelocity: widget.triggerVelocity,
    );
    if (delta == 0) {
      return;
    }
    final targetIndex =
        (controller.index + delta).clamp(0, controller.length - 1);
    if (targetIndex == controller.index) {
      return;
    }
    _handled = true;
    controller.animateTo(
      targetIndex,
      duration: widget.animationDuration,
      curve: widget.animationCurve,
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      dragStartBehavior: DragStartBehavior.down,
      onHorizontalDragStart: (_) {
        _dragDx = 0;
        _handled = false;
      },
      onHorizontalDragUpdate: (details) {
        _dragDx += details.delta.dx;
        _maybeSwitch();
      },
      onHorizontalDragEnd: (details) {
        _maybeSwitch(velocityX: details.primaryVelocity ?? 0);
        _reset();
      },
      onHorizontalDragCancel: _reset,
      child: widget.child,
    );
  }
}
