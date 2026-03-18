import 'dart:async';

import 'package:flutter/material.dart';
import 'package:live_core/live_core.dart';
import 'package:live_storage/live_storage.dart';
import 'package:nolive_app/src/app/bootstrap/bootstrap.dart';
import 'package:nolive_app/src/app/routing/app_routes.dart';
import 'package:nolive_app/src/features/settings/application/manage_history_preferences_use_case.dart';
import 'package:nolive_app/src/shared/presentation/widgets/app_surface_card.dart';
import 'package:nolive_app/src/shared/presentation/widgets/empty_state_card.dart';

class WatchHistoryPage extends StatefulWidget {
  const WatchHistoryPage({required this.bootstrap, super.key});

  final AppBootstrap bootstrap;

  @override
  State<WatchHistoryPage> createState() => _WatchHistoryPageState();
}

class _WatchHistoryPageState extends State<WatchHistoryPage> {
  List<HistoryRecord> _records = const [];
  HistoryPreferences _preferences = const HistoryPreferences();
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final snapshot = await widget.bootstrap.listLibrarySnapshot();
      final preferences = await widget.bootstrap.loadHistoryPreferences();
      if (!mounted) {
        return;
      }
      setState(() {
        _records = snapshot.history;
        _preferences = preferences;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = '$error';
        _isLoading = false;
      });
    }
  }

  Future<void> _removeRecord(HistoryRecord record) async {
    await widget.bootstrap.removeHistoryRecord(
      providerId: record.providerId,
      roomId: record.roomId,
    );
    await _refresh();
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已删除 ${_displayStreamerName(record)}')),
    );
  }

  Future<void> _clearHistory() async {
    if (_records.isEmpty) {
      return;
    }
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            return AlertDialog(
              title: const Text('清空全部观看记录'),
              content: const Text('此操作不可撤销，是否继续？'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('确认清空'),
                ),
              ],
            );
          },
        ) ??
        false;
    if (!confirmed) {
      return;
    }
    await widget.bootstrap.clearHistory();
    await _refresh();
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已清空观看记录')),
    );
  }

  Future<void> _setHistoryRecordingEnabled(bool enabled) async {
    final next = _preferences.copyWith(recordWatchHistory: enabled);
    setState(() {
      _preferences = next;
    });
    await widget.bootstrap.updateHistoryPreferences(next);
  }

  void _openRoom(HistoryRecord record) {
    Navigator.of(context).pushNamed(
      AppRoutes.room,
      arguments: RoomRouteArguments(
        providerId: ProviderId(record.providerId),
        roomId: record.roomId,
      ),
    );
  }

  String _providerLabel(HistoryRecord record) {
    final descriptor = widget.bootstrap.providerRegistry.findDescriptorById(
      record.providerId,
    );
    if (descriptor != null) {
      return descriptor.displayName;
    }
    return switch (record.providerId) {
      'bilibili' => '哔哩哔哩',
      'chaturbate' => 'Chaturbate',
      'douyu' => '斗鱼',
      'huya' => '虎牙',
      'douyin' => '抖音直播',
      _ => record.providerId,
    };
  }

  String _displayStreamerName(HistoryRecord record) {
    final value = record.streamerName.trim();
    return value.isEmpty ? '未知主播' : value;
  }

  String _displayTitle(HistoryRecord record) {
    final value = record.title.trim();
    return value.isEmpty ? '房间号 ${record.roomId}' : value;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('观看记录'),
        actions: [
          TextButton(
            key: const Key('watch-history-clear-button'),
            onPressed: _isLoading || _records.isEmpty ? null : _clearHistory,
            child: const Text('清空'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }
    if (_errorMessage != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        children: [
          _HistoryRecordingCard(
            enabled: _preferences.recordWatchHistory,
            onChanged: _setHistoryRecordingEnabled,
          ),
          const SizedBox(height: 12),
          EmptyStateCard(
            title: '观看记录加载失败',
            message: _errorMessage!,
            icon: Icons.error_outline,
            action: FilledButton.tonal(
              onPressed: _refresh,
              child: const Text('重试'),
            ),
          ),
        ],
      );
    }
    if (_records.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        children: [
          _HistoryRecordingCard(
            enabled: _preferences.recordWatchHistory,
            onChanged: _setHistoryRecordingEnabled,
          ),
          const SizedBox(height: 12),
          EmptyStateCard(
            title: _preferences.recordWatchHistory ? '暂无观看记录' : '观看记录已关闭',
            message: _preferences.recordWatchHistory
                ? '打开任意直播间后，这里会自动记录最近访问。'
                : '重新开启后，新进入的直播间才会继续写入记录。',
            icon: Icons.history_toggle_off,
            action: FilledButton.tonal(
              onPressed: _refresh,
              child: const Text('刷新'),
            ),
          ),
        ],
      );
    }
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      itemCount: _records.length + 1,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        if (index == 0) {
          return _HistoryRecordingCard(
            enabled: _preferences.recordWatchHistory,
            onChanged: _setHistoryRecordingEnabled,
          );
        }
        final record = _records[index - 1];
        return _HistoryRecordTile(
          key: Key('watch-history-item-${record.providerId}-${record.roomId}'),
          streamerName: _displayStreamerName(record),
          providerLabel: _providerLabel(record),
          title: _displayTitle(record),
          roomLabel: '房间号 ${record.roomId}',
          viewedAtLabel: _formatViewedAt(record.viewedAt),
          deleteButtonKey: Key(
            'watch-history-delete-${record.providerId}-${record.roomId}',
          ),
          onTap: () => _openRoom(record),
          onDelete: () => _removeRecord(record),
        );
      },
    );
  }
}

class _HistoryRecordingCard extends StatelessWidget {
  const _HistoryRecordingCard({
    required this.enabled,
    required this.onChanged,
  });

  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      child: SwitchListTile.adaptive(
        key: const Key('watch-history-recording-switch'),
        contentPadding: EdgeInsets.zero,
        value: enabled,
        title: const Text('记录观看历史'),
        subtitle: Text(enabled ? '进入直播间时自动写入观看记录' : '当前不会新增观看记录'),
        onChanged: onChanged,
      ),
    );
  }
}

class _HistoryRecordTile extends StatelessWidget {
  const _HistoryRecordTile({
    required this.streamerName,
    required this.providerLabel,
    required this.title,
    required this.roomLabel,
    required this.viewedAtLabel,
    required this.deleteButtonKey,
    required this.onTap,
    required this.onDelete,
    super.key,
  });

  final String streamerName;
  final String providerLabel;
  final String title;
  final String roomLabel;
  final String viewedAtLabel;
  final Key deleteButtonKey;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return AppSurfaceCard(
      padding: EdgeInsets.zero,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              streamerName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            viewedAtLabel,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '$providerLabel · $roomLabel',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  key: deleteButtonKey,
                  tooltip: '删除记录',
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _formatViewedAt(DateTime viewedAt) {
  final now = DateTime.now();
  if (DateUtils.isSameDay(now, viewedAt)) {
    return '${_twoDigits(viewedAt.hour)}:${_twoDigits(viewedAt.minute)}';
  }
  return '${_twoDigits(viewedAt.month)}-${_twoDigits(viewedAt.day)} '
      '${_twoDigits(viewedAt.hour)}:${_twoDigits(viewedAt.minute)}';
}

String _twoDigits(int value) => value.toString().padLeft(2, '0');
