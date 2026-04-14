import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:live_core/live_core.dart';
import 'package:live_player/live_player.dart';
import 'package:nolive_app/src/features/room/application/load_room_use_case.dart';
import 'package:nolive_app/src/features/room/application/twitch_playback_recovery.dart';
import 'package:nolive_app/src/features/room/presentation/room_runtime_helper_contexts.dart';

typedef RoomTwitchSwitchQuality = Future<void> Function(
  LoadedRoomSnapshot snapshot,
  LivePlayQuality quality, {
  bool resetTwitchRecoveryAttempts,
  LivePlayQuality? twitchStartupPromotionQuality,
});

typedef RoomTwitchRefreshPlayback = Future<void> Function(
  LoadedRoomSnapshot snapshot,
  LivePlayQuality quality, {
  LivePlayQuality? twitchStartupPromotionQuality,
  bool resetTwitchRecoveryAttempts,
  PlaybackSource? preferredPlaybackSource,
  List<LivePlayUrl>? currentPlayUrls,
});

typedef RoomTwitchSwitchLine = Future<void> Function(
  LivePlayUrl playUrl, {
  bool resetTwitchRecoveryAttempts,
});

@immutable
class RoomTwitchRecoveryState {
  const RoomTwitchRecoveryState({
    this.recoveryToken = 0,
    this.recoverySourceKey,
    this.recoveryAttempts = 0,
    this.startupPromotionQuality,
  });

  final int recoveryToken;
  final String? recoverySourceKey;
  final int recoveryAttempts;
  final LivePlayQuality? startupPromotionQuality;

  RoomTwitchRecoveryState copyWith({
    int? recoveryToken,
    String? recoverySourceKey,
    bool clearRecoverySourceKey = false,
    int? recoveryAttempts,
    LivePlayQuality? startupPromotionQuality,
    bool clearStartupPromotionQuality = false,
  }) {
    return RoomTwitchRecoveryState(
      recoveryToken: recoveryToken ?? this.recoveryToken,
      recoverySourceKey: clearRecoverySourceKey
          ? null
          : (recoverySourceKey ?? this.recoverySourceKey),
      recoveryAttempts: recoveryAttempts ?? this.recoveryAttempts,
      startupPromotionQuality: clearStartupPromotionQuality
          ? null
          : (startupPromotionQuality ?? this.startupPromotionQuality),
    );
  }
}

class RoomTwitchRecoveryController {
  RoomTwitchRecoveryController({
    required this.runtime,
    this.trace,
    Future<void> Function(Duration duration)? delay,
  }) : _delay = delay ?? _defaultDelay;

  final RoomRuntimeInspectionContext runtime;
  final void Function(String message)? trace;
  final Future<void> Function(Duration duration) _delay;

  static Future<void> _defaultDelay(Duration duration) {
    return Future<void>.delayed(duration);
  }

  RoomTwitchRecoveryState _current = const RoomTwitchRecoveryState();
  bool _disposed = false;

  RoomTwitchRecoveryState get current => _current;

  void applyStartupPlan(TwitchStartupPlan plan) {
    if (_disposed) {
      return;
    }
    _replaceState(
      _current.copyWith(
        recoveryToken: _current.recoveryToken + 1,
        clearRecoverySourceKey: true,
        recoveryAttempts: 0,
        startupPromotionQuality: plan.promotionQuality,
        clearStartupPromotionQuality: plan.promotionQuality == null,
      ),
    );
  }

  void prepareForResolvedPlayback({
    LivePlayQuality? startupPromotionQuality,
    bool resetAttempts = true,
  }) {
    if (_disposed) {
      return;
    }
    _replaceState(
      _current.copyWith(
        recoveryToken: _current.recoveryToken + 1,
        clearRecoverySourceKey: true,
        recoveryAttempts: resetAttempts ? 0 : _current.recoveryAttempts,
        startupPromotionQuality: startupPromotionQuality,
        clearStartupPromotionQuality: startupPromotionQuality == null,
      ),
    );
  }

  void prepareForLineSwitch({bool resetAttempts = true}) {
    if (_disposed) {
      return;
    }
    _replaceState(
      _current.copyWith(
        recoveryToken: _current.recoveryToken + 1,
        clearRecoverySourceKey: true,
        recoveryAttempts: resetAttempts ? 0 : _current.recoveryAttempts,
        clearStartupPromotionQuality: true,
      ),
    );
  }

