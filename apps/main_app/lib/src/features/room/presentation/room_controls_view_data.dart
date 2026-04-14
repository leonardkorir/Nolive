class RoomControlsViewData {
  const RoomControlsViewData({
    required this.hasPlayback,
    required this.playbackUnavailableReason,
    required this.requestedQualityLabel,
    required this.effectiveQualityLabel,
    required this.currentLineLabel,
    required this.scaleModeLabel,
    required this.pipSupported,
    required this.supportsDesktopMiniWindow,
    required this.desktopMiniWindowActive,
    required this.supportsPlayerCapture,
    required this.scheduledCloseAt,
    required this.chatTextSize,
    required this.chatTextGap,
    required this.chatBubbleStyle,
    required this.showPlayerSuperChat,
    required this.playerSuperChatDisplaySeconds,
  });

  final bool hasPlayback;
  final String playbackUnavailableReason;
  final String requestedQualityLabel;
  final String effectiveQualityLabel;
  final String currentLineLabel;
  final String scaleModeLabel;
  final bool pipSupported;
  final bool supportsDesktopMiniWindow;
  final bool desktopMiniWindowActive;
  final bool supportsPlayerCapture;
  final DateTime? scheduledCloseAt;
  final int chatTextSize;
  final int chatTextGap;
  final bool chatBubbleStyle;
  final bool showPlayerSuperChat;
  final int playerSuperChatDisplaySeconds;
}

class RoomPlayerDebugViewData {
  const RoomPlayerDebugViewData({
    required this.backendLabel,
    required this.currentStatusLabel,
    required this.requestedQualityLabel,
    required this.effectiveQualityLabel,
    required this.currentLineLabel,
    required this.scaleModeLabel,
    required this.usingNativeDanmakuBatchMask,
  });

  final String backendLabel;
  final String currentStatusLabel;
  final String requestedQualityLabel;
  final String effectiveQualityLabel;
  final String currentLineLabel;
  final String scaleModeLabel;
  final bool usingNativeDanmakuBatchMask;
}
