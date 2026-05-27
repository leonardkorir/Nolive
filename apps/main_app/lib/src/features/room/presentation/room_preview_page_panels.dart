import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:nolive_app/src/shared/presentation/gestures/responsive_page_swipe_physics.dart';

import 'room_panel_controller.dart';
import 'room_preview_page_section_widgets.dart';

const double _panelSwipeVelocityThreshold = 80;
const double _panelSettleThresholdFraction = 0.12;

class RoomPanelPager extends StatefulWidget {
  const RoomPanelPager({
    required this.selectedPanel,
    required this.pageController,
    required this.onSelectPanel,
    required this.onPageChanged,
    required this.children,
    super.key,
  }) : assert(children.length == RoomPanel.values.length);

  final RoomPanel selectedPanel;
  final PageController pageController;
  final ValueChanged<RoomPanel> onSelectPanel;
  final ValueChanged<int> onPageChanged;
  final List<Widget> children;

  @override
  State<RoomPanelPager> createState() => _RoomPanelPagerState();
}

class _RoomPanelPagerState extends State<RoomPanelPager> {
  ScrollDirection _lastHorizontalUserScrollDirection = ScrollDirection.idle;
  double _horizontalDragOffset = 0;

  bool _handleUserScroll(UserScrollNotification notification) {
    if (notification.metrics.axis == Axis.horizontal &&
        notification.direction != ScrollDirection.idle) {
      _lastHorizontalUserScrollDirection = notification.direction;
    }
    return false;
  }

  void _handleHorizontalDragStart(DragStartDetails details) {
    _horizontalDragOffset = 0;
  }

  void _handleHorizontalDragUpdate(DragUpdateDetails details) {
    final pageController = widget.pageController;
    if (!pageController.hasClients) {
      return;
    }
    _horizontalDragOffset += details.delta.dx;
    _lastHorizontalUserScrollDirection = _horizontalDragOffset < 0
        ? ScrollDirection.reverse
        : ScrollDirection.forward;
    final position = pageController.position;
    final nextPixels = (position.pixels - details.delta.dx)
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    pageController.jumpTo(nextPixels);
  }

  void _handleHorizontalDragEnd(DragEndDetails details) {
    _settleHorizontalDrag(details.primaryVelocity ?? 0);
  }

  void _handleHorizontalDragCancel() {
    _settleHorizontalDrag(0);
  }

  void _settleHorizontalDrag(double gestureVelocity) {
    final pageController = widget.pageController;
    if (!pageController.hasClients) {
      return;
    }
    final page = pageController.page ?? widget.selectedPanel.index.toDouble();
    final scrollVelocity = -gestureVelocity;
    final targetPage = resolveResponsivePageTarget(
      page: page,
      velocity: scrollVelocity,
      velocityThreshold: _panelSwipeVelocityThreshold,
      settlePageThresholdFraction: _panelSettleThresholdFraction,
      direction: _lastHorizontalUserScrollDirection,
    ).round().clamp(0, widget.children.length - 1);
    unawaited(
      pageController.animateToPage(
        targetPage,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final surfaceColor = Theme.of(context).colorScheme.surface;
    return Column(
      children: [
        Material(
          color: surfaceColor,
          child: Row(
            children: [
              Expanded(
                child: RoomPanelTab(
                  key: const Key('room-panel-tab-chat'),
                  label: '聊天',
                  selected: widget.selectedPanel == RoomPanel.chat,
                  onTap: () => widget.onSelectPanel(RoomPanel.chat),
                ),
              ),
              Expanded(
                child: RoomPanelTab(
                  key: const Key('room-panel-tab-super-chat'),
                  label: 'SC',
                  selected: widget.selectedPanel == RoomPanel.superChat,
                  onTap: () => widget.onSelectPanel(RoomPanel.superChat),
                ),
              ),
              Expanded(
                child: RoomPanelTab(
                  key: const Key('room-panel-tab-follow'),
                  label: '关注',
                  selected: widget.selectedPanel == RoomPanel.follow,
                  onTap: () => widget.onSelectPanel(RoomPanel.follow),
                ),
              ),
              Expanded(
                child: RoomPanelTab(
                  key: const Key('room-panel-tab-settings'),
                  label: '设置',
                  selected: widget.selectedPanel == RoomPanel.settings,
                  onTap: () => widget.onSelectPanel(RoomPanel.settings),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            dragStartBehavior: DragStartBehavior.down,
            onHorizontalDragStart: _handleHorizontalDragStart,
            onHorizontalDragUpdate: _handleHorizontalDragUpdate,
            onHorizontalDragEnd: _handleHorizontalDragEnd,
            onHorizontalDragCancel: _handleHorizontalDragCancel,
            child: NotificationListener<UserScrollNotification>(
              onNotification: _handleUserScroll,
              child: PageView(
                key: const Key('room-panel-page-view'),
                controller: widget.pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: widget.onPageChanged,
                children: widget.children,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
