import 'package:flutter/material.dart';
import 'package:nolive_app/src/shared/presentation/theme/nolive_tokens.dart';
import 'package:nolive_app/src/shared/presentation/user_facing_error.dart';
import 'package:nolive_app/src/shared/presentation/widgets/empty_state_card.dart';

/// Shared spacing for settings subpages (aligns with Settings / Profile cards).
const EdgeInsets kSettingsPagePadding = EdgeInsets.fromLTRB(16, 16, 16, 40);

/// Leading icon tile used in settings lists (radius from design tokens).
class SettingsLeadingIcon extends StatelessWidget {
  const SettingsLeadingIcon({required this.icon, super.key});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final radius = NoliveRadii.of(context).md;
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Icon(icon, color: colorScheme.onSurface),
    );
  }
}

/// Friendly empty/error block for settings futures.
class SettingsErrorState extends StatelessWidget {
  const SettingsErrorState({
    required this.title,
    this.error,
    this.fallback = '加载失败，请稍后重试',
    super.key,
  });

  final String title;
  final Object? error;
  final String fallback;

  @override
  Widget build(BuildContext context) {
    return EmptyStateCard(
      title: title,
      message: formatUserFacingError(error, fallback: fallback),
      icon: Icons.error_outline,
    );
  }
}
