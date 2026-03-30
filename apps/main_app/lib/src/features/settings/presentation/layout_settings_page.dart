import 'package:flutter/material.dart';
import 'package:live_core/live_core.dart';
import 'package:nolive_app/src/app/bootstrap/bootstrap.dart';
import 'package:nolive_app/src/features/settings/application/manage_layout_preferences_use_case.dart';
import 'package:nolive_app/src/shared/presentation/widgets/app_surface_card.dart';
import 'package:nolive_app/src/shared/presentation/widgets/provider_badge.dart';
import 'package:nolive_app/src/shared/presentation/widgets/section_header.dart';
import 'package:nolive_app/src/shared/presentation/widgets/settings_action_buttons.dart';

class LayoutSettingsPage extends StatelessWidget {
  const LayoutSettingsPage({required this.bootstrap, super.key});

  final AppBootstrap bootstrap;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('主页设置')),
      body: ValueListenableBuilder<LayoutPreferences>(
        valueListenable: bootstrap.layoutPreferences,
        builder: (context, preferences, _) {
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionHeader(
                  title: '主页设置',
                ),
                const SizedBox(height: 12),
                SettingsActionButton(
                  expanded: true,
                  action: SettingsAction(
                    label: '恢复默认',
                    icon: Icons.restart_alt_outlined,
                    onPressed: () => bootstrap.updateLayoutPreferences(
                      LayoutPreferences.defaults(),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _ReorderCard<ShellTabId>(
                  title: '导航顺序',
                  items: preferences.shellTabOrder
                      .where((item) => item != ShellTabId.search)
                      .toList(growable: false),
                  itemLabel: (item) => item.label,
                  itemLeading: _buildShellTabIcon,
                  onReorder: (items) => bootstrap.updateLayoutPreferences(
                    preferences.copyWith(shellTabOrder: items),
                  ),
                ),
                const SizedBox(height: 16),
                _ProviderReorderCard(
                  title: '平台顺序',
                  items: preferences.providerOrder,
                  itemLabel: (providerId) => _providerLabel(providerId),
                  itemLeading: _buildProviderIcon,
                  onReorder: (items) => bootstrap.updateLayoutPreferences(
                    preferences.copyWith(providerOrder: items),
                  ),
                  isEnabled: preferences.isProviderEnabled,
                  onToggle: (providerId, enabled) {
                    final nextEnabled = _toggleProvider(
                      preferences,
                      providerId,
                      enabled,
                    );
                    bootstrap.updateLayoutPreferences(
                      preferences.copyWith(enabledProviderIds: nextEnabled),
                    );
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  String _providerLabel(String providerId) {
    final descriptor =
        bootstrap.providerRegistry.findDescriptorById(providerId);
    return descriptor?.displayName ?? providerId;
  }

  Widget _buildShellTabIcon(ShellTabId item) {
    final (icon, color) = switch (item) {
      ShellTabId.home => (Icons.home_rounded, const Color(0xFF1778D4)),
      ShellTabId.browse => (Icons.grid_view_rounded, const Color(0xFF0F9D92)),
      ShellTabId.search => (Icons.search_rounded, const Color(0xFF7C3AED)),
      ShellTabId.library => (
          Icons.favorite_rounded,
          const Color(0xFFE11D48),
        ),
      ShellTabId.profile => (
          Icons.sentiment_satisfied_alt,
          const Color(0xFFF97316),
        ),
    };
    return SizedBox(
      width: 32,
      height: 32,
      child: Center(
        child: Icon(icon, size: 22, color: color),
      ),
    );
  }

  Widget _buildProviderIcon(String providerId) {
    final logoAsset = ProviderBadge.logoAssetOf(ProviderId(providerId));
    if (logoAsset != null) {
      return SizedBox(
        width: 32,
        height: 32,
        child: Center(
          child: Image.asset(
            logoAsset,
            width: 22,
            height: 22,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
          ),
        ),
      );
    }

    return SizedBox(
      width: 32,
      height: 32,
      child: Center(
        child: Icon(
          ProviderBadge.iconOf(ProviderId(providerId)),
          size: 20,
          color: ProviderBadge.accentColorOf(ProviderId(providerId)),
        ),
      ),
    );
  }

  List<String> _toggleProvider(
    LayoutPreferences preferences,
    String providerId,
    bool enabled,
  ) {
    final enabledIds = preferences.enabledProviderIds.toSet();
    if (enabled) {
      enabledIds.add(providerId);
    } else {
      enabledIds.remove(providerId);
    }
    return preferences.providerOrder
        .where(enabledIds.contains)
        .toList(growable: false);
  }
}

class _ReorderCard<T> extends StatelessWidget {
  const _ReorderCard({
    required this.title,
    required this.items,
    required this.itemLabel,
    required this.onReorder,
    this.itemLeading,
  });

  final String title;
  final List<T> items;
  final String Function(T item) itemLabel;
  final ValueChanged<List<T>> onReorder;
  final Widget Function(T item)? itemLeading;

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          ReorderableListView.builder(
            shrinkWrap: true,
            buildDefaultDragHandles: false,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: items.length,
            onReorder: (oldIndex, newIndex) {
              final nextItems = List<T>.from(items);
              if (newIndex > oldIndex) {
                newIndex -= 1;
              }
              final item = nextItems.removeAt(oldIndex);
              nextItems.insert(newIndex, item);
              onReorder(nextItems);
            },
            itemBuilder: (context, index) {
              final item = items[index];
              return ListTile(
                key: ValueKey('$title-$item'),
                contentPadding: EdgeInsets.zero,
                leading: itemLeading?.call(item),
                title: Text(itemLabel(item)),
                subtitle: const Text('长按拖动即可重新排序'),
                trailing: ReorderableDragStartListener(
                  index: index,
                  child: const Icon(Icons.drag_handle_rounded),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ProviderReorderCard extends StatelessWidget {
  const _ProviderReorderCard({
    required this.title,
    required this.items,
    required this.itemLabel,
    required this.itemLeading,
    required this.isEnabled,
    required this.onToggle,
    required this.onReorder,
  });

  final String title;
  final List<String> items;
  final String Function(String item) itemLabel;
  final Widget Function(String item) itemLeading;
  final bool Function(String providerId) isEnabled;
  final void Function(String providerId, bool enabled) onToggle;
  final ValueChanged<List<String>> onReorder;

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          ReorderableListView.builder(
            shrinkWrap: true,
            buildDefaultDragHandles: false,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: items.length,
            onReorder: (oldIndex, newIndex) {
              final nextItems = List<String>.from(items);
              if (newIndex > oldIndex) {
                newIndex -= 1;
              }
              final item = nextItems.removeAt(oldIndex);
              nextItems.insert(newIndex, item);
              onReorder(nextItems);
            },
            itemBuilder: (context, index) {
              final item = items[index];
              final enabled = isEnabled(item);
              return ListTile(
                key: ValueKey('$title-$item'),
                contentPadding: EdgeInsets.zero,
                leading: itemLeading(item),
                title: Text(itemLabel(item)),
                subtitle: Text(
                  enabled ? '已开启，长按拖动即可重新排序' : '已关闭，不会在首页、发现和搜索中显示',
                ),
                trailing: SizedBox(
                  width: 120,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Switch.adaptive(
                        key: Key('layout-provider-toggle-$item'),
                        value: enabled,
                        onChanged: (value) => onToggle(item, value),
                      ),
                      ReorderableDragStartListener(
                        index: index,
                        child: const Icon(Icons.drag_handle_rounded),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
