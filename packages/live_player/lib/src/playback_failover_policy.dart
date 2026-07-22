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
  /// Soft stalls get a small same-line retry budget ([maxRetriesPerLine]).
  /// Hard open failures should pass [preferSwitchLine] so effective retries
  /// become 0 and the next CDN is tried immediately (device logs: Douyu
  /// `retryCurrentLine` on a dead hw3 URL while line 2 was never tried).
  const PlaybackFailoverPolicy({
    this.maxRetriesPerLine = 1,
    this.retryDelay = const Duration(seconds: 1),
  });

  final int maxRetriesPerLine;
  final Duration retryDelay;

  /// Prefer switch-first for hard open failures (`Failed to open`, TCP read
  /// errors). Soft stalls still use [maxRetriesPerLine] retries.
  ///
  /// Matcher is intentionally strict: bare `timeout` / path digits like
  /// `404` in a URL must not force hard-open recovery (zero debounce + full
  /// play reload).
  ///
  /// [hasReachedPlaying]: when true, pure mid-stream transport glitches
  /// (`ffurl_read`, bare connection reset) are **not** treated as hard-open so
  /// a brief TCP blip does not force immediate CDN switch. Explicit
  /// `Failed to open` and HTTP 403/404 stay hard regardless.
  static bool isHardOpenFailure(
    String? errorMessage, {
    bool hasReachedPlaying = false,
  }) {
    if (errorMessage == null || errorMessage.trim().isEmpty) {
      return false;
    }
    final n = errorMessage.toLowerCase();

    // Always hard: open failed before/at demuxer open.
    if (n.contains('failed to open')) {
      return true;
    }

    // HTTP status only when it looks like a status token, not a path fragment.
    if (RegExp(r'\b(http\s*)?(error\s*)?(status( code)?\s*)?404\b').hasMatch(n) ||
        RegExp(r'\b(http\s*)?(error\s*)?(status( code)?\s*)?403\b').hasMatch(n) ||
        RegExp(r'\bhttp\s+error\b').hasMatch(n)) {
      return true;
    }

    final hasOpenOrConnectWording = n.contains('open') ||
        n.contains('connect') ||
        n.contains('connection');

    // Pure mid-stream read glitches after first playing: soft path.
    if (hasReachedPlaying) {
      if (n.contains('ffurl_read') && !hasOpenOrConnectWording) {
        return false;
      }
      if ((n.contains('connection reset') ||
              n.contains('connection refused') ||
              n.contains('network is unreachable') ||
              n.contains('no route to host')) &&
          !n.contains('failed to open')) {
        // Mid-stream TCP blip — soft retry/switch with normal debounce.
        return false;
      }
    }

    if (n.contains('ffurl_read') ||
        n.contains('connection refused') ||
        n.contains('connection reset') ||
        n.contains('connection timed out') ||
        n.contains('connect timed out') ||
        n.contains('network is unreachable') ||
        n.contains('no route to host')) {
      return true;
    }

    // Open/connect timeouts only (not mid-stream "read timeout" alone).
    if ((n.contains('timed out') || n.contains('timeout')) &&
        (n.contains('open') ||
            n.contains('connect') ||
            n.contains('connection') ||
            n.contains('failed'))) {
      return true;
    }
    return false;
  }

  /// [lineCount] must be > 0. [currentLineIndex] is 0-based.
  /// [retryCountOnCurrentLine] is how many retries already attempted.
  ///
  /// When [preferSwitchLine] is true (hard open failure), skip same-line
  /// retries and advance immediately when another line exists. On the last
  /// line, soft and hard paths both go terminal once the effective retry
  /// budget is exhausted (no special last-line free retry for hard opens).
  PlaybackFailoverDecision decide({
    required int currentLineIndex,
    required int lineCount,
    required int retryCountOnCurrentLine,
    bool preferSwitchLine = false,
  }) {
    assert(lineCount > 0);
    final clampedIndex = currentLineIndex.clamp(0, lineCount - 1);
    final effectiveMaxRetries = preferSwitchLine ? 0 : maxRetriesPerLine;

    if (retryCountOnCurrentLine < effectiveMaxRetries) {
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
