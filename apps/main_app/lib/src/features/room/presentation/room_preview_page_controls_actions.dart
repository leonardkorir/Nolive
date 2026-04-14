import 'dart:async';

import 'package:flutter/material.dart';
import 'package:live_core/live_core.dart';
import 'package:live_player/live_player.dart';
import 'package:nolive_app/src/features/room/presentation/room_controls_presentation_helpers.dart';
import 'package:nolive_app/src/features/room/presentation/room_controls_view_data.dart';

bool isRoomAutoCloseOptionSelected({
  required int minutes,
  required DateTime? scheduledCloseAt,
  DateTime? now,
}) {
  if (scheduledCloseAt == null) {
    return false;
  }
  final remainingMinutes =
      scheduledCloseAt.difference(now ?? DateTime.now()).inMinutes;
  return (remainingMinutes - minutes).abs() <= 1;
}

Future<void> showRoomPlayerDebugSheet({
  required BuildContext context,
  required RoomWrapFlatTileScope wrapFlatTileScope,
  required RoomPlayerDebugViewData debugViewData,
  required Stream<PlayerDiagnostics> diagnosticsStream,
  required PlayerDiagnostics initialDiagnostics,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: false,
    builder: (context) {
      return StreamBuilder<PlayerDiagnostics>(
        stream: diagnosticsStream,
        initialData: initialDiagnostics,
        builder: (context, snapshot) {
          final diagnostics = snapshot.data ?? initialDiagnostics;
          final children = <Widget>[
            const ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('调试面板'),
              subtitle: Text('当前播放器状态、音视频参数与最近日志。'),
            ),
            _RoomDebugMetadataRow(
              label: '播放器内核',
              value: debugViewData.backendLabel,
            ),
            _RoomDebugMetadataRow(
              label: '播放器状态',
              value: debugViewData.currentStatusLabel,
            ),
            _RoomDebugMetadataRow(
              label: '请求清晰度',
              value: debugViewData.requestedQualityLabel,
            ),
            _RoomDebugMetadataRow(
              label: '实际清晰度',
              value: debugViewData.effectiveQualityLabel,
            ),
            _RoomDebugMetadataRow(
              label: '当前线路',
              value: debugViewData.currentLineLabel,
            ),
            _RoomDebugMetadataRow(
              label: '画面尺寸',
              value: diagnostics.width == null
                  ? '未知'
                  : '${diagnostics.width} x ${diagnostics.height ?? '-'}',
            ),
            _RoomDebugMetadataRow(
              label: '缓冲状态',
              value: diagnostics.buffering ? 'buffering' : 'ready',
            ),
            _RoomDebugMetadataRow(
              label: '已缓冲',
              value: '${diagnostics.buffered.inMilliseconds} ms',
            ),
            _RoomDebugMetadataRow(
              label: '低延迟模式',
              value: diagnostics.lowLatencyMode ? '开启' : '关闭',
            ),
            _RoomDebugMetadataRow(
              label: '重缓冲次数',
              value: '${diagnostics.rebufferCount}',
            ),
            _RoomDebugMetadataRow(
              label: '最近卡顿',
              value: diagnostics.lastRebufferDuration == null
                  ? '暂无'
                  : '${diagnostics.lastRebufferDuration!.inMilliseconds} ms',
            ),
            _RoomDebugMetadataRow(
              label: '画面缩放',
              value: debugViewData.scaleModeLabel,
            ),
            _RoomDebugMetadataRow(
              label: '弹幕频控',
              value: debugViewData.usingNativeDanmakuBatchMask ? '原生' : 'Dart',
            ),
            _RoomDebugMetadataRow(
              label: '调试日志',
              value: diagnostics.debugLogEnabled ? '已开启' : '未开启',
            ),
            if (diagnostics.error?.isNotEmpty ?? false)
              _RoomDebugMetadataRow(label: '最近错误', value: diagnostics.error!),
          ];

          if (diagnostics.videoParams.isNotEmpty) {
            children.add(
              const Padding(
                padding: EdgeInsets.only(top: 16, bottom: 8),
                child: Text('视频参数'),
              ),
            );
            children.addAll(
              diagnostics.videoParams.entries.map(
                (entry) => _RoomDebugMetadataRow(
                  label: entry.key,
                  value: entry.value,
                ),
              ),
            );
          }

          if (diagnostics.audioParams.isNotEmpty) {
            children.add(
              const Padding(
                padding: EdgeInsets.only(top: 16, bottom: 8),
                child: Text('音频参数'),
              ),
            );
            children.addAll(
              diagnostics.audioParams.entries.map(
                (entry) => _RoomDebugMetadataRow(
                  label: entry.key,
                  value: entry.value,
                ),
              ),
            );
          }

          if (diagnostics.recentLogs.isNotEmpty) {
            children.add(
              const Padding(
                padding: EdgeInsets.only(top: 16, bottom: 8),
                child: Text('最近日志'),
              ),
            );
            children.add(
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  diagnostics.recentLogs.join('\n'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            );
          }

          return SafeArea(
            child: wrapFlatTileScope(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                children: children,
              ),
            ),
          );
        },
      );
    },
  );
}

