import 'package:flutter/material.dart';
import 'package:live_core/live_core.dart';
import 'package:nolive_app/src/app/bootstrap/bootstrap.dart';
import 'package:nolive_app/src/app/routing/app_routes.dart';
import 'package:nolive_app/src/features/category/application/load_provider_categories_use_case.dart';
import 'package:nolive_app/src/features/search/presentation/search_page.dart';
import 'package:nolive_app/src/shared/presentation/widgets/empty_state_card.dart';
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
            .where((item) => item.supports(ProviderCapability.categories))
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
                  _ProviderCategoriesTab(
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
