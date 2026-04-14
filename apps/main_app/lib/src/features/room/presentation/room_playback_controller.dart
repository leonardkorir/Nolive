import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:live_core/live_core.dart';
import 'package:live_player/live_player.dart';
import 'package:nolive_app/src/shared/application/player_runtime_controller.dart';

const String _mdkTextureInitializationErrorPrefix =
    'MDK texture initialization ';
const Duration _mdkTexturePreRefreshRetryDelay = Duration(milliseconds: 320);
const Duration _mdkTextureRecoveryFirstRetryDelay = Duration(milliseconds: 180);
const Duration _mdkTextureRecoveryBackendRefreshRetryDelay =
    Duration(milliseconds: 320);

typedef RoomPlaybackPostFrameScheduler = void Function(
  Future<void> Function() action,
);
typedef RoomPlaybackDelay = Future<void> Function(Duration duration);
typedef RoomPlaybackEndOfFrame = Future<void> Function();
typedef RoomPlaybackResetEmbeddedView = Future<void> Function(String label);
typedef RoomPlaybackResolveCurrentSource = PlaybackSource? Function();
typedef RoomPlaybackMountCheck = bool Function();
typedef RoomPlaybackTrace = void Function(String message);

bool shouldForcePlaybackBootstrap(PlayerState state) {
  return state.status == PlaybackStatus.error;
}

bool shouldAttemptMdkBackendRefreshAfterSetSource(PlayerState state) {
  final errorMessage = state.errorMessage;
  return state.backend == PlayerBackend.mdk &&
      state.status == PlaybackStatus.error &&
      errorMessage != null &&
      errorMessage.startsWith(_mdkTextureInitializationErrorPrefix);
}

Duration resolveMdkTextureRecoveryRetryDelay(int attemptCount) {
  return switch (attemptCount) {
    0 => _mdkTextureRecoveryFirstRetryDelay,
    1 => _mdkTextureRecoveryBackendRefreshRetryDelay,
    _ => Duration.zero,
  };
}

bool shouldPreRefreshMdkBackendBeforeSameSourceRebind({
  required PlayerState state,
  required PlaybackSource playbackSource,
  required PlayerBackend runtimeBackend,
  PlaybackSource? currentPlaybackSource,
}) {
  final backend = state.backend ?? runtimeBackend;
  if (backend != PlayerBackend.mdk) {
    return false;
  }
  final currentSource = currentPlaybackSource ?? state.source;
  if (currentSource == null) {
    return false;
  }
  return currentSource.url == playbackSource.url &&
      _samePlaybackExternalMediaForPreRefresh(
        currentSource.externalAudio,
        playbackSource.externalAudio,
      );
}

bool _samePlaybackExternalMediaForPreRefresh(
  PlaybackExternalMedia? left,
  PlaybackExternalMedia? right,
) {
  if (left == null || right == null) {
    return left == right;
  }
  return left.url == right.url;
}

class RoomPlaybackController extends ChangeNotifier {
  RoomPlaybackController({
    required this.playerRuntime,
    required this.providerId,
    required this.trace,
    required this.isMounted,
    required this.resolveCurrentPlaybackSource,
    required this.resetEmbeddedPlayerViewAfterBackendRefresh,
    RoomPlaybackPostFrameScheduler? schedulePostFrame,
    RoomPlaybackDelay? delay,
    RoomPlaybackEndOfFrame? waitForEndOfFrame,
  })  : _schedulePostFrame = schedulePostFrame ?? _defaultSchedulePostFrame,
        _delay = delay ?? _defaultDelay,
        _waitForEndOfFrame = waitForEndOfFrame ?? _defaultWaitForEndOfFrame;

  final PlayerRuntimeController playerRuntime;
  final ProviderId providerId;
  final RoomPlaybackTrace trace;
  final RoomPlaybackMountCheck isMounted;
  final RoomPlaybackResolveCurrentSource resolveCurrentPlaybackSource;
  final RoomPlaybackResetEmbeddedView
      resetEmbeddedPlayerViewAfterBackendRefresh;
  final RoomPlaybackPostFrameScheduler _schedulePostFrame;
  final RoomPlaybackDelay _delay;
  final RoomPlaybackEndOfFrame _waitForEndOfFrame;