Future<void> showRoomAutoCloseSheet({
  required BuildContext context,
  required RoomWrapFlatTileScope wrapFlatTileScope,
  required DateTime? scheduledCloseAt,
  required void Function(Duration? duration) onSelectDuration,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: false,
    builder: (context) {
      return SafeArea(
        child: wrapFlatTileScope(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text('关闭定时关闭'),
                trailing: scheduledCloseAt == null
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () {
                  Navigator.of(context).pop();
                  onSelectDuration(null);
                },
              ),
              for (final minutes in const [15, 30, 60, 120])
                ListTile(
                  title: Text('$minutes 分钟后关闭'),
                  trailing: isRoomAutoCloseOptionSelected(
                    minutes: minutes,
                    scheduledCloseAt: scheduledCloseAt,
                  )
                      ? const Icon(Icons.check_rounded)
                      : null,
                  onTap: () {
                    Navigator.of(context).pop();
                    onSelectDuration(Duration(minutes: minutes));
                  },
                ),
            ],
          ),
        ),
      );
    },
  );
}

Future<void> showRoomQuickActionsSheet({
  required BuildContext context,
  required RoomWrapFlatTileScope wrapFlatTileScope,
  required RoomControlsViewData viewData,
  required Future<void> Function() onRefresh,
  required Future<void> Function() onShowQuality,
  required Future<void> Function() onShowLine,
  required Future<RoomControlsViewData> Function() onCycleScaleMode,
  required Future<void> Function() onEnterPictureInPicture,
  required Future<void> Function() onToggleDesktopMiniWindow,
  required Future<void> Function() onCaptureScreenshot,
  required Future<void> Function() onShowAutoCloseSheet,
  required Future<void> Function() onShowDebugPanel,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: false,
    isScrollControlled: true,
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (sheetContext) {
      var currentViewData = viewData;
      return SafeArea(
        child: StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            return wrapFlatTileScope(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                children: [
                  ListTile(
                    key: const Key('room-quick-refresh-button'),
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.refresh),
                    title: const Text('刷新'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () async {
                      Navigator.of(sheetContext).pop();
                      await onRefresh();
                    },
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.play_circle_outline),
                    title: const Text('切换清晰度'),
                    subtitle: currentViewData.hasPlayback
                        ? null
                        : Text(currentViewData.playbackUnavailableReason),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: currentViewData.hasPlayback
                        ? () async {
                            Navigator.of(sheetContext).pop();
                            await onShowQuality();
                          }
                        : null,
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.switch_video_outlined),
                    title: const Text('切换线路'),
                    subtitle: currentViewData.hasPlayback
                        ? null
                        : Text(currentViewData.playbackUnavailableReason),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: currentViewData.hasPlayback
                        ? () async {
                            Navigator.of(sheetContext).pop();
                            await onShowLine();
                          }
                        : null,
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.aspect_ratio_outlined),
                    title: const Text('画面尺寸'),
                    trailing: Text(currentViewData.scaleModeLabel),
                    onTap: () async {
                      final nextViewData = await onCycleScaleMode();
                      if (!sheetContext.mounted) {
                        return;
                      }
                      setSheetState(() {
                        currentViewData = nextViewData;
                      });
                    },
                  ),
                  if (currentViewData.pipSupported)
                    ListTile(
                      key: const Key('room-quick-pip-button'),
                      contentPadding: EdgeInsets.zero,
                      leading:
                          const Icon(Icons.picture_in_picture_alt_outlined),
                      title: const Text('小窗播放'),
                      subtitle: currentViewData.hasPlayback
                          ? null
                          : Text(currentViewData.playbackUnavailableReason),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: currentViewData.hasPlayback
                          ? () async {
                              Navigator.of(sheetContext).pop();
                              await onEnterPictureInPicture();
                            }
                          : null,
                    ),
                  if (currentViewData.supportsDesktopMiniWindow)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.open_in_new_rounded),
                      title: Text(
                        currentViewData.desktopMiniWindowActive
                            ? '退出桌面小窗'
                            : '桌面小窗',
                      ),
                      subtitle: currentViewData.hasPlayback
                          ? null
                          : Text(currentViewData.playbackUnavailableReason),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: currentViewData.hasPlayback
                          ? () async {
                              Navigator.of(sheetContext).pop();
                              await onToggleDesktopMiniWindow();
                            }
                          : null,
                    ),
                  if (currentViewData.supportsPlayerCapture)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.camera_alt_outlined),
                      title: const Text('截图'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        unawaited(onCaptureScreenshot());
                      },
                    ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.timer_outlined),
                    title: const Text('定时关闭'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () async {
                      Navigator.of(sheetContext).pop();
                      await onShowAutoCloseSheet();
                    },
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.bug_report_outlined),
                    title: const Text('调试面板'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () async {
                      Navigator.of(sheetContext).pop();
                      await onShowDebugPanel();
                    },
                  ),
                ],
              ),
            );
          },
        ),
      );
    },
  );
}

