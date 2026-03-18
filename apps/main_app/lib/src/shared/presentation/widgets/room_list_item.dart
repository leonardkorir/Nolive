import 'package:flutter/material.dart';

import 'app_surface_card.dart';
import 'persisted_network_image.dart';

class RoomListItem extends StatelessWidget {
  const RoomListItem({
    required this.title,
    required this.subtitle,
    required this.trailing,
    this.avatarImageUrl,
    this.avatarFallbackText,
    this.tags = const [],
    this.onTap,
    this.onLongPress,
    this.footer,
    super.key,
  });

  final String title;
  final String subtitle;
  final String trailing;
  final String? avatarImageUrl;
  final String? avatarFallbackText;
  final List<String> tags;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return AppSurfaceCard(
      padding: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if ((avatarImageUrl?.isNotEmpty ?? false) ||
                      (avatarFallbackText?.isNotEmpty ?? false)) ...[
                    _RoomListAvatar(
                      imageUrl: avatarImageUrl,
                      fallbackText: avatarFallbackText,
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            height: 1.25,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      trailing,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
              if (tags.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final tag in tags)
                      Chip(
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        label: Text(tag),
                      ),
                  ],
                ),
              ],
              if (footer != null) ...[
                const SizedBox(height: 8),
                footer!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _RoomListAvatar extends StatelessWidget {
  const _RoomListAvatar({this.imageUrl, this.fallbackText});

  final String? imageUrl;
  final String? fallbackText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final trimmed = fallbackText?.trim() ?? '';
    final initial = trimmed.isNotEmpty ? trimmed.substring(0, 1) : '主';

    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: (imageUrl?.isNotEmpty ?? false)
          ? PersistedNetworkImage(
              imageUrl: imageUrl!,
              bucket: PersistedImageBucket.avatar,
              fit: BoxFit.cover,
              fallback: _RoomListAvatarFallback(initial: initial),
            )
          : _RoomListAvatarFallback(initial: initial),
    );
  }
}

class _RoomListAvatarFallback extends StatelessWidget {
  const _RoomListAvatarFallback({required this.initial});

  final String initial;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: colorScheme.primaryContainer,
      child: Center(
        child: Text(
          initial,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w600,
              ),
        ),
      ),
    );
  }
}
