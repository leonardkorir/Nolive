import 'dart:io';

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
  final ProviderId providerId;
  final String roomId;
  final TargetPlatform targetPlatform;
  final bool isWeb;
  final void Function(String message)? trace;

  RoomSessionLoadResult? _current;

  RoomSessionLoadResult? get current => _current;

  void clearCurrent() {
    _current = null;
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
      preloadedPlayUrls: allowSnapshotPlayUrlsReuse &&
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
    _trace('load start preferredQuality=${preferredQualityId ?? '-'}');
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
      Platform.isAndroid ? 1.0 : playerPreferences.volume,
    );

    final startedAt = DateTime.now();
    final snapshot = await dependencies.loadRoom(
      providerId: providerId,
      roomId: roomId,
      preferHighestQuality: playerPreferences.preferHighestQuality,
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
    );
    final playbackQuality = startupPlan.startupQuality;
    if (playbackQuality.id != requestedQuality.id ||
        playbackQuality.label != requestedQuality.label) {
      _trace(
        'startup quality adjusted '
        '${requestedQuality.id}/${requestedQuality.label} -> '
        '${playbackQuality.id}/${playbackQuality.label}',
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
    _current = result;
    return result;
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
  }) {
    if (snapshot.providerId != ProviderId.twitch) {
      return TwitchStartupPlan(startupQuality: requestedQuality);
    }
    return resolveTwitchStartupPlan(
      qualities: snapshot.qualities,
      requestedQuality: requestedQuality,
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
