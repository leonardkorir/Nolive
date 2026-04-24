import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nolive_app/src/app/home/presentation/home_page.dart';
import 'package:nolive_app/src/app/shell/app_shell_dependencies.dart';
import 'package:nolive_app/src/features/browse/presentation/browse_page.dart';
import 'package:nolive_app/src/features/library/presentation/library_page.dart';
import 'package:nolive_app/src/features/profile/presentation/profile_page.dart';
import 'package:nolive_app/src/features/settings/application/manage_layout_preferences_use_case.dart';

class AppShellPage extends StatefulWidget {
  const AppShellPage({required this.dependencies, super.key});

  final AppShellDependencies dependencies;

  @override
  State<AppShellPage> createState() => _AppShellPageState();
}

class _AppShellPageState extends State<AppShellPage> {
  late final Map<ShellTabId, _AppDestination> _destinationCatalog = {
    ShellTabId.home: _AppDestination(
      id: ShellTabId.home,
      label: '首页',
      icon: Icons.home_outlined,
      selectedIcon: Icons.home_rounded,
      builder: () => HomePage(dependencies: widget.dependencies.home),
    ),
    ShellTabId.browse: _AppDestination(
      id: ShellTabId.browse,
      label: '发现',
      icon: Icons.grid_view_rounded,
      selectedIcon: Icons.grid_view,
      builder: () => BrowsePage(dependencies: widget.dependencies.browse),
    ),
    ShellTabId.library: _AppDestination(
      id: ShellTabId.library,
      label: '关注',
      icon: Icons.favorite_border_rounded,
      selectedIcon: Icons.favorite_rounded,
      builder: () => LibraryPage(dependencies: widget.dependencies.library),
    ),
    ShellTabId.profile: _AppDestination(
      id: ShellTabId.profile,
      label: '我的',
      icon: Icons.sentiment_satisfied_outlined,
      selectedIcon: Icons.sentiment_satisfied_alt,
      builder: () => ProfilePage(),
    ),
  };

  late final Map<ShellTabId, Widget?> _pages = {
    for (final tabId in ShellTabId.values) tabId: null,
  };

  ShellTabId? _currentTab;

  Widget _pageAt(ShellTabId tabId) {
    return _pages[tabId] ??= _destinationCatalog[tabId]!.builder();
  }

  Widget _indexedPage(ShellTabId tabId) {
    return _pageAt(tabId);
  }

  void _selectTab(ShellTabId tabId) {
    setState(() {
      _currentTab = tabId;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<LayoutPreferences>(
      valueListenable: widget.dependencies.home.layoutPreferences,
      builder: (context, preferences, _) {
        final destinations = preferences.shellTabOrder
            .where((tabId) => tabId != ShellTabId.search)
            .map((tabId) => _destinationCatalog[tabId]!)
            .toList(growable: false);
        final currentTab = _currentTab;
        final currentIndex = currentTab == null
            ? -1
            : destinations.indexWhere((item) => item.id == currentTab);
        final selectedTab =
            currentIndex == -1 ? destinations.first.id : currentTab!;
        if (currentTab != selectedTab) {
          _currentTab = selectedTab;
        }
        final selectedIndex = destinations.indexWhere(
          (item) => item.id == selectedTab,
        );
        final size = MediaQuery.sizeOf(context);
        final shortestSide = size.shortestSide;
        final isWide = shortestSide >= 840;
        final useExtendedRail = shortestSide >= 1280;
        _pageAt(selectedTab);
        final content = IndexedStack(
          index: selectedIndex,
          children: [
            for (final destination in destinations)
              _indexedPage(destination.id),
          ],
        );

        return Shortcuts(
          shortcuts: const {
            SingleActivator(LogicalKeyboardKey.digit1, alt: true):
                _SelectTabIntent(0),
            SingleActivator(LogicalKeyboardKey.digit2, alt: true):
                _SelectTabIntent(1),
            SingleActivator(LogicalKeyboardKey.digit3, alt: true):
                _SelectTabIntent(2),
            SingleActivator(LogicalKeyboardKey.digit4, alt: true):
                _SelectTabIntent(3),
            SingleActivator(LogicalKeyboardKey.digit5, alt: true):
                _SelectTabIntent(4),
          },
          child: Actions(
            actions: {
              _SelectTabIntent: CallbackAction<_SelectTabIntent>(
                onInvoke: (intent) {
                  if (intent.index < 0 || intent.index >= destinations.length) {
                    return null;
                  }
                  _selectTab(destinations[intent.index].id);
                  return null;
                },
              ),
            },
            child: FocusTraversalGroup(
              child: isWide
                  ? Scaffold(
                      body: SafeArea(
                        child: Row(
                          children: [
                            NavigationRail(
                              selectedIndex: selectedIndex,
                              useIndicator: true,
                              extended: useExtendedRail,
                              labelType: useExtendedRail
                                  ? NavigationRailLabelType.none
                                  : NavigationRailLabelType.all,
                              destinations: [
                                for (final destination in destinations)
                                  NavigationRailDestination(
                                    icon: Icon(destination.icon),
                                    selectedIcon:
                                        Icon(destination.selectedIcon),
                                    label: Text(
                                      destination.label,
                                      key: Key(
                                        'shell-tab-label-${destination.id.name}',
                                      ),
                                    ),
                                  ),
                              ],
                              onDestinationSelected: (index) {
                                _selectTab(destinations[index].id);
                              },
                            ),
                            const VerticalDivider(width: 1),
                            Expanded(child: content),
                          ],
                        ),
                      ),
                    )
                  : Scaffold(
                      body: SafeArea(child: content),
                      bottomNavigationBar: NavigationBar(
                        selectedIndex: selectedIndex,
                        labelBehavior:
                            NavigationDestinationLabelBehavior.alwaysHide,
                        onDestinationSelected: (index) {
                          _selectTab(destinations[index].id);
                        },
                        destinations: [
                          for (final destination in destinations)
                            NavigationDestination(
                              key: Key('shell-tab-${destination.id.name}'),
                              icon: Icon(destination.icon),
                              selectedIcon: Icon(destination.selectedIcon),
                              label: destination.label,
                              tooltip: destination.label,
                            ),
                        ],
                      ),
                    ),
            ),
          ),
        );
      },
    );
  }
}

class _AppDestination {
  const _AppDestination({
    required this.id,
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.builder,
  });

  final ShellTabId id;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget Function() builder;
}

class _SelectTabIntent extends Intent {
  const _SelectTabIntent(this.index);

  final int index;
}
