import 'package:live_player/live_player.dart';
import 'package:nolive_app/src/features/room/application/room_playback_backend_policy.dart';
import 'package:nolive_app/src/features/room/presentation/room_controls_action_context.dart';
import 'package:nolive_app/src/features/room/presentation/room_playback_controller.dart';
import 'package:nolive_app/src/features/settings/application/manage_player_preferences_use_case.dart';

class RoomControlsSettingsReturnActions {
  const RoomControlsSettingsReturnActions({required this.context});

  final RoomControlsActionContext context;

  Future<void> handlePlayerSettingsReturn({
    required PlayerPreferences previousPreferences,
  }) async {
    final nextPreferences = await context.loadPlayerPreferences();
    if (!context.isMounted()) {
      return;
    }
    final runtimeBackend = resolveRoomPlaybackBackend(
      providerId: context.providerId,
      preferredBackend: nextPreferences.backend,
      targetPlatform: context.targetPlatform,
      isWeb: context.isWeb,
    );
    var backendChanged = false;
    if (context.runtime.resolveBackend() != runtimeBackend) {
      backendChanged = true;
      context.trace(
        'player settings return enforce backend '
        '${context.runtime.resolveBackend().name} -> ${runtimeBackend.name}',
      );
      await context.runtime.ensureBackendWithoutPlaybackState(
        runtimeBackend,
      );
    }
    if (!context.isMounted()) {
      return;
    }
    context.applyPlayerPreferences(nextPreferences);
    if (shouldRefreshRoomAfterPlayerSettingsReturn(
      previous: previousPreferences,
      next: nextPreferences,
    )) {
      context.trace(
        'player settings return refresh room '
        'preferHighest=${previousPreferences.preferHighestQuality}->${nextPreferences.preferHighestQuality} '
        'forceHttps=${previousPreferences.forceHttpsEnabled}->${nextPreferences.forceHttpsEnabled}',
      );
      await context.refreshRoom(reloadPlayer: false);
      return;
    }
    final playbackSource = context.resolveCurrentPlaybackSource();
    final playbackAvailable = context.resolvePlaybackAvailable();
    if (playbackSource == null || !playbackAvailable) {
      return;
    }
    final playerState = context.runtime.readCurrentState();
    final forceBootstrap = shouldForcePlaybackBootstrap(playerState);
    if (!backendChanged && !forceBootstrap) {
      return;
    }
    context.trace(
      'player settings return rebootstrap '
      'status=${playerState.status.name} '
      'source=${_summarizePlaybackSource(playbackSource)} '
      'backendChanged=$backendChanged',
    );
    context.schedulePlaybackBootstrap(
      playbackSource: playbackSource,
      hasPlayback: playbackAvailable,
      autoPlay: nextPreferences.autoPlayEnabled,
      force: forceBootstrap,
    );
  }

  Future<void> handleDanmakuSettingsReturn() async {
    final blockedKeywords = await context.loadBlockedKeywords();
    if (!context.isMounted()) {
      return;
    }
    final danmakuPreferences = await context.loadDanmakuPreferences();
    if (!context.isMounted()) {
      return;
    }
    context.applyDanmakuPreferences(
      preferences: danmakuPreferences,
      blockedKeywords: blockedKeywords,
    );
    final detail = await context.loadCurrentRoomDetailForDanmaku();
    if (!context.isMounted() || detail == null) {
      return;
    }
    try {
      final session = await context.openRoomDanmaku(detail: detail);
      if (!context.isMounted()) {
        await session?.disconnect();
        return;
      }
      if (session == null) {
        return;
      }
      await context.bindDanmakuSession(session);
    } catch (error) {
      context.trace('reload danmaku after settings failed error=$error');
    }
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
