import 'package:flutter/material.dart';
import 'package:live_core/live_core.dart';
import 'package:nolive_app/src/shared/domain/follow_watch_entry.dart';

import 'provider_badge.dart';
import 'streamer_avatar.dart';

class FollowWatchRow extends StatelessWidget {
  const FollowWatchRow({
    required this.entry,
    required this.providerDescriptor,
    required this.onTap,
    this.onLongPress,
    this.onRemove,
    this.isPlaying = false,
    this.highContrastOverlay = false,
    this.showChevron = false,
    this.showSurface = true,
    super.key,
  });

  final FollowWatchEntry entry;
  final ProviderDescriptor providerDescriptor;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onRemove;
  final bool isPlaying;
  final bool highContrastOverlay;
  final bool showChevron;
  final bool showSurface;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final presentationBrightness = highContrastOverlay
        ? Brightness.dark
        : theme.brightness;
    final room = entry.detail;
    final displayStreamerName = normalizeDisplayText(entry.displayStreamerName);
    final areaLabel = normalizeDisplayText(entry.displayAreaName);
    final tagsLabel = normalizeDisplayText(entry.displayTags.join(' · '));
    final liveDuration = _liveDuration(room?.startedAt);
    final subtitle = normalizeDisplayText(
      entry.isPasswordProtected
          ? '房间已加锁，需要密码（当前不支持输入密码观看）'
          : entry.hasError && room == null
          ? '状态暂未知，点击仍可尝试进入房间'
          : entry.title,
    );
    final titleColor = highContrastOverlay
        ? const Color(0xFFF8FAFC)
        : colorScheme.onSurface;
    final subtitleColor = highContrastOverlay
        ? const Color(0xFFFFC978)
        : theme.brightness == Brightness.dark
        ? const Color(0xFFF5C46B)
        : const Color(0xFFB7791F);
    final metaColor = highContrastOverlay
        ? const Color(0xFFD5DAE1)
        : colorScheme.onSurfaceVariant;
    final status = _FollowStatusPresentation.resolve(
      brightness: presentationBrightness,
      isLive: entry.isLive,
      isPlaying: isPlaying,
      hasError: entry.hasError,
      isPasswordProtected: entry.isPasswordProtected,
    );
    final avatarSize = highContrastOverlay ? 44.0 : (showSurface ? 42.0 : 44.0);
    final rowMinHeight = highContrastOverlay
        ? 84.0
        : (showSurface ? 72.0 : 82.0);
    final rowPadding = highContrastOverlay
        ? const EdgeInsets.fromLTRB(12, 10, 8, 10)
        : showSurface
        ? const EdgeInsets.fromLTRB(9, 8, 4, 8)
        : const EdgeInsets.fromLTRB(12, 8, 6, 8);
    final horizontalGap = highContrastOverlay
        ? 10.0
        : (showSurface ? 8.0 : 10.0);
    final backgroundColor = highContrastOverlay
        ? (isPlaying ? const Color(0xF24B2E18) : const Color(0xD91D232C))
        : showSurface
        ? (isPlaying
              ? Color.alphaBlend(
                  colorScheme.secondary.withValues(
                    alpha: theme.brightness == Brightness.dark ? 0.14 : 0.08,
                  ),
                  theme.cardColor,
                )
              : theme.cardColor)
        : Colors.transparent;
    final borderRadius = BorderRadius.circular(
      highContrastOverlay ? 14 : (showSurface ? 10 : 0),
    );
    final border = highContrastOverlay
        ? Border.all(
            color: isPlaying
                ? const Color(0x66FFB36A)
                : Colors.white.withValues(alpha: 0.12),
          )
        : null;
    final compactOverlayLayout = highContrastOverlay;
    final placeBadgesWithTrailingAction =
        !compactOverlayLayout && (onRemove != null || showChevron);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(
          highContrastOverlay ? 16 : (showSurface ? 12 : 0),
        ),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Ink(
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: borderRadius,
            border: border,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: rowMinHeight),
            child: Padding(
              padding: rowPadding,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  StreamerAvatar(
                    size: avatarSize,
                    imageUrl: entry.displayStreamerAvatarUrl,
                    fallbackText: displayStreamerName,
                    isLive: entry.isLive,
                    liveRingWidth: showSurface ? 1.6 : 2,
                  ),
                  SizedBox(width: horizontalGap),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (compactOverlayLayout)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                displayStreamerName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: titleColor,
                                  fontWeight: FontWeight.w700,
                                  fontSize: showSurface ? 13.4 : 14.6,
                                  height: 1.08,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Wrap(
                                spacing: 5,
                                runSpacing: 4,
                                children: [
                                  if (areaLabel.isNotEmpty)
                                    _MiniPill(
                                      label: areaLabel,
                                      maxWidth: 84,
                                      foreground: highContrastOverlay
                                          ? const Color(0xFF8ED9FF)
                                          : theme.brightness == Brightness.dark
                                          ? const Color(0xFF95D0FF)
                                          : const Color(0xFF5EA2EB),
                                      background: highContrastOverlay
                                          ? const Color(0xFF13283A)
                                          : theme.brightness == Brightness.dark
                                          ? const Color(0xFF102438)
                                          : const Color(0xFFF0F7FF),
                                    ),
                                  _MiniPill(
                                    label: status.label,
                                    foreground: status.foreground,
                                    background: status.background,
                                  ),
                                ],
                              ),
                            ],
                          )
                        else if (placeBadgesWithTrailingAction)
                          _FollowListBody(
                            displayStreamerName: displayStreamerName,
                            subtitle: subtitle,
                            tagsLabel: tagsLabel,
                            liveDuration: liveDuration,
                            titleColor: titleColor,
                            subtitleColor: subtitleColor,
                            metaColor: metaColor,
                            showSurface: showSurface,
                            areaLabel: areaLabel,
                            status: status,
                            areaForeground: highContrastOverlay
                                ? const Color(0xFF8ED9FF)
                                : theme.brightness == Brightness.dark
                                ? const Color(0xFF95D0FF)
                                : const Color(0xFF5EA2EB),
                            areaBackground: highContrastOverlay
                                ? const Color(0xFF13283A)
                                : theme.brightness == Brightness.dark
                                ? const Color(0xFF102438)
                                : const Color(0xFFF0F7FF),
                            providerDescriptor: providerDescriptor,
                            showChevron: showChevron,
                            onRemove: onRemove,
                            isLive: entry.isLive,
                            chevronColor: highContrastOverlay
                                ? const Color(0xFFF8FAFC)
                                : null,
                          )
                        else ...[
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  displayStreamerName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    color: titleColor,
                                    fontWeight: FontWeight.w700,
                                    fontSize: showSurface ? 13.8 : 14.8,
                                    height: 1.08,
                                  ),
                                ),
                              ),
                              if (areaLabel.isNotEmpty) ...[
                                const SizedBox(width: 5),
                                _MiniPill(
                                  label: areaLabel,
                                  maxWidth: 96,
                                  foreground: highContrastOverlay
                                      ? const Color(0xFF8ED9FF)
                                      : theme.brightness == Brightness.dark
                                      ? const Color(0xFF95D0FF)
                                      : const Color(0xFF5EA2EB),
                                  background: highContrastOverlay
                                      ? const Color(0xFF13283A)
                                      : theme.brightness == Brightness.dark
                                      ? const Color(0xFF102438)
                                      : const Color(0xFFF0F7FF),
                                ),
                              ],
                              const SizedBox(width: 5),
                              _MiniPill(
                                label: status.label,
                                foreground: status.foreground,
                                background: status.background,
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.left,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: subtitleColor,
                                fontWeight: FontWeight.w700,
                                fontSize: compactOverlayLayout
                                    ? (showSurface ? 10.8 : 11.2)
                                    : (showSurface ? 11.8 : 12.0),
                                height: 1.14,
                              ),
                            ),
                          ),
                        ],
                        if (!placeBadgesWithTrailingAction) ...[
                          SizedBox(height: showSurface ? 2 : 3),
                          if (compactOverlayLayout)
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Expanded(
                                      child: _ProviderMeta(
                                        providerDescriptor: providerDescriptor,
                                        textStyle: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              color: metaColor,
                                              fontWeight: FontWeight.w500,
                                              fontSize: showSurface
                                                  ? 10.1
                                                  : 10.4,
                                              height: 1.1,
                                            ),
                                      ),
                                    ),
                                    if (liveDuration.isNotEmpty) ...[
                                      const SizedBox(width: 6),
                                      _DurationText(
                                        label: liveDuration,
                                        foregroundColor: metaColor,
                                      ),
                                    ],
                                  ],
                                ),
                                if (tagsLabel.isNotEmpty) ...[
                                  const SizedBox(height: 3),
                                  Text(
                                    tagsLabel,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: metaColor,
                                      fontWeight: FontWeight.w500,
                                      fontSize: showSurface ? 9.9 : 10.2,
                                      height: 1.1,
                                    ),
                                  ),
                                ],
                              ],
                            )
                          else
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Flexible(
                                  child: _ProviderMeta(
                                    providerDescriptor: providerDescriptor,
                                    textStyle: theme.textTheme.bodySmall
                                        ?.copyWith(
                                          color: metaColor,
                                          fontWeight: FontWeight.w500,
                                          fontSize: showSurface ? 10.1 : 10.4,
                                          height: 1.1,
                                        ),
                                  ),
                                ),
                                if (tagsLabel.isNotEmpty) ...[
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      tagsLabel,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: metaColor,
                                            fontWeight: FontWeight.w500,
                                            fontSize: showSurface ? 9.9 : 10.2,
                                            height: 1.1,
                                          ),
                                    ),
                                  ),
                                ] else
                                  const Spacer(),
                                if (liveDuration.isNotEmpty)
                                  _DurationText(
                                    label: liveDuration,
                                    foregroundColor: metaColor,
                                  ),
                              ],
                            ),
                        ],
                      ],
                    ),
                  ),
                  if (!placeBadgesWithTrailingAction &&
                      (onRemove != null || showChevron)) ...[
                    const SizedBox(width: 1),
                    _TrailingAction(
                      showChevron: showChevron,
                      onRemove: onRemove,
                      isLive: entry.isLive,
                      chevronColor: highContrastOverlay
                          ? const Color(0xFFF8FAFC)
                          : null,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _liveDuration(DateTime? startedAt) {
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
}

/// Library list layout: keep partition chips in their original trailing place,
/// only shift user tags on the meta row so their left edge matches the chips.
class _FollowListBody extends StatefulWidget {
  const _FollowListBody({
    required this.displayStreamerName,
    required this.subtitle,
    required this.tagsLabel,
    required this.liveDuration,
    required this.titleColor,
    required this.subtitleColor,
    required this.metaColor,
    required this.showSurface,
    required this.areaLabel,
    required this.status,
    required this.areaForeground,
    required this.areaBackground,
    required this.providerDescriptor,
    required this.showChevron,
    required this.onRemove,
    required this.isLive,
    required this.chevronColor,
  });

  final String displayStreamerName;
  final String subtitle;
  final String tagsLabel;
  final String liveDuration;
  final Color titleColor;
  final Color subtitleColor;
  final Color metaColor;
  final bool showSurface;
  final String areaLabel;
  final _FollowStatusPresentation status;
  final Color areaForeground;
  final Color areaBackground;
  final ProviderDescriptor providerDescriptor;
  final bool showChevron;
  final VoidCallback? onRemove;
  final bool isLive;
  final Color? chevronColor;

  @override
  State<_FollowListBody> createState() => _FollowListBodyState();
}

class _FollowListBodyState extends State<_FollowListBody> {
  final GlobalKey _badgesKey = GlobalKey();
  final GlobalKey _bodyKey = GlobalKey();
  double _tagsLeft = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncTagsLeft());
  }

  @override
  void didUpdateWidget(covariant _FollowListBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncTagsLeft());
  }

  void _syncTagsLeft() {
    if (!mounted) {
      return;
    }
    final badgesBox =
        _badgesKey.currentContext?.findRenderObject() as RenderBox?;
    final bodyBox = _bodyKey.currentContext?.findRenderObject() as RenderBox?;
    if (badgesBox == null ||
        bodyBox == null ||
        !badgesBox.hasSize ||
        !bodyBox.hasSize) {
      return;
    }
    // Leading chip box left + MiniPill horizontal padding (6) so user tags
    // line up with the area label text (e.g. 吃鸡行动), not past it.
    const chipLabelInset = 6.0;
    final badgesOriginGlobal = badgesBox.localToGlobal(Offset.zero);
    final next = (bodyBox.globalToLocal(badgesOriginGlobal).dx + chipLabelInset)
        .clamp(0.0, bodyBox.size.width);
    if ((next - _tagsLeft).abs() > 0.5) {
      setState(() {
        _tagsLeft = next;
      });
      // Re-measure after provider width reacts to the new tag offset.
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncTagsLeft());
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tagsStyle = theme.textTheme.bodySmall?.copyWith(
      color: widget.metaColor,
      fontWeight: FontWeight.w500,
      fontSize: widget.showSurface ? 9.9 : 10.2,
      height: 1.1,
    );
    final providerStyle = theme.textTheme.bodySmall?.copyWith(
      color: widget.metaColor,
      fontWeight: FontWeight.w500,
      fontSize: widget.showSurface ? 10.1 : 10.4,
      height: 1.1,
    );

    return Column(
      key: _bodyKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Original name + trailing chips (chips stay where they were).
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                widget.displayStreamerName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: widget.titleColor,
                  fontWeight: FontWeight.w700,
                  fontSize: widget.showSurface ? 13.8 : 14.8,
                  height: 1.08,
                ),
              ),
            ),
            const SizedBox(width: 6),
            _TrailingBadges(
              // Align user tags to the first chip (e.g. 吃鸡行动), not the
              // outer trailing box which may be wider than the chips.
              leadingChipKey: _badgesKey,
              areaLabel: widget.areaLabel,
              status: widget.status,
              areaForeground: widget.areaForeground,
              areaBackground: widget.areaBackground,
            ),
          ],
        ),
        const SizedBox(height: 2),
        // Original subtitle + unfollow action.
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                widget.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.left,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: widget.subtitleColor,
                  fontWeight: FontWeight.w700,
                  fontSize: widget.showSurface ? 11.8 : 12.0,
                  height: 1.14,
                ),
              ),
            ),
            const SizedBox(width: 6),
            _TrailingAction(
              showChevron: widget.showChevron,
              onRemove: widget.onRemove,
              isLive: widget.isLive,
              chevronColor: widget.chevronColor,
            ),
          ],
        ),
        SizedBox(height: widget.showSurface ? 2 : 3),
        // Meta row: provider left; tags on same row, left edge = chips left edge.
        LayoutBuilder(
          builder: (context, constraints) {
            final hasTags = widget.tagsLabel.isNotEmpty;
            final hasDuration = widget.liveDuration.isNotEmpty;
            // Approximate duration block; tags stop before it.
            const durationReserve = 72.0;
            final tagsLeft = hasTags ? _tagsLeft : constraints.maxWidth;
            final providerMaxWidth = hasTags
                ? (tagsLeft - 8).clamp(0.0, constraints.maxWidth)
                : constraints.maxWidth - (hasDuration ? durationReserve : 0);
            final tagsRight = hasDuration ? durationReserve : 0.0;

            return SizedBox(
              height: 16,
              width: constraints.maxWidth,
              child: Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  Positioned(
                    left: 0,
                    width: providerMaxWidth,
                    top: 0,
                    bottom: 0,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _ProviderMeta(
                        providerDescriptor: widget.providerDescriptor,
                        textStyle: providerStyle,
                      ),
                    ),
                  ),
                  if (hasTags)
                    Positioned(
                      left: tagsLeft,
                      right: tagsRight,
                      top: 0,
                      bottom: 0,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          widget.tagsLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.left,
                          style: tagsStyle,
                        ),
                      ),
                    ),
                  if (hasDuration)
                    Positioned(
                      right: 0,
                      top: 0,
                      bottom: 0,
                      child: _DurationText(
                        label: widget.liveDuration,
                        foregroundColor: widget.metaColor,
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class _TrailingBadges extends StatelessWidget {
  const _TrailingBadges({
    required this.areaLabel,
    required this.status,
    required this.areaForeground,
    required this.areaBackground,
    this.leadingChipKey,
  });

  final String areaLabel;
  final _FollowStatusPresentation status;
  final Color areaForeground;
  final Color areaBackground;
  final Key? leadingChipKey;

  @override
  Widget build(BuildContext context) {
    // Original trailing chips: pack to the end; do not change their position.
    final areaChip = areaLabel.isEmpty
        ? null
        : _MiniPill(
            label: areaLabel,
            maxWidth: 96,
            foreground: areaForeground,
            background: areaBackground,
          );
    final statusChip = _MiniPill(
      label: status.label,
      maxWidth: 64,
      foreground: status.foreground,
      background: status.background,
    );
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 156),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (areaChip != null) ...[
            Flexible(
              child: Align(
                alignment: Alignment.centerRight,
                child: KeyedSubtree(key: leadingChipKey, child: areaChip),
              ),
            ),
            const SizedBox(width: 4),
            Flexible(child: statusChip),
          ] else
            Flexible(
              child: KeyedSubtree(key: leadingChipKey, child: statusChip),
            ),
        ],
      ),
    );
  }
}

