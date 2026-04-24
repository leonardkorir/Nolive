import 'package:flutter/material.dart';
import 'package:live_core/live_core.dart';

import 'app_surface_card.dart';
import 'persisted_network_image.dart';
import 'provider_badge.dart';
import 'streamer_avatar.dart';

double liveRoomGridMainAxisExtentForWidth(
  double availableWidth,
  int crossAxisCount,
) {
  const spacing = 6.0;
  final itemWidth =
      (availableWidth - (spacing * (crossAxisCount - 1))) / crossAxisCount;
  final coverHeight = itemWidth / (16 / 9);
  return coverHeight + 30;
}

SliverGridDelegate buildLiveRoomGridDelegate(BuildContext context) {
  final width = MediaQuery.sizeOf(context).width;
  final crossAxisCount = width >= 1280
      ? 5
      : width >= 960
          ? 4
          : width >= 620
              ? 3
              : 2;

  return SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: crossAxisCount,
    mainAxisExtent: liveRoomGridMainAxisExtentForWidth(width, crossAxisCount),
    crossAxisSpacing: 6,
    mainAxisSpacing: 6,
  );
}

class LiveRoomGridCard extends StatelessWidget {
  const LiveRoomGridCard({
    required this.room,
    required this.descriptor,
    this.onTap,
    super.key,
  });

  final LiveRoom room;
  final ProviderDescriptor descriptor;
  final VoidCallback? onTap;

  static const double compactMainAxisExtent = 150;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = ProviderBadge.accentColorOf(descriptor.id);
    final coverUrl = room.keyframeUrl ?? room.coverUrl;
    final areaLabel = normalizeDisplayText(
      room.areaName?.isNotEmpty == true
          ? room.areaName
          : descriptor.displayName,
    );
    final normalizedTitle = normalizeDisplayText(room.title);
    final normalizedStreamerName = normalizeDisplayText(room.streamerName);

    return AppSurfaceCard(
      padding: EdgeInsets.zero,
      borderRadius: 12,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (coverUrl != null && coverUrl.isNotEmpty)
                      PersistedNetworkImage(
                        imageUrl: coverUrl,
                        bucket: PersistedImageBucket.roomCover,
                        fit: BoxFit.cover,
                        fallback: _Placeholder(accent: accent),
                      )
                    else
                      _Placeholder(accent: accent),
                    Positioned(
                      left: 6,
                      top: 6,
                      child: _ProviderCornerBadge(
                        descriptor: descriptor,
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [Colors.black87, Colors.transparent],
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                areaLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w500,
                                  fontSize: 10.2,
                                  height: 1.2,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.local_fire_department_rounded,
                                  size: 12,
                                  color: Colors.white,
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  _viewerCountLabel(
                                    viewerCount: room.viewerCount,
                                    isLive: room.isLive,
                                  ),
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 10.2,
                                    height: 1.2,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(5, 2, 5, 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    StreamerAvatar(
                      size: 23,
                      imageUrl: room.streamerAvatarUrl,
                      fallbackText: normalizedStreamerName,
                      isLive: room.isLive,
                      liveRingWidth: 1.2,
                      fallbackTextStyle: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            normalizedTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w500,
                              color: theme.colorScheme.onSurface,
                              height: 1.18,
                              fontSize: 11.2,
                            ),
                          ),
                          const SizedBox(height: 0.5),
                          Text(
                            normalizedStreamerName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              height: 1.18,
                              fontSize: 10.1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _viewerCountLabel({
    required int? viewerCount,
    required bool isLive,
  }) {
    final value = viewerCount;
    if (value == null) {
      return isLive ? '直播中' : '未开播';
    }
    if (value >= 10000) {
      final label = (value / 10000).toStringAsFixed(value >= 100000 ? 0 : 1);
      return '$label万';
    }
    return '$value';
  }
}

class _ProviderCornerBadge extends StatelessWidget {
  const _ProviderCornerBadge({
    required this.descriptor,
  });

  final ProviderDescriptor descriptor;

  @override
  Widget build(BuildContext context) {
    final logoAsset = ProviderBadge.logoAssetOf(descriptor.id);
    return SizedBox(
      width: 18,
      height: 18,
      child: logoAsset == null
          ? Icon(
              ProviderBadge.iconOf(descriptor.id),
              size: 18,
              color: Colors.white,
            )
          : Image.asset(
              logoAsset,
              width: 18,
              height: 18,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
              semanticLabel: '${descriptor.displayName} logo',
              errorBuilder: (context, error, stackTrace) => Icon(
                ProviderBadge.iconOf(descriptor.id),
                size: 18,
                color: Colors.white,
              ),
            ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: 0.84),
            accent.withValues(alpha: 0.38)
          ],
        ),
      ),
      child: const Center(
        child: Icon(
          Icons.live_tv_rounded,
          color: Colors.white,
          size: 30,
        ),
      ),
    );
  }
}
