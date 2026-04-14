import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:live_core/live_core.dart';
import 'package:nolive_app/src/app/routing/app_routes.dart';
import 'package:nolive_app/src/features/browse/application/browse_feature_dependencies.dart';
import 'package:nolive_app/src/features/browse/application/load_provider_highlights_use_case.dart';
import 'package:nolive_app/src/features/category/application/manage_favorite_category_tags_use_case.dart';
import 'package:nolive_app/src/features/category/application/load_provider_categories_use_case.dart';
import 'package:nolive_app/src/features/category/presentation/category_search_support.dart';
import 'package:nolive_app/src/features/search/presentation/search_page.dart';
import 'package:nolive_app/src/shared/presentation/adaptive/app_adaptive_layout.dart';
import 'package:nolive_app/src/shared/presentation/gestures/responsive_tab_swipe_switcher.dart';
import 'package:nolive_app/src/shared/presentation/widgets/empty_state_card.dart';
import 'package:nolive_app/src/shared/presentation/widgets/live_room_grid_card.dart';
import 'package:nolive_app/src/shared/presentation/widgets/persisted_network_image.dart';
import 'package:nolive_app/src/shared/presentation/widgets/provider_badge.dart';
import 'package:nolive_app/src/shared/presentation/widgets/provider_tab_label.dart';

class BrowsePage extends StatelessWidget {
  const BrowsePage({required this.dependencies, super.key});