Future<void> showRoomQualitySheet({
  required BuildContext context,
  required RoomWrapFlatTileScope wrapFlatTileScope,
  required LivePlayQuality selectedQuality,
  required List<LivePlayQuality> qualities,
  required Future<void> Function(LivePlayQuality quality) onSelected,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: false,
    builder: (sheetContext) {
      return SafeArea(
        child: wrapFlatTileScope(
          child: RadioGroup<String>(
            groupValue: selectedQuality.id,
            onChanged: (value) {
              if (value == null) {
                return;
              }
              final quality = qualities.firstWhere(
                (item) => item.id == value,
                orElse: () => selectedQuality,
              );
              Navigator.of(sheetContext).pop();
              unawaited(onSelected(quality));
            },
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.only(top: 8, bottom: 16),
              children: [
                const ListTile(
                  title: Text('切换清晰度'),
                  subtitle: Text('若平台实际返回降档流，会在房间头部显示实际清晰度。'),
                ),
                for (final quality in qualities)
                  RadioListTile<String>(
                    value: quality.id,
                    title: Text(quality.label),
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

Future<void> showRoomLineSheet({
  required BuildContext context,
  required RoomWrapFlatTileScope wrapFlatTileScope,
  required PlaybackSource playbackSource,
  required List<LivePlayUrl> playUrls,
  required Future<void> Function(LivePlayUrl playUrl) onSelected,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: false,
    builder: (sheetContext) {
      return SafeArea(
        child: wrapFlatTileScope(
          child: RadioGroup<String>(
            groupValue: playbackSource.url.toString(),
            onChanged: (value) {
              if (value == null) {
                return;
              }
              final selectedItem = playUrls.firstWhere(
                (item) => item.url == value,
                orElse: () => playUrls.first,
              );
              Navigator.of(sheetContext).pop();
              unawaited(onSelected(selectedItem));
            },
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.only(top: 8, bottom: 16),
              children: [
                const ListTile(
                  title: Text('切换线路'),
                  subtitle: Text('优先选择更稳定的线路，必要时手动切到备用线路。'),
                ),
                for (final item in playUrls)
                  RadioListTile<String>(
                    value: item.url,
                    title: Text(item.lineLabel ?? '线路'),
                    subtitle: Text(
                      item.url,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _RoomDebugMetadataRow extends StatelessWidget {
  const _RoomDebugMetadataRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 104,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
