part of 'room_preview_page.dart';

extension _RoomPreviewPagePanelsExtension on _RoomPreviewPageState {
  Widget _buildControlsPanel({
    required BuildContext context,
    required _RoomPageState state,
    required LivePlayQuality selectedQuality,
    required List<PlayerBackend> availableBackends,
    required List<LivePlayUrl> playUrls,
    required PlaybackSource? playbackSource,
    required bool hasPlayback,
    required PlayerState? playerState,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppSurfaceCard(
          child: _buildFlatTileScope(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('播放器',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600, fontSize: 15)),
                if (!hasPlayback) ...[
                  const SizedBox(height: 8),
                  Text(
                    state.snapshot.playbackUnavailableReason ??
                        '当前房间暂时没有可用播放流。',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('播放器设置'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _openPlayerSettings,
                ),
                const Divider(height: 1),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('切换清晰度'),
                  trailing: Text(
                      hasPlayback ? _effectiveQualityOf(state).label : '不可用'),
                  onTap: hasPlayback ? () => _showQualitySheet(state) : null,
                ),
                const Divider(height: 1),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('切换线路'),
                  trailing: Text(
                    hasPlayback && playbackSource != null
                        ? _lineLabelOf(playUrls, playbackSource)
                        : '不可用',
                  ),
                  onTap: hasPlayback && playbackSource != null
                      ? () => _showLineSheet(playUrls, playbackSource)
                      : null,
                ),
                const Divider(height: 1),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('画面尺寸'),
                  trailing: Text(_labelOfScaleMode(_scaleMode)),
                  onTap: () {
                    final modes = PlayerScaleMode.values;
                    final index = modes.indexOf(_scaleMode);
                    _updateScaleMode(modes[(index + 1) % modes.length]);
                  },
                ),
                if (_pipSupported) ...[
                  const Divider(height: 1),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('小窗播放'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: hasPlayback ? _enterPictureInPicture : null,
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        AppSurfaceCard(
          child: _buildFlatTileScope(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('聊天区',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600, fontSize: 15)),
                const SizedBox(height: 12),
                _RoomStepperRow(
                  title: '文字大小',
                  value: _chatTextSize.round(),
                  onChanged: (next) {
                    unawaited(
                      _updateRoomUiPreferences(
                        _roomUiPreferences.copyWith(
                          chatTextSize: next.clamp(12, 22).toDouble(),
                        ),
                      ),
                    );
                  },
                ),
                const Divider(height: 1),
                _RoomStepperRow(
                  title: '上下间隔',
                  value: _chatTextGap.round(),
                  onChanged: (next) {
                    unawaited(
                      _updateRoomUiPreferences(
                        _roomUiPreferences.copyWith(
                          chatTextGap: next.clamp(0, 12).toDouble(),
                        ),
                      ),
                    );
                  },
                ),
                const Divider(height: 1),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _chatBubbleStyle,
                  title: const Text('气泡样式'),
                  onChanged: (value) {
                    unawaited(
                      _updateRoomUiPreferences(
                        _roomUiPreferences.copyWith(chatBubbleStyle: value),
                      ),
                    );
                  },
                ),
                const Divider(height: 1),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _showPlayerSuperChat,
                  title: const Text('播放器中显示SC'),
                  onChanged: (value) {
                    unawaited(
                      _updateRoomUiPreferences(
                        _roomUiPreferences.copyWith(showPlayerSuperChat: value),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        AppSurfaceCard(
          child: _buildFlatTileScope(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('更多设置',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600, fontSize: 15)),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('关键词屏蔽'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () =>
                      Navigator.of(context).pushNamed(AppRoutes.danmakuShield),
                ),
                const Divider(height: 1),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('弹幕设置'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _openDanmakuSettings,
                ),
                const Divider(height: 1),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    _scheduledCloseAt == null
                        ? '定时关闭'
                        : '定时关闭 · ${_scheduledCloseAt!.hour.toString().padLeft(2, '0')}:${_scheduledCloseAt!.minute.toString().padLeft(2, '0')}',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _showAutoCloseSheet,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSuperChatPanel(BuildContext context) {
    return ValueListenableBuilder<List<LiveMessage>>(
      valueListenable: _superChatMessagesNotifier,
      builder: (context, superChatMessages, _) {
        final messages = superChatMessages.take(24).toList(growable: false);
        if (messages.isEmpty) {
          return Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _danmakuSession == null ? '当前没有 SC 会话。' : '暂时还没有 SC 消息。',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var index = 0; index < messages.length; index += 1) ...[
              _DanmakuFeedTile(
                icon: Icons.stars_outlined,
                title: messages[index].content,
                subtitle: [
                  if (messages[index].userName?.isNotEmpty ?? false)
                    messages[index].userName!,
                  if (messages[index].timestamp != null)
                    _formatTimestamp(messages[index].timestamp!),
                ].join(' · '),
              ),
              if (index != messages.length - 1) const SizedBox(height: 8),
            ],
          ],
        );
      },
    );
  }

  Widget _buildChatPanel(BuildContext context, LiveRoomDetail room) {
    return ValueListenableBuilder<List<LiveMessage>>(
      valueListenable: _messagesNotifier,
      builder: (context, messages, _) {
        final theme = Theme.of(context);
        final statusPresentation = _chaturbateRoomStatusOf(room);
        if (_danmakuSession == null || messages.isEmpty) {
          if (statusPresentation != null) {
            return AppSurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    statusPresentation.label,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: _chatTextGap + 6),
                  Text(
                    statusPresentation.description,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      height: 1.4,
                    ),
                  ),
                  SizedBox(height: _chatTextGap + 6),
                  FilledButton.tonalIcon(
                    onPressed: () => _refreshRoom(showFeedback: true),
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('刷新房间状态'),
                  ),
                ],
              ),
            );
          }
          return Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: double.infinity,
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '正在读取直播间信息',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontSize: _chatTextSize,
                        height: 1.28,
                      ),
                    ),
                    SizedBox(height: _chatTextGap + 6),
                    Text(
                      '开始连接弹幕服务器',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontSize: _chatTextSize,
                        height: 1.28,
                      ),
                    ),
                    SizedBox(height: _chatTextGap + 6),
                    Text(
                      '弹幕服务器连接正常',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontSize: _chatTextSize,
                        height: 1.28,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final visibleMessages = messages
            .skip(math.max(0, messages.length - 36))
            .toList(growable: true)
          ..sort((left, right) {
            final leftTime =
                left.timestamp ?? DateTime.fromMillisecondsSinceEpoch(0);
            final rightTime =
                right.timestamp ?? DateTime.fromMillisecondsSinceEpoch(0);
            return leftTime.compareTo(rightTime);
          });
        return Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: double.infinity,
            child: ListView.separated(
              controller: _chatScrollController,
              padding: EdgeInsets.zero,
              physics: const BouncingScrollPhysics(),
              itemCount: visibleMessages.length,
              separatorBuilder: (_, __) => SizedBox(height: _chatTextGap),
              itemBuilder: (context, index) {
                return _RoomChatMessageTile(
                  message: visibleMessages[index],
                  fontSize: _chatTextSize,
                  gap: 0,
                  bubbleStyle: _chatBubbleStyle,
                );
              },
            ),
          ),
        );
      },
    );
  }
}
