part of 'room_preview_page.dart';

extension _RoomPreviewPageFollowExtension on _RoomPreviewPageState {
  Future<void> _toggleFollow(LoadedRoomSnapshot snapshot) async {
    final followed = await widget.bootstrap.toggleFollowRoom(
      providerId: snapshot.providerId.value,
      roomId: snapshot.detail.roomId,
      streamerName: snapshot.detail.streamerName,
      streamerAvatarUrl: snapshot.detail.streamerAvatarUrl,
      title: snapshot.detail.title,
      areaName: snapshot.detail.areaName,
      coverUrl: snapshot.detail.coverUrl,
      keyframeUrl: snapshot.detail.keyframeUrl,
    );
    if (!mounted) {
      return;
    }
    FollowWatchlist? nextWatchlist;
    final watchlist = _runtimeFollowWatchlistSnapshot;
    if (followed) {
      if (watchlist != null) {
        final record = await _findFollowRecord(
          providerId: snapshot.providerId.value,
          roomId: snapshot.detail.roomId,
        );
        if (record != null) {
          final currentEntry = FollowWatchEntry(
            record: record,
            detail: snapshot.detail,
          );
          nextWatchlist = FollowWatchlist(
            entries: [
              currentEntry,
              ...watchlist.entries.where(
                (entry) =>
                    entry.record.providerId != snapshot.providerId.value ||
                    entry.record.roomId != snapshot.detail.roomId,
              ),
            ],
          );
        }
      }
    } else if (watchlist != null) {
      nextWatchlist = FollowWatchlist(
        entries: watchlist.entries
            .where(
              (entry) =>
                  entry.record.providerId != snapshot.providerId.value ||
                  entry.record.roomId != snapshot.detail.roomId,
            )
            .toList(growable: false),
      );
    }
    _updateViewState(() {
      _isFollowed = followed;
      _followWatchlistRequestId += 1;
      _followWatchlistFuture = null;
      if (nextWatchlist != null) {
        _followWatchlistCache = nextWatchlist;
        _followWatchlistHydrated = true;
      } else {
        _followWatchlistHydrated = false;
      }
    });
    if (nextWatchlist != null) {
      widget.bootstrap.followWatchlistSnapshot.value = nextWatchlist;
    }
    if (_selectedPanel == _RoomPanel.follow && nextWatchlist == null) {
      unawaited(_ensureFollowWatchlistLoaded(force: true));
    }
  }

  Future<FollowRecord?> _findFollowRecord({
    required String providerId,
    required String roomId,
  }) async {
    final records = await widget.bootstrap.followRepository.listAll();
    for (final record in records) {
      if (record.providerId == providerId && record.roomId == roomId) {
        return record;
      }
    }
    return null;
  }

