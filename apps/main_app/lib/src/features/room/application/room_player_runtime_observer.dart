import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:live_core/live_core.dart';
import 'package:live_player/live_player.dart';
import 'package:nolive_app/src/features/room/application/room_page_rebuild_scope.dart';
import 'package:nolive_app/src/features/room/application/room_runtime_helper_contexts.dart';
import 'package:nolive_app/src/shared/application/app_log.dart';

String formatPlayerDiagnosticsSummary({
  required PlayerDiagnostics diagnostics,
  required PlaybackSource source,
}) {
  final width =
      diagnostics.width ?? int.tryParse(diagnostics.videoParams['width'] ?? '');
  final height =
      diagnostics.height ??
      int.tryParse(diagnostics.videoParams['height'] ?? '');
  final frameRate = diagnostics.videoParams['frame_rate'] ?? '-';
  final decoder = diagnostics.videoParams['codec'] ?? '-';
  final lastRebufferMs = diagnostics.lastRebufferDuration?.inMilliseconds;
  return 'player diagnostics '
      'backend=${diagnostics.backend.name} '
      'decoder=$decoder '
      'size=${width ?? '-'}x${height ?? '-'} '
      'frameRate=$frameRate '
      'bufferProfile=${source.bufferProfile.name} '
      'rebufferCount=${diagnostics.rebufferCount} '
      'lastRebufferMs=${lastRebufferMs ?? '-'}';
}

String? resolvePlayerDiagnosticsSourceSignature(PlaybackSource? source) {
  if (source == null) {
    return null;
  }
  return [
    source.url.toString(),
    source.externalAudio?.url.toString() ?? '',
    source.bufferProfile.name,
  ].join('|');
}

String summarizeRoomPlaybackSource(PlaybackSource? source) {
  final url = source?.url;
  if (url == null) {
    return '-';
  }
  final audio = source?.externalAudio?.url;
  final base = '${url.host}${url.path}';
  if (audio == null) {
    return base;
  }
  return '$base + audio=${audio.host}${audio.path}';
}

typedef RoomPlayerRuntimeStateCallback =
    void Function(
      PlayerState state, {
      required bool playbackAvailable,
      bool forceRebuild,
    });
typedef RoomPlayerUnexpectedStopCallback =
    Future<void> Function(PlayerState state);
typedef RoomPlayerShouldRecoverUnexpectedStop =
    bool Function(PlayerState state);

bool _defaultFalse() => false;
bool _defaultTrue(PlayerState _) => true;

Future<void> _noopUnexpectedStopRecovery(PlayerState state) async {}

class RoomPlayerRuntimeObserverContext {
  const RoomPlayerRuntimeObserverContext({
    required this.providerId,
    required this.roomId,
    required this.runtime,
    required this.trace,
    required this.resolvePlaybackAvailable,
    required this.onPlayerStateChanged,
    this.resolveIsLeavingRoom = _defaultFalse,
    this.resolvePlaybackRebindInFlight = _defaultFalse,
    this.shouldRecoverUnexpectedStop = _defaultTrue,
    this.onUnexpectedPlaybackStop = _noopUnexpectedStopRecovery,
    this.unexpectedStopRecoveryDelay = const Duration(seconds: 2),
    this.resolveUnexpectedStopRecoveryDelay,
  });

  final ProviderId providerId;
  final String roomId;
  final RoomRuntimeObservationContext runtime;
  final void Function(String message) trace;
  final bool Function() resolvePlaybackAvailable;
  final RoomPlayerRuntimeStateCallback onPlayerStateChanged;
  final bool Function() resolveIsLeavingRoom;
  final bool Function() resolvePlaybackRebindInFlight;
  final RoomPlayerShouldRecoverUnexpectedStop shouldRecoverUnexpectedStop;
  final RoomPlayerUnexpectedStopCallback onUnexpectedPlaybackStop;
  final Duration unexpectedStopRecoveryDelay;

  /// Optional per-state delay. When null, [unexpectedStopRecoveryDelay] is used.
  /// Hard open failures (Douyu/mpv `Failed to open`) should use near-zero delay.
  final Duration Function(PlayerState state)?
  resolveUnexpectedStopRecoveryDelay;

  Duration recoveryDelayFor(PlayerState state) {
    return resolveUnexpectedStopRecoveryDelay?.call(state) ??
        unexpectedStopRecoveryDelay;
  }
}

class RoomPlayerRuntimeObserver {
  RoomPlayerRuntimeObserver({required this.context});

  final RoomPlayerRuntimeObserverContext context;

