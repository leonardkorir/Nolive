import 'dart:async';

import 'package:live_core/live_core.dart';
import 'package:live_player/live_player.dart';
import 'package:nolive_app/src/features/room/application/room_generic_line_failover.dart';
import 'package:nolive_app/src/features/room/application/room_playback_session_state.dart';
import 'package:nolive_app/src/features/room/application/resolve_play_source_use_case.dart';

typedef RoomFailoverBindSource =
    Future<bool> Function({
      required PlaybackSource playbackSource,
      required String label,
      required bool autoPlay,
      PlaybackSource? currentPlaybackSource,
    });

typedef RoomFailoverRefreshRoom =
    Future<void> Function({
      required bool showFeedback,
      required bool reloadPlayer,
      required bool forcePlaybackRebind,
    });

/// Drives multi-line CDN failover and the terminal play-source reload budget.
///
/// This ran inside `_RoomPreviewPageState` as ~170 lines of async orchestration
/// reaching into four controllers, so the rules could only be exercised by
/// mounting the whole room page. Everything the loop needs is a callback here,
/// including [delay], so the escalation ladder can be driven in a plain test.
class RoomPlaybackFailoverCoordinator {
  RoomPlaybackFailoverCoordinator({
    required this.resolveProviderId,
    required this.resolveRoomId,
    required this.resolvePlaybackSession,
    required this.isActive,
    required this.isLeavingRoom,
    required this.isRefreshInFlight,
    required this.isRebindInFlight,
    required this.bindPlaybackSource,
    required this.refreshRoom,
    required this.trace,
    Future<void> Function(Duration duration)? delay,
    RoomGenericLineFailoverController? lineFailover,
    RoomTerminalPlayReloadBudget? terminalReloadBudget,
  }) : _delay = delay ?? _defaultDelay,
       _lineFailover = lineFailover ?? RoomGenericLineFailoverController(),
       _terminalReloadBudget =
           terminalReloadBudget ?? RoomTerminalPlayReloadBudget();

  final ProviderId Function() resolveProviderId;
  final String Function() resolveRoomId;
  final RoomPlaybackSessionState Function() resolvePlaybackSession;

  /// False once the page is gone; every await point re-checks it.
  final bool Function() isActive;
  final bool Function() isLeavingRoom;
  final bool Function() isRefreshInFlight;
  final bool Function() isRebindInFlight;
  final RoomFailoverBindSource bindPlaybackSource;
  final RoomFailoverRefreshRoom refreshRoom;
  final void Function(String message) trace;

  final Future<void> Function(Duration duration) _delay;
  final RoomGenericLineFailoverController _lineFailover;
  final RoomTerminalPlayReloadBudget _terminalReloadBudget;

  String? _terminalReloadRoomKey;
  bool _hasReachedPlaying = false;

  /// True while [handleUnexpectedPlaybackStop] is between entry and return.
  ///
  /// Stops can fire again during a delay or bind await; without this guard a
  /// second ladder walks the same lines and can double-spend the terminal
  /// reload budget.
  bool _handlingUnexpectedStop = false;

  static Future<void> _defaultDelay(Duration duration) {
    return Future<void>.delayed(duration);
  }

  /// True after this room/source reached [PlaybackStatus.playing] at least
  /// once, so mid-stream TCP glitches are not treated as a hard open failure.
  bool get hasReachedPlaying => _hasReachedPlaying;

  /// Feed player state transitions so the terminal budget only resets after
  /// continuous healthy playback, never after a failed reload.
  ///
  /// Registering the room key has to happen *before* the flag is raised: the
  /// page used to do it the other way round, so the first `playing` tick of a
  /// room set the flag and then immediately cleared it as part of registering
  /// that room. The flag only stuck from the second tick onward.
  void notePlaying({required bool isPlaying}) {
    if (isPlaying) {
      _ensureTerminalBudgetForActiveRoom();
      _hasReachedPlaying = true;
    }
    _terminalReloadBudget.notePlaying(isPlaying: isPlaying);
  }

  Future<void> handleUnexpectedPlaybackStop(PlayerState state) async {
    if (isLeavingRoom() || isRebindInFlight() || isRefreshInFlight()) {
      return;
    }
    if (_handlingUnexpectedStop) {
      trace(
        'generic multi-line failover skip overlapping stop '
        'while a ladder is already in flight',
      );
      return;
    }
    _handlingUnexpectedStop = true;
    try {
      await _handleUnexpectedPlaybackStopBody(state);
    } finally {
      _handlingUnexpectedStop = false;
    }
  }

