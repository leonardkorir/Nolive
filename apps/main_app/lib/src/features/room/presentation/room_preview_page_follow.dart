import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:live_core/live_core.dart';
import 'package:nolive_app/src/features/library/application/load_follow_watchlist_use_case.dart';
import 'package:nolive_app/src/features/room/application/room_follow_watchlist_controller.dart';
import 'package:nolive_app/src/shared/presentation/widgets/app_surface_card.dart';
import 'package:nolive_app/src/shared/presentation/widgets/follow_watch_row.dart';

class RoomFollowEntryViewData {
  const RoomFollowEntryViewData({
    required this.entry,
    required this.providerDescriptor,
    required this.isPlaying,
  });

  final FollowWatchEntry entry;
  final ProviderDescriptor providerDescriptor;
  final bool isPlaying;
}

class RoomFollowPanel extends StatelessWidget {
  const RoomFollowPanel({
    required this.followState,
    required this.entries,
    required this.onRefresh,
    required this.onOpenSettings,
    required this.onOpenEntry,
    super.key,
  });

  final RoomFollowWatchlistState followState;
  final List<RoomFollowEntryViewData> entries;
  final VoidCallback onRefresh;
  final VoidCallback onOpenSettings;
  final ValueChanged<FollowWatchEntry> onOpenEntry;

  @override
  Widget build(BuildContext context) {
    final isLoading = followState.isLoading;
    final watchlist = followState.watchlist;

    if (watchlist == null && isLoading) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(
            context: context,
            watchlist: const FollowWatchlist(entries: []),
            isLoading: true,
          ),
          const SizedBox(height: 8),
          _buildLoadingState(context),
        ],
      );
    }

    if (followState.error != null && watchlist == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(
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
                Text('${followState.error}'),
                const SizedBox(height: 12),
                FilledButton.tonal(
                  onPressed: onRefresh,
                  child: const Text('重试'),
                ),
              ],
            ),
          ),
        ],
      );
    }

    final resolvedWatchlist = watchlist ?? const FollowWatchlist(entries: []);
    if (entries.isEmpty) {
      final emptyMessage = watchlist == null
          ? '这里会显示最近一次刷新后仍在直播的关注房间。先点右上角刷新，就能对齐关注页当前的开播结果。'
          : '当前没有正在直播的关注房间。点右上角刷新后，会重新同步关注页的开播结果。';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(
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
                      onPressed: isLoading ? null : onRefresh,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('刷新关注列表'),
                    ),
                    TextButton.icon(
                      onPressed: onOpenSettings,
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
        _buildHeader(
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
                'room-follow-entry-${entries[index].entry.record.providerId}-${entries[index].entry.roomId}',
              ),
              entry: entries[index].entry,
              providerDescriptor: entries[index].providerDescriptor,
              isPlaying: entries[index].isPlaying,
              onTap: () => onOpenEntry(entries[index].entry),
            ),
          ),
      ],
    );
  }

  Widget _buildHeader({
    required BuildContext context,
    required FollowWatchlist watchlist,
    required bool isLoading,
  }) {
    final theme = Theme.of(context);
    final hasSnapshot = watchlist.entries.isNotEmpty || followState.hydrated;
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
              onPressed: isLoading ? null : onRefresh,
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
              onPressed: onOpenSettings,
              icon: const Icon(Icons.tune_rounded),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingState(BuildContext context) {
    final baseColor =
        Theme.of(context).colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.76,
            );
    return AppSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: List<Widget>.generate(
          3,
          (index) => Padding(
            padding: EdgeInsets.only(bottom: index == 2 ? 0 : 10),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest
                    .withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: baseColor,
                        borderRadius: BorderRadius.circular(12),
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
      ),
    );
  }
}

class RoomFullscreenFollowDrawer extends StatelessWidget {
  const RoomFullscreenFollowDrawer({
    required this.showDrawer,
    required this.followState,
    required this.entries,
    required this.onClose,
    required this.onOpenEntry,
    super.key,
  });

  final bool showDrawer;
  final RoomFollowWatchlistState followState;
  final List<RoomFollowEntryViewData> entries;
  final VoidCallback onClose;
  final ValueChanged<FollowWatchEntry> onOpenEntry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final drawerWidth =
        math.min(MediaQuery.sizeOf(context).width * 0.54, 388.0).toDouble();
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      top: MediaQuery.paddingOf(context).top + 12,
      bottom: MediaQuery.paddingOf(context).bottom + 12,
      right: showDrawer ? 12 : -(drawerWidth + 24),
      child: IgnorePointer(
        ignoring: !showDrawer,
        child: SizedBox(
          width: drawerWidth,
          child: DecoratedBox(
            key: const Key('room-fullscreen-follow-drawer'),
            decoration: BoxDecoration(
              color: const Color(0xED11161D),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0x33FFFFFF)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.32),
                  blurRadius: 24,
                  offset: const Offset(-8, 12),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '关注中正在直播',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: const Color(0xFFF8FAFC),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        key: const Key('room-fullscreen-follow-close-button'),
                        onPressed: onClose,
                        color: Colors.white,
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  Text(
                    followState.isLoading
                        ? '正在同步关注页开播结果…'
                        : entries.isEmpty
                            ? '当前没有正在直播的关注房间'
                            : '${entries.length} 个房间可直接切换',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: const Color(0xCCD5DAE1),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: entries.isEmpty
                        ? Center(
                            child: Text(
                              '长按右侧时会显示这里。\n等关注页同步到开播结果后，就能直接切房。',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: const Color(0xCCD5DAE1),
                                height: 1.45,
                              ),
                            ),
                          )
                        : ListView.separated(
                            itemCount: entries.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 6),
                            itemBuilder: (context, index) {
                              final item = entries[index];
                              return FollowWatchRow(
                                key: Key(
                                  'room-fullscreen-follow-entry-${item.entry.record.providerId}-${item.entry.roomId}',
                                ),
                                entry: item.entry,
                                providerDescriptor: item.providerDescriptor,
                                isPlaying: item.isPlaying,
                                highContrastOverlay: true,
                                showSurface: false,
                                showChevron: true,
                                onTap: () => onOpenEntry(item.entry),
                              );
                            },
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
