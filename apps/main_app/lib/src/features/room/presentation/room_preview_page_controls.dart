import 'package:flutter/material.dart';
import 'package:nolive_app/src/features/room/presentation/room_controls_presentation_helpers.dart';
import 'package:nolive_app/src/features/room/presentation/room_controls_view_data.dart';
import 'package:nolive_app/src/shared/presentation/widgets/app_surface_card.dart';

class RoomControlsPanel extends StatelessWidget {
  const RoomControlsPanel({
    required this.wrapFlatTileScope,
    required this.viewData,
    required this.onOpenPlayerSettings,
    required this.onShowQuality,
    required this.onShowLine,
    required this.onCycleScaleMode,
    required this.onEnterPictureInPicture,
    required this.onToggleDesktopMiniWindow,
    required this.onCaptureScreenshot,
    required this.onShowDebugPanel,
    required this.onUpdateChatTextSize,
    required this.onUpdateChatTextGap,
    required this.onUpdateChatBubbleStyle,
    required this.onUpdateShowPlayerSuperChat,
    required this.onUpdatePlayerSuperChatDisplaySeconds,
    required this.onOpenDanmakuShield,
    required this.onOpenDanmakuSettings,
    required this.onShowAutoCloseSheet,
    super.key,
  });

  final RoomWrapFlatTileScope wrapFlatTileScope;
  final RoomControlsViewData viewData;
  final VoidCallback onOpenPlayerSettings;
  final VoidCallback onShowQuality;
  final VoidCallback onShowLine;
  final VoidCallback onCycleScaleMode;
  final VoidCallback onEnterPictureInPicture;
  final VoidCallback onToggleDesktopMiniWindow;
  final VoidCallback onCaptureScreenshot;
  final VoidCallback onShowDebugPanel;
  final ValueChanged<int> onUpdateChatTextSize;
  final ValueChanged<int> onUpdateChatTextGap;
  final ValueChanged<bool> onUpdateChatBubbleStyle;
  final ValueChanged<bool> onUpdateShowPlayerSuperChat;
  final ValueChanged<int> onUpdatePlayerSuperChatDisplaySeconds;
  final VoidCallback onOpenDanmakuShield;
  final VoidCallback onOpenDanmakuSettings;
  final VoidCallback onShowAutoCloseSheet;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppSurfaceCard(
          child: wrapFlatTileScope(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '播放器',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                if (!viewData.hasPlayback) ...[
                  const SizedBox(height: 8),
                  Text(
                    viewData.playbackUnavailableReason,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('播放器设置'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: onOpenPlayerSettings,
                ),
                const Divider(height: 1),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('切换清晰度'),
                  trailing: Text(viewData.hasPlayback
                      ? viewData.effectiveQualityLabel
                      : '不可用'),
                  onTap: viewData.hasPlayback ? onShowQuality : null,
                ),
                const Divider(height: 1),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('切换线路'),
                  trailing: Text(
                      viewData.hasPlayback ? viewData.currentLineLabel : '不可用'),
                  onTap: viewData.hasPlayback ? onShowLine : null,
                ),
                const Divider(height: 1),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('画面尺寸'),
                  trailing: Text(viewData.scaleModeLabel),
                  onTap: onCycleScaleMode,
                ),
                if (viewData.pipSupported) ...[
                  const Divider(height: 1),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('小窗播放'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap:
                        viewData.hasPlayback ? onEnterPictureInPicture : null,
                  ),
                ],
                if (viewData.supportsDesktopMiniWindow) ...[
                  const Divider(height: 1),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      viewData.desktopMiniWindowActive ? '退出桌面小窗' : '桌面小窗',
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap:
                        viewData.hasPlayback ? onToggleDesktopMiniWindow : null,
                  ),
                ],
                if (viewData.supportsPlayerCapture) ...[
                  const Divider(height: 1),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('截图'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: onCaptureScreenshot,
                  ),
                ],
                const Divider(height: 1),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('调试面板'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: onShowDebugPanel,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        AppSurfaceCard(
          child: wrapFlatTileScope(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '聊天区',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 12),
                _RoomStepperRow(
                  title: '文字大小',
                  value: viewData.chatTextSize,
                  onChanged: onUpdateChatTextSize,
                ),
                const Divider(height: 1),
                _RoomStepperRow(
                  title: '上下间隔',
                  value: viewData.chatTextGap,
                  onChanged: onUpdateChatTextGap,
                ),
                const Divider(height: 1),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: viewData.chatBubbleStyle,
                  title: const Text('气泡样式'),
                  onChanged: onUpdateChatBubbleStyle,
                ),
                const Divider(height: 1),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: viewData.showPlayerSuperChat,
                  title: const Text('播放器中显示SC'),
                  onChanged: onUpdateShowPlayerSuperChat,
                ),
                const Divider(height: 1),
                _RoomStepperRow(
                  title: 'SC 展示时长',
                  value: viewData.playerSuperChatDisplaySeconds,
                  suffix: '秒',
                  onChanged: onUpdatePlayerSuperChatDisplaySeconds,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        AppSurfaceCard(
          child: wrapFlatTileScope(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '更多设置',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('关键词屏蔽'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: onOpenDanmakuShield,
                ),
                const Divider(height: 1),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('弹幕设置'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: onOpenDanmakuSettings,
                ),
                const Divider(height: 1),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    viewData.scheduledCloseAt == null
                        ? '定时关闭'
                        : '定时关闭 · ${viewData.scheduledCloseAt!.hour.toString().padLeft(2, '0')}:${viewData.scheduledCloseAt!.minute.toString().padLeft(2, '0')}',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: onShowAutoCloseSheet,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _RoomStepperRow extends StatelessWidget {
  const _RoomStepperRow({
    required this.title,
    required this.value,
    required this.onChanged,
    this.suffix = '',
  });

  final String title;
  final int value;
  final ValueChanged<int> onChanged;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                    fontSize: 13.5,
                  ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints.tightFor(width: 28, height: 28),
                  onPressed: () => onChanged(value - 1),
                  iconSize: 18,
                  icon: const Icon(Icons.remove),
                ),
                SizedBox(
                  width: suffix.isEmpty ? 32 : 52,
                  child: Center(
                    child: Text('$value$suffix'),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints.tightFor(width: 28, height: 28),
                  onPressed: () => onChanged(value + 1),
                  iconSize: 18,
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