  Future<void> _handleUnexpectedPlaybackStopBody(PlayerState state) async {
    final providerId = resolveProviderId();
    _ensureTerminalBudgetForActiveRoom();
    // ensureSession (not reset): preserve retry/line across repeated stops.
    _syncFailoverState(currentSource: state.source);
    final hardOpen = PlaybackFailoverPolicy.isHardOpenFailure(
      state.errorMessage,
      hasReachedPlaying: _hasReachedPlaying,
    );
    if (shouldUseGenericMultiLineFailover(providerId) &&
        _lineFailover.canHandle) {
      // Loop lines until bind succeeds or terminal — bind false is not
      // "all CDNs exhausted" and must not jump to full play-source reload.
      while (_lineFailover.canHandle) {
        final step = _lineFailover.nextStep(errorMessage: state.errorMessage);
        if (step == null) {
          break;
        }
        if (step.action == PlaybackFailoverAction.terminalFailure) {
          await _reloadPlaySourcesAfterTerminal(
            hardOpen: hardOpen,
            lineIndex: step.lineIndex,
          );
          return;
        }
        if (step.playbackSource == null) {
          continue;
        }
        trace(
          'generic multi-line failover action=${step.action.name} '
          'line=${step.lineIndex + 1}/${_lineFailover.lines.length} '
          'retry=${step.retryCount} '
          'hardOpen=$hardOpen',
        );
        if (step.delay > Duration.zero) {
          await _delay(step.delay);
        }
        if (!isActive() || isLeavingRoom() || isRefreshInFlight()) {
          return;
        }
        final bound = await bindPlaybackSource(
          playbackSource: step.playbackSource!,
          label: 'generic multi-line failover',
          autoPlay: true,
          currentPlaybackSource: state.source,
        );
        if (bound) {
          return;
        }
        trace(
          'generic multi-line failover bind failed '
          'line=${step.lineIndex + 1} — try next line',
        );
      }
    }
    if (hardOpen) {
      await _reloadPlaySourcesAfterTerminal(hardOpen: true);
      return;
    }
    await refreshRoom(
      showFeedback: false,
      reloadPlayer: false,
      forcePlaybackRebind: true,
    );
  }

  void _syncFailoverState({PlaybackSource? currentSource}) {
    final providerId = resolveProviderId();
    if (!shouldUseGenericMultiLineFailover(providerId)) {
      _lineFailover.clear();
      return;
    }
    final session = resolvePlaybackSession();
    final urls = session.playUrls;
    if (urls.isEmpty) {
      _lineFailover.clear();
      return;
    }
    _lineFailover.ensureSession(
      playUrls: urls,
      currentSource: currentSource ?? session.playbackSource,
      sourceBuilder: (line) {
        return playbackSourceFromLivePlayUrl(
          line,
          quality: session.effectiveQuality ?? session.selectedQuality,
          providerId: providerId,
        );
      },
    );
    // Terminal reload budget resets only on successful playing (see
    // notePlaying) so a failed reloadRoom cannot clear the cap.
  }

  void _ensureTerminalBudgetForActiveRoom() {
    final key = '${resolveProviderId().value}/${resolveRoomId()}';
    if (_terminalReloadRoomKey == key) {
      return;
    }
    _terminalReloadRoomKey = key;
    _terminalReloadBudget.reset();
    _hasReachedPlaying = false;
  }

  /// Full play-URL re-fetch after multi-line terminal (or hard-open
  /// fallthrough).
  ///
  /// Budget + growing delay prevent tight loops when every CDN is dead. The
  /// slot is spent only after preconditions still pass post-delay; an abort
  /// refunds it.
  Future<void> _reloadPlaySourcesAfterTerminal({
    required bool hardOpen,
    int? lineIndex,
  }) async {
    final delay = _terminalReloadBudget.peekDelay();
    if (delay == null) {
      trace(
        'generic multi-line failover terminal budget exhausted '
        'used=${_terminalReloadBudget.used} hardOpen=$hardOpen — stop',
      );
      return;
    }
    trace(
      'generic multi-line failover terminal '
      '${lineIndex == null ? '' : 'line=${lineIndex + 1}/${_lineFailover.lines.length} '}'
      'hardOpen=$hardOpen used=${_terminalReloadBudget.used} '
      'delayMs=${delay.inMilliseconds} — waiting before reload',
    );
    if (delay > Duration.zero) {
      await _delay(delay);
    }
    if (!isActive() || isLeavingRoom() || isRefreshInFlight()) {
      trace(
        'generic multi-line failover terminal reload aborted '
        'after delay (active=${isActive()} leaving=${isLeavingRoom()} '
        'refreshInFlight=${isRefreshInFlight()}) — no budget spend',
      );
      return;
    }
    final spent = _terminalReloadBudget.consume();
    if (spent == null) {
      trace(
        'generic multi-line failover terminal budget exhausted after delay '
        'hardOpen=$hardOpen — stop',
      );
      return;
    }
    trace(
      'generic multi-line failover terminal reload '
      'reload=${_terminalReloadBudget.used} hardOpen=$hardOpen',
    );
    _lineFailover.clear();
    await refreshRoom(
      showFeedback: false,
      reloadPlayer: true,
      forcePlaybackRebind: true,
    );
  }
}
