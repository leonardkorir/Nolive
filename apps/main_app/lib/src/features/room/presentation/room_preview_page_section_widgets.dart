part of 'room_preview_page.dart';

class _MetadataRow extends StatelessWidget {
  const _MetadataRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 4),
          SelectableText(value),
        ],
      ),
    );
  }
}

class _RoomPanelTab extends StatelessWidget {
  const _RoomPanelTab({
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

class _RoomStepperRow extends StatelessWidget {
  const _RoomStepperRow({
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final int value;
  final ValueChanged<int> onChanged;

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
                  width: 32,
                  child: Center(
                    child: Text('$value'),
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

class _RoomChatMessageTile extends StatelessWidget {
  const _RoomChatMessageTile({
    required this.message,
    required this.fontSize,
    required this.gap,
    required this.bubbleStyle,
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

class _DanmakuFeedTile extends StatelessWidget {
  const _DanmakuFeedTile({
    required this.icon,
    required this.title,
    required this.subtitle,
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