  void _openFollowRoom(FollowWatchEntry entry) {
    if (entry.record.providerId == widget.providerId.value &&
        entry.roomId == widget.roomId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前已经在这个直播间里了')),
      );
      return;
    }
    Navigator.of(context).pushReplacementNamed(
      AppRoutes.room,
      arguments: RoomRouteArguments(
        providerId: ProviderId(entry.record.providerId),
        roomId: entry.roomId,
      ),
    );
  }

  (String, String) _describeRoomLoadError(Object? error) {
    if (error case final ProviderParseException providerError
        when providerError.providerId == ProviderId.chaturbate) {
      final message = providerError.message;
      if (message.contains('Cloudflare challenge') ||
          message.contains('status 403') ||
          message.contains('status 401')) {
        return (
          'Chaturbate 请求被拦截',
          '当前房间页请求被 Chaturbate 或 Cloudflare 拦截。请回到账号管理，优先使用 Chaturbate 的“网页登录”重新完成验证并保存 Cookie；如果仍手动粘贴，也请复制能正常打开该房间的浏览器完整 Cookie。'
        );
      }
      if (message.contains('initialRoomDossier') ||
          message.contains('push_services') ||
          message.contains('csrftoken')) {
        return (
          'Chaturbate 房间页解析失败',
          '当前房间页没有返回预期的初始化数据，通常是页面结构变化或返回了异常页。建议先重试；如果持续出现，需要按最新页面结构调整解析器。'
        );
      }
    }
    return ('暂时打不开这个直播间', '请稍后重试，或者切换线路与播放器设置后再回来。');
  }

  Widget _buildFollowPanel({
    required BuildContext context,
  }) {
    return FutureBuilder<FollowWatchlist>(
      future: _followWatchlistFuture,
      initialData: _followWatchlistCache,
      builder: (context, snapshot) {
        final isLoading = snapshot.connectionState == ConnectionState.waiting;
        final watchlist = snapshot.data;

        if (watchlist == null && isLoading) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildFollowPanelHeader(
                context: context,
                watchlist: const FollowWatchlist(entries: []),
                isLoading: true,
              ),
              const SizedBox(height: 8),
              _buildFollowLoadingState(context),
            ],
          );
        }

        if (snapshot.hasError && watchlist == null) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildFollowPanelHeader(
                context: context,
                watchlist: const FollowWatchlist(entries: []),
                isLoading: false,
              ),
              AppSurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '关注列表加载失败',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text('${snapshot.error}'),
                    const SizedBox(height: 12),
                    FilledButton.tonal(
                      onPressed: () =>
                          _ensureFollowWatchlistLoaded(force: true),
                      child: const Text('重试'),
                    ),
                  ],
                ),
              ),
            ],
          );
        }

        final resolvedWatchlist =
            watchlist ?? const FollowWatchlist(entries: []);
        final entries = resolvedWatchlist.entries
            .where((entry) => entry.isLive)
            .toList(growable: false)
          ..sort((left, right) {
            final leftCurrent =
                left.record.providerId == widget.providerId.value &&
                    left.roomId == widget.roomId;
            final rightCurrent =
                right.record.providerId == widget.providerId.value &&
                    right.roomId == widget.roomId;
            if (leftCurrent != rightCurrent) {
              return leftCurrent ? -1 : 1;
            }
            final liveCompare =
                (right.isLive ? 1 : 0).compareTo(left.isLive ? 1 : 0);
            if (liveCompare != 0) {
              return liveCompare;
            }
            return left.displayStreamerName
                .compareTo(right.displayStreamerName);
          });

        if (entries.isEmpty) {
          final emptyMessage = watchlist == null
              ? '这里会显示最近一次刷新后仍在直播的关注房间。先点右上角刷新，就能对齐关注页当前的开播结果。'
              : '当前没有正在直播的关注房间。点右上角刷新后，会重新同步关注页的开播结果。';
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildFollowPanelHeader(
                context: context,
                watchlist: resolvedWatchlist,
                isLoading: isLoading,
              ),
              AppSurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(emptyMessage),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: isLoading
                              ? null
                              : () => _ensureFollowWatchlistLoaded(force: true),
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('刷新关注列表'),
                        ),
                        TextButton.icon(
                          onPressed: () => Navigator.of(
                            context,
                            rootNavigator: true,
                          ).pushNamed(AppRoutes.followSettings),
                          icon: const Icon(Icons.favorite_border_rounded),
                          label: const Text('打开关注设置'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildFollowPanelHeader(
              context: context,
              watchlist: resolvedWatchlist,
              isLoading: isLoading,
            ),
            const SizedBox(height: 8),
            for (var index = 0; index < entries.length; index += 1)
              Padding(
                padding: EdgeInsets.only(
                  bottom: index == entries.length - 1 ? 0 : 3,
                ),
                child: FollowWatchRow(
                  key: Key(
                    'room-follow-entry-${entries[index].record.providerId}-${entries[index].roomId}',
                  ),
                  entry: entries[index],
                  providerDescriptor: widget.bootstrap.providerRegistry
                          .findDescriptorById(
                              entries[index].record.providerId) ??
                      ProviderDescriptor(
                        id: ProviderId(entries[index].record.providerId),
                        displayName: entries[index].record.providerId,
                        capabilities: const {},
                        supportedPlatforms: const {ProviderPlatform.android},
                        maturity: ProviderMaturity.inMigration,
                      ),
                  isPlaying: entries[index].record.providerId ==
                          widget.providerId.value &&
                      entries[index].roomId == widget.roomId,
                  onTap: () => _openFollowRoom(entries[index]),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildFollowPanelHeader({
    required BuildContext context,
    required FollowWatchlist watchlist,
    required bool isLoading,
  }) {
    final theme = Theme.of(context);
    final hasSnapshot =
        watchlist.entries.isNotEmpty || _followWatchlistHydrated;
    final summary = !hasSnapshot
        ? '显示最近一次刷新后仍在直播的关注房间。'
        : watchlist.liveCount == 0
            ? '当前没有开播中的关注房间'
            : '${watchlist.liveCount} 个正在直播 · 共 ${watchlist.entries.length} 个关注房间';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '关注列表',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: 15.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    summary,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              key: const Key('room-follow-refresh-button'),
              tooltip: '刷新关注列表',
              onPressed: isLoading
                  ? null
                  : () => _ensureFollowWatchlistLoaded(force: true),
              icon: isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded),
            ),
            IconButton(
              key: const Key('room-follow-settings-button'),
              tooltip: '打开关注设置',
              onPressed: () => Navigator.of(
                context,
                rootNavigator: true,
              ).pushNamed(AppRoutes.followSettings),
              icon: const Icon(Icons.tune_rounded),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFollowLoadingState(BuildContext context) {
    final theme = Theme.of(context);
    final baseColor = theme.colorScheme.surfaceContainerHighest
        .withValues(alpha: theme.brightness == Brightness.dark ? 0.45 : 0.7);
    return Column(
      children: List.generate(
        3,
        (index) => Padding(
          padding: EdgeInsets.only(bottom: index == 2 ? 0 : 3),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: baseColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          height: 12,
                          width: 136,
                          decoration: BoxDecoration(
                            color: baseColor,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          height: 10,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: baseColor,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          height: 10,
                          width: 156,
                          decoration: BoxDecoration(
                            color: baseColor,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
