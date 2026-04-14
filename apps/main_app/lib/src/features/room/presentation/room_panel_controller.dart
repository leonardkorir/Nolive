import 'dart:async';

import 'package:flutter/widgets.dart';

enum RoomPanel {
  chat,
  superChat,
  follow,
  settings,
}

@visibleForTesting
bool shouldSynchronizeRoomPanelPage({
  required int selectedPanelIndex,
  required double? controllerPage,
  required bool isScrollInProgress,
}) {
  if (isScrollInProgress) {
    return false;
  }
  if (controllerPage == null) {
    return true;
  }
  return (controllerPage - selectedPanelIndex).abs() > 0.01;
}

class RoomPanelController extends ChangeNotifier {
  RoomPanelController({
    required PageController pageController,
    required this.onEnterChatPanel,
    required this.onEnterFollowPanel,
  }) : _pageController = pageController;

  final PageController _pageController;
  final VoidCallback onEnterChatPanel;
  final VoidCallback onEnterFollowPanel;

  RoomPanel _selectedPanel = RoomPanel.chat;
  bool _pageSyncScheduled = false;
  bool _disposed = false;

  RoomPanel get selectedPanel => _selectedPanel;

  void selectPanel(RoomPanel panel) {
    if (_selectedPanel == panel) {
      return;
    }
    _selectedPanel = panel;
    notifyListeners();
    if (_pageController.hasClients) {
      unawaited(
        _pageController.animateToPage(
          panel.index,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        ),
      );
    } else {
      schedulePageSync();
    }
    _triggerPanelSideEffects(panel);
  }

  void handlePageChanged(int index) {
    if (_disposed) {
      return;
    }
    final nextPanel = RoomPanel.values[index];
    if (_selectedPanel == nextPanel) {
      return;
    }
    _selectedPanel = nextPanel;
    notifyListeners();
    _triggerPanelSideEffects(nextPanel);
  }

  void schedulePageSync() {
    if (_pageSyncScheduled || _disposed) {
      return;
    }
    _pageSyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pageSyncScheduled = false;
      if (_disposed || !_pageController.hasClients) {
        return;
      }
      final position = _pageController.position;
      if (!shouldSynchronizeRoomPanelPage(
        selectedPanelIndex: _selectedPanel.index,
        controllerPage: _pageController.page,
        isScrollInProgress: position.isScrollingNotifier.value,
      )) {
        return;
      }
      _pageController.jumpToPage(_selectedPanel.index);
    });
  }

  void _triggerPanelSideEffects(RoomPanel panel) {
    switch (panel) {
      case RoomPanel.chat:
        onEnterChatPanel();
      case RoomPanel.follow:
        onEnterFollowPanel();
      case RoomPanel.superChat:
      case RoomPanel.settings:
        break;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
