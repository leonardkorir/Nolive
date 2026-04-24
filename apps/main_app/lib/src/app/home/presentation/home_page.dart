import 'dart:async';

import 'package:flutter/material.dart';
import 'package:live_core/live_core.dart';
import 'package:nolive_app/src/app/home/application/home_feature_dependencies.dart';
import 'package:nolive_app/src/app/routing/app_routes.dart';
import 'package:nolive_app/src/features/search/presentation/search_page.dart';
import 'package:nolive_app/src/shared/application/app_log.dart';
import 'package:nolive_app/src/shared/presentation/adaptive/app_adaptive_layout.dart';
import 'package:nolive_app/src/shared/presentation/gestures/responsive_tab_swipe_switcher.dart';
import 'package:nolive_app/src/shared/presentation/widgets/empty_state_card.dart';
import 'package:nolive_app/src/shared/presentation/widgets/live_room_grid_card.dart';
import 'package:nolive_app/src/shared/presentation/widgets/provider_tab_label.dart';

class HomePage extends StatefulWidget {
  const HomePage({required this.dependencies, super.key});

  final HomeFeatureDependencies dependencies;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        widget.dependencies.layoutPreferences,
        widget.dependencies.providerCatalogRevision,
      ]),
      builder: (context, _) {
        final preferences = widget.dependencies.layoutPreferences.value;
        final providers = widget.dependencies
            .listAvailableProviders()
            .where((item) => item.supports(ProviderCapability.recommendRooms))
            .toList(growable: false)
          ..sort((a, b) => preferences
              .providerSortIndex(a.id.value)
              .compareTo(preferences.providerSortIndex(b.id.value)));

        if (providers.isEmpty) {
          return const Scaffold(body: Center(child: Text('暂无可用平台')));
        }
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
                    key: const Key('home-appbar-search-button'),
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
                            dependencies:
                                widget.dependencies.searchDependencies,
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
                key: const Key('home-provider-tab-swipe-switcher'),
                child: TabBarView(
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    for (final descriptor in providers)
                      _HomeProviderFeedTab(
                        key: PageStorageKey('home-${descriptor.id.value}'),
                        dependencies: widget.dependencies,
                        descriptor: descriptor,
                        pageHorizontalPadding: adaptive.pageHorizontalPadding,
                        onOpenRoom: (room) {
                          Navigator.of(tabContext).pushNamed(
                            AppRoutes.room,
                            arguments: RoomRouteArguments(
                              providerId: descriptor.id,
                              roomId: room.roomId,
                            ),
                          );
                        },
                        onOpenCategories: () {
                          Navigator.of(tabContext).pushNamed(
                            AppRoutes.providerCategories,
                            arguments: ProviderCategoriesRouteArguments(
                              providerId: descriptor.id,
                            ),
                          );
                        },
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
              key: Key('home-provider-tab-${descriptor.id.value}'),
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

class _HomeProviderFeedTab extends StatefulWidget {
  const _HomeProviderFeedTab({
    required this.dependencies,
    required this.descriptor,
    required this.pageHorizontalPadding,
    required this.onOpenRoom,
    required this.onOpenCategories,
    super.key,
  });

  final HomeFeatureDependencies dependencies;
  final ProviderDescriptor descriptor;
  final double pageHorizontalPadding;
  final ValueChanged<LiveRoom> onOpenRoom;
  final VoidCallback onOpenCategories;

  @override
  State<_HomeProviderFeedTab> createState() => _HomeProviderFeedTabState();
}

class _HomeProviderFeedTabState extends State<_HomeProviderFeedTab>
    with AutomaticKeepAliveClientMixin<_HomeProviderFeedTab> {
  static const int _maxInitialViewportPrefetchPasses = 4;

  final List<LiveRoom> _rooms = [];
  final ScrollController _scrollController = ScrollController();

  int _initialViewportPrefetchPasses = 0;
  int _loadRequestId = 0;
  int _observedProviderCatalogRevision = 0;
  bool _loadingInitial = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  int _currentPage = 0;
  Object? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _observedProviderCatalogRevision =
        widget.dependencies.providerCatalogRevision.value;
    widget.dependencies.providerCatalogRevision.addListener(
      _handleProviderCatalogRevisionChanged,
    );
    _scrollController.addListener(_handleScroll);
    _loadFirstPage();
  }

  @override
  void didUpdateWidget(covariant _HomeProviderFeedTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(
      oldWidget.dependencies.providerCatalogRevision,
      widget.dependencies.providerCatalogRevision,
    )) {
      return;
    }
    oldWidget.dependencies.providerCatalogRevision.removeListener(
      _handleProviderCatalogRevisionChanged,
    );
    _observedProviderCatalogRevision =
        widget.dependencies.providerCatalogRevision.value;
    widget.dependencies.providerCatalogRevision.addListener(
      _handleProviderCatalogRevisionChanged,
    );
  }

  @override
  void dispose() {
    widget.dependencies.providerCatalogRevision.removeListener(
      _handleProviderCatalogRevisionChanged,
    );
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (!_scrollController.hasClients || _loadingMore || _loadingInitial) {
      return;
    }
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 360) {
      _loadMore();
    }
  }

  void _handleProviderCatalogRevisionChanged() {
    final nextRevision = widget.dependencies.providerCatalogRevision.value;
    if (nextRevision == _observedProviderCatalogRevision) {
      return;
    }
    _observedProviderCatalogRevision = nextRevision;
    _loadFirstPage();
  }

  Future<void> _loadFirstPage() async {
    final requestId = ++_loadRequestId;
    setState(() {
      _loadingInitial = true;
      _error = null;
      _currentPage = 0;
      _hasMore = false;
      _initialViewportPrefetchPasses = 0;
    });

    try {
      final response = await _loadRecommendPage(page: 1);
      if (!mounted || requestId != _loadRequestId) {
        return;
      }
      if (response.items.isEmpty) {
        throw Exception('未拿到首页推荐内容');
      }

      setState(() {
        _rooms
          ..clear()
          ..addAll(_sortRooms(_dedupeRooms(response.items)));
        _currentPage = response.page;
        _hasMore = response.hasMore;
        _loadingInitial = false;
      });
      _scheduleAutoLoadMoreIfNeeded();
    } catch (error, stackTrace) {
      if (!mounted || requestId != _loadRequestId) {
        return;
      }
      AppLog.instance.error(
        'home',
        'provider recommend load failed '
            'provider=${widget.descriptor.id.value} page=1',
        error: error,
        stackTrace: stackTrace,
      );
      setState(() {
        _error = error;
        _loadingInitial = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) {
      return;
    }
    setState(() {
      _loadingMore = true;
    });
    final requestId = ++_loadRequestId;
    try {
      final response = await _loadRecommendPage(page: _currentPage + 1);
      if (!mounted || requestId != _loadRequestId) {
        return;
      }
      final mergedRooms = _mergeRooms(_rooms, response.items);
      setState(() {
        _rooms
          ..clear()
          ..addAll(mergedRooms);
        _currentPage = response.page;
        _hasMore = response.hasMore;
        _loadingMore = false;
      });
      _scheduleAutoLoadMoreIfNeeded();
    } catch (error, stackTrace) {
      if (!mounted || requestId != _loadRequestId) {
        return;
      }
      AppLog.instance.error(
        'home',
        'provider recommend load failed '
            'provider=${widget.descriptor.id.value} page=${_currentPage + 1}',
        error: error,
        stackTrace: stackTrace,
      );
      setState(() {
        _error = error;
        _loadingMore = false;
      });
    }
  }

  void _scheduleAutoLoadMoreIfNeeded() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          _loadingInitial ||
          _loadingMore ||
          !_hasMore ||
          _initialViewportPrefetchPasses >= _maxInitialViewportPrefetchPasses) {
        return;
      }
      if (!_scrollController.hasClients) {
        _initialViewportPrefetchPasses += 1;
        unawaited(_loadMore());
        return;
      }
      final position = _scrollController.position;
      final needsViewportPrefetch =
          position.maxScrollExtent <= 0 || position.extentAfter <= 180;
      if (needsViewportPrefetch) {
        _initialViewportPrefetchPasses += 1;
        unawaited(_loadMore());
      }
    });
  }

  Future<PagedResponse<LiveRoom>> _loadRecommendPage({required int page}) {
    return widget.dependencies.loadProviderRecommendRooms(
      providerId: widget.descriptor.id,
      page: page,
    );
  }

  List<LiveRoom> _dedupeRooms(List<LiveRoom> rooms) {
    final seen = <String>{};
    final items = <LiveRoom>[];
    for (final room in rooms) {
      final key = '${room.providerId}:${room.roomId}';
      if (seen.add(key)) {
        items.add(room);
      }
    }
    return items;
  }

  List<LiveRoom> _sortRooms(List<LiveRoom> rooms) {
    final sorted = [...rooms];
    sorted.sort((left, right) {
      if (left.isLive != right.isLive) {
        return right.isLive ? 1 : -1;
      }
      final popularity =
          (right.viewerCount ?? -1).compareTo(left.viewerCount ?? -1);
      if (popularity != 0) {
        return popularity;
      }
      return left.roomId.compareTo(right.roomId);
    });
    return sorted;
  }

  List<LiveRoom> _mergeRooms(List<LiveRoom> current, List<LiveRoom> incoming) {
    return _sortRooms(_dedupeRooms([...current, ...incoming]));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_loadingInitial && _rooms.isEmpty) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }

    if (_error != null && _rooms.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadFirstPage,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            widget.pageHorizontalPadding,
            16,
            widget.pageHorizontalPadding,
            120,
          ),
          children: [
            EmptyStateCard(
              title: '${widget.descriptor.displayName} 首页加载失败',
              message: '$_error',
              icon: Icons.error_outline,
              action: FilledButton.tonalIcon(
                onPressed: _loadFirstPage,
                icon: const Icon(Icons.refresh),
                label: const Text('重新加载'),
              ),
            ),
          ],
        ),
      );
    }

    if (_rooms.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadFirstPage,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            widget.pageHorizontalPadding,
            16,
            widget.pageHorizontalPadding,
            120,
          ),
          children: [
            EmptyStateCard(
              title: '${widget.descriptor.displayName} 暂时没有内容',
              message: '可以先去分类页看看，或者稍后再刷新一次。',
              icon: Icons.live_tv_outlined,
              action: FilledButton.tonalIcon(
                onPressed: widget.onOpenCategories,
                icon: const Icon(Icons.grid_view_rounded),
                label: const Text('打开分类'),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadFirstPage,
      child: CustomScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              widget.pageHorizontalPadding / 2,
              6,
              widget.pageHorizontalPadding / 2,
              18,
            ),
            sliver: SliverGrid(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final room = _rooms[index];
                  return LiveRoomGridCard(
                    room: room,
                    descriptor: widget.descriptor,
                    onTap: () => widget.onOpenRoom(room),
                  );
                },
                childCount: _rooms.length,
              ),
              gridDelegate: buildLiveRoomGridDelegate(context),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                widget.pageHorizontalPadding,
                0,
                widget.pageHorizontalPadding,
                96,
              ),
              child: Center(
                child: _loadingMore
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: CircularProgressIndicator.adaptive(),
                      )
                    : _hasMore
                        ? Text(
                            '继续滑动自动加载更多',
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                          )
                        : Text(
                            '已经到底了',
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                          ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
