import 'package:flutter/material.dart';
import 'package:live_core/live_core.dart';
import 'package:nolive_app/src/app/bootstrap/bootstrap.dart';
import 'package:nolive_app/src/app/routing/app_routes.dart';
import 'package:nolive_app/src/features/search/presentation/search_page.dart';
import 'package:nolive_app/src/shared/presentation/widgets/empty_state_card.dart';
import 'package:nolive_app/src/shared/presentation/widgets/live_room_grid_card.dart';
import 'package:nolive_app/src/shared/presentation/widgets/provider_tab_label.dart';

class HomePage extends StatefulWidget {
  const HomePage({required this.bootstrap, super.key});

  final AppBootstrap bootstrap;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        widget.bootstrap.layoutPreferences,
        widget.bootstrap.providerCatalogRevision,
      ]),
      builder: (context, _) {
        final preferences = widget.bootstrap.layoutPreferences.value;
        final providers = widget.bootstrap
            .listAvailableProviders()
            .where((item) => item.supports(ProviderCapability.recommendRooms))
            .toList(growable: false)
          ..sort((a, b) => preferences
              .providerSortIndex(a.id.value)
              .compareTo(preferences.providerSortIndex(b.id.value)));

        if (providers.isEmpty) {
          return const Scaffold(body: Center(child: Text('暂无可用平台')));
        }

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
                        builder: (context) => SearchPage(
                          bootstrap: widget.bootstrap,
                          standalone: true,
                        ),
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
                  _HomeProviderFeedTab(
                    key: PageStorageKey('home-${descriptor.id.value}'),
                    bootstrap: widget.bootstrap,
                    descriptor: descriptor,
                    onOpenRoom: (room) {
                      Navigator.of(context).pushNamed(
                        AppRoutes.room,
                        arguments: RoomRouteArguments(
                          providerId: descriptor.id,
                          roomId: room.roomId,
                        ),
                      );
                    },
                    onOpenCategories: () {
                      Navigator.of(context).pushNamed(
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

class _HomeProviderFeedTab extends StatefulWidget {
  const _HomeProviderFeedTab({
    required this.bootstrap,
    required this.descriptor,
    required this.onOpenRoom,
    required this.onOpenCategories,
    super.key,
  });

  final AppBootstrap bootstrap;
  final ProviderDescriptor descriptor;
  final ValueChanged<LiveRoom> onOpenRoom;
  final VoidCallback onOpenCategories;

  @override
  State<_HomeProviderFeedTab> createState() => _HomeProviderFeedTabState();
}

class _HomeProviderFeedTabState extends State<_HomeProviderFeedTab>
    with AutomaticKeepAliveClientMixin<_HomeProviderFeedTab> {
  final List<LiveRoom> _rooms = [];
  final ScrollController _scrollController = ScrollController();

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
    _scrollController.addListener(_handleScroll);
    _loadFirstPage();
  }

  @override
  void dispose() {
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

  Future<void> _loadFirstPage() async {
    setState(() {
      _loadingInitial = true;
      _error = null;
      _currentPage = 0;
      _hasMore = false;
    });

    try {
      final response = await _loadRecommendPage(page: 1);
      if (!mounted) {
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
    } catch (error) {
      if (!mounted) {
        return;
      }
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
    try {
      final response = await _loadRecommendPage(page: _currentPage + 1);
      if (!mounted) {
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
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error;
        _loadingMore = false;
      });
    }
  }

  Future<PagedResponse<LiveRoom>> _loadRecommendPage({required int page}) {
    return widget.bootstrap.loadProviderRecommendRooms(
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
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
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
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
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
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification.metrics.pixels >=
              notification.metrics.maxScrollExtent - 360) {
            _loadMore();
          }
          return false;
        },
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(6, 6, 6, 18),
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
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                child: Center(
                  child: _loadingMore
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: CircularProgressIndicator.adaptive(),
                        )
                      : _hasMore
                          ? FilledButton.tonalIcon(
                              onPressed: _loadMore,
                              icon: const Icon(Icons.expand_more),
                              label: const Text('加载更多'),
                            )
                          : Text(
                              '已经到底了',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
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
      ),
    );
  }
}
