import 'package:flutter/material.dart';
import 'package:live_core/live_core.dart';
import 'package:live_player/live_player.dart';
import 'package:nolive_app/src/features/room/application/room_session_controller.dart';
import 'package:nolive_app/src/features/room/presentation/room_preview_page_section_widgets.dart';
import 'package:nolive_app/src/shared/presentation/widgets/persisted_network_image.dart';

typedef EmbeddedPlayerLifecycleViewFlags = ({
  bool pauseUponEnteringBackgroundMode,
  bool resumeUponEnteringForegroundMode,
});

const Object _roomPlayerSurfaceViewDataNoChange = Object();

typedef RoomEmbeddedPlayerViewBuilder = Widget Function(double? aspectRatio);

EmbeddedPlayerLifecycleViewFlags resolveEmbeddedPlayerLifecycleViewFlags({
  required bool androidPlaybackBridgeSupported,
  required bool backgroundAutoPauseEnabled,
}) {
  if (androidPlaybackBridgeSupported) {
    return (
      pauseUponEnteringBackgroundMode: false,
      resumeUponEnteringForegroundMode: false,
    );
  }
  return (
    pauseUponEnteringBackgroundMode: backgroundAutoPauseEnabled,
    resumeUponEnteringForegroundMode: backgroundAutoPauseEnabled,
  );
}

@visibleForTesting
bool resolveRoomPlayerPosterBackdropVisibility({
  required bool fullscreen,
  required bool hasPlayback,
  required bool embedPlayer,
}) {
  return !(fullscreen && hasPlayback && embedPlayer);
}

@immutable
class RoomPlayerSurfaceViewData {
  const RoomPlayerSurfaceViewData({
    required this.room,
    required this.hasPlayback,
    required this.embedPlayer,
    required this.fullscreen,
    required this.suspendEmbeddedPlayer,
    required this.supportsEmbeddedView,
    required this.showDanmakuOverlay,
    required this.showPlayerSuperChat,
    required this.showInlinePlayerChrome,
    required this.playerBindingInFlight,
    required this.backendLabel,
    required this.liveDurationLabel,
    required this.unavailableReason,
    this.statusPresentation,
    this.inlineQualityLabel,
    this.inlineLineLabel,
  });

  final LiveRoomDetail room;
  final bool hasPlayback;
  final bool embedPlayer;
  final bool fullscreen;
  final bool suspendEmbeddedPlayer;
  final bool supportsEmbeddedView;
  final bool showDanmakuOverlay;
  final bool showPlayerSuperChat;
  final bool showInlinePlayerChrome;
  final bool playerBindingInFlight;
  final String backendLabel;
  final String liveDurationLabel;
  final String unavailableReason;
  final RoomChaturbateStatusPresentation? statusPresentation;
  final String? inlineQualityLabel;
  final String? inlineLineLabel;

  String? get posterUrl => room.keyframeUrl ?? room.coverUrl;

