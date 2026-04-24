import 'package:live_core/live_core.dart';
import 'package:live_player/live_player.dart';
import 'package:nolive_app/src/features/room/application/load_room_use_case.dart';
import 'package:nolive_app/src/features/room/application/resolve_play_source_use_case.dart';
import 'package:nolive_app/src/features/room/application/twitch_playback_recovery.dart';
import 'package:nolive_app/src/features/room/presentation/room_controls_action_context.dart';
import 'package:nolive_app/src/features/room/presentation/room_playback_controller.dart';

class RoomControlsPlaybackActions {
  const RoomControlsPlaybackActions({required this.context});

  final RoomControlsActionContext context;

  Future<void> switchQuality(
    LoadedRoomSnapshot snapshot,
    LivePlayQuality quality, {
    bool resetTwitchRecoveryAttempts = true,
    LivePlayQuality? twitchStartupPromotionQuality,
  }) async {
    if (!snapshot.hasPlayback) {
      _showPlaybackUnavailableHint(snapshot.playbackUnavailableReason);
      return;
    }
    final resolved = await context.resolvePlaybackRefresh(snapshot, quality);
    context.trace(
      'manual switch quality=${quality.id}/${quality.label} '
      'playback=${_summarizePlaybackSource(resolved.playbackSource)}',
    );
    await _applyResolvedPlaybackSource(
      resolved,
      selectedQuality: quality,
      twitchStartupPromotionQuality: twitchStartupPromotionQuality,
      resetTwitchRecoveryAttempts: resetTwitchRecoveryAttempts,
    );
    context.scheduleTwitchRecovery(
      snapshot: snapshot,
      playbackSource: resolved.playbackSource,
      playUrls: resolved.playUrls,
      selectedQuality: quality,
    );
    _showQualityFallbackHint(
      requestedQuality: quality,
      effectiveQuality: resolved.effectiveQuality,
    );
  }

  Future<void> refreshPlaybackSource(
    LoadedRoomSnapshot snapshot,
    LivePlayQuality quality, {
    LivePlayQuality? twitchStartupPromotionQuality,
    bool resetTwitchRecoveryAttempts = false,
    PlaybackSource? preferredPlaybackSource,
    List<LivePlayUrl>? currentPlayUrls,
  }) async {
    var resolved = await context.resolvePlaybackRefresh(snapshot, quality);
    LivePlayUrl? refreshedLine;
    if (preferredPlaybackSource != null && currentPlayUrls != null) {
      refreshedLine = selectTwitchRefreshLine(
        playbackSource: preferredPlaybackSource,
        currentPlayUrls: currentPlayUrls,
        refreshedPlayUrls: resolved.playUrls,
      );
      if (refreshedLine != null) {
        resolved = ResolvedPlaySource(
          quality: resolved.quality,
          effectiveQuality: resolved.effectiveQuality,
          playUrls: resolved.playUrls,
          playbackSource: context.playbackSourceFromLine(
            refreshedLine,
            quality: resolved.effectiveQuality,
          ),
        );
      }
    }
    context.trace(
      'refresh playback quality=${quality.id}/${quality.label} '
      'line=${refreshedLine?.lineLabel ?? '-'} '
      'playerType=${refreshedLine?.metadata?['playerType'] ?? '-'} '
      'playback=${_summarizePlaybackSource(resolved.playbackSource)}',
    );
    await _applyResolvedPlaybackSource(
      resolved,
      selectedQuality: quality,
      twitchStartupPromotionQuality: twitchStartupPromotionQuality,
      resetTwitchRecoveryAttempts: resetTwitchRecoveryAttempts,
    );
    context.scheduleTwitchRecovery(
      snapshot: snapshot,
      playbackSource: resolved.playbackSource,
      playUrls: resolved.playUrls,
      selectedQuality: quality,
    );
  }

  Future<void> switchLine(
    LivePlayUrl playUrl, {
    bool resetTwitchRecoveryAttempts = true,
  }) async {
    final source = context.playbackSourceFromLine(
      playUrl,
      quality: context.resolveEffectiveQuality() ??
          context.resolveSelectedQuality() ??
          context.resolveLatestLoadedState()?.snapshot.selectedQuality,
    );
    context.trace(
      'manual switch line=${playUrl.lineLabel ?? '-'} '
      'playerType=${playUrl.metadata?['playerType'] ?? '-'} '
      'playback=${_summarizePlaybackSource(source)}',
    );
    if (context.providerId == ProviderId.twitch) {
      context.prepareTwitchForLineSwitch(
        resetAttempts: resetTwitchRecoveryAttempts,
      );
    }
    final bound = await context.bindPlaybackSourceWithRecovery(
      playbackSource: source,
      label: 'manual switch line',
      autoPlay: context.resolveAutoPlayEnabled(),
      autoPlayDelay: context.providerId == ProviderId.twitch
          ? const Duration(milliseconds: 120)
          : Duration.zero,
      preferFreshBackendBeforeFirstSetSource:
          shouldPreRefreshMdkBackendBeforeSameSourceRebind(
        state: context.runtime.readCurrentState(),
        playbackSource: source,
        runtimeBackend: context.runtime.resolveBackend(),
        currentPlaybackSource: context.resolvePlaybackReferenceSource(),
      ),
    );
    if (!bound || !context.isMounted()) {
      return;
    }
    context.updatePlaybackSourceForLineSwitch(
      playbackSource: source,
      hasPlayback: true,
    );
    final latestState = context.resolveLatestLoadedState();
    if (latestState == null) {
      return;
    }
    final selectedQuality = context.resolveSelectedQuality() ??
        latestState.snapshot.selectedQuality;
    final currentPlayUrls = context.resolveCurrentPlayUrls();
    final playUrls = currentPlayUrls.isNotEmpty
        ? currentPlayUrls
        : latestState.snapshot.playUrls;
    context.scheduleTwitchRecovery(
      snapshot: latestState.snapshot,
      playbackSource: source,
      playUrls: playUrls,
      selectedQuality: selectedQuality,
    );
  }

