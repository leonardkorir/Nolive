import 'package:flutter/material.dart';
import 'package:live_core/live_core.dart';

class ProviderBadge extends StatelessWidget {
  const ProviderBadge({
    required this.descriptor,
    this.showBackground = true,
    this.compact = false,
    super.key,
  });

  final ProviderDescriptor descriptor;
  final bool showBackground;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = accentColorOf(descriptor.id);
    final iconSize = showBackground ? 11.0 : (compact ? 13.0 : 14.0);
    final textSize = showBackground ? 10.0 : (compact ? 11.2 : 11.8);
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(iconOf(descriptor.id), size: iconSize, color: accent),
        SizedBox(width: showBackground ? 3 : 4),
        Text(
          descriptor.displayName,
          style: theme.textTheme.labelMedium?.copyWith(
            color: accent,
            fontWeight: FontWeight.w600,
            fontSize: textSize,
            height: 1.2,
          ),
        ),
      ],
    );

    if (!showBackground) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 1.5),
        child: child,
      );
    }

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 4.5 : 5,
        vertical: compact ? 2 : 2.5,
      ),
      decoration: BoxDecoration(
        color: accent.withValues(
          alpha: theme.brightness == Brightness.dark ? 0.18 : 0.12,
        ),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withValues(alpha: 0.28)),
      ),
      child: child,
    );
  }

  static IconData iconOf(ProviderId providerId) {
    return switch (providerId.value) {
      'bilibili' => Icons.live_tv_rounded,
      'chaturbate' => Icons.visibility_rounded,
      'douyu' => Icons.sports_esports_rounded,
      'huya' => Icons.local_fire_department_rounded,
      'douyin' => Icons.music_note_rounded,
      'twitch' => Icons.videogame_asset_rounded,
      'youtube' => Icons.smart_display_rounded,
      _ => Icons.play_circle_outline,
    };
  }

  static Color accentColorOf(ProviderId providerId) {
    return switch (providerId.value) {
      'bilibili' => const Color(0xFF00A1D6),
      'chaturbate' => const Color(0xFFE64A19),
      'douyu' => const Color(0xFFFF8A00),
      'huya' => const Color(0xFFFFB000),
      'douyin' => const Color(0xFFFC2B55),
      'twitch' => const Color(0xFF9146FF),
      'youtube' => const Color(0xFFFF0033),
      _ => const Color(0xFFE11D48),
    };
  }

  static String? logoAssetOf(ProviderId providerId) {
    return switch (providerId.value) {
      'chaturbate' => 'assets/branding/chaturbate.png',
      'bilibili' => 'assets/branding/bilibili_2.png',
      'douyu' => 'assets/branding/douyu.png',
      'huya' => 'assets/branding/huya.png',
      'douyin' => 'assets/branding/douyin.png',
      'twitch' => 'assets/branding/twitch.png',
      'youtube' => 'assets/branding/youtube.png',
      _ => null,
    };
  }

  static String monogramOf(ProviderId providerId) {
    return switch (providerId.value) {
      'chaturbate' => 'CB',
      'bilibili' => 'B',
      'douyu' => 'DY',
      'huya' => 'HY',
      'douyin' => '抖',
      'twitch' => 'TW',
      'youtube' => 'YT',
      _ => providerId.value.isEmpty
          ? 'L'
          : providerId.value.substring(0, 1).toUpperCase(),
    };
  }
}