class _TrailingAction extends StatelessWidget {
  const _TrailingAction({
    required this.showChevron,
    required this.onRemove,
    required this.isLive,
    this.chevronColor,
  });

  final bool showChevron;
  final VoidCallback? onRemove;
  final bool isLive;
  final Color? chevronColor;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    if (onRemove != null) {
      // Offline matches grey "未开播" chip; live keeps red.
      final iconColor = isLive
          ? colorScheme.error.withValues(alpha: 0.9)
          : theme.brightness == Brightness.dark
          ? const Color(0xFFAFB7C5)
          : const Color(0xFF667085);
      return IconButton(
        tooltip: '取消关注',
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints.tightFor(width: 28, height: 28),
        onPressed: onRemove,
        icon: Icon(Icons.heart_broken_rounded, size: 16, color: iconColor),
      );
    }
    if (!showChevron) {
      return const SizedBox.shrink();
    }
    return Icon(
      Icons.chevron_right_rounded,
      size: 20,
      color: chevronColor ?? colorScheme.onSurfaceVariant,
    );
  }
}

class _ProviderMeta extends StatelessWidget {
  const _ProviderMeta({
    required this.providerDescriptor,
    required this.textStyle,
  });

  final ProviderDescriptor providerDescriptor;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    final logoAsset = ProviderBadge.logoAssetOf(providerDescriptor.id);
    final label = switch (providerDescriptor.id.value) {
      'douyu' => '斗鱼直播',
      'douyin' => '抖音直播',
      'bilibili' => '哔哩哔哩',
      'huya' => '虎牙直播',
      'chaturbate' => 'Chaturbate',
      'twitch' => 'Twitch',
      'youtube' => 'YouTube 直播',
      _ => providerDescriptor.displayName,
    };
    return Row(
      mainAxisSize: MainAxisSize.max,
      children: [
        if (logoAsset != null)
          Image.asset(
            logoAsset,
            width: 16,
            height: 16,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
            errorBuilder: (context, error, stackTrace) =>
                _ProviderMetaFallback(providerDescriptor: providerDescriptor),
          )
        else
          _ProviderMetaFallback(providerDescriptor: providerDescriptor),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textStyle,
          ),
        ),
      ],
    );
  }
}

