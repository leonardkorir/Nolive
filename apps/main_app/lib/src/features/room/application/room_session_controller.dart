import 'package:flutter/foundation.dart';
import 'package:live_core/live_core.dart';
import 'package:live_player/live_player.dart';

import 'load_room_use_case.dart';
import 'resolve_play_source_use_case.dart';
import 'room_playback_backend_policy.dart';
import 'room_playback_startup_quality_policy.dart';
import 'room_preview_dependencies.dart';
import 'twitch_playback_recovery.dart';
import '../../settings/application/manage_danmaku_preferences_use_case.dart';
import '../../settings/application/manage_player_preferences_use_case.dart';
import '../../settings/application/manage_room_ui_preferences_use_case.dart';

@immutable
class RoomSessionLoadResult {
  const RoomSessionLoadResult({
    required this.snapshot,
    required this.resolved,
    required this.playerPreferences,
    required this.danmakuPreferences,
    required this.roomUiPreferences,
    required this.blockedKeywords,
    required this.playbackQuality,
    required this.startupPlan,
  });

  final LoadedRoomSnapshot snapshot;
  final ResolvedPlaySource? resolved;
  final PlayerPreferences playerPreferences;
  final DanmakuPreferences danmakuPreferences;
  final RoomUiPreferences roomUiPreferences;
  final List<String> blockedKeywords;
  final LivePlayQuality playbackQuality;
  final TwitchStartupPlan startupPlan;
}

TwitchStartupPlan resolveRoomStartupPlan({
  required LoadedRoomSnapshot snapshot,
  required LivePlayQuality requestedQuality,
  bool promoteTwitchAutoStartup = false,
}) {
  if (snapshot.providerId != ProviderId.twitch) {
    return TwitchStartupPlan(startupQuality: requestedQuality);
  }
  return resolveTwitchStartupPlan(
    qualities: snapshot.qualities,
    requestedQuality: requestedQuality,
    promoteAutoStartup: promoteTwitchAutoStartup,
  );
}

class RoomSessionController {
  RoomSessionController({
    required this.dependencies,
    required this.providerId,
    required this.roomId,
    required this.targetPlatform,
    required this.isWeb,
    this.trace,
  });

  final RoomSessionDependencies dependencies;
  ProviderId providerId;
  String roomId;
  final TargetPlatform targetPlatform;
  final bool isWeb;
  final void Function(String message)? trace;

  RoomSessionLoadResult? _current;
  int _generation = 0;

  RoomSessionLoadResult? get current => _current;

  void clearCurrent() {
    _current = null;
  }

  void retargetRoom({
    required ProviderId providerId,
    required String roomId,
  }) {
    this.providerId = providerId;
    this.roomId = roomId;
    _current = null;
    _generation += 1;
  }

  Future<RoomSessionLoadResult> load({String? preferredQualityId}) {
    return _loadCore(
      preferredQualityId: preferredQualityId,
      recordHistory: null,
    );
  }

  Future<RoomSessionLoadResult> reload({String? preferredQualityId}) {
    return _loadCore(
      preferredQualityId: preferredQualityId,
      recordHistory: false,
    );
  }

  Future<ResolvedPlaySource?> resolvePlayback({
    required LoadedRoomSnapshot snapshot,
    required LivePlayQuality quality,
    required bool preferHttps,
    bool allowSnapshotPlayUrlsReuse = true,
  }) async {
    if (!snapshot.hasPlayback) {
      return null;
    }
    final startedAt = DateTime.now();
    final resolved = await dependencies.resolvePlaySource(
      providerId: providerId,
      detail: snapshot.detail,
      quality: quality,
      preferHttps: preferHttps,
      preloadedPlayUrls:
          allowSnapshotPlayUrlsReuse &&
              _canReuseSnapshotPlayUrls(
                snapshot: snapshot,
                requestedQuality: quality,
              )
          ? snapshot.playUrls
          : null,
    );
    _trace(
      'resolvePlaySource done in ${DateTime.now().difference(startedAt).inMilliseconds}ms '
      'quality=${quality.id}/${quality.label} '
      'effective=${resolved.effectiveQuality.id}/${resolved.effectiveQuality.label} '
      'playback=${_summarizePlaybackSource(resolved.playbackSource)}',
    );
    return resolved;
  }