  Future<void> _applyResolvedPlaybackSource(
    ResolvedPlaySource resolved, {
    LivePlayQuality? selectedQuality,
    LivePlayQuality? twitchStartupPromotionQuality,
    bool resetTwitchRecoveryAttempts = true,
  }) async {
    if (context.providerId == ProviderId.twitch) {
      context.prepareTwitchForResolvedPlayback(
        startupPromotionQuality: twitchStartupPromotionQuality,
        resetAttempts: resetTwitchRecoveryAttempts,
      );
    }
    final currentState = context.runtime.readCurrentState();
    var playbackSourceToStore = resolved.playbackSource;
    if (_shouldSkipEquivalentChaturbateRebind(
      currentState: currentState,
      resolved: resolved,
      selectedQuality: selectedQuality,
    )) {
      playbackSourceToStore = currentState.source ?? resolved.playbackSource;
      context.trace(
        'manual apply source skipped equivalent chaturbate proxy '
        'playback=${_summarizePlaybackSource(playbackSourceToStore)}',
      );
    } else {
      final bound = await context.bindPlaybackSourceWithRecovery(
        playbackSource: resolved.playbackSource,
        label: 'manual apply source',
        autoPlay: context.resolveAutoPlayEnabled(),
        autoPlayDelay: context.providerId == ProviderId.twitch
            ? const Duration(milliseconds: 120)
            : Duration.zero,
        preferFreshBackendBeforeFirstSetSource:
            shouldPreRefreshMdkBackendBeforeSameSourceRebind(
          state: currentState,
          playbackSource: resolved.playbackSource,
          runtimeBackend: context.runtime.resolveBackend(),
          currentPlaybackSource: context.resolvePlaybackReferenceSource(),
        ),
      );
      if (!bound || !context.isMounted()) {
        return;
      }
    }
    final activeRoomDetail = context.resolveActiveRoomDetail() ??
        context.resolveLatestLoadedState()?.snapshot.detail;
    if (activeRoomDetail == null) {
      return;
    }
    final nextSelectedQuality = selectedQuality ??
        context.resolveSelectedQuality() ??
        context.resolveLatestLoadedState()?.snapshot.selectedQuality ??
        resolved.quality;
    context.replaceResolvedPlaybackSession(
      activeRoomDetail: activeRoomDetail,
      selectedQuality: nextSelectedQuality,
      effectiveQuality: resolved.effectiveQuality,
      playbackSource: playbackSourceToStore,
      playUrls: resolved.playUrls,
    );
  }

  bool _shouldSkipEquivalentChaturbateRebind({
    required PlayerState currentState,
    required ResolvedPlaySource resolved,
    LivePlayQuality? selectedQuality,
  }) {
    if (context.providerId != ProviderId.chaturbate) {
      return false;
    }
    final currentSource = currentState.source;
    if (currentSource == null ||
        !_isChaturbateProxySource(currentSource) ||
        !_isChaturbateProxySource(resolved.playbackSource)) {
      return false;
    }
    if (currentState.status == PlaybackStatus.error ||
        currentState.status == PlaybackStatus.idle ||
        currentState.status == PlaybackStatus.completed) {
      return false;
    }
    final requestedQuality =
        selectedQuality ?? context.resolveSelectedQuality();
    final currentEffectiveQuality = context.resolveEffectiveQuality();
    if (requestedQuality != null &&
        currentEffectiveQuality != null &&
        (requestedQuality.id != currentEffectiveQuality.id ||
            requestedQuality.label != currentEffectiveQuality.label)) {
      return false;
    }
    return true;
  }

  bool _isChaturbateProxySource(PlaybackSource source) {
    final uri = source.url;
    return uri.host == '127.0.0.1' &&
        uri.pathSegments.contains('chaturbate-llhls');
  }

  void _showQualityFallbackHint({
    required LivePlayQuality requestedQuality,
    required LivePlayQuality effectiveQuality,
  }) {
    if (requestedQuality.id == effectiveQuality.id &&
        requestedQuality.label == effectiveQuality.label) {
      return;
    }
    context.showMessage(
      '已请求 ${requestedQuality.label}，当前源实际返回 ${effectiveQuality.label}',
    );
  }

  void _showPlaybackUnavailableHint(String? reason) {
    context.showMessage(reason ?? '当前房间暂时没有可用播放地址。');
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
