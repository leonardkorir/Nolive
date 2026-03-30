part of 'room_preview_page.dart';

extension _RoomPreviewPageSectionsExtension on _RoomPreviewPageState {
  Widget _buildLoadingRoomShell({
    required BuildContext context,
    required ProviderDescriptor? descriptor,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final room = _activeRoomDetail;
    final posterUrl = room?.keyframeUrl ?? room?.coverUrl;
    final providerLabel = descriptor?.displayName ?? widget.providerId.value;
    final streamerName = normalizeDisplayText(room?.streamerName);
    final avatarTextSource =
        streamerName.isEmpty ? providerLabel : streamerName;
    final avatarLabel = avatarTextSource.isEmpty
        ? '?'
        : avatarTextSource.substring(0, 1).toUpperCase();

    Widget buildTab(String label, Key key, bool selected) {
      return Expanded(
        child: _RoomPanelTab(
          key: key,
          label: label,
          selected: selected,
          onTap: () {},
        ),
      );
    }

    return ColoredBox(
      color: colorScheme.surface,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
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
                        Color(0xAA000000),
                      ],
                    ),
                  ),
                ),
                Center(
                  child: Container(
                    key: const Key('room-loading-shell'),
                    constraints: const BoxConstraints(maxWidth: 320),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 16,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.62),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator.adaptive(),
                        const SizedBox(height: 14),
                        Text(
                          '正在进入 $providerLabel 房间',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          room?.title ?? '房间号 ${widget.roomId}',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: Colors.white.withValues(alpha: 0.9),
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Material(
            color: colorScheme.surface,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 21,
                    backgroundColor: colorScheme.secondaryContainer,
                    child: Text(
                      avatarLabel,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: colorScheme.onSecondaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          streamerName.isEmpty ? '正在读取主播信息' : streamerName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          providerLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          IgnorePointer(
            child: Material(
              color: colorScheme.surface,
              child: Row(
                children: [
                  buildTab('聊天', const Key('room-panel-tab-chat'), true),
                  buildTab(
                    'SC',
                    const Key('room-panel-tab-super-chat'),
                    false,
                  ),
                  buildTab('关注', const Key('room-panel-tab-follow'), false),
                  buildTab(
                    '设置',
                    const Key('room-panel-tab-settings'),
                    false,
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: AppSurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '房间已经进入，后台继续加载播放和聊天数据',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '视频源解析中',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '弹幕与关注状态稍后补齐',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoomBody({
    required BuildContext context,
    required _RoomPageState state,
    required LiveRoomDetail room,
    required bool fullscreenActive,
    required ProviderDescriptor? descriptor,
    required LivePlayQuality selectedQuality,
    required LivePlayQuality effectiveQuality,
    required PlaybackSource? playbackSource,
    required List<LivePlayUrl> playUrls,
    required bool hasPlayback,
    required List<PlayerBackend> availableBackends,
  }) {
    final tabSwitcher = Material(
      color: Theme.of(context).colorScheme.surface,
      child: Row(
        children: [
          Expanded(
            child: _RoomPanelTab(
              key: const Key('room-panel-tab-chat'),
              label: '聊天',
              selected: _selectedPanel == _RoomPanel.chat,
              onTap: () => _selectPanel(_RoomPanel.chat),
            ),
          ),
          Expanded(
            child: _RoomPanelTab(
              key: const Key('room-panel-tab-super-chat'),
              label: 'SC',
              selected: _selectedPanel == _RoomPanel.superChat,
              onTap: () => _selectPanel(_RoomPanel.superChat),
            ),
          ),
          Expanded(
            child: _RoomPanelTab(
              key: const Key('room-panel-tab-follow'),
              label: '关注',
              selected: _selectedPanel == _RoomPanel.follow,
              onTap: () => _selectPanel(_RoomPanel.follow),
            ),
          ),
          Expanded(
            child: _RoomPanelTab(
              key: const Key('room-panel-tab-settings'),
              label: '设置',
              selected: _selectedPanel == _RoomPanel.settings,
              onTap: () => _selectPanel(_RoomPanel.settings),
            ),
          ),
        ],
      ),
    );

    final panelPageView = _buildRoomPanelPageView(
      context: context,
      state: state,
      room: room,
      selectedQuality: selectedQuality,
      availableBackends: availableBackends,
      playUrls: playUrls,
      playbackSource: playbackSource,
      hasPlayback: hasPlayback,
    );

    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compactHeight = constraints.maxHeight < 680;
          if (compactHeight) {
            return ListView(
              padding: EdgeInsets.zero,
              children: [
                _buildPlayerHero(
                  context: context,
                  room: room,
                  playbackSource: playbackSource,
                  hasPlayback: hasPlayback,
                  embedPlayer: !fullscreenActive,
                  fullscreen: false,
                  onShowQuality:
                      hasPlayback ? () => _showQualitySheet(state) : null,
                  onShowLine: hasPlayback
                      ? () => _showLineSheet(playUrls, playbackSource!)
                      : null,
                  inlineQualityLabel: hasPlayback
                      ? _compactQualityLabel(_effectiveQualityOf(state).label)
                      : null,
                  inlineLineLabel: hasPlayback
                      ? _compactLineLabel(
                          _lineLabelOf(playUrls, playbackSource!))
                      : null,
                ),
                _buildRoomHeader(
                  context: context,
                  state: state,
                  room: room,
                  descriptor: descriptor,
                  selectedQuality: selectedQuality,
                  effectiveQuality: effectiveQuality,
                ),
                tabSwitcher,
                SizedBox(
                  height: 300,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
                    child: panelPageView,
                  ),
                ),
                _buildRoomBottomActions(
                  state: state,
                  room: room,
                ),
              ],
            );
          }

          return Column(
            children: [
              _buildPlayerHero(
                context: context,
                room: room,
                playbackSource: playbackSource,
                hasPlayback: hasPlayback,
                embedPlayer: !fullscreenActive,
                fullscreen: false,
                onShowQuality:
                    hasPlayback ? () => _showQualitySheet(state) : null,
                onShowLine: hasPlayback
                    ? () => _showLineSheet(playUrls, playbackSource!)
                    : null,
                inlineQualityLabel: hasPlayback
                    ? _compactQualityLabel(_effectiveQualityOf(state).label)
                    : null,
                inlineLineLabel: hasPlayback
                    ? _compactLineLabel(_lineLabelOf(playUrls, playbackSource!))
                    : null,
              ),
              _buildRoomHeader(
                context: context,
                state: state,
                room: room,
                descriptor: descriptor,
                selectedQuality: selectedQuality,
                effectiveQuality: effectiveQuality,
              ),
              tabSwitcher,
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
                  child: panelPageView,
                ),
              ),
              _buildRoomBottomActions(
                state: state,
                room: room,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildRoomPanelPageView({
    required BuildContext context,
    required _RoomPageState state,
    required LiveRoomDetail room,
    required LivePlayQuality selectedQuality,
    required List<PlayerBackend> availableBackends,
    required List<LivePlayUrl> playUrls,
    required PlaybackSource? playbackSource,
    required bool hasPlayback,
  }) {
    return PageView(
      key: const Key('room-panel-page-view'),
      controller: _panelPageController,
      onPageChanged: _handlePanelPageChanged,
      children: [
        _buildChatPanel(context, room),
        _buildRoomPanelScrollPage(
          child: _buildSuperChatPanel(context),
        ),
        _buildRoomPanelScrollPage(
          child: _buildFollowPanel(context: context),
        ),
        _buildRoomPanelScrollPage(
          child: _buildControlsPanel(
            context: context,
            state: state,
            selectedQuality: selectedQuality,
            availableBackends: availableBackends,
            playUrls: playUrls,
            playbackSource: playbackSource,
            hasPlayback: hasPlayback,
          ),
        ),
      ],
    );
  }

  Widget _buildRoomPanelScrollPage({
    required Widget child,
  }) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 12),
      child: child,
    );
  }

  Widget _buildRoomHeader({
    required BuildContext context,
    required _RoomPageState state,
    required LiveRoomDetail room,
    required ProviderDescriptor? descriptor,
    required LivePlayQuality selectedQuality,
    required LivePlayQuality effectiveQuality,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final providerLabel = descriptor?.displayName ?? widget.providerId.value;
    final roomStreamerName = normalizeDisplayText(room.streamerName);
    final statusPresentation = _chaturbateRoomStatusOf(room);
    final viewerLabel = room.viewerCount == null
        ? '-'
        : room.viewerCount! >= 10000
            ? '${(room.viewerCount! / 10000).toStringAsFixed(room.viewerCount! >= 100000 ? 0 : 1)}万'
            : '${room.viewerCount!}';

    final showQualityLabel = _hasQualityFallback(state);

    return Material(
      color: colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            StreamerAvatar(
              size: 42,
              imageUrl: room.streamerAvatarUrl,
              fallbackText: roomStreamerName,
              isLive: room.isLive,
              outlineColor: colorScheme.outlineVariant,
              fallbackTextStyle: applyZhTextStyleOrNull(
                Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    roomStreamerName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                          fontSize: 15.5,
                          height: 1.08,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    providerLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 9.5,
                          height: 1.04,
                        ),
                  ),
                  if (statusPresentation != null) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        statusPresentation.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: colorScheme.onSecondaryContainer,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.local_fire_department_rounded,
                      color: Colors.orange,
                      size: 15,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      viewerLabel,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            fontSize: 13.5,
                          ),
                    ),
                  ],
                ),
                if (showQualityLabel) ...[
                  const SizedBox(height: 4),
                  Text(
                    _qualityBadgeLabel(state),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.w500,
                          fontSize: 9,
                          height: 1.02,
                        ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoomBottomActions({
    required _RoomPageState state,
    required LiveRoomDetail room,
  }) {
    final buttonStyle = TextButton.styleFrom(
      foregroundColor: Theme.of(context).colorScheme.onSurface,
      padding: const EdgeInsets.symmetric(vertical: 10),
      minimumSize: Size.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      textStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w500,
            fontSize: 13.5,
          ),
    );
    return SafeArea(
      top: false,
      child: ColoredBox(
        color: Theme.of(context).colorScheme.surface,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: TextButton.icon(
                  key: const Key('room-follow-toggle-button'),
                  style: buttonStyle,
                  onPressed: () => _toggleFollow(state.snapshot),
                  icon: Icon(
                    _isFollowed ? Icons.favorite : Icons.favorite_border,
                    size: 18,
                  ),
                  label: Text(
                    _isFollowed ? '取消关注' : '关注',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              Expanded(
                child: TextButton.icon(
                  style: buttonStyle,
                  onPressed: () => _refreshRoom(showFeedback: true),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text(
                    '刷新',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              Expanded(
                child: TextButton.icon(
                  style: buttonStyle,
                  onPressed: () => _shareRoomLink(room),
                  icon: const Icon(Icons.share_outlined, size: 18),
                  label: const Text(
                    '分享',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