class _ProviderMetaFallback extends StatelessWidget {
  const _ProviderMetaFallback({required this.providerDescriptor});

  final ProviderDescriptor providerDescriptor;

  @override
  Widget build(BuildContext context) {
    final accent = ProviderBadge.accentColorOf(providerDescriptor.id);
    return Container(
      width: 16,
      height: 16,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        ProviderBadge.monogramOf(providerDescriptor.id),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: accent,
          fontWeight: FontWeight.w700,
          fontSize: 7.4,
          height: 1,
        ),
      ),
    );
  }
}

class _DurationText extends StatelessWidget {
  const _DurationText({required this.label, this.foregroundColor});

  final String label;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.access_time_rounded,
          size: 10,
          color: foregroundColor ?? colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 3),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: foregroundColor ?? colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w500,
            fontSize: 9.6,
            height: 1.1,
          ),
        ),
      ],
    );
  }
}

class _MiniPill extends StatelessWidget {
  const _MiniPill({
    required this.label,
    required this.foreground,
    required this.background,
    this.maxWidth,
  });

  final String label;
  final Color foreground;
  final Color background;
  final double? maxWidth;

  @override
  Widget build(BuildContext context) {
    final child = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: foreground,
        fontWeight: FontWeight.w700,
        fontSize: 9.2,
        height: 1.0,
      ),
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: maxWidth == null
          ? child
          : ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth!),
              child: child,
            ),
    );
  }
}

