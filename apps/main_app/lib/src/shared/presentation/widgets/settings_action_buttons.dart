import 'dart:math' as math;

import 'package:flutter/material.dart';

class SettingsAction {
  const SettingsAction({
    required this.label,
    required this.onPressed,
    this.icon,
    this.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Key? key;
}

class SettingsActionButton extends StatelessWidget {
  const SettingsActionButton({
    required this.action,
    this.expanded = false,
    super.key,
  });

  final SettingsAction action;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final button = FilledButton.tonal(
      key: action.key,
      onPressed: action.onPressed,
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 52),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (action.icon != null) ...[
            Icon(action.icon, size: 20),
            const SizedBox(width: 10),
          ],
          Text(
            action.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );

    if (!expanded) {
      return button;
    }
    return SizedBox(width: double.infinity, child: button);
  }
}

class SettingsActionGrid extends StatelessWidget {
  const SettingsActionGrid({
    required this.actions,
    this.compactColumns = 2,
    this.wideColumns = 3,
    this.spacing = 12,
    this.runSpacing = 12,
    super.key,
  });

  final List<SettingsAction> actions;
  final int compactColumns;
  final int wideColumns;
  final double spacing;
  final double runSpacing;

  @override
  Widget build(BuildContext context) {
    if (actions.isEmpty) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final requestedColumns = maxWidth >= 920 ? wideColumns : compactColumns;
        final columns = math.max(1, math.min(requestedColumns, actions.length));
        final itemWidth = columns == 1
            ? maxWidth
            : (maxWidth - spacing * (columns - 1)) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: runSpacing,
          children: [
            for (final action in actions)
              SizedBox(
                width: itemWidth,
                child: SettingsActionButton(action: action),
              ),
          ],
        );
      },
    );
  }
}