  StreamSubscription<PlayerState>? _playerStateSubscription;
  StreamSubscription<PlayerDiagnostics>? _playerDiagnosticsSubscription;
  String? _lastPlayerStateLogSignature;
  String? _lastPlayerDiagnosticsSummarySignature;
  String? _lastPlayerDiagnosticsSourceSignature;
  String? _lastPlayerDiagnosticsError;
  String? _lastPlayerRecentLogEntry;
  PlaybackBufferProfile? _lastPlayerBufferProfile;
  Timer? _unexpectedStopRecoveryTimer;
  String? _unexpectedStopRecoverySignature;
  bool _unexpectedStopRecoveryInFlight = false;
  bool _disposed = false;

  void attach() {
    _playerStateSubscription ??= context.runtime.states.listen(
      _handlePlayerState,
    );
    _playerDiagnosticsSubscription ??= context.runtime.diagnostics.listen(
      _handlePlayerDiagnostics,
    );
  }

  void syncCurrentState() {
    if (_disposed) {
      return;
    }
    _forwardPlayerState(context.runtime.readCurrentState());
  }

  Future<void> dispose() async {
    _disposed = true;
    _cancelUnexpectedStopRecovery();
    await _playerStateSubscription?.cancel();
    await _playerDiagnosticsSubscription?.cancel();
  }

  void _handlePlayerState(PlayerState state) {
    if (_disposed) {
      return;
    }
    _forwardPlayerState(state);
  }

  void _forwardPlayerState(PlayerState state, {bool forceRebuild = false}) {
    final playbackAvailable = context.resolvePlaybackAvailable();
    context.onPlayerStateChanged(
      state,
      playbackAvailable: playbackAvailable,
      forceRebuild: forceRebuild,
    );
    _handleUnexpectedStopState(state, playbackAvailable: playbackAvailable);
    if (kReleaseMode) {
      return;
    }
    final signature = [
      state.status.name,
      state.errorMessage ?? '',
      summarizeRoomPlaybackSource(state.source),
      (state.buffered.inSeconds / 5).floor(),
    ].join('|');
    if (_lastPlayerStateLogSignature == signature) {
      return;
    }
    _lastPlayerStateLogSignature = signature;
    context.trace(
      'player status=${state.status.name} '
      'buffer=${state.buffered.inMilliseconds}ms '
      'pos=${state.position.inMilliseconds}ms '
      'source=${summarizeRoomPlaybackSource(state.source)} '
      'error=${state.errorMessage ?? '-'}',
    );
  }

  void _handleUnexpectedStopState(
    PlayerState state, {
    required bool playbackAvailable,
  }) {
    if (!playbackAvailable ||
        state.source == null ||
        context.resolveIsLeavingRoom() ||
        context.resolvePlaybackRebindInFlight() ||
        !context.shouldRecoverUnexpectedStop(state)) {
      _cancelUnexpectedStopRecovery();
      return;
    }
    if (state.status != PlaybackStatus.completed &&
        state.status != PlaybackStatus.error) {
      _cancelUnexpectedStopRecovery();
      return;
    }
    final signature = _unexpectedStopSignature(state);
    if (_unexpectedStopRecoverySignature == signature &&
        _unexpectedStopRecoveryTimer != null) {
      return;
    }
    _unexpectedStopRecoveryTimer?.cancel();
    _unexpectedStopRecoverySignature = signature;
    final delay = context.recoveryDelayFor(state);
    _unexpectedStopRecoveryTimer = Timer(delay, () {
      unawaited(_runUnexpectedStopRecovery(signature));
    });
    context.trace(
      'player unexpected stop recovery scheduled status=${state.status.name} '
      'delayMs=${delay.inMilliseconds}',
    );
  }

  Future<void> _runUnexpectedStopRecovery(String signature) async {
    _unexpectedStopRecoveryTimer = null;
    final current = context.runtime.readCurrentState();
    if (_disposed ||
        _unexpectedStopRecoveryInFlight ||
        context.resolveIsLeavingRoom() ||
        context.resolvePlaybackRebindInFlight() ||
        !context.shouldRecoverUnexpectedStop(current) ||
        !context.resolvePlaybackAvailable()) {
      return;
    }
    if (_unexpectedStopSignature(current) != signature ||
        (current.status != PlaybackStatus.completed &&
            current.status != PlaybackStatus.error) ||
        current.source == null) {
      return;
    }
    _unexpectedStopRecoveryInFlight = true;
    try {
      context.trace(
        'player unexpected stop recovery refresh status=${current.status.name}',
      );
      await context.onUnexpectedPlaybackStop(current);
    } catch (error) {
      context.trace('player unexpected stop recovery failed: $error');
    } finally {
      _unexpectedStopRecoveryInFlight = false;
      if (_unexpectedStopRecoverySignature == signature) {
        _unexpectedStopRecoverySignature = null;
      }
    }
  }

