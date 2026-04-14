import 'package:flutter/material.dart';
import 'package:live_core/live_core.dart';
import 'package:nolive_app/src/features/settings/application/manage_player_preferences_use_case.dart';
import 'package:nolive_app/src/shared/presentation/theme/zh_text.dart';

String formatRoomLiveDuration(DateTime? startedAt) {
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

String formatRoomMessageTimestamp(DateTime value) {
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  final second = value.second.toString().padLeft(2, '0');
  return '$hour:$minute:$second';
}

String labelOfRoomScaleMode(PlayerScaleMode scaleMode) {
  return switch (scaleMode) {
    PlayerScaleMode.contain => '适应画面',
    PlayerScaleMode.cover => '铺满画面',
    PlayerScaleMode.fill => '拉伸填满',
    PlayerScaleMode.fitWidth => '按宽适配',
    PlayerScaleMode.fitHeight => '按高适配',
  };
}

BoxFit fitForRoomScaleMode(PlayerScaleMode scaleMode) {
  return switch (scaleMode) {
    PlayerScaleMode.contain => BoxFit.contain,
    PlayerScaleMode.cover => BoxFit.cover,
    PlayerScaleMode.fill => BoxFit.fill,
    PlayerScaleMode.fitWidth => BoxFit.fitWidth,
    PlayerScaleMode.fitHeight => BoxFit.fitHeight,
  };
}

class RoomChaturbateStatusPresentation {
  const RoomChaturbateStatusPresentation({
    required this.label,
    required this.description,
  });

  final String label;
  final String description;
}

RoomChaturbateStatusPresentation? resolveRoomChaturbateStatusPresentation(
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
    return const RoomChaturbateStatusPresentation(
      label: '私密表演中',
      description: '主播当前正在 Private Show 中，暂时没有公开播放流。等表演结束后刷新即可恢复正常播放。',
    );
  }
  if (normalized.contains('group show')) {
    return const RoomChaturbateStatusPresentation(
      label: '群组表演中',
      description: '主播当前正在 Group Show 中，暂时没有公开播放流。结束后刷新即可恢复正常播放。',
    );
  }
  if (normalized == 'away') {
    return const RoomChaturbateStatusPresentation(
      label: '暂时离开',
      description: '主播暂时离开，当前没有公开播放流。返回公开状态后刷新即可恢复。',
    );
  }
  if (normalized == 'offline') {
    return const RoomChaturbateStatusPresentation(
      label: '未开播',
      description: '当前房间未处于公开直播状态，后续如果恢复开播，刷新即可恢复正常播放。',
    );
  }
  return RoomChaturbateStatusPresentation(
    label: rawStatus,
    description: '当前房间状态为 "$rawStatus"，暂时没有公开播放流。请稍后刷新重试。',
  );
}

class RoomPanelTab extends StatelessWidget {
  const RoomPanelTab({
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(0, 10, 0, 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? colorScheme.primary : Colors.transparent,
              width: selected ? 2 : 1,
            ),
          ),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: selected ? colorScheme.primary : colorScheme.onSurface,
                fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
                fontSize: 12.5,
              ),
        ),
      ),
    );
  }
}

class RoomChatMessageTile extends StatelessWidget {
  const RoomChatMessageTile({
    required this.message,
    required this.fontSize,
    required this.gap,
    required this.bubbleStyle,
    super.key,
  });

  final LiveMessage message;
  final double fontSize;
  final double gap;
  final bool bubbleStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final userName = message.userName?.trim() ?? '';

    if (userName == 'LiveSysMessage') {
      return Padding(
        padding: EdgeInsets.only(bottom: gap),
        child: SelectableText(
          message.content,
          style: applyZhTextStyleOrNull(
            theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontSize: fontSize,
              height: 1.22,
            ),
          ),
        ),
      );
    }

    final text = SelectableText.rich(
      TextSpan(
        style: applyZhTextStyleOrNull(
          theme.textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurface,
            fontSize: fontSize,
            height: 1.22,
          ),
        ),
        children: [
          if (userName.isNotEmpty)
            TextSpan(
              text: '$userName：',
              style: applyZhTextStyle().copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
                fontSize: fontSize,
              ),
            ),
          TextSpan(text: message.content),
        ],
      ),
    );

    final content = Padding(
      padding: EdgeInsets.symmetric(
        horizontal: bubbleStyle ? 12 : 0,
        vertical: bubbleStyle ? 8 : 0,
      ),
      child: text,
    );

    return Padding(
      padding: EdgeInsets.only(bottom: gap),
      child: bubbleStyle
          ? DecoratedBox(
              decoration: BoxDecoration(
                color:
                    colorScheme.surfaceContainerHighest.withValues(alpha: 0.72),
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(12),
                  bottomLeft: Radius.circular(12),
                  bottomRight: Radius.circular(12),
                ),
              ),
              child: content,
            )
          : content,
    );
  }
}

class DanmakuFeedTile extends StatelessWidget {
  const DanmakuFeedTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: applyZhTextStyleOrNull(
                    Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: applyZhTextStyleOrNull(
                    Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
