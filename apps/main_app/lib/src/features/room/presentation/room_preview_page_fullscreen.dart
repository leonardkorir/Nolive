part of 'room_preview_page.dart';

extension _RoomPreviewPageFullscreenExtension on _RoomPreviewPageState {
  Widget _buildFullscreenOverlay({
    required BuildContext context,
    required _RoomPageState state,
    required LiveRoomDetail room,
    required ProviderDescriptor? descriptor,
    required PlayerState? playerState,
    required PlaybackSource playbackSource,
    required List<LivePlayUrl> playUrls,
  }) {
    final liveDuration = _formatLiveDuration(room.startedAt);
    return ColoredBox(
      key: const Key('room-fullscreen-overlay'),
      color: Colors.black,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                if (_lockFullscreenControls) {
                  return;
                }
                _updateViewState(() {
                  _showFullscreenChrome = !_showFullscreenChrome;
                });
                if (_showFullscreenChrome) {
                  _scheduleFullscreenChromeAutoHide();
                } else {
                  _fullscreenChromeTimer?.cancel();
                }
              },
              onDoubleTap: _lockFullscreenControls
                  ? null
                  : () {
                      if (_isFullscreen) {
                        unawaited(_exitFullscreen());
                      } else {
                        unawaited(_enterFullscreen());
                      }
                    },
              onVerticalDragStart: (details) {
                unawaited(_handleVerticalDragStart(details));
              },
              onVerticalDragUpdate: (details) {
                unawaited(_handleVerticalDragUpdate(details));
              },
              onVerticalDragEnd: (details) {
                unawaited(_handleVerticalDragEnd(details));
              },
              child: _buildPlayerHero(
                context: context,
                room: room,
                playbackSource: playbackSource,
                hasPlayback: true,
                playerState: playerState,
                embedPlayer: true,
                fullscreen: true,
              ),
            ),
          ),
          if (_gestureTipText != null)
            Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  child: Text(
                    _gestureTipText!,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
              ),
            ),
          if (_showFullscreenChrome) ...[
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: Container(
                padding: EdgeInsets.fromLTRB(
                  10,
                  MediaQuery.paddingOf(context).top + 6,
                  10,
                  8,
                ),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black87, Colors.transparent],
                  ),
                ),
                child: Row(
                  children: [
                    IconButton(
                      key: const Key('room-exit-fullscreen-button'),
                      onPressed: _exitFullscreen,
                      color: Colors.white,
                      icon: const Icon(Icons.arrow_back),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${normalizeDisplayText(room.title)} - ${normalizeDisplayText(room.streamerName)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                      ),
                    ),
                    if (_pipSupported)
                      IconButton(
                        onPressed: () {
                          _scheduleFullscreenChromeAutoHide();
                          unawaited(_enterPictureInPicture());
                        },
                        color: Colors.white,
                        icon: const Icon(Icons.picture_in_picture_alt_outlined),
                      ),
                    IconButton(
                      onPressed: () {
                        _showQuickActionsSheet();
                        _scheduleFullscreenChromeAutoHide();
                      },
                      color: Colors.white,
                      icon: const Icon(Icons.more_horiz_rounded),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 8,
              top: MediaQuery.sizeOf(context).height * 0.42,
              child: IconButton(
                key: const Key('room-fullscreen-lock-button'),
                onPressed: () {
                  _updateViewState(() {
                    _lockFullscreenControls = !_lockFullscreenControls;
                  });
                  _scheduleFullscreenChromeAutoHide();
                },
                color: Colors.white,
                icon: Icon(
                  _lockFullscreenControls
                      ? Icons.lock_outline_rounded
                      : Icons.lock_open_outlined,
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: EdgeInsets.fromLTRB(
                  14,
                  18,
                  14,
                  MediaQuery.paddingOf(context).bottom + 12,
                ),
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
                      onPressed: () {
                        _refreshRoom(showFeedback: true);
                        _scheduleFullscreenChromeAutoHide();
                      },
                      color: Colors.white,
                      icon: const Icon(Icons.refresh),
                    ),
                    IconButton(
                      onPressed: () {
                        _updateViewState(() {
                          _showDanmakuOverlay = !_showDanmakuOverlay;
                        });
                        _scheduleFullscreenChromeAutoHide();
                      },
                      color: Colors.white,
                      icon: Icon(
                        _showDanmakuOverlay
                            ? Icons.subtitles_outlined
                            : Icons.subtitles_off_outlined,
                      ),
                    ),
                    IconButton(
                      key: const Key('room-fullscreen-danmaku-settings-button'),
                      onPressed: () {
                        _openDanmakuSettings();
                        _scheduleFullscreenChromeAutoHide();
                      },
                      color: Colors.white,
                      icon: const Icon(Icons.tune_rounded),
                    ),
                    Expanded(
                      child: Center(
                        child: Text(
                          liveDuration.isEmpty ? '' : liveDuration,
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        _showQualitySheet(state);
                        _scheduleFullscreenChromeAutoHide();
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        minimumSize: const Size(0, 36),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        _effectiveQualityOf(state).label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        _showLineSheet(playUrls, playbackSource);
                        _scheduleFullscreenChromeAutoHide();
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        minimumSize: const Size(0, 36),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        playUrls
                                .firstWhere(
                                  (item) =>
                                      item.url == playbackSource.url.toString(),
                                  orElse: () => playUrls.first,
                                )
                                .lineLabel ??
                            '线路',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: _exitFullscreen,
                      color: Colors.white,
                      icon: const Icon(Icons.fullscreen_exit),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