  String _unexpectedStopSignature(PlayerState state) {
    return [
      state.status.name,
      state.source?.url.toString() ?? '',
      state.errorMessage ?? '',
    ].join('|');
  }

  void _cancelUnexpectedStopRecovery() {
    _unexpectedStopRecoveryTimer?.cancel();
    _unexpectedStopRecoveryTimer = null;
    _unexpectedStopRecoverySignature = null;
  }

  int? _lastNotifiedVideoWidth;
  int? _lastNotifiedVideoHeight;

  void _handlePlayerDiagnostics(PlayerDiagnostics diagnostics) {
    if (_disposed) {
      return;
    }
    final verboseTracingEnabled = !kReleaseMode;
    final source = context.runtime.readCurrentState().source;
    final sourceSignature = resolvePlayerDiagnosticsSourceSignature(source);
    if (_lastPlayerDiagnosticsSourceSignature != sourceSignature) {
      _lastPlayerDiagnosticsSourceSignature = sourceSignature;
      _lastPlayerDiagnosticsSummarySignature = null;
      _lastPlayerDiagnosticsError = null;
      _lastPlayerRecentLogEntry = diagnostics.recentLogs.isEmpty
          ? null
          : diagnostics.recentLogs.last;
      _lastPlayerBufferProfile = null;
      _lastNotifiedVideoWidth = null;
      _lastNotifiedVideoHeight = null;
    }
    // First real video size must rebuild the room page so loading shell can
    // dismiss even if position ticks are throttled (1s) in release and
    // PlayerState fields are unchanged.
    final width = diagnostics.width ?? 0;
    final height = diagnostics.height ?? 0;
    if (shouldForceRoomPageRebuildForVideoSizeChange(
      previousWidth: _lastNotifiedVideoWidth,
      previousHeight: _lastNotifiedVideoHeight,
      nextWidth: width,
      nextHeight: height,
    )) {
      _lastNotifiedVideoWidth = width;
      _lastNotifiedVideoHeight = height;
      _forwardPlayerState(
        context.runtime.readCurrentState(),
        forceRebuild: true,
      );
    }
    if (source == null) {
      _lastPlayerDiagnosticsSummarySignature = null;
      _lastPlayerBufferProfile = null;
    } else if (verboseTracingEnabled) {
      final summary = formatPlayerDiagnosticsSummary(
        diagnostics: diagnostics,
        source: source,
      );
      if (summary != _lastPlayerDiagnosticsSummarySignature) {
        _lastPlayerDiagnosticsSummarySignature = summary;
        context.trace(summary);
      }
      if (source.bufferProfile != _lastPlayerBufferProfile) {
        _lastPlayerBufferProfile = source.bufferProfile;
        if (source.bufferProfile == PlaybackBufferProfile.heavyStreamStable) {
          context.trace('player buffer profile=${source.bufferProfile.name}');
        }
      }
    }
    final error = diagnostics.error?.trim();
    if (error != null &&
        error.isNotEmpty &&
        error != _lastPlayerDiagnosticsError) {
      _lastPlayerDiagnosticsError = error;
      context.trace('player diagnostics error=$error');
    }
    if (!verboseTracingEnabled) {
      return;
    }
    if (source == null) {
      return;
    }
    final recentLogs = diagnostics.recentLogs;
    if (recentLogs.isEmpty) {
      return;
    }
    var startIndex = 0;
    final lastEntry = _lastPlayerRecentLogEntry;
    if (lastEntry != null) {
      final matchIndex = recentLogs.lastIndexOf(lastEntry);
      if (matchIndex == recentLogs.length - 1) {
        return;
      }
      if (matchIndex >= 0) {
        startIndex = matchIndex + 1;
      }
    }
    for (var index = startIndex; index < recentLogs.length; index += 1) {
      final entry = recentLogs[index].trim();
      if (entry.isEmpty) {
        continue;
      }
      final logTag = switch (diagnostics.backend) {
        PlayerBackend.mdk => 'player/mdk-log',
        PlayerBackend.mpv => 'player/mpv-log',
        _ => 'player/log',
      };
      AppLog.instance.info(
        logTag,
        '[${context.providerId.value}/${context.roomId}] $entry',
      );
    }
    _lastPlayerRecentLogEntry = recentLogs.last;
  }
}
