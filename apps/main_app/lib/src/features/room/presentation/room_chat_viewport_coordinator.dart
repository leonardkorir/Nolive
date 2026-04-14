import 'package:flutter/widgets.dart';
import 'package:nolive_app/src/features/room/presentation/room_panel_controller.dart';

class RoomChatViewportCoordinator {
  RoomChatViewportCoordinator() : controller = ScrollController();

  final ScrollController controller;

  bool _disposed = false;
  bool _scrollQueued = false;
  bool _pendingForceScroll = false;

  void handleMessagesChanged({
    required RoomPanel selectedPanel,
  }) {
    if (selectedPanel != RoomPanel.chat) {
      return;
    }
    scrollToBottom();
  }

  void scrollToBottom({bool force = false}) {
    if (_disposed) {
      return;
    }
    _pendingForceScroll = _pendingForceScroll || force;
    if (_scrollQueued) {
      return;
    }
    _scrollQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollQueued = false;
      final shouldForceScroll = _pendingForceScroll;
      _pendingForceScroll = false;
      if (_disposed || !controller.hasClients) {
        return;
      }
      final position = controller.position;
      if (!shouldForceScroll &&
          position.maxScrollExtent - position.pixels > 120) {
        return;
      }
      controller.jumpTo(position.maxScrollExtent);
    });
  }

  void dispose() {
    _disposed = true;
    controller.dispose();
  }
}
