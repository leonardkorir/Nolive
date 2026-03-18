import 'package:flutter/material.dart';
import 'package:nolive_app/src/shared/presentation/theme/zh_text.dart';

import 'persisted_network_image.dart';

class StreamerAvatar extends StatelessWidget {
  const StreamerAvatar({
    required this.size,
    required this.fallbackText,
    this.imageUrl,
    this.isLive = false,
    this.outlineColor,
    this.outlineWidth = 1,
    this.liveRingColor = const Color(0xFFFF4D4F),
    this.liveRingWidth = 1.5,
    this.backgroundColor,
    this.fallbackTextStyle,
    super.key,
  });

  final double size;
  final String? imageUrl;
  final String fallbackText;
  final bool isLive;
  final Color? outlineColor;
  final double outlineWidth;
  final Color liveRingColor;
  final double liveRingWidth;
  final Color? backgroundColor;
  final TextStyle? fallbackTextStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trimmed = fallbackText.trim();
    final initial =
        trimmed.isEmpty ? '主' : trimmed.substring(0, 1).toUpperCase();
    final palette = _AvatarPalette.forBrightness(theme.brightness);
    final effectiveBackgroundColor = backgroundColor ?? palette.background;
    final borderColor = isLive ? liveRingColor : outlineColor;
    final double borderWidth = isLive
        ? liveRingWidth
        : borderColor == null
            ? 0.0
            : outlineWidth;
    final double inset = borderColor == null ? 0.0 : borderWidth;
    final fallbackStyle = fallbackTextStyle ??
        applyZhTextStyleOrNull(theme.textTheme.titleMedium?.copyWith(
          color: palette.foreground,
          fontWeight: FontWeight.w600,
          height: 1,
        )) ??
        applyZhTextStyle(TextStyle(
          color: palette.foreground,
          fontWeight: FontWeight.w600,
          height: 1,
        ));

    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: borderColor == null
              ? null
              : Border.all(color: borderColor, width: borderWidth),
        ),
        child: Padding(
          padding: EdgeInsets.all(inset),
          child: ClipOval(
            child: PersistedNetworkImage(
              imageUrl: imageUrl ?? '',
              bucket: PersistedImageBucket.avatar,
              fallback: _AvatarFallback(
                initial: initial,
                backgroundColor: effectiveBackgroundColor,
                textStyle: fallbackStyle,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AvatarPalette {
  const _AvatarPalette({
    required this.background,
    required this.foreground,
  });

  final Color background;
  final Color foreground;

  static const List<_AvatarPalette> _lightPalettes = [
    _AvatarPalette(
      background: Color(0xFFFFFFFF),
      foreground: Color(0xFF7A5230),
    ),
  ];

  static const List<_AvatarPalette> _darkPalettes = [
    _AvatarPalette(
      background: Color(0xFF12161E),
      foreground: Color(0xFFE3C9AD),
    ),
  ];

  static _AvatarPalette forBrightness(Brightness brightness) {
    return brightness == Brightness.dark
        ? _darkPalettes.first
        : _lightPalettes.first;
  }
}

class _AvatarFallback extends StatelessWidget {
  const _AvatarFallback({
    required this.initial,
    required this.backgroundColor,
    required this.textStyle,
  });

  final String initial;
  final Color backgroundColor;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: backgroundColor,
      child: Center(
        child: Text(
          initial,
          style: textStyle,
          maxLines: 1,
          overflow: TextOverflow.clip,
          textAlign: TextAlign.center,
          strutStyle: const StrutStyle(
            forceStrutHeight: true,
            height: 1,
            leading: 0,
          ),
          textHeightBehavior: const TextHeightBehavior(
            applyHeightToFirstAscent: false,
            applyHeightToLastDescent: false,
          ),
        ),
      ),
    );
  }
}