  Future<ResolvedPlaySource> resolvePlaybackRefresh({
    required LoadedRoomSnapshot snapshot,
    required LivePlayQuality quality,
    required bool preferHttps,
  }) {
    return dependencies.resolvePlaySource(
      providerId: snapshot.providerId,
      detail: snapshot.detail,
      quality: quality,
      preferHttps: preferHttps,
    );
  }

  PlaybackSource playbackSourceFromLine(
    LivePlayUrl playUrl, {
    LivePlayQuality? quality,
  }) {
    return playbackSourceFromLivePlayUrl(playUrl, quality: quality);
  }

  Future<RoomSessionLoadResult> _loadCore({
    required String? preferredQualityId,
    required bool? recordHistory,
  }) async {
    final myGeneration = ++_generation;
    _trace(
      'load start preferredQuality=${preferredQualityId ?? '-'} generation=$myGeneration',
    );
    await _waitForPendingRoomTeardown(myGeneration);
    final playerPreferences = await dependencies.loadPlayerPreferences();
    final blockedKeywords = await dependencies.loadBlockedKeywords();
    final danmakuPreferences = await dependencies.loadDanmakuPreferences();
    final roomUiPreferences = await dependencies.loadRoomUiPreferences();

    final runtimeBackend = resolveRoomPlaybackBackend(
      providerId: providerId,
      preferredBackend: playerPreferences.backend,
      targetPlatform: targetPlatform,
      isWeb: isWeb,
    );
    if (runtimeBackend != playerPreferences.backend) {
      _trace(
        'runtime backend override '
        '${playerPreferences.backend.name} -> ${runtimeBackend.name}',
      );
    }
    await dependencies.playerRuntime.ensureBackendWithoutPlaybackState(
      runtimeBackend,
    );
    await dependencies.playerRuntime.initialize();
    await dependencies.playerRuntime.setVolume(
      resolveRoomRuntimePlayerVolume(
        playerPreferences: playerPreferences,
        targetPlatform: targetPlatform,
      ),
    );

    final startedAt = DateTime.now();
    final snapshot = await dependencies.loadRoom(
      providerId: providerId,
      roomId: roomId,
      preferHighestQuality: playerPreferences.preferHighestQuality,
      preferAdaptiveAutoQuality: playerPreferences.autoQualityEnabled,
      qualityPreference: playerPreferences.wifiQualityPreference,
      cellularQualityPreference: playerPreferences.cellularQualityPreference,
      recordHistory: recordHistory,
    );
    _trace(
      'loadRoom done in ${DateTime.now().difference(startedAt).inMilliseconds}ms '
      'qualities=${snapshot.qualities.length} '
      'playUrls=${snapshot.playUrls.length} '
      'selected=${snapshot.selectedQuality.id}/${snapshot.selectedQuality.label}',
    );

    final requestedQuality = _resolveRequestedQuality(
      snapshot: snapshot,
      preferredQualityId: preferredQualityId,
    );
    final startupRequestedQuality = resolveRoomStartupRequestedQuality(
      providerId: snapshot.providerId,
      qualities: snapshot.qualities,
      requestedQuality: requestedQuality,
      targetPlatform: targetPlatform,
      explicitSelection: preferredQualityId != null,
      isWeb: isWeb,
    );
    final startupPlan = _resolveStartupPlan(
      snapshot: snapshot,
      requestedQuality: startupRequestedQuality,
      explicitSelection: preferredQualityId != null,
      autoQualityEnabled: playerPreferences.autoQualityEnabled,
      preferHighestQuality: playerPreferences.preferHighestQuality,
    );
    final playbackQuality = startupPlan.startupQuality;
    if (snapshot.selectedQuality.id != requestedQuality.id ||
        snapshot.selectedQuality.label != requestedQuality.label) {
      _trace(
        'requested quality differs from loaded snapshot '
        'loaded=${snapshot.selectedQuality.id}/${snapshot.selectedQuality.label} '
        'requested=${requestedQuality.id}/${requestedQuality.label}',
      );
    }
    if (playbackQuality.id != requestedQuality.id ||
        playbackQuality.label != requestedQuality.label) {
      _trace(
        'startup quality adjusted '
        '${requestedQuality.id}/${requestedQuality.label} -> '
        '${playbackQuality.id}/${playbackQuality.label}',
      );
    }
    if (snapshot.providerId == ProviderId.twitch) {
      final promotion = startupPlan.promotionQuality;
      _trace(
        'twitch startup plan autoQuality=${playerPreferences.autoQualityEnabled} '
        'preferHighest=${playerPreferences.preferHighestQuality} '
        'startup=${playbackQuality.id}/${playbackQuality.label} '
        'promotion=${promotion == null ? '-' : '${promotion.id}/${promotion.label}'}',
      );
    }

    final resolved = await resolvePlayback(
      snapshot: snapshot,
      quality: playbackQuality,
      preferHttps: playerPreferences.forceHttpsEnabled,
    );

    final result = RoomSessionLoadResult(
      snapshot: snapshot,
      resolved: resolved,
      playerPreferences: playerPreferences,
      danmakuPreferences: danmakuPreferences,
      roomUiPreferences: roomUiPreferences,
      blockedKeywords: blockedKeywords,
      playbackQuality: playbackQuality,
      startupPlan: startupPlan,
    );
    if (myGeneration == _generation) {
      _current = result;
    } else {
      _trace(
        'Discarding outdated load result for generation $myGeneration (current: $_generation)',
      );
    }
    return result;
  }

