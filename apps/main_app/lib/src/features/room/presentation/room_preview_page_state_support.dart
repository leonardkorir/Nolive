part of 'room_preview_page.dart';

enum _RoomPanel {
  chat,
  superChat,
  follow,
  settings,
}

class _RoomPageState {
  const _RoomPageState({
    required this.snapshot,
    required this.resolved,
    required this.preferences,
  });

  final LoadedRoomSnapshot snapshot;
  final ResolvedPlaySource? resolved;
  final PlayerPreferences preferences;
}

class _ChaturbateRoomStatusPresentation {
  const _ChaturbateRoomStatusPresentation({
    required this.label,
    required this.description,
  });

  final String label;
  final String description;
}

extension _RoomPreviewPageStateSupport on _RoomPreviewPageState {
  FollowWatchlist? get _runtimeFollowWatchlistSnapshot =>
      widget.bootstrap.followWatchlistSnapshot.value;

  RoomUiPreferences get _roomUiPreferences => RoomUiPreferences(
        chatTextSize: _chatTextSize,
        chatTextGap: _chatTextGap,
        chatBubbleStyle: _chatBubbleStyle,
        showPlayerSuperChat: _showPlayerSuperChat,
        playerSuperChatDisplaySeconds: _playerSuperChatDisplaySeconds,
      );

  void _handleFollowWatchlistSnapshotChanged() {
    if (!mounted) {
      return;
    }
    _updateViewState(() {
      _followWatchlistCache = _runtimeFollowWatchlistSnapshot;
      _followWatchlistHydrated = _runtimeFollowWatchlistSnapshot != null;
    });
  }

  void _selectPanel(_RoomPanel panel) {
    if (_selectedPanel == panel) {
      return;
    }
    _updateViewState(() {
      _selectedPanel = panel;
    });
    if (_panelPageController.hasClients) {
      unawaited(
        _panelPageController.animateToPage(
          panel.index,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        ),
      );
    }
    if (panel == _RoomPanel.chat) {
      _scheduleChatScrollToBottom(force: true);
    }
    if (panel == _RoomPanel.follow) {
      unawaited(_ensureFollowWatchlistLoaded());
    }
  }

  void _handlePanelPageChanged(int index) {
    final nextPanel = _RoomPanel.values[index];
    if (_selectedPanel == nextPanel || !mounted) {
      return;
    }
    _updateViewState(() {
      _selectedPanel = nextPanel;
    });
    if (nextPanel == _RoomPanel.chat) {
      _scheduleChatScrollToBottom(force: true);
    }
    if (nextPanel == _RoomPanel.follow) {
      unawaited(_ensureFollowWatchlistLoaded());
    }
  }

  BoxFit _fitForScaleMode() {
    return switch (_scaleMode) {
      PlayerScaleMode.contain => BoxFit.contain,
      PlayerScaleMode.cover => BoxFit.cover,
      PlayerScaleMode.fill => BoxFit.fill,
      PlayerScaleMode.fitWidth => BoxFit.fitWidth,
      PlayerScaleMode.fitHeight => BoxFit.fitHeight,
    };
  }
}
