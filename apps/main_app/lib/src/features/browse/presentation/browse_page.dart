import 'package:flutter/material.dart';
import 'package:live_core/live_core.dart';
import 'package:nolive_app/src/app/bootstrap/bootstrap.dart';
import 'package:nolive_app/src/app/routing/app_routes.dart';
import 'package:nolive_app/src/features/browse/application/load_provider_highlights_use_case.dart';
import 'package:nolive_app/src/features/category/application/load_provider_categories_use_case.dart';
import 'package:nolive_app/src/features/search/presentation/search_page.dart';
import 'package:nolive_app/src/shared/presentation/widgets/empty_state_card.dart';
import 'package:nolive_app/src/shared/presentation/widgets/live_room_grid_card.dart';
import 'package:nolive_app/src/shared/presentation/widgets/persisted_network_image.dart';
import 'package:nolive_app/src/shared/presentation/widgets/provider_tab_label.dart';

class BrowsePage extends StatelessWidget {
  const BrowsePage({required this.bootstrap, super.key});

  final AppBootstrap bootstrap;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        bootstrap.layoutPreferences,
        bootstrap.providerCatalogRevision,
      ]),
      builder: (context, _) {
        final preferences = bootstrap.layoutPreferences.value;
        final providers = bootstrap
            .listAvailableProviders()
            .where(
              (item) =>
                  item.supports(ProviderCapability.categories) ||
                  item.supports(ProviderCapability.searchRooms) ||
                  item.supports(ProviderCapability.recommendRooms),
            )
            .toList(growable: false)
          ..sort((a, b) => preferences
              .providerSortIndex(a.id.value)
              .compareTo(preferences.providerSortIndex(b.id.value)));

        return DefaultTabController(
          length: providers.length,
          child: Scaffold(
            appBar: AppBar(
              centerTitle: false,
              toolbarHeight: 52,
              titleSpacing: 8,
              title: _ProviderTabs(providers: providers),
              actions: [
                IconButton(
                  tooltip: '搜索',
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (context) =>
                            SearchPage(bootstrap: bootstrap, standalone: true),
                      ),
                    );
                  },
                  icon: const Icon(Icons.search_rounded),
                ),
                const SizedBox(width: 4),
              ],
            ),
            body: TabBarView(
              children: [
                for (final descriptor in providers)
                  descriptor.supports(ProviderCapability.categories)
                      ? _ProviderCategoriesTab(
                          bootstrap: bootstrap,
                          descriptor: descriptor,
                        )
                      : _ProviderDiscoveryTab(
                          bootstrap: bootstrap,
                          descriptor: descriptor,
                        ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ProviderTabs extends StatelessWidget {
  const _ProviderTabs({required this.providers});

  final List<ProviderDescriptor> providers;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TabBar(
        isScrollable: true,
        tabAlignment: TabAlignment.center,
        dividerColor: Colors.transparent,
        indicatorSize: TabBarIndicatorSize.label,
        labelPadding: const EdgeInsets.symmetric(horizontal: 18),
        overlayColor: WidgetStateProperty.all(Colors.transparent),
        splashBorderRadius: BorderRadius.circular(999),
        tabs: [
          for (final descriptor in providers)
            Tab(
              key: Key('browse-provider-tab-${descriptor.id.value}'),
              height: 34,
              child: ProviderTabLabel(
                descriptor: descriptor,
              ),
            ),
        ],
      ),
    );
  }
}

class _ProviderDiscoveryTab extends StatefulWidget {
  const _ProviderDiscoveryTab({
    required this.bootstrap,
    required this.descriptor,
  });

  final AppBootstrap bootstrap;
  final ProviderDescriptor descriptor;

  @override
  State<_ProviderDiscoveryTab> createState() => _ProviderDiscoveryTabState();
}

class _ProviderDiscoveryTabState extends State<_ProviderDiscoveryTab>
    with AutomaticKeepAliveClientMixin<_ProviderDiscoveryTab> {
  late Future<List<ProviderHighlightSection>> _future;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<ProviderHighlightSection>> _load() {
    return widget.bootstrap.loadProviderHighlights(
      providerId: widget.descriptor.id,
    );
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _load();
    });
    await _future;
  }

  void _openRoom(LiveRoom room) {
    Navigator.of(context).pushNamed(
      AppRoutes.room,
      arguments: RoomRouteArguments(
        providerId: widget.descriptor.id,
        roomId: room.roomId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return RefreshIndicator(
      onRefresh: _refresh,
      child: FutureBuilder<List<ProviderHighlightSection>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator.adaptive());
          }
          if (snapshot.hasError) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(20),
              children: [
                EmptyStateCard(
                  title: '发现内容加载失败',
                  message: '${snapshot.error}',
                  icon: Icons.travel_explore_rounded,
                ),
              ],
            );
          }
          final sections = snapshot.data ?? const [];
          if (sections.isEmpty) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(20),
              children: const [
                EmptyStateCard(
                  title: '暂无发现内容',
                  message: '当前平台还没有可用的推荐或搜索结果。',
                  icon: Icons.explore_off_rounded,
                ),
              ],
            );
          }
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 96),
            children: [
              _DiscoveryIntroCard(descriptor: widget.descriptor),
              const SizedBox(height: 10),
              for (var index = 0; index < sections.length; index++) ...[
                _DiscoverySection(
                  key: Key(
                    'browse-discover-section-'
                    '${widget.descriptor.id.value}-$index',
                  ),
                  section: sections[index],
                  onOpenRoom: _openRoom,
                ),
                if (index != sections.length - 1) const SizedBox(height: 18),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _ProviderCategoriesTab extends StatefulWidget {
  const _ProviderCategoriesTab({
    required this.bootstrap,
    required this.descriptor,
  });

  final AppBootstrap bootstrap;
  final ProviderDescriptor descriptor;

  @override
  State<_ProviderCategoriesTab> createState() => _ProviderCategoriesTabState();
}

class _ProviderCategoriesTabState extends State<_ProviderCategoriesTab>
    with AutomaticKeepAliveClientMixin<_ProviderCategoriesTab> {
  late Future<ProviderCategoriesPayload> _future;
  final Set<String> _expandedCategoryIds = <String>{};

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _future = widget.bootstrap.loadProviderCategories(widget.descriptor.id);
  }

  Future<void> _refresh() async {
    setState(() {
      _future = widget.bootstrap.loadProviderCategories(widget.descriptor.id);
      _expandedCategoryIds.clear();
    });
    await _future;
  }

  List<LiveSubCategory> _childrenOf(LiveCategory category) {
    if (category.children.isNotEmpty) {
      return category.children;
    }
    return [
      LiveSubCategory(
        id: category.id,
        parentId: category.id,
        name: category.name,
      ),
    ];
  }

  List<LiveSubCategory> _visibleChildren(LiveCategory category) {
    final children = _childrenOf(category);
    if (_expandedCategoryIds.contains(category.id) || children.length <= 15) {
      return children;
    }
    return children.take(15).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return RefreshIndicator(
      onRefresh: _refresh,
      child: FutureBuilder<ProviderCategoriesPayload>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator.adaptive());
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(20),
              children: [
                EmptyStateCard(
                  title: '分类加载失败',
                  message: '${snapshot.error}',
                  icon: Icons.error_outline,
                ),
              ],
            );
          }

          final payload = snapshot.data!;
          return LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final crossAxisCount = (width / 88).floor().clamp(4, 6);
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(0, 6, 0, 96),
                children: [
                  for (final category in payload.categories) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                      child: Text(
                        category.name,
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13.2,
                                ),
                      ),
                    ),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                        childAspectRatio: 1,
                      ),
                      itemCount: _visibleChildren(category).length +
                          (_childrenOf(category).length > 15 &&
                                  !_expandedCategoryIds.contains(category.id)
                              ? 1
                              : 0),
                      itemBuilder: (context, index) {
                        final visibleChildren = _visibleChildren(category);
                        if (index >= visibleChildren.length) {
                          return _CategoryTile(
                            label: '显示全部',
                            showAllTile: true,
                            onTap: () {
                              setState(() {
                                _expandedCategoryIds.add(category.id);
                              });
                            },
                          );
                        }
                        final subCategory = visibleChildren[index];
                        return _CategoryTile(
                          key: Key(
                            'browse-category-${widget.descriptor.id.value}-${subCategory.id}',
                          ),
                          label: subCategory.name,
                          imageUrl: subCategory.pic,
                          onTap: () {
                            Navigator.of(context).pushNamed(
                              AppRoutes.providerCategories,
                              arguments: ProviderCategoriesRouteArguments(
                                providerId: widget.descriptor.id,
                                initialCategoryId: subCategory.id,
                              ),
                            );
                          },
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                  ],
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _DiscoveryIntroCard extends StatelessWidget {
  const _DiscoveryIntroCard({
    required this.descriptor,
  });

  final ProviderDescriptor descriptor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = Theme.of(context).colorScheme.primary;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.travel_explore_rounded, color: accent, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '${descriptor.displayName} 暂未接入原生分类页，当前发现流使用推荐房间和预设搜索结果组合生成。',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 11.6,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DiscoverySection extends StatelessWidget {
  const _DiscoverySection({
    required this.section,
    required this.onOpenRoom,
    super.key,
  });

  final ProviderHighlightSection section;
  final ValueChanged<LiveRoom> onOpenRoom;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                section.query.isEmpty ? '平台推荐' : '搜索发现',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ),
            if (section.query.isNotEmpty)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  section.query,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: buildLiveRoomGridDelegate(context),
          itemCount: section.rooms.length,
          itemBuilder: (context, index) {
            final room = section.rooms[index];
            return LiveRoomGridCard(
              key: Key(
                'browse-discover-room-'
                '${section.descriptor.id.value}-${room.roomId}',
              ),
              room: room,
              descriptor: section.descriptor,
              onTap: () => onOpenRoom(room),
            );
          },
        ),
      ],
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.label,
    required this.onTap,
    this.imageUrl,
    this.showAllTile = false,
    super.key,
  });

  final String label;
  final String? imageUrl;
  final VoidCallback onTap;
  final bool showAllTile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: theme.cardColor,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          child: showAllTile
              ? Center(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 11.2,
                      height: 1.08,
                    ),
                  ),
                )
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: theme.brightness == Brightness.dark
                            ? colorScheme.surfaceContainerHighest
                            : Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: colorScheme.outlineVariant,
                        ),
                      ),
                      child: PersistedNetworkImage(
                        imageUrl: imageUrl ?? '',
                        bucket: PersistedImageBucket.categoryIcon,
                        fallback: Center(
                          child: Text(
                            label.trim().isEmpty
                                ? '分'
                                : label.trim().substring(0, 1),
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: theme.brightness == Brightness.dark
                                  ? const Color(0xFFE3C9AD)
                                  : const Color(0xFF7A5230),
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w500,
                        height: 1.08,
                        fontSize: 11.1,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