  Future<void> _waitForPendingRoomTeardown(int generation) async {
    final runtime = dependencies.playerRuntime;
    if (!runtime.hasPendingRoomTeardown) {
      return;
    }
    final startedAt = DateTime.now();
    _trace('load waiting for pending room teardown generation=$generation');
    await runtime.waitForPendingRoomTeardown();
    _trace(
      'load pending room teardown released in '
      '${DateTime.now().difference(startedAt).inMilliseconds}ms '
      'generation=$generation',
    );
  }

  LivePlayQuality _resolveRequestedQuality({
    required LoadedRoomSnapshot snapshot,
    required String? preferredQualityId,
  }) {
    if (preferredQualityId == null) {
      return snapshot.selectedQuality;
    }
    return snapshot.qualities.firstWhere(
      (item) => item.id == preferredQualityId,
      orElse: () => snapshot.selectedQuality,
    );
  }

  TwitchStartupPlan _resolveStartupPlan({
    required LoadedRoomSnapshot snapshot,
    required LivePlayQuality requestedQuality,
    required bool explicitSelection,
    required bool autoQualityEnabled,
    required bool preferHighestQuality,
  }) {
    // Auto-on: stay on adaptive auto forever (no second load / no warmup).
    // Auto-off + high: warm on auto, then promote to the requested fixed tier
    // (typically 1080 / site highest). Any other combo plays the selected tier
    // directly without a Twitch startup promotion.
    final promoteTwitchAutoStartup =
        !explicitSelection && !autoQualityEnabled && preferHighestQuality;
    return resolveRoomStartupPlan(
      snapshot: snapshot,
      requestedQuality: requestedQuality,
      promoteTwitchAutoStartup: promoteTwitchAutoStartup,
    );
  }

  bool _canReuseSnapshotPlayUrls({
    required LoadedRoomSnapshot snapshot,
    required LivePlayQuality requestedQuality,
  }) {
    return snapshot.selectedQuality.id == requestedQuality.id &&
        snapshot.selectedQuality.label == requestedQuality.label;
  }

  void _trace(String message) {
    trace?.call(message);
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
}

double resolveRoomRuntimePlayerVolume({
  required PlayerPreferences playerPreferences,
  required TargetPlatform targetPlatform,
}) {
  if (targetPlatform == TargetPlatform.android) {
    return 1.0;
  }
  return playerPreferences.volume;
}
