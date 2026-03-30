part of 'room_preview_page.dart';

extension _RoomPreviewPagePlayerSurfaceExtension on _RoomPreviewPageState {
  Widget _buildPictureInPictureChild() {
    return FutureBuilder<_RoomPageState>(
      future: _future,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const ColoredBox(color: Colors.black);
        }
        final state = snapshot.data!;
        final room = state.snapshot.detail;
        final playbackSource =
            _playbackSource ?? state.resolved?.playbackSource;
        final playUrls =
            _playUrls.isEmpty ? state.snapshot.playUrls : _playUrls;
        final hasPlayback = playbackSource != null && playUrls.isNotEmpty;
        final posterUrl = room.keyframeUrl ?? room.coverUrl;

        return ColoredBox(
          color: Colors.black,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (hasPlayback)
                widget.bootstrap.player.supportsEmbeddedView
                    ? widget.bootstrap.player.buildView(
                        key: ValueKey(
                          'room-player-${widget.bootstrap.player.backend.name}-pip',
                        ),
                        aspectRatio: null,
                        fit: _fitForScaleMode(),
                        pauseUponEnteringBackgroundMode:
                            _backgroundAutoPauseEnabled,
                        resumeUponEnteringForegroundMode:
                            _backgroundAutoPauseEnabled,
                      )
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

  Widget _buildPlayerHero({
    required BuildContext context,
    required LiveRoomDetail room,
    required PlaybackSource? playbackSource,
    required bool hasPlayback,
    required bool embedPlayer,
    required bool fullscreen,
    VoidCallback? onShowQuality,
    VoidCallback? onShowLine,
    String? inlineQualityLabel,
    String? inlineLineLabel,
  }) {
    final posterUrl = room.keyframeUrl ?? room.coverUrl;
    final statusPresentation = _chaturbateRoomStatusOf(room);
    final unavailableReason =
        statusPresentation?.description ?? '当前房间暂时没有公开播放流，请稍后刷新重试。';

    return AspectRatio(
      aspectRatio:
          fullscreen ? MediaQuery.of(context).size.aspectRatio : 16 / 9,
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (!fullscreen &&
              constraints.maxWidth > 0 &&
              constraints.maxHeight > 0) {
            _inlinePlayerViewportSize = constraints.biggest;
          }
          return Stack(
            fit: StackFit.expand,
            children: [
              DecoratedBox(
                decoration: const BoxDecoration(color: Colors.black),
                child: posterUrl == null
                    ? null
                    : PersistedNetworkImage(
                        imageUrl: posterUrl,
                        bucket: PersistedImageBucket.roomCover,
                        fit: BoxFit.cover,
                        fallback: const SizedBox.shrink(),
                      ),
              ),
              DecoratedBox(
                decoration: const BoxDecoration(
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
              if (embedPlayer && hasPlayback)
                Positioned.fill(
                  child: widget.bootstrap.player.supportsEmbeddedView
                      ? widget.bootstrap.player.buildView(
                          key: ValueKey(
                            'room-player-${widget.bootstrap.player.backend.name}-${fullscreen ? 'fullscreen' : 'inline'}',
                          ),
                          aspectRatio: fullscreen ? null : 16 / 9,
                          fit: _fitForScaleMode(),
                          pauseUponEnteringBackgroundMode:
                              _backgroundAutoPauseEnabled,
                          resumeUponEnteringForegroundMode:
                              _backgroundAutoPauseEnabled,
                        )
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            final backendLabel = widget
                                .bootstrap.player.backend.name
                                .toUpperCase();
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
                                                  backendLabel,
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
                                            backendLabel,
                                            style: Theme.of(context)
                                                .textTheme
                                                .headlineSmall
                                                ?.copyWith(color: Colors.white),
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            fullscreen
                                                ? '正在进入观看模式'
                                                : '正在加载直播画面',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            textAlign: TextAlign.center,
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodyMedium
                                                ?.copyWith(
                                                    color: Colors.white70),
                                          ),
                                        ],
                                      ),
                              ),
                            );
                          },
                        ),
                )
              else if (!hasPlayback)
                Center(
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 300),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
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
                          statusPresentation?.label ?? '当前暂不可播放',
                          textAlign: TextAlign.center,
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          unavailableReason,
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
                        horizontal: 16, vertical: 12),
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
              if (fullscreen && _showDanmakuOverlay)
                Positioned.fill(
                  child: IgnorePointer(
                    child: ValueListenableBuilder<List<LiveMessage>>(
                      valueListenable: _messagesNotifier,
                      builder: (context, messages, _) {
                        final overlayPool = messages
                            .where(
                              (message) =>
                                  message.type != LiveMessageType.online,
                            )
                            .toList(growable: false);
                        final overlayLimit = fullscreen ? 20 : 12;
                        final overlayMessages = overlayPool
                            .skip(
                              math.max(0, overlayPool.length - overlayLimit),
                            )
                            .toList(growable: false);
                        if (overlayMessages.isEmpty) {
                          return const SizedBox.shrink();
                        }
                        return _DanmakuOverlay(
                          key: const Key('room-danmaku-overlay'),
                          messages: overlayMessages,
                          fullscreen: fullscreen,
                          preferences: _danmakuPreferences,
                        );
                      },
                    ),
                  ),
                ),
              if (!fullscreen)
                Positioned.fill(
                  child: GestureDetector(
                    key: const Key('room-inline-player-tap-target'),
                    behavior: HitTestBehavior.opaque,
                    onTap: _toggleInlinePlayerChrome,
                    onDoubleTap: hasPlayback ? _enterFullscreen : null,
                    child: const SizedBox.expand(),
                  ),
                ),
              if (fullscreen && _showPlayerSuperChat)
                Positioned(
                  left: fullscreen ? 18 : 12,
                  bottom: fullscreen ? 18 : (_showInlinePlayerChrome ? 62 : 12),
                  child: IgnorePointer(
                    child: ValueListenableBuilder<List<LiveMessage>>(
                      valueListenable: _playerSuperChatMessagesNotifier,
                      builder: (context, superChatMessages, _) {
                        if (superChatMessages.isEmpty) {
                          return const SizedBox.shrink();
                        }
                        return ConstrainedBox(
                          key: const Key('room-player-super-chat-overlay'),
                          constraints:
                              BoxConstraints(maxWidth: fullscreen ? 300 : 220),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (final message in superChatMessages.reversed)
                                Container(
                                  margin: const EdgeInsets.only(top: 8),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.58),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Text(
                                    message.content,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                        ),
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              if (!fullscreen)
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 200),
                  left: 0,
                  right: 0,
                  bottom: _showInlinePlayerChrome ? 0 : -52,
                  child: IgnorePointer(
                    key: const Key('room-inline-controls-ignore-pointer'),
                    ignoring: !_showInlinePlayerChrome,
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
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints.tightFor(
                                width: 32, height: 32),
                            iconSize: 18,
                            onPressed: () {
                              _refreshRoom(showFeedback: true);
                              _showInlinePlayerChromeTemporarily();
                            },
                            color: Colors.white,
                            icon: const Icon(Icons.refresh),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints.tightFor(
                                width: 32, height: 32),
                            iconSize: 18,
                            onPressed: hasPlayback
                                ? () {
                                    _updateViewState(() {
                                      _showDanmakuOverlay =
                                          !_showDanmakuOverlay;
                                    });
                                    _showInlinePlayerChromeTemporarily();
                                  }
                                : null,
                            color: Colors.white,
                            icon: Icon(
                              _showDanmakuOverlay
                                  ? Icons.subtitles_outlined
                                  : Icons.subtitles_off_outlined,
                            ),
                          ),
                          if (hasPlayback && _showDanmakuOverlay)
                            IconButton(
                              key: const Key(
                                  'room-inline-danmaku-settings-button'),
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints.tightFor(
                                  width: 32, height: 32),
                              iconSize: 18,
                              onPressed: () {
                                _openDanmakuSettings();
                                _showInlinePlayerChromeTemporarily();
                              },
                              color: Colors.white,
                              icon: const Icon(Icons.tune_rounded),
                            ),
                          if (_formatLiveDuration(room.startedAt).isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(left: 4),
                              child: Text(
                                _formatLiveDuration(room.startedAt),
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
                          if (hasPlayback &&
                              onShowQuality != null &&
                              (inlineQualityLabel?.isNotEmpty ?? false))
                            TextButton(
                              onPressed: () {
                                onShowQuality();
                                _showInlinePlayerChromeTemporarily();
                              },
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 4),
                                minimumSize: const Size(0, 32),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: Text(
                                inlineQualityLabel!,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          if (hasPlayback &&
                              onShowLine != null &&
                              (inlineLineLabel?.isNotEmpty ?? false))
                            TextButton(
                              onPressed: () {
                                onShowLine();
                                _showInlinePlayerChromeTemporarily();
                              },
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 4),
                                minimumSize: const Size(0, 32),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: Text(
                                inlineLineLabel!,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          if (hasPlayback)
                            IconButton(
                              key: const Key('room-inline-fullscreen-button'),
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints.tightFor(
                                  width: 32, height: 32),
                              iconSize: 18,
                              onPressed: () {
                                _enterFullscreen();
                              },
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

  String _formatLiveDuration(DateTime? startedAt) {
    if (startedAt == null) {
      return '';
    }
    final elapsed = DateTime.now().difference(startedAt.toLocal());
    if (elapsed.isNegative) {
      return '';
    }
    final hours = elapsed.inHours;
    final minutes = elapsed.inMinutes.remainder(60);
    final seconds = elapsed.inSeconds.remainder(60);
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  String _formatTimestamp(DateTime value) {
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    final second = value.second.toString().padLeft(2, '0');
    return '$hour:$minute:$second';
  }

  String _labelOfScaleMode(PlayerScaleMode scaleMode) {
    return switch (scaleMode) {
      PlayerScaleMode.contain => '适应画面',
      PlayerScaleMode.cover => '铺满画面',
      PlayerScaleMode.fill => '拉伸填满',
      PlayerScaleMode.fitWidth => '按宽适配',
      PlayerScaleMode.fitHeight => '按高适配',
    };
  }

  _ChaturbateRoomStatusPresentation? _chaturbateRoomStatusOf(
    LiveRoomDetail room,
  ) {
    if (room.providerId != ProviderId.chaturbate.value) {
      return null;
    }
    final rawStatus = room.metadata?['roomStatus']?.toString().trim() ?? '';
    if (rawStatus.isEmpty || rawStatus.toLowerCase() == 'public') {
      return null;
    }
    final normalized = rawStatus.toLowerCase();
    if (normalized.contains('private show')) {
      return const _ChaturbateRoomStatusPresentation(
        label: '私密表演中',
        description: '主播当前正在 Private Show 中，暂时没有公开播放流。等表演结束后刷新即可恢复正常播放。',
      );
    }
    if (normalized.contains('group show')) {
      return const _ChaturbateRoomStatusPresentation(
        label: '群组表演中',
        description: '主播当前正在 Group Show 中，暂时没有公开播放流。结束后刷新即可恢复正常播放。',
      );
    }
    if (normalized == 'away') {
      return const _ChaturbateRoomStatusPresentation(
        label: '暂时离开',
        description: '主播暂时离开，当前没有公开播放流。返回公开状态后刷新即可恢复。',
      );
    }
    if (normalized == 'offline') {
      return const _ChaturbateRoomStatusPresentation(
        label: '未开播',
        description: '当前房间未处于公开直播状态，后续如果恢复开播，刷新即可恢复正常播放。',
      );
    }
    return _ChaturbateRoomStatusPresentation(
      label: rawStatus,
      description: '当前房间状态为 "$rawStatus"，暂时没有公开播放流。请稍后刷新重试。',
    );
  }
}