  static void _defaultSchedulePostFrame(Future<void> Function() action) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(action());
    });
  }

  static Future<void> _defaultDelay(Duration duration) {
    return Future<void>.delayed(duration);
  }

  static Future<void> _defaultWaitForEndOfFrame() {
    return WidgetsBinding.instance.endOfFrame;
  }

  bool _disposed = false;
  bool _playbackBootstrapScheduled = false;
  bool _pendingPlaybackAvailable = false;
  bool _pendingPlaybackAutoPlay = false;
  bool _pendingPlaybackForceSourceRebind = false;
  PlaybackSource? _pendingPlaybackSource;
  String? _mdkTextureRecoverySourceKey;
  int _mdkTextureRecoveryAttemptCount = 0;
  int _playbackRebindInFlightCount = 0;
  Completer<void>? _playbackRebindIdleCompleter;

  bool get rebindInFlight => _playbackRebindInFlightCount > 0;

  PlaybackSource? get pendingPlaybackSource => _pendingPlaybackSource;

  bool get pendingPlaybackAvailable => _pendingPlaybackAvailable;

  bool get pendingPlaybackAutoPlay => _pendingPlaybackAutoPlay;

  bool get _isActive => !_disposed && isMounted();

  void schedulePlaybackBootstrap({
    required PlaybackSource? playbackSource,
    required bool hasPlayback,
    required bool autoPlay,
    bool force = false,
  }) {
    if (_disposed) {
      return;
    }
    if (force) {
      _pendingPlaybackForceSourceRebind = true;
    }
    if (!force &&
        !_pendingPlaybackForceSourceRebind &&
        _pendingPlaybackAvailable == hasPlayback &&
        _pendingPlaybackAutoPlay == autoPlay &&
        _samePlaybackSource(_pendingPlaybackSource, playbackSource)) {
      final currentState = playerRuntime.currentState;
      if (hasPlayback &&
          playbackSource != null &&
          _isRuntimeStableForTarget(
            state: currentState,
            playbackSource: playbackSource,
            autoPlay: autoPlay,
          )) {
        return;
      }
      final status = currentState.status;
      final runtimeActive = currentState.source != null ||
          status == PlaybackStatus.playing ||
          status == PlaybackStatus.ready ||
          status == PlaybackStatus.buffering ||
          status == PlaybackStatus.paused;
      if (!runtimeActive) {
        return;
      }
    }
    _pendingPlaybackSource = playbackSource;
    _pendingPlaybackAvailable = hasPlayback;
    _pendingPlaybackAutoPlay = autoPlay;
    if (_playbackBootstrapScheduled) {
      return;
    }
    _playbackBootstrapScheduled = true;
    _schedulePostFrame(() async {
      _playbackBootstrapScheduled = false;
      if (!_isActive) {
        return;
      }
      await _flushPendingPlaybackBootstrap();
    });
  }

  Future<void> _flushPendingPlaybackBootstrap() async {
    final targetAvailable = _pendingPlaybackAvailable;
    final targetAutoPlay = _pendingPlaybackAutoPlay;
    final targetSource = _pendingPlaybackSource;
    final targetForceSourceRebind = _pendingPlaybackForceSourceRebind;
    _pendingPlaybackForceSourceRebind = false;

    final currentState = playerRuntime.currentState;
    final currentSource = currentState.source;
    final isInitialTwitchBootstrap =
        providerId == ProviderId.twitch && currentSource == null;

    if (!targetAvailable || targetSource == null) {
      resetRecoveryState();
      final status = playerRuntime.currentState.status;
      if (playerRuntime.currentState.source != null ||
          status == PlaybackStatus.playing ||
          status == PlaybackStatus.ready ||
          status == PlaybackStatus.buffering ||
          status == PlaybackStatus.paused) {
        trace('playback bootstrap stop current=${status.name}');
        await playerRuntime.stop();
      }
      return;
    }

    if (isInitialTwitchBootstrap) {
      trace('twitch initial bootstrap wait-surface');
      await _waitForEndOfFrame();
      if (!_isActive) {
        return;
      }
      await _delay(const Duration(milliseconds: 220));
      if (!_isActive) {
        return;
      }
      if (_didPendingPlaybackTargetChange(
        available: targetAvailable,
        autoPlay: targetAutoPlay,
        playbackSource: targetSource,
      )) {
        schedulePlaybackBootstrap(
          playbackSource: _pendingPlaybackSource,
          hasPlayback: _pendingPlaybackAvailable,
          autoPlay: _pendingPlaybackAutoPlay,
          force: _pendingPlaybackForceSourceRebind,
        );
        return;
      }
    }

    final shouldForceSourceRebind =
        targetForceSourceRebind || shouldForcePlaybackBootstrap(currentState);
    if (targetForceSourceRebind) {
      trace(
        'playback bootstrap force rebind '
        'source=${_summarizePlaybackSource(targetSource)}',
      );
    }
    final shouldSetSource = shouldForceSourceRebind ||
        !_samePlaybackSource(currentSource, targetSource);
    if (shouldSetSource) {
      final activeBackend = currentState.backend ?? playerRuntime.backend;
      final bound = await bindPlaybackSource(
        playbackSource: targetSource,
        label: 'playback bootstrap',
        preferFreshBackendBeforeFirstSetSource:
            shouldForceSourceRebind && activeBackend == PlayerBackend.mdk,
        currentPlaybackSource: shouldForceSourceRebind
            ? _resolvePlaybackReferenceSource()
            : currentState.source,
        shouldAbortRetry: () {
          if (!_didPendingPlaybackTargetChange(
            available: targetAvailable,
            autoPlay: targetAutoPlay,
            playbackSource: targetSource,
          )) {
            return false;
          }
          schedulePlaybackBootstrap(
            playbackSource: _pendingPlaybackSource,
            hasPlayback: _pendingPlaybackAvailable,
            autoPlay: _pendingPlaybackAutoPlay,
            force: _pendingPlaybackForceSourceRebind,
          );
          return true;
        },
      );
      if (!bound || !_isActive) {
        return;
      }
      if (providerId == ProviderId.twitch) {
        await _delay(
          isInitialTwitchBootstrap
              ? const Duration(milliseconds: 220)
              : const Duration(milliseconds: 120),
        );
        if (!_isActive) {
          return;
        }
      }
      if (_shouldSkipPlayAfterSetSource(
        state: playerRuntime.currentState,
        source: targetSource,
        context: 'playback bootstrap',
      )) {
        return;
      }
    }
    if (_shouldSkipPlayAfterSetSource(
      state: playerRuntime.currentState,
      source: targetSource,
      context: 'playback bootstrap',
    )) {
      return;
    }
    if (targetAutoPlay &&
        playerRuntime.currentState.status != PlaybackStatus.playing) {
      trace(
        'playback bootstrap play source=${_summarizePlaybackSource(targetSource)}',
      );
      await playerRuntime.play();
    }

    if (_didPendingPlaybackTargetChange(
          available: targetAvailable,
          autoPlay: targetAutoPlay,
          playbackSource: targetSource,
        ) ||
        _pendingPlaybackForceSourceRebind) {
      schedulePlaybackBootstrap(
        playbackSource: _pendingPlaybackSource,
        hasPlayback: _pendingPlaybackAvailable,
        autoPlay: _pendingPlaybackAutoPlay,
        force: _pendingPlaybackForceSourceRebind,
      );
    }
  }

  Future<bool> bindPlaybackSource({
    required PlaybackSource playbackSource,
    required String label,
    bool autoPlay = false,
    Duration autoPlayDelay = Duration.zero,
    PlaybackSource? currentPlaybackSource,
    bool preferFreshBackendBeforeFirstSetSource = false,
    bool Function()? shouldAbortRetry,
  }) async {
    if (_disposed) {
      return false;
    }
    final shouldPreRefreshBackend = preferFreshBackendBeforeFirstSetSource ||
        shouldPreRefreshMdkBackendBeforeSameSourceRebind(
          state: playerRuntime.currentState,
          playbackSource: playbackSource,
          runtimeBackend: playerRuntime.backend,
          currentPlaybackSource: currentPlaybackSource,
        );
    final bound = await _setPlaybackSourceWithMdkRecovery(
      playbackSource: playbackSource,
      label: label,
      refreshBackendBeforeFirstSetSource: shouldPreRefreshBackend,
      shouldAbortRetry: shouldAbortRetry,
    );
    if (!bound || !_isActive) {
      return false;
    }
    if (autoPlayDelay > Duration.zero) {
      await _delay(autoPlayDelay);
      if (!_isActive) {
        return false;
      }
    }
    if (!autoPlay ||
        _shouldSkipPlayAfterSetSource(
          state: playerRuntime.currentState,
          source: playbackSource,
          context: label,
        )) {
      return true;
    }
    trace('$label play source=${_summarizePlaybackSource(playbackSource)}');
    await playerRuntime.play();
    return true;
  }

  Future<void> stopCurrentPlayback({
    required String label,
  }) async {
    if (_disposed) {
      return;
    }
    _beginPlaybackRebind();
    try {
      trace('$label stop status=${playerRuntime.currentState.status.name}');
      await playerRuntime.stop();
    } finally {
      _endPlaybackRebind();
    }
  }

  Future<void> refreshBackendWithoutPlaybackState({
    required String label,
    bool resetEmbeddedView = false,
  }) async {
    if (_disposed) {
      return;
    }
    _beginPlaybackRebind();
    try {
      trace('$label refresh backend');
      await playerRuntime.refreshBackendWithoutPlaybackState();
      if (!resetEmbeddedView || !_isActive) {
        return;
      }
      await resetEmbeddedPlayerViewAfterBackendRefresh(label);
    } finally {
      _endPlaybackRebind();
    }
  }

  Future<void> restorePlaybackState({
    required PlayerState previousState,
    required String label,
  }) async {
    if (_disposed) {
      return;
    }
    final source = previousState.source;
    if (source == null) {
      return;
    }
    trace(
      '$label restore source=${_summarizePlaybackSource(source)} '
      'status=${previousState.status.name}',
    );
    final status = previousState.status;
    final restored = await bindPlaybackSource(
      playbackSource: source,
      label: '$label restore',
      autoPlay: status == PlaybackStatus.playing ||
          status == PlaybackStatus.buffering,
      currentPlaybackSource: null,
    );
    if (!restored || !_isActive) {
      return;
    }
    if (status == PlaybackStatus.paused &&
        !_shouldSkipPlayAfterSetSource(
          state: playerRuntime.currentState,
          source: source,
          context: '$label restore',
        )) {
      await playerRuntime.pause();
    }
  }

  Future<void> waitForPlaybackRebindToFinish({
    required String reason,
  }) async {
    final completer = _playbackRebindIdleCompleter;
    if (completer == null || completer.isCompleted) {
      return;
    }
    trace('$reason wait playback rebind');
    try {
      await completer.future.timeout(const Duration(seconds: 8));
    } on TimeoutException {
      trace('$reason wait playback rebind timed out');
    }
  }

  void resetRecoveryState() {
    _mdkTextureRecoverySourceKey = null;
    _mdkTextureRecoveryAttemptCount = 0;
  }

  @override
  void dispose() {
    _disposed = true;
    final completer = _playbackRebindIdleCompleter;
    _playbackRebindIdleCompleter = null;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
    super.dispose();
  }

  Future<bool> _setPlaybackSourceWithMdkRecovery({
    required PlaybackSource playbackSource,
    required String label,
    bool refreshBackendBeforeFirstSetSource = false,
    bool Function()? shouldAbortRetry,
  }) async {
    _beginPlaybackRebind();
    try {
      _prepareMdkTextureRecoveryState(playbackSource);
      if (refreshBackendBeforeFirstSetSource) {
        trace(
          '$label mdk same-source backend refresh '
          'source=${_summarizePlaybackSource(playbackSource)}',
        );
        await playerRuntime.refreshBackendWithoutPlaybackState();
        await resetEmbeddedPlayerViewAfterBackendRefresh(label);
        await _awaitMdkTextureRecoveryRetryStabilization(
          attemptCount: -1,
          label: label,
        );
        if (!_canContinueMdkTextureRecovery(shouldAbortRetry)) {
          resetRecoveryState();
          return false;
        }
      }
      while (true) {
        final attemptCount = _mdkTextureRecoveryAttemptCount;
        final actionLabel = switch (attemptCount) {
          0 => '$label setSource',
          _ => '$label retry setSource',
        };
        await _logAndSetSource(
          playbackSource: playbackSource,
          label: actionLabel,
        );
        if (!shouldAttemptMdkBackendRefreshAfterSetSource(
            playerRuntime.currentState)) {
          resetRecoveryState();
          return true;
        }

        final error = playerRuntime.currentState.errorMessage ?? '-';
        if (attemptCount == 0) {
          _mdkTextureRecoveryAttemptCount = 1;
          trace('$label mdk texture timeout first retry error=$error');
          await playerRuntime.stop();
          await _awaitMdkTextureRecoveryRetryStabilization(
            attemptCount: attemptCount,
            label: label,
          );
          if (!_canContinueMdkTextureRecovery(shouldAbortRetry)) {
            resetRecoveryState();
            return false;
          }
          continue;
        }

        if (attemptCount == 1) {
          _mdkTextureRecoveryAttemptCount = 2;
          trace(
              '$label mdk texture timeout backend refresh retry error=$error');
          await playerRuntime.stop();
          await playerRuntime.refreshBackendWithoutPlaybackState();
          await resetEmbeddedPlayerViewAfterBackendRefresh(label);
          await _awaitMdkTextureRecoveryRetryStabilization(
            attemptCount: attemptCount,
            label: label,
          );
          if (!_canContinueMdkTextureRecovery(shouldAbortRetry)) {
            resetRecoveryState();
            return false;
          }
          continue;
        }

        trace('$label mdk texture timeout exhausted error=$error');
        resetRecoveryState();
        return true;
      }
    } finally {
      _endPlaybackRebind();
    }
  }

  void _beginPlaybackRebind() {
    final nextCount = _playbackRebindInFlightCount + 1;
    _playbackRebindInFlightCount = nextCount;
    if (nextCount == 1) {
      _playbackRebindIdleCompleter = Completer<void>();
      notifyListeners();
    }
  }

  void _endPlaybackRebind() {
    if (_playbackRebindInFlightCount <= 0) {
      return;
    }
    final nextCount = _playbackRebindInFlightCount - 1;
    _playbackRebindInFlightCount = nextCount;
    if (nextCount == 0) {
      final completer = _playbackRebindIdleCompleter;
      _playbackRebindIdleCompleter = null;
      if (completer != null && !completer.isCompleted) {
        completer.complete();
      }
      notifyListeners();
    }
  }

  Duration _resolveMdkTextureRecoverySettleDelay(int attemptCount) {
    if (attemptCount < 0) {
      return _mdkTexturePreRefreshRetryDelay;
    }
    return resolveMdkTextureRecoveryRetryDelay(attemptCount);
  }

  Future<void> _logAndSetSource({
    required PlaybackSource playbackSource,
    required String label,
  }) async {
    trace('$label ${_summarizePlaybackSource(playbackSource)}');
    await playerRuntime.setSource(playbackSource);
    trace(
      '$label done '
      'status=${playerRuntime.currentState.status.name} '
      'error=${playerRuntime.currentState.errorMessage ?? '-'}',
    );
  }

  bool _didPendingPlaybackTargetChange({
    required bool available,
    required bool autoPlay,
    required PlaybackSource playbackSource,
  }) {
    return _pendingPlaybackAvailable != available ||
        _pendingPlaybackAutoPlay != autoPlay ||
        !_samePlaybackSource(_pendingPlaybackSource, playbackSource);
  }

  bool _isRuntimeStableForTarget({
    required PlayerState state,
    required PlaybackSource playbackSource,
    required bool autoPlay,
  }) {
    if (!_samePlaybackSource(state.source, playbackSource)) {
      return false;
    }
    return switch (state.status) {
      PlaybackStatus.playing || PlaybackStatus.buffering => true,
      PlaybackStatus.ready => !autoPlay,
      PlaybackStatus.paused => !autoPlay,
      _ => false,
    };
  }

  bool _canContinueMdkTextureRecovery(bool Function()? shouldAbortRetry) {
    if (!_isActive) {
      return false;
    }
    return !(shouldAbortRetry?.call() ?? false);
  }

  Future<void> _awaitMdkTextureRecoveryRetryStabilization({
    required int attemptCount,
    required String label,
  }) async {
    final delay = _resolveMdkTextureRecoverySettleDelay(attemptCount);
    if (delay <= Duration.zero || !_isActive) {
      return;
    }
    final settleReason = attemptCount < 0
        ? 'mdk same-source refresh settle'
        : 'mdk texture timeout settle';
    final settleSuffix = attemptCount < 0 ? '' : ' attempt=${attemptCount + 1}';
    trace(
      '$label $settleReason ${delay.inMilliseconds}ms$settleSuffix',
    );
    await _waitForEndOfFrame();
    if (!_isActive) {
      return;
    }
    await _delay(delay);
  }

  void _prepareMdkTextureRecoveryState(PlaybackSource playbackSource) {
    final nextKey = _mdkTextureRecoveryKey(playbackSource);
    if (_mdkTextureRecoverySourceKey == nextKey) {
      return;
    }
    _mdkTextureRecoverySourceKey = nextKey;
    _mdkTextureRecoveryAttemptCount = 0;
  }

  PlaybackSource? _resolvePlaybackReferenceSource() {
    return playerRuntime.currentState.source ??
        resolveCurrentPlaybackSource() ??
        _pendingPlaybackSource;
  }

  bool _shouldSkipPlayAfterSetSource({
    required PlayerState state,
    required PlaybackSource source,
    required String context,
  }) {
    if (!_samePlaybackSource(state.source, source)) {
      trace(
        '$context skip play '
        'source=${_summarizePlaybackSource(source)} '
        'current=${_summarizePlaybackSource(state.source)} '
        'status=${state.status.name}',
      );
      return true;
    }
    if (state.status != PlaybackStatus.error) {
      return false;
    }
    trace(
      '$context skip play '
      'source=${_summarizePlaybackSource(source)} '
      'error=${state.errorMessage ?? '-'}',
    );
    return true;
  }

  String _mdkTextureRecoveryKey(PlaybackSource source) {
    final sortedHeaders = source.headers.entries.toList(growable: false)
      ..sort((left, right) => left.key.compareTo(right.key));
    final headerSignature =
        sortedHeaders.map((entry) => '${entry.key}=${entry.value}').join('&');
    final audio = source.externalAudio;
    final audioSignature = audio == null
        ? '-'
        : '${audio.url}|${audio.mimeType ?? '-'}|${audio.label ?? '-'}';
    return [
      source.url.toString(),
      headerSignature,
      audioSignature,
      source.bufferProfile.name,
    ].join('|');
  }

  String _summarizePlaybackSource(PlaybackSource? source) {
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

  bool _samePlaybackSource(PlaybackSource? left, PlaybackSource? right) {
    if (left == null || right == null) {
      return left == right;
    }
    return left.url == right.url &&
        mapEquals(left.headers, right.headers) &&
        left.bufferProfile == right.bufferProfile &&
        _sameExternalMedia(left.externalAudio, right.externalAudio);
  }

  bool _sameExternalMedia(
    PlaybackExternalMedia? left,
    PlaybackExternalMedia? right,
  ) {
    if (left == null || right == null) {
      return left == right;
    }
    return left.url == right.url && mapEquals(left.headers, right.headers);
  }
}
