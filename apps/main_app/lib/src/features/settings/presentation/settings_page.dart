import 'package:flutter/material.dart';
import 'package:nolive_app/src/shared/presentation/app_settings_entries.dart';
import 'package:nolive_app/src/shared/presentation/settings_page_chrome.dart';
import 'package:nolive_app/src/shared/presentation/widgets/app_surface_card.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, this.entries = kAppSettingsEntries});

  /// Shared catalog — also used by Profile settings section.
  final List<AppSettingsEntry> entries;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: kSettingsPagePadding,
        children: [
          SettingsEntriesBlock(entries: entries),
        ],
      ),
    );
  }
}

/// Renders [AppSettingsEntry] tiles in a surface card (shared with Profile).
class SettingsEntriesBlock extends StatelessWidget {
  const SettingsEntriesBlock({required this.entries, super.key});

  final List<AppSettingsEntry> entries;

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      child: Column(
        children: [
          for (var index = 0; index < entries.length; index += 1) ...[
            SettingsEntryTile(item: entries[index]),
            if (index != entries.length - 1) const Divider(height: 1),
          ],
        ],
      ),
    );
  }
}

class SettingsEntryTile extends StatelessWidget {
  const SettingsEntryTile({required this.item, super.key});

  final AppSettingsEntry item;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: SettingsLeadingIcon(icon: item.icon),
      title: Text(item.title),
      subtitle: Text(
        item.subtitle,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
      ),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => Navigator.of(context).pushNamed(item.routeName),
    );
  }
}