class _FollowStatusPresentation {
  const _FollowStatusPresentation({
    required this.label,
    required this.foreground,
    required this.background,
  });

  final String label;
  final Color foreground;
  final Color background;

  static _FollowStatusPresentation resolve({
    required Brightness brightness,
    required bool isLive,
    required bool isPlaying,
    required bool hasError,
    bool isPasswordProtected = false,
  }) {
    if (isPlaying) {
      return _FollowStatusPresentation(
        label: '观看中',
        foreground: brightness == Brightness.dark
            ? const Color(0xFF7BE495)
            : const Color(0xFF15803D),
        background: brightness == Brightness.dark
            ? const Color(0xFF12261A)
            : const Color(0xFFEAF8EE),
      );
    }
    if (isPasswordProtected) {
      return _FollowStatusPresentation(
        label: '加锁',
        foreground: brightness == Brightness.dark
            ? const Color(0xFFB8C0CC)
            : const Color(0xFF475467),
        background: brightness == Brightness.dark
            ? const Color(0xFF1F2630)
            : const Color(0xFFEAECF0),
      );
    }
    if (isLive) {
      return _FollowStatusPresentation(
        label: '直播中',
        foreground: brightness == Brightness.dark
            ? const Color(0xFFFF8B7E)
            : const Color(0xFFD14343),
        background: brightness == Brightness.dark
            ? const Color(0xFF351819)
            : const Color(0xFFFCEBEC),
      );
    }
    if (hasError) {
      // Probe/network failure — not "room broken". Prefer 未知 over 异常 so
      // Chaturbate CF/context misses (and other providers) are not overstated.
      return _FollowStatusPresentation(
        label: '未知',
        foreground: brightness == Brightness.dark
            ? const Color(0xFFF5C46B)
            : const Color(0xFFB7791F),
        background: brightness == Brightness.dark
            ? const Color(0xFF3A2A0F)
            : const Color(0xFFFFF4DE),
      );
    }
    return _FollowStatusPresentation(
      label: '未开播',
      foreground: brightness == Brightness.dark
          ? const Color(0xFFAFB7C5)
          : const Color(0xFF667085),
      background: brightness == Brightness.dark
          ? const Color(0xFF1B212B)
          : const Color(0xFFF1F4F8),
    );
  }
}
