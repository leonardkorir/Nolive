import 'package:flutter/material.dart';
import 'package:nolive_app/src/shared/presentation/gestures/responsive_page_swipe_physics.dart';

import 'room_panel_controller.dart';
import 'room_preview_page_section_widgets.dart';

class RoomPanelPager extends StatelessWidget {
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
                  selected: selectedPanel == RoomPanel.chat,
                  onTap: () => onSelectPanel(RoomPanel.chat),
                ),
              ),
              Expanded(
                child: RoomPanelTab(
                  key: const Key('room-panel-tab-super-chat'),
                  label: 'SC',
                  selected: selectedPanel == RoomPanel.superChat,
                  onTap: () => onSelectPanel(RoomPanel.superChat),
                ),
              ),
              Expanded(
                child: RoomPanelTab(
                  key: const Key('room-panel-tab-follow'),
                  label: '关注',
                  selected: selectedPanel == RoomPanel.follow,
                  onTap: () => onSelectPanel(RoomPanel.follow),
                ),
              ),
              Expanded(
                child: RoomPanelTab(
                  key: const Key('room-panel-tab-settings'),
                  label: '设置',
                  selected: selectedPanel == RoomPanel.settings,
                  onTap: () => onSelectPanel(RoomPanel.settings),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: PageView(
            key: const Key('room-panel-page-view'),
            controller: pageController,
            physics: const ResponsivePageSwipePhysics(),
            onPageChanged: onPageChanged,
            children: children,
          ),
        ),
      ],
    );
  }
}