  RoomPlayerSurfaceViewData copyWith({
    LiveRoomDetail? room,
    bool? hasPlayback,
    bool? embedPlayer,
    bool? fullscreen,
    bool? suspendEmbeddedPlayer,
    bool? supportsEmbeddedView,
    bool? showDanmakuOverlay,
    bool? showPlayerSuperChat,
    bool? showInlinePlayerChrome,
    bool? playerBindingInFlight,
    String? backendLabel,
    String? liveDurationLabel,
    String? unavailableReason,
    Object? statusPresentation = _roomPlayerSurfaceViewDataNoChange,
    Object? inlineQualityLabel = _roomPlayerSurfaceViewDataNoChange,
    Object? inlineLineLabel = _roomPlayerSurfaceViewDataNoChange,
  }) {
    return RoomPlayerSurfaceViewData(
      room: room ?? this.room,
      hasPlayback: hasPlayback ?? this.hasPlayback,
      embedPlayer: embedPlayer ?? this.embedPlayer,
      fullscreen: fullscreen ?? this.fullscreen,
      suspendEmbeddedPlayer:
          suspendEmbeddedPlayer ?? this.suspendEmbeddedPlayer,
      supportsEmbeddedView: supportsEmbeddedView ?? this.supportsEmbeddedView,
      showDanmakuOverlay: showDanmakuOverlay ?? this.showDanmakuOverlay,
      showPlayerSuperChat: showPlayerSuperChat ?? this.showPlayerSuperChat,
      showInlinePlayerChrome:
          showInlinePlayerChrome ?? this.showInlinePlayerChrome,
      playerBindingInFlight:
          playerBindingInFlight ?? this.playerBindingInFlight,
      backendLabel: backendLabel ?? this.backendLabel,
      liveDurationLabel: liveDurationLabel ?? this.liveDurationLabel,
      unavailableReason: unavailableReason ?? this.unavailableReason,
      statusPresentation:
          statusPresentation == _roomPlayerSurfaceViewDataNoChange
              ? this.statusPresentation
              : statusPresentation as RoomChaturbateStatusPresentation?,
      inlineQualityLabel:
          inlineQualityLabel == _roomPlayerSurfaceViewDataNoChange
              ? this.inlineQualityLabel
              : inlineQualityLabel as String?,
      inlineLineLabel: inlineLineLabel == _roomPlayerSurfaceViewDataNoChange
          ? this.inlineLineLabel
          : inlineLineLabel as String?,
    );
  }
}

class RoomPictureInPictureChild extends StatelessWidget {
  const RoomPictureInPictureChild({
    required this.future,
    required this.currentPlaybackSource,
    required this.currentPlayUrls,
    required this.supportsEmbeddedView,
    required this.buildEmbeddedPlayerView,
    super.key,
  });

  final Future<RoomSessionLoadResult> future;
  final PlaybackSource? currentPlaybackSource;
  final List<LivePlayUrl> currentPlayUrls;
  final bool supportsEmbeddedView;
  final RoomEmbeddedPlayerViewBuilder buildEmbeddedPlayerView;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<RoomSessionLoadResult>(
      future: future,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const ColoredBox(color: Colors.black);
        }
        final state = snapshot.data!;
        final room = state.snapshot.detail;
        final playbackSource =
            currentPlaybackSource ?? state.resolved?.playbackSource;
        final playUrls =
            currentPlayUrls.isEmpty ? state.snapshot.playUrls : currentPlayUrls;
        final hasPlayback = playbackSource != null && playUrls.isNotEmpty;
        final posterUrl = room.keyframeUrl ?? room.coverUrl;

        return ColoredBox(
          color: Colors.black,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (hasPlayback)
                supportsEmbeddedView
                    ? buildEmbeddedPlayerView(null)
                    : const SizedBox.expand()
              else if (posterUrl != null)
                PersistedNetworkImage(
                  imageUrl: posterUrl,
                  bucket: PersistedImageBucket.roomCover,
                  fit: BoxFit.cover,
                  fallback: const SizedBox.shrink(),
                ),
            ],
          ),
        );
      },
    );
  }
}

class RoomPlayerSurfaceSection extends StatelessWidget {
  const RoomPlayerSurfaceSection({
    required this.data,
    required this.buildEmbeddedPlayerView,
    this.onInlineViewportChanged,
    this.onToggleInlineChrome,
    this.onEnterFullscreen,
    this.onRefresh,
    this.onToggleDanmakuOverlay,
    this.onOpenDanmakuSettings,
    this.onShowQuality,
    this.onShowLine,
    this.onKeepInlinePlayerChromeVisible,
    this.danmakuOverlay,
    this.playerSuperChatOverlay,
    super.key,
  });

  final RoomPlayerSurfaceViewData data;
  final RoomEmbeddedPlayerViewBuilder buildEmbeddedPlayerView;
  final ValueChanged<Size>? onInlineViewportChanged;
  final VoidCallback? onToggleInlineChrome;
  final VoidCallback? onEnterFullscreen;
  final VoidCallback? onRefresh;
  final VoidCallback? onToggleDanmakuOverlay;
  final VoidCallback? onOpenDanmakuSettings;
  final VoidCallback? onShowQuality;
  final VoidCallback? onShowLine;
  final VoidCallback? onKeepInlinePlayerChromeVisible;
  final Widget? danmakuOverlay;
  final Widget? playerSuperChatOverlay;