  final BrowseFeatureDependencies dependencies;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        dependencies.layoutPreferences,
        dependencies.providerCatalogRevision,
      ]),
      builder: (context, _) {
        final preferences = dependencies.layoutPreferences.value;
        final providers = dependencies
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
        final adaptive = AppAdaptiveLayoutSpec.of(context);

        return DefaultTabController(
          length: providers.length,
          child: Builder(
            builder: (tabContext) => Scaffold(
              appBar: AppBar(
                centerTitle: false,
                toolbarHeight: 52,
                titleSpacing: 8,
                title: _ProviderTabs(
                  providers: providers,
                  logoSize: adaptive.providerTabLogoSize,
                  labelPadding: adaptive.providerTabLabelPadding,
                ),
                actions: [
                  IconButton(
                    key: const Key('browse-appbar-search-button'),
                    tooltip: '搜索',
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      final controller =
                          DefaultTabController.maybeOf(tabContext);
                      final selectedIndex = controller?.index ?? 0;
                      final selectedProvider = providers[selectedIndex];
                      Navigator.of(tabContext).push(
                        MaterialPageRoute<void>(
                          builder: (context) => SearchPage(
                            dependencies: dependencies.searchDependencies,
                            standalone: true,
                            initialProviderId: selectedProvider.id,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.search_rounded),
                  ),
                  const SizedBox(width: 4),
                ],
              ),
              body: ResponsiveTabSwipeSwitcher(
                key: const Key('browse-provider-tab-swipe-switcher'),
                child: TabBarView(
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    for (final descriptor in providers)
                      descriptor.supports(ProviderCapability.categories)
                          ? _ProviderCategoriesTab(
                              dependencies: dependencies,
                              descriptor: descriptor,
                            )
                          : _ProviderDiscoveryTab(
                              dependencies: dependencies,
                              descriptor: descriptor,
                              pageHorizontalPadding:
                                  adaptive.pageHorizontalPadding,
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

class _ProviderTabs extends StatelessWidget {
  const _ProviderTabs({
    required this.providers,
    required this.logoSize,
    required this.labelPadding,
  });

  final List<ProviderDescriptor> providers;
  final double logoSize;
  final EdgeInsetsGeometry labelPadding;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TabBar(
        isScrollable: true,
        tabAlignment: TabAlignment.center,
        dividerColor: Colors.transparent,
        indicatorSize: TabBarIndicatorSize.label,
        labelPadding: labelPadding,
        overlayColor: WidgetStateProperty.all(Colors.transparent),
        splashBorderRadius: BorderRadius.circular(999),
        tabs: [
          for (final descriptor in providers)
            Tab(
              key: Key('browse-provider-tab-${descriptor.id.value}'),
              height: 34,
              child: ProviderTabLabel(
                descriptor: descriptor,
                logoSize: logoSize,
              ),
            ),
        ],
      ),
    );
  }
}

class _ProviderDiscoveryTab extends StatefulWidget {
  const _ProviderDiscoveryTab({
    required this.dependencies,
    required this.descriptor,
    required this.pageHorizontalPadding,
  });

  final BrowseFeatureDependencies dependencies;
  final ProviderDescriptor descriptor;
  final double pageHorizontalPadding;

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
    return widget.dependencies.loadProviderHighlights(
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
              padding: EdgeInsets.all(widget.pageHorizontalPadding),
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
              padding: EdgeInsets.all(widget.pageHorizontalPadding),
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
            padding: EdgeInsets.fromLTRB(
              widget.pageHorizontalPadding * 0.75,
              10,
              widget.pageHorizontalPadding * 0.75,
              96,
            ),
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
    required this.dependencies,
    required this.descriptor,
  });

  final BrowseFeatureDependencies dependencies;
  final ProviderDescriptor descriptor;

  @override
  State<_ProviderCategoriesTab> createState() => _ProviderCategoriesTabState();
}

class _ProviderCategoriesTabState extends State<_ProviderCategoriesTab>
    with AutomaticKeepAliveClientMixin<_ProviderCategoriesTab> {
  late Future<ProviderCategoriesPayload> _future;
  late final TextEditingController _searchController;
  final Set<String> _expandedCategoryIds = <String>{};
  List<FavoriteCategoryTag> _favoriteTags = const <FavoriteCategoryTag>[];
  String _categoryQuery = '';

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _future = widget.dependencies.loadProviderCategories(widget.descriptor.id);
    _reloadFavoriteTags();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() {
      _future = widget.dependencies.loadProviderCategories(
        widget.descriptor.id,
      );
      _expandedCategoryIds.clear();
    });
    await _reloadFavoriteTags();
    await _future;
  }

  Future<void> _reloadFavoriteTags() async {
    final tags = await widget.dependencies.loadFavoriteCategoryTags();
    if (!mounted) {
      return;
    }
    setState(() {
      _favoriteTags = tags
          .where((item) => item.providerId == widget.descriptor.id)
          .toList(growable: false);
    });
  }

  List<LiveSubCategory> _childrenOf(LiveCategory category) {
    if (category.children.isNotEmpty) {
      return category.children;
    }
    return [
      LiveSubCategory(
        id: category.id,
        parentId: category.id,
        name: normalizeDisplayText(category.name),
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

  Future<void> _openCategory(LiveSubCategory category) async {
    await Navigator.of(context).pushNamed(
      AppRoutes.providerCategories,
      arguments: ProviderCategoriesRouteArguments(
        providerId: widget.descriptor.id,
        initialCategoryId: category.id,
      ),
    );
    if (mounted) {
      await _reloadFavoriteTags();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final adaptive = AppAdaptiveLayoutSpec.of(context);
    final queryActive = _categoryQuery.trim().isNotEmpty;
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
              padding: EdgeInsets.all(adaptive.pageHorizontalPadding),
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
          final filteredGroups = filterCategoryGroups(
            payload.categories,
            _categoryQuery,
            childrenOf: _childrenOf,
          );
          return LayoutBuilder(
            builder: (context, constraints) {
              final horizontalPadding = adaptive.pageHorizontalPadding;
              final width = constraints.maxWidth - (horizontalPadding * 2);
              final crossAxisCount =
                  adaptive.browseCategoryCrossAxisCount(width);
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(0, 6, 0, 96),
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      horizontalPadding,
                      8,
                      horizontalPadding,
                      8,
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: adaptive.categorySearchMaxWidth,
                        ),
                        child: TextField(
                          key: Key(
                            'browse-category-search-field-${widget.descriptor.id.value}',
                          ),
                          controller: _searchController,
                          decoration: InputDecoration(
                            hintText: '搜索分类',
                            prefixIcon: const Icon(Icons.search_rounded),
                            suffixIcon: _categoryQuery.trim().isEmpty
                                ? null
                                : IconButton(
                                    tooltip: '清空',
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() {
                                        _categoryQuery = '';
                                      });
                                    },
                                    icon: const Icon(Icons.close_rounded),
                                  ),
                          ),
                          onChanged: (value) {
                            setState(() {
                              _categoryQuery = value;
                            });
                          },
                        ),
                      ),
                    ),
                  ),
                  if (_favoriteTags.isNotEmpty)
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        horizontalPadding,
                        0,
                        horizontalPadding,
                        12,
                      ),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final tag in _favoriteTags)
                            ActionChip(
                              key: Key(
                                'browse-favorite-category-chip-'
                                '${widget.descriptor.id.value}-${tag.categoryId}',
                              ),
                              avatar: _FavoriteCategoryAvatar(
                                descriptor: widget.descriptor,
                                imageUrl: tag.imageUrl,
                              ),
                              label: Text(normalizeDisplayText(tag.label)),
                              onPressed: () {
                                _openCategory(
                                  LiveSubCategory(
                                    id: tag.categoryId,
                                    parentId: tag.categoryId,
                                    name: normalizeDisplayText(tag.label),
                                    pic: tag.imageUrl,
                                  ),
                                );
                              },
                            ),
                        ],
                      ),
                    ),
                  if (queryActive && filteredGroups.isEmpty)
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        horizontalPadding,
                        24,
                        horizontalPadding,
                        96,
                      ),
                      child: const EmptyStateCard(
                        title: '没有找到匹配分类',
                        message: '换个关键词再试试。',
                        icon: Icons.search_off_rounded,
                      ),
                    ),
                  for (final category in filteredGroups) ...[
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        horizontalPadding,
                        8,
                        horizontalPadding,
                        6,
                      ),
                      child: Text(
                        normalizeDisplayText(category.group.name),
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  fontSize: adaptive.categoryTileTextSize + 2,
                                ),
                      ),
                    ),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      padding: EdgeInsets.fromLTRB(
                        horizontalPadding,
                        0,
                        horizontalPadding,
                        0,
                      ),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                        childAspectRatio: adaptive.categoryTileChildAspectRatio,
                      ),
                      itemCount: (queryActive
                                  ? category.items
                                  : _visibleChildren(category.group))
                              .length +
                          (!queryActive &&
                                  _childrenOf(category.group).length > 15 &&
                                  !_expandedCategoryIds
                                      .contains(category.group.id)
                              ? 1
                              : 0),
                      itemBuilder: (context, index) {
                        final visibleChildren = queryActive
                            ? category.items
                            : _visibleChildren(category.group);
                        if (index >= visibleChildren.length) {
                          return _CategoryTile(
                            label: '显示全部',
                            showAllTile: true,
                            descriptor: widget.descriptor,
                            visualExtent: adaptive.categoryTileVisualExtent,
                            labelFontSize: adaptive.categoryTileTextSize,
                            onTap: () {
                              setState(() {
                                _expandedCategoryIds.add(category.group.id);
                              });
                            },
                          );
                        }
                        final subCategory = visibleChildren[index];
                        return _CategoryTile(
                          key: Key(
                            'browse-category-${widget.descriptor.id.value}-${subCategory.id}',
                          ),
                          descriptor: widget.descriptor,
                          categoryId: subCategory.id,
                          label: normalizeDisplayText(subCategory.name),
                          imageUrl: subCategory.pic,
                          visualExtent: adaptive.categoryTileVisualExtent,
                          labelFontSize: adaptive.categoryTileTextSize,
                          onTap: () => _openCategory(subCategory),
                        );
                      },
                    ),
                    SizedBox(height: adaptive.sectionGap + 2),
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
    required this.descriptor,
    required this.label,
    required this.onTap,
    required this.visualExtent,
    required this.labelFontSize,
    this.imageUrl,
    this.categoryId,
    this.showAllTile = false,
    super.key,
  });

  final ProviderDescriptor descriptor;
  final String label;
  final String? imageUrl;
  final String? categoryId;
  final VoidCallback onTap;
  final bool showAllTile;
  final double visualExtent;
  final double labelFontSize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final normalizedLabel = normalizeDisplayText(label);
    final normalizedImageUrl = imageUrl?.trim() ?? '';
    final hasImage = normalizedImageUrl.isNotEmpty;
    final compactLayout = visualExtent <= 44;
    final contentPadding = compactLayout
        ? const EdgeInsets.fromLTRB(3, 2, 3, 4)
        : const EdgeInsets.fromLTRB(6, 8, 6, 8);
    final labelGap = compactLayout ? 2.0 : 8.0;
    return Material(
      color: theme.cardColor,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: contentPadding,
          child: showAllTile
              ? Center(
                  child: Text(
                    normalizedLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: labelFontSize,
                      height: 1.08,
                    ),
                  ),
                )
              : Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final visualSize = math.min(
                            constraints.maxWidth,
                            math.max(visualExtent, constraints.maxHeight),
                          );
                          return Align(
                            alignment: Alignment.topCenter,
                            child: SizedBox.square(
                              key: categoryId == null
                                  ? null
                                  : Key(
                                      'browse-category-visual-'
                                      '${descriptor.id.value}-$categoryId',
                                    ),
                              dimension: visualSize,
                              child: Padding(
                                padding: const EdgeInsets.all(4),
                                child: hasImage
                                    ? PersistedNetworkImage(
                                        imageUrl: normalizedImageUrl,
                                        bucket:
                                            PersistedImageBucket.categoryIcon,
                                        fit: BoxFit.contain,
                                        filterQuality: FilterQuality.high,
                                        fallback: _CategoryTileFallback(
                                          label: normalizedLabel,
                                        ),
                                      )
                                    : _CategoryTileFallback(
                                        label: normalizedLabel,
                                      ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    SizedBox(height: labelGap),
                    Text(
                      normalizedLabel,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w500,
                        height: 1.08,
                        fontSize: labelFontSize,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _CategoryTileFallback extends StatelessWidget {
  const _CategoryTileFallback({
    required this.label,
  });

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trimmed = label.trim();
    final monogram = trimmed.isEmpty ? '分' : trimmed.substring(0, 1);
    final displayFontSize = theme.textTheme.displaySmall?.fontSize ?? 36;
    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          monogram,
          style: theme.textTheme.displaySmall?.copyWith(
            color: theme.colorScheme.onSurface,
            fontWeight: FontWeight.w700,
            height: 1,
            letterSpacing: -0.4,
            fontSize: displayFontSize * 0.6,
          ),
        ),
      ),
    );
  }
}

class _FavoriteCategoryAvatar extends StatelessWidget {
  const _FavoriteCategoryAvatar({
    required this.descriptor,
    required this.imageUrl,
  });

  final ProviderDescriptor descriptor;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 18,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: PersistedNetworkImage(
          imageUrl: imageUrl ?? '',
          bucket: PersistedImageBucket.categoryIcon,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          fallback: Icon(
            ProviderBadge.iconOf(descriptor.id),
            size: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
