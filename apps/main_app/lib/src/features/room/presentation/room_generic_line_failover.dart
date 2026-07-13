import 'package:live_core/live_core.dart';
import 'package:live_player/live_player.dart';

/// Tracks multi-line failover state for non–site-specialized providers.
///
/// Twitch / Chaturbate / Stripchat keep their specialized recovery paths;
/// this controller is for ordinary multi-URL domestic live playlists.
///
/// Important: [ensureSession] must be used across repeated unexpected stops so
/// retry/line counters are preserved. Only a changed play-URL set resets state.
class RoomGenericLineFailoverController {
  RoomGenericLineFailoverController({
    this.policy = const PlaybackFailoverPolicy(),
  });

  final PlaybackFailoverPolicy policy;

  List<LivePlayUrl> _lines = const [];
  int _lineIndex = 0;
  int _retryCount = 0;
  String _sessionSignature = '';
  PlaybackSource? Function(LivePlayUrl line)? _sourceBuilder;

  int get lineIndex => _lineIndex;
  int get retryCount => _retryCount;
  List<LivePlayUrl> get lines => _lines;
  String get sessionSignature => _sessionSignature;

  static String signatureFor(List<LivePlayUrl> playUrls) {
    return playUrls.map((line) => line.url).join('\u0001');
  }

  /// Full hard reset (new quality / new room playlist).
  void reset({
    required List<LivePlayUrl> playUrls,
    PlaybackSource? Function(LivePlayUrl line)? sourceBuilder,
    PlaybackSource? currentSource,
  }) {
    _lines = List<LivePlayUrl>.from(playUrls);
    _sessionSignature = signatureFor(_lines);
    _sourceBuilder = sourceBuilder;
    _retryCount = 0;
    _lineIndex = 0;
    if (currentSource != null && _lines.isNotEmpty) {
      final match = _lines.indexWhere(
        (line) => line.url.toString() == currentSource.url.toString(),
      );
      if (match >= 0) {
        _lineIndex = match;
      }
    }
  }

  /// Keeps retry/line counters when the play-URL set is unchanged.
  ///
  /// Call this on every unexpected stop before [nextStep]. Only when the
  /// playlist signature changes (or was empty) does this re-seed counters.
  bool ensureSession({
    required List<LivePlayUrl> playUrls,
    PlaybackSource? Function(LivePlayUrl line)? sourceBuilder,
    PlaybackSource? currentSource,
  }) {
    final nextSignature = signatureFor(playUrls);
    _sourceBuilder = sourceBuilder;
    if (playUrls.isEmpty) {
      clear();
      return true;
    }
    if (_sessionSignature == nextSignature && _lines.isNotEmpty) {
      // Same playlist: preserve _retryCount / _lineIndex across stops.
      return false;
    }
    reset(
      playUrls: playUrls,
      sourceBuilder: sourceBuilder,
      currentSource: currentSource,
    );
    return true;
  }

  void clear() {
    _lines = const [];
    _lineIndex = 0;
    _retryCount = 0;
    _sessionSignature = '';
    _sourceBuilder = null;
  }

  bool get canHandle => _lines.isNotEmpty;

  /// Returns the next action for an unexpected stop/error.
  RoomGenericLineFailoverStep? nextStep() {
    if (_lines.isEmpty) {
      return null;
    }
    final decision = policy.decide(
      currentLineIndex: _lineIndex,
      lineCount: _lines.length,
      retryCountOnCurrentLine: _retryCount,
    );
    switch (decision.action) {
      case PlaybackFailoverAction.retryCurrentLine:
        _retryCount = decision.nextRetryCount;
        _lineIndex = decision.nextLineIndex;
        final line = _lines[_lineIndex];
        return RoomGenericLineFailoverStep(
          action: decision.action,
          lineIndex: _lineIndex,
          retryCount: _retryCount,
          delay: decision.delay,
          line: line,
          playbackSource: _sourceBuilder?.call(line),
        );
      case PlaybackFailoverAction.switchToNextLine:
        _retryCount = 0;
        _lineIndex = decision.nextLineIndex;
        final line = _lines[_lineIndex];
        return RoomGenericLineFailoverStep(
          action: decision.action,
          lineIndex: _lineIndex,
          retryCount: _retryCount,
          delay: decision.delay,
          line: line,
          playbackSource: _sourceBuilder?.call(line),
        );
      case PlaybackFailoverAction.terminalFailure:
        return RoomGenericLineFailoverStep(
          action: decision.action,
          lineIndex: _lineIndex,
          retryCount: _retryCount,
          delay: Duration.zero,
          line: _lines[_lineIndex],
          playbackSource: null,
        );
    }
  }
}

class RoomGenericLineFailoverStep {
  const RoomGenericLineFailoverStep({
    required this.action,
    required this.lineIndex,
    required this.retryCount,
    required this.delay,
    required this.line,
    required this.playbackSource,
  });

  final PlaybackFailoverAction action;
  final int lineIndex;
  final int retryCount;
  final Duration delay;
  final LivePlayUrl line;
  final PlaybackSource? playbackSource;
}

/// Providers that already own specialized recovery and should not use generic
/// multi-line failover.
bool shouldUseGenericMultiLineFailover(ProviderId providerId) {
  return providerId != ProviderId.twitch &&
      providerId != ProviderId.chaturbate &&
      providerId != ProviderId.stripchat;
}
