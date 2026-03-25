import 'package:live_core/live_core.dart';
import 'package:live_player/live_player.dart';

const Duration kTwitchRecoveryProgressThreshold = Duration(milliseconds: 1500);
const Duration kTwitchPromotionPositionThreshold = Duration(milliseconds: 1200);
const Duration kTwitchPromotionBufferThreshold = Duration(seconds: 3);
const Duration kTwitchStartupFixedRetryDelay = Duration(seconds: 2);
const Duration kTwitchStartupInitialAutoRetryDelay = Duration(seconds: 2);
const Duration kTwitchStartupFollowupAutoRetryDelay = Duration(seconds: 2);

enum TwitchFixedRecoveryAction {
  none,
  switchLine,
  refreshCurrentLine,
  stop,
}

class TwitchFixedRecoveryDecision {
  const TwitchFixedRecoveryDecision({
    required this.action,
    this.recoveryLine,
  });

  final TwitchFixedRecoveryAction action;
  final LivePlayUrl? recoveryLine;
}

class TwitchStartupPlan {
  const TwitchStartupPlan({
    required this.startupQuality,
    this.promotionQuality,
  });

  final LivePlayQuality startupQuality;
  final LivePlayQuality? promotionQuality;
}

TwitchStartupPlan resolveTwitchStartupPlan({
  required List<LivePlayQuality> qualities,
  required LivePlayQuality requestedQuality,
}) {
  LivePlayQuality? autoQuality;
  for (final item in qualities) {
    if (item.id == 'auto') {
      autoQuality = item;
      break;
    }
  }
  if (autoQuality == null || requestedQuality.id == 'auto') {
    return TwitchStartupPlan(startupQuality: requestedQuality);
  }
  return TwitchStartupPlan(
    startupQuality: LivePlayQuality(
      id: autoQuality.id,
      label: autoQuality.label,
      isDefault: autoQuality.isDefault,
      sortOrder: autoQuality.sortOrder,
      metadata: {
        ...?autoQuality.metadata,
        'twitchStartupAuto': true,
      },
    ),
    promotionQuality: requestedQuality,
  );
}

bool shouldAttemptTwitchPlaybackRecovery(
  PlayerState state, {
  Duration progressThreshold = kTwitchRecoveryProgressThreshold,
}) {
  if (state.status == PlaybackStatus.error ||
      state.status == PlaybackStatus.completed ||
      state.source == null) {
    return false;
  }
  return state.position < progressThreshold &&
      state.buffered < progressThreshold;
}

bool shouldPromoteTwitchPlaybackQuality(
  PlayerState state, {
  Duration positionThreshold = kTwitchPromotionPositionThreshold,
  Duration bufferThreshold = kTwitchPromotionBufferThreshold,
}) {
  if (state.source == null) {
    return false;
  }
  return state.position >= positionThreshold ||
      state.buffered >= bufferThreshold;
}

Duration resolveTwitchRecoveryDelay({
  required LivePlayQuality currentQuality,
  required int recoveryAttempts,
}) {
  if (currentQuality.id == 'auto') {
    return recoveryAttempts == 0
        ? kTwitchStartupInitialAutoRetryDelay
        : kTwitchStartupFollowupAutoRetryDelay;
  }
  return kTwitchStartupFixedRetryDelay;
}

LivePlayQuality? selectTwitchStartupRecoveryQuality({
  required LivePlayQuality currentQuality,
  required LivePlayQuality? promotionQuality,
}) {
  if (currentQuality.id != 'auto') {
    return null;
  }
  return promotionQuality;
}

LivePlayQuality? selectTwitchRecoveryQuality({
  required List<LivePlayQuality> qualities,
  required LivePlayQuality currentQuality,
}) {
  return null;
}

TwitchFixedRecoveryDecision resolveTwitchFixedRecoveryDecision({
  required PlayerState state,
  required int recoveryAttempts,
  required PlaybackSource playbackSource,
  required List<LivePlayUrl> playUrls,
}) {
  if (!shouldAttemptTwitchPlaybackRecovery(state)) {
    return const TwitchFixedRecoveryDecision(
      action: TwitchFixedRecoveryAction.none,
    );
  }
  final recoveryLine = selectTwitchRecoveryLine(
    playbackSource: playbackSource,
    playUrls: playUrls,
  );
  if (recoveryAttempts == 0 && recoveryLine != null) {
    return TwitchFixedRecoveryDecision(
      action: TwitchFixedRecoveryAction.switchLine,
      recoveryLine: recoveryLine,
    );
  }
  if (recoveryAttempts == 1) {
    return const TwitchFixedRecoveryDecision(
      action: TwitchFixedRecoveryAction.refreshCurrentLine,
    );
  }
  return const TwitchFixedRecoveryDecision(
    action: TwitchFixedRecoveryAction.stop,
  );
}

LivePlayUrl? selectTwitchRecoveryLine({
  required PlaybackSource playbackSource,
  required List<LivePlayUrl> playUrls,
}) {
  if (playUrls.length < 2) {
    return null;
  }
  final currentUrl = playbackSource.url.toString();
  final currentLine = playUrls.firstWhere(
    (item) => item.url == currentUrl,
    orElse: () => playUrls.first,
  );
  final currentType = currentLine.metadata?['playerType']?.toString().trim();
  if (currentType == 'popout') {
    final siteFallback = playUrls.where((item) {
      return item.url != currentUrl &&
          item.metadata?['playerType']?.toString().trim() == 'site';
    });
    if (siteFallback.isNotEmpty) {
      return siteFallback.first;
    }
  }
  for (final item in playUrls) {
    if (item.url != currentUrl) {
      return item;
    }
  }
  return null;
}

LivePlayUrl? selectTwitchRefreshLine({
  required PlaybackSource playbackSource,
  required List<LivePlayUrl> currentPlayUrls,
  required List<LivePlayUrl> refreshedPlayUrls,
}) {
  if (currentPlayUrls.isEmpty || refreshedPlayUrls.isEmpty) {
    return null;
  }
  final currentLine = currentPlayUrls.firstWhere(
    (item) => item.url == playbackSource.url.toString(),
    orElse: () => currentPlayUrls.first,
  );
  final upstreamUrl = currentLine.metadata?['upstreamUrl']?.toString().trim();
  if (upstreamUrl?.isNotEmpty == true) {
    for (final item in refreshedPlayUrls) {
      if (item.metadata?['upstreamUrl']?.toString().trim() == upstreamUrl) {
        return item;
      }
    }
  }
  final playerType = currentLine.metadata?['playerType']?.toString().trim();
  if (playerType?.isNotEmpty == true) {
    for (final item in refreshedPlayUrls) {
      if (item.metadata?['playerType']?.toString().trim() == playerType) {
        return item;
      }
    }
  }
  final lineLabel = currentLine.lineLabel?.trim();
  if (lineLabel?.isNotEmpty == true) {
    for (final item in refreshedPlayUrls) {
      if (item.lineLabel?.trim() == lineLabel) {
        return item;
      }
    }
  }
  return null;
}