  @override
  Widget build(BuildContext context) {
    final showPosterBackdrop = resolveRoomPlayerPosterBackdropVisibility(
      fullscreen: data.fullscreen,
      hasPlayback: data.hasPlayback,
      embedPlayer: data.embedPlayer,
    );

    return AspectRatio(
      aspectRatio:
          data.fullscreen ? MediaQuery.of(context).size.aspectRatio : 16 / 9,
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (!data.fullscreen &&
              constraints.maxWidth > 0 &&
              constraints.maxHeight > 0) {
            onInlineViewportChanged?.call(constraints.biggest);
          }
          return Stack(
            fit: StackFit.expand,
            children: [
              DecoratedBox(
                decoration: const BoxDecoration(color: Colors.black),
                child: !showPosterBackdrop || data.posterUrl == null
                    ? null
                    : PersistedNetworkImage(
                        imageUrl: data.posterUrl!,
                        bucket: PersistedImageBucket.roomCover,
                        fit: BoxFit.cover,
                        fallback: const SizedBox.shrink(),
                      ),
              ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0x66000000),
                      Color(0x22000000),
                      Color(0x88000000),
                    ],
                  ),
                ),
              ),
              if (data.embedPlayer &&
                  data.hasPlayback &&
                  !data.suspendEmbeddedPlayer)
                Positioned.fill(
                  child: data.supportsEmbeddedView
                      ? buildEmbeddedPlayerView(data.fullscreen ? null : 16 / 9)
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            final compact = constraints.maxHeight < 140;
                            return Center(
                              child: Padding(
                                padding: EdgeInsets.all(compact ? 12 : 20),
                                child: compact
                                    ? DecoratedBox(
                                        decoration: BoxDecoration(
                                          color: Colors.black
                                              .withValues(alpha: 0.42),
                                          borderRadius:
                                              BorderRadius.circular(18),
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 14,
                                            vertical: 10,
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.ondemand_video_rounded,
                                                color: Colors.white
                                                    .withValues(alpha: 0.8),
                                                size: 24,
                                              ),
                                              const SizedBox(width: 8),
                                              Flexible(
                                                child: Text(
                                                  data.backendLabel,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .titleMedium
                                                      ?.copyWith(
                                                        color: Colors.white,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      )
                                    : Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.ondemand_video_rounded,
                                            color: Colors.white
                                                .withValues(alpha: 0.8),
                                            size: 44,
                                          ),
                                          const SizedBox(height: 12),
                                          Text(
                                            data.backendLabel,
                                            style: Theme.of(context)
                                                .textTheme
                                                .headlineSmall
                                                ?.copyWith(color: Colors.white),
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            data.fullscreen
                                                ? '正在进入观看模式'
                                                : '正在加载直播画面',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            textAlign: TextAlign.center,
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodyMedium
                                                ?.copyWith(
                                                  color: Colors.white70,
                                                ),
                                          ),
                                        ],
                                      ),
                              ),
                            );
                          },
                        ),
                )
              else if (!data.hasPlayback)
                Center(
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 300),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.62),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.lock_clock_outlined,
                          color: Colors.white,
                          size: 30,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          data.statusPresentation?.label ?? '当前暂不可播放',
                          textAlign: TextAlign.center,
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          data.unavailableReason,
                          textAlign: TextAlign.center,
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: Colors.white.withValues(alpha: 0.88),
                                    height: 1.35,
                                  ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Text(
                      '全屏中 · 轻触返回房间页',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              if (data.fullscreen &&
                  data.showDanmakuOverlay &&
                  danmakuOverlay != null)
                Positioned.fill(
                  child: IgnorePointer(child: danmakuOverlay!),
                ),
              if (!data.fullscreen)
                Positioned.fill(
                  child: GestureDetector(
                    key: const Key('room-inline-player-tap-target'),
                    behavior: HitTestBehavior.opaque,
                    onTap: onToggleInlineChrome,
                    onDoubleTap: data.hasPlayback ? onEnterFullscreen : null,
                    child: const SizedBox.expand(),
                  ),
                ),
              if (data.fullscreen &&
                  data.showPlayerSuperChat &&
                  playerSuperChatOverlay != null)
                Positioned(
                  left: data.fullscreen ? 18 : 12,
                  bottom: data.fullscreen
                      ? 18
                      : (data.showInlinePlayerChrome ? 62 : 12),
                  child: IgnorePointer(
                    child: playerSuperChatOverlay!,
                  ),
                ),
              if (!data.fullscreen)
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 200),
                  left: 0,
                  right: 0,
                  bottom: data.showInlinePlayerChrome ? 0 : -52,
                  child: IgnorePointer(
                    key: const Key('room-inline-controls-ignore-pointer'),
                    ignoring: !data.showInlinePlayerChrome,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Colors.black87],
                        ),
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            key: const Key('room-inline-refresh-button'),
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints.tightFor(
                              width: 32,
                              height: 32,
                            ),
                            iconSize: 18,
                            onPressed: data.playerBindingInFlight
                                ? null
                                : () {
                                    onRefresh?.call();
                                    onKeepInlinePlayerChromeVisible?.call();
                                  },
                            color: Colors.white,
                            icon: const Icon(Icons.refresh),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints.tightFor(
                              width: 32,
                              height: 32,
                            ),
                            iconSize: 18,
                            onPressed: data.hasPlayback
                                ? () {
                                    onToggleDanmakuOverlay?.call();
                                    onKeepInlinePlayerChromeVisible?.call();
                                  }
                                : null,
                            color: Colors.white,
                            icon: Icon(
                              data.showDanmakuOverlay
                                  ? Icons.subtitles_outlined
                                  : Icons.subtitles_off_outlined,
                            ),
                          ),
                          if (data.hasPlayback && data.showDanmakuOverlay)
                            IconButton(
                              key: const Key(
                                'room-inline-danmaku-settings-button',
                              ),
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints.tightFor(
                                width: 32,
                                height: 32,
                              ),
                              iconSize: 18,
                              onPressed: () {
                                onOpenDanmakuSettings?.call();
                                onKeepInlinePlayerChromeVisible?.call();
                              },
                              color: Colors.white,
                              icon: const Icon(Icons.tune_rounded),
                            ),
                          if (data.liveDurationLabel.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(left: 4),
                              child: Text(
                                data.liveDurationLabel,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: Colors.white,
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w500,
                                    ),
                              ),
                            ),
                          const Spacer(),
                          if (data.hasPlayback &&
                              onShowQuality != null &&
                              (data.inlineQualityLabel?.isNotEmpty ?? false))
                            TextButton(
                              onPressed: () {
                                onShowQuality?.call();
                                onKeepInlinePlayerChromeVisible?.call();
                              },
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 4),
                                minimumSize: const Size(0, 32),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: Text(
                                data.inlineQualityLabel!,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          if (data.hasPlayback &&
                              onShowLine != null &&
                              (data.inlineLineLabel?.isNotEmpty ?? false))
                            TextButton(
                              onPressed: () {
                                onShowLine?.call();
                                onKeepInlinePlayerChromeVisible?.call();
                              },
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 4),
                                minimumSize: const Size(0, 32),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: Text(
                                data.inlineLineLabel!,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          if (data.hasPlayback)
                            IconButton(
                              key: const Key('room-inline-fullscreen-button'),
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints.tightFor(
                                width: 32,
                                height: 32,
                              ),
                              iconSize: 18,
                              onPressed: data.playerBindingInFlight
                                  ? null
                                  : onEnterFullscreen,
                              color: Colors.white,
                              icon: const Icon(Icons.fullscreen),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
