import 'package:flutter/material.dart';
import 'package:live_core/live_core.dart';

import 'provider_badge.dart';

class ProviderTabLabel extends StatelessWidget {
  const ProviderTabLabel({
    required this.descriptor,
    this.logoSize = 22,
    super.key,
  });

  final ProviderDescriptor descriptor;
  final double logoSize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ProviderLogo(
          descriptor: descriptor,
          size: logoSize,
        ),
        const SizedBox(width: 8),
        Text(
          descriptor.displayName,
          maxLines: 1,
          overflow: TextOverflow.fade,
          softWrap: false,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
            height: 1.08,
          ),
        ),
      ],
    );
  }
}

class _ProviderLogo extends StatelessWidget {
  const _ProviderLogo({
    required this.descriptor,
    required this.size,
  });

  final ProviderDescriptor descriptor;
  final double size;

  @override
  Widget build(BuildContext context) {
    final assetPath = ProviderBadge.logoAssetOf(descriptor.id);
    if (assetPath != null) {
      return Image.asset(
        assetPath,
        width: size,
        height: size,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        semanticLabel: '${descriptor.displayName} logo',
        errorBuilder: (context, error, stackTrace) => _ProviderLogoFallback(
          descriptor: descriptor,
          size: size,
        ),
      );
    }
    return _ProviderLogoFallback(
      descriptor: descriptor,
      size: size,
    );
  }
}

class _ProviderLogoFallback extends StatelessWidget {
  const _ProviderLogoFallback({
    required this.descriptor,
    required this.size,
  });

  final ProviderDescriptor descriptor;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = ProviderBadge.accentColorOf(descriptor.id);
    final monogram = ProviderBadge.monogramOf(descriptor.id);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: theme.brightness == Brightness.dark
            ? accent.withValues(alpha: 0.18)
            : accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color: accent.withValues(
              alpha: theme.brightness == Brightness.dark ? 0.34 : 0.22),
        ),
      ),
      child: Text(
        monogram,
        style: theme.textTheme.labelMedium?.copyWith(
          color: accent,
          fontWeight: FontWeight.w700,
          fontSize: monogram.length > 1 ? 9.5 : 11,
          height: 1,
        ),
      ),
    );
  }
}