  Future<void> scheduleRecovery({
    required ProviderId providerId,
    required LoadedRoomSnapshot snapshot,
    required PlaybackSource? playbackSource,
    required List<LivePlayUrl> playUrls,
    required LivePlayQuality selectedQuality,
    required LivePlayQuality Function() resolveCurrentQuality,
    required bool Function() isMounted,
    required RoomTwitchSwitchQuality switchQuality,
    required RoomTwitchRefreshPlayback refreshPlaybackSource,
    required RoomTwitchSwitchLine switchLine,
  }) async {
    if (_disposed ||
        providerId != ProviderId.twitch ||
        playbackSource == null) {
      return;
    }
    final sourceKey = playbackSource.url.toString();
    if (_current.recoverySourceKey == sourceKey) {
      return;
    }
    _replaceState(
      _current.copyWith(
        recoverySourceKey: sourceKey,
        recoveryToken: _current.recoveryToken + 1,
      ),
    );
    final token = _current.recoveryToken;
    final delay = resolveTwitchRecoveryDelay(
      currentQuality: resolveCurrentQuality(),
      recoveryAttempts: _current.recoveryAttempts,
    );
    await _delay(delay);

    if (!_isActive(isMounted) || token != _current.recoveryToken) {
      return;
    }
    final currentState = runtime.readCurrentState();
    if (!_samePlaybackSource(currentState.source, playbackSource)) {
      return;
    }
    final currentQuality = resolveCurrentQuality();
    final promotionQuality = _current.startupPromotionQuality;
    if (promotionQuality != null && currentQuality.id == 'auto') {
      if (shouldPromoteTwitchPlaybackQuality(currentState)) {
        _trace(
          'twitch startup promotion '
          'pos=${currentState.position.inMilliseconds}ms '
          'buffer=${currentState.buffered.inMilliseconds}ms '
          'switch-quality=${promotionQuality.id}/${promotionQuality.label}',
        );
        _replaceState(
          _current.copyWith(
            recoveryAttempts: 0,
            clearStartupPromotionQuality: true,
          ),
        );
        await switchQuality(
          snapshot,
          promotionQuality,
          resetTwitchRecoveryAttempts: false,
        );
        return;
      }
      if (shouldAttemptTwitchPlaybackRecovery(currentState) &&
          _current.recoveryAttempts == 1) {
        _replaceState(_current.copyWith(recoveryAttempts: 2));
        _trace(
          'twitch startup promotion refresh '
          'pos=${currentState.position.inMilliseconds}ms '
          'buffer=${currentState.buffered.inMilliseconds}ms '
          'quality=${currentQuality.id}/${currentQuality.label}',
        );
        await refreshPlaybackSource(
          snapshot,
          currentQuality,
          twitchStartupPromotionQuality: promotionQuality,
          resetTwitchRecoveryAttempts: false,
        );
        return;
      }
      if (shouldAttemptTwitchPlaybackRecovery(currentState) &&
          _current.recoveryAttempts >= 2) {
        _trace(
          'twitch startup promotion recovery '
          'pos=${currentState.position.inMilliseconds}ms '
          'buffer=${currentState.buffered.inMilliseconds}ms '
          'switch-quality=${promotionQuality.id}/${promotionQuality.label}',
        );
        _replaceState(
          _current.copyWith(
            recoveryAttempts: 0,
            clearStartupPromotionQuality: true,
          ),
        );
        await switchQuality(
          snapshot,
          promotionQuality,
          resetTwitchRecoveryAttempts: false,
        );
        return;
      }
      if (_current.recoveryAttempts == 0) {
        _replaceState(_current.copyWith(recoveryAttempts: 1));
      }
      _trace(
        'twitch startup promotion wait '
        'pos=${currentState.position.inMilliseconds}ms '
        'buffer=${currentState.buffered.inMilliseconds}ms '
        'target=${promotionQuality.id}/${promotionQuality.label}',
      );
      _replaceState(_current.copyWith(clearRecoverySourceKey: true));
      unawaited(
        scheduleRecovery(
          providerId: providerId,
          snapshot: snapshot,
          playbackSource: playbackSource,
          playUrls: playUrls,
          selectedQuality: selectedQuality,
          resolveCurrentQuality: resolveCurrentQuality,
          isMounted: isMounted,
          switchQuality: switchQuality,
          refreshPlaybackSource: refreshPlaybackSource,
          switchLine: switchLine,
        ),
      );
      return;
    }

    final fixedRecovery = resolveTwitchFixedRecoveryDecision(
      state: currentState,
      recoveryAttempts: _current.recoveryAttempts,
      playbackSource: playbackSource,
      playUrls: playUrls,
    );
    switch (fixedRecovery.action) {
      case TwitchFixedRecoveryAction.none:
        return;
      case TwitchFixedRecoveryAction.switchLine:
        final recoveryLine = fixedRecovery.recoveryLine;
        if (recoveryLine == null) {
          return;
        }
        _replaceState(_current.copyWith(recoveryAttempts: 1));
        _trace(
          'twitch startup recovery '
          'pos=${currentState.position.inMilliseconds}ms '
          'buffer=${currentState.buffered.inMilliseconds}ms '
          'switch-line=${recoveryLine.lineLabel ?? '-'} '
          "playerType=${recoveryLine.metadata?['playerType'] ?? '-'}",
        );
        await switchLine(
          recoveryLine,
          resetTwitchRecoveryAttempts: false,
        );
        return;
      case TwitchFixedRecoveryAction.refreshCurrentLine:
        _replaceState(_current.copyWith(recoveryAttempts: 2));
        _trace(
          'twitch startup recovery '
          'pos=${currentState.position.inMilliseconds}ms '
          'buffer=${currentState.buffered.inMilliseconds}ms '
          'action=refresh-current-line '
          'quality=${currentQuality.id}/${currentQuality.label}',
        );
        await refreshPlaybackSource(
          snapshot,
          currentQuality,
          resetTwitchRecoveryAttempts: false,
          preferredPlaybackSource: playbackSource,
          currentPlayUrls: playUrls,
        );
        return;
      case TwitchFixedRecoveryAction.stop:
        _trace(
          'twitch startup recovery '
          'pos=${currentState.position.inMilliseconds}ms '
          'buffer=${currentState.buffered.inMilliseconds}ms '
          'action=stop-after-line-refresh',
        );
        return;
    }
  }

  void dispose() {
    _disposed = true;
    _replaceState(
      _current.copyWith(
        recoveryToken: _current.recoveryToken + 1,
        clearRecoverySourceKey: true,
        clearStartupPromotionQuality: true,
      ),
    );
  }

  bool _isActive(bool Function() isMounted) {
    return !_disposed && isMounted();
  }

  void _replaceState(RoomTwitchRecoveryState next) {
    _current = next;
  }

  void _trace(String message) {
    trace?.call(message);
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
