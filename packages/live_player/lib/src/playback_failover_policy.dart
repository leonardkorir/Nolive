/// Generic multi-line live failover:
/// retry current line → advance to next line → terminal failure.
enum PlaybackFailoverAction {
  retryCurrentLine,
  switchToNextLine,
  terminalFailure,
}

class PlaybackFailoverDecision {
  const PlaybackFailoverDecision({
    required this.action,
    required this.nextRetryCount,
    required this.nextLineIndex,
    this.delay = Duration.zero,
  });

  final PlaybackFailoverAction action;
  final int nextRetryCount;
  final int nextLineIndex;
  final Duration delay;
}

class PlaybackFailoverPolicy {
  const PlaybackFailoverPolicy({
    this.maxRetriesPerLine = 2,
    this.retryDelay = const Duration(seconds: 1),
  });

  final int maxRetriesPerLine;
  final Duration retryDelay;

  /// [lineCount] must be > 0. [currentLineIndex] is 0-based.
  /// [retryCountOnCurrentLine] is how many retries already attempted.
  PlaybackFailoverDecision decide({
    required int currentLineIndex,
    required int lineCount,
    required int retryCountOnCurrentLine,
  }) {
    assert(lineCount > 0);
    final clampedIndex = currentLineIndex.clamp(0, lineCount - 1);

    if (retryCountOnCurrentLine < maxRetriesPerLine) {
      final nextRetry = retryCountOnCurrentLine + 1;
      return PlaybackFailoverDecision(
        action: PlaybackFailoverAction.retryCurrentLine,
        nextRetryCount: nextRetry,
        nextLineIndex: clampedIndex,
        delay: nextRetry > 1 ? retryDelay : Duration.zero,
      );
    }

    final nextLine = clampedIndex + 1;
    if (nextLine < lineCount) {
      return PlaybackFailoverDecision(
        action: PlaybackFailoverAction.switchToNextLine,
        nextRetryCount: 0,
        nextLineIndex: nextLine,
      );
    }

    return PlaybackFailoverDecision(
      action: PlaybackFailoverAction.terminalFailure,
      nextRetryCount: retryCountOnCurrentLine,
      nextLineIndex: clampedIndex,
    );
  }
}
