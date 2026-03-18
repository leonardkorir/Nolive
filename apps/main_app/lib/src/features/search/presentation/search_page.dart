import 'package:flutter/material.dart';
import 'package:live_core/live_core.dart';
import 'package:nolive_app/src/app/bootstrap/bootstrap.dart';
import 'package:nolive_app/src/app/routing/app_routes.dart';
import 'package:nolive_app/src/shared/presentation/widgets/empty_state_card.dart';
import 'package:nolive_app/src/shared/presentation/widgets/live_room_grid_card.dart';
import 'package:nolive_app/src/shared/presentation/widgets/provider_tab_label.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({
    required this.bootstrap,
    this.standalone = false,
    super.key,
  });

  final AppBootstrap bootstrap;
  final bool standalone;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  late final TextEditingController _queryController;
  String _submittedQuery = '';
  int _searchVersion = 0;

  @override
  void initState() {
    super.initState();
    _queryController = TextEditingController();
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  void _submitSearch() {
    final query = _queryController.text.trim();
    if (query.isEmpty) {
      return;
    }
    setState(() {
      _submittedQuery = query;
      _searchVersion += 1;
    });
  }

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
            .where((item) => item.supports(ProviderCapability.searchRooms))
            .toList(growable: false)
          ..sort((a, b) => preferences
              .providerSortIndex(a.id.value)
              .compareTo(preferences.providerSortIndex(b.id.value)));

        if (providers.isEmpty) {
          return const Scaffold(body: Center(child: Text('暂无可搜索平台')));
        }

        return DefaultTabController(
          length: providers.length,
          child: Scaffold(
            appBar: AppBar(
              automaticallyImplyLeading: widget.standalone,
              titleSpacing: 8,
              title: TextField(
                controller: _queryController,
                autofocus: widget.standalone,
                decoration: InputDecoration(
                  hintText: '搜索直播间',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_queryController.text.isNotEmpty)
                        IconButton(
                          tooltip: '清空',
                          onPressed: () {
                            _queryController.clear();
                            setState(() {
                              _submittedQuery = '';
                            });
                          },
                          icon: const Icon(Icons.close_rounded),
                        ),
                      IconButton(
                        key: const Key('search-submit-button'),
                        tooltip: '开始搜索',
                        onPressed: _submitSearch,
                        icon: const Icon(Icons.arrow_forward_rounded),
                      ),
                    ],
                  ),
                ),
                textInputAction: TextInputAction.search,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _submitSearch(),
              ),
              bottom: TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.center,
                dividerColor: Colors.transparent,
                indicatorSize: TabBarIndicatorSize.label,
                labelPadding: const EdgeInsets.symmetric(horizontal: 18),
                overlayColor: WidgetStateProperty.all(Colors.transparent),
                tabs: [
                  for (final descriptor in providers)
                    Tab(
                      key: Key('search-provider-tab-${descriptor.id.value}'),
                      height: 36,
                      child: ProviderTabLabel(descriptor: descriptor),
                    ),
                ],
              ),
            ),
            body: TabBarView(
              children: [
                for (final descriptor in providers)
                  _SearchResultsTab(
                    key: PageStorageKey('search-${descriptor.id.value}'),
                    bootstrap: widget.bootstrap,
                    descriptor: descriptor,
                    query: _submittedQuery,
                    searchVersion: _searchVersion,
                    onOpenRoom: (room) {
                      Navigator.of(context).pushNamed(
                        AppRoutes.room,
                        arguments: RoomRouteArguments(
                          providerId: ProviderId(room.providerId),
                          roomId: room.roomId,
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

class _SearchResultsTab extends StatefulWidget {
  const _SearchResultsTab({
    required this.bootstrap,
    required this.descriptor,
    required this.query,
    required this.searchVersion,
    required this.onOpenRoom,
    super.key,
  });

  final AppBootstrap bootstrap;
  final ProviderDescriptor descriptor;
  final String query;
  final int searchVersion;
  final ValueChanged<LiveRoom> onOpenRoom;

  @override
  State<_SearchResultsTab> createState() => _SearchResultsTabState();
}

class _SearchResultsTabState extends State<_SearchResultsTab>
    with AutomaticKeepAliveClientMixin<_SearchResultsTab> {
  final List<LiveRoom> _rooms = [];
  final ScrollController _scrollController = ScrollController();

  bool _loading = false;
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
  }

  @override
  void didUpdateWidget(covariant _SearchResultsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.searchVersion != oldWidget.searchVersion &&
        widget.query.trim().isNotEmpty) {
      _runSearch();
    }
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (!_scrollController.hasClients || _loading || _loadingMore) {
      return;
    }
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 360) {
      _loadMore();
    }
  }

  Future<void> _runSearch() async {
    setState(() {
      _loading = true;
      _error = null;
      _currentPage = 0;
      _hasMore = false;
    });

    try {
      final response = await widget.bootstrap.searchProviderRooms(
        providerId: widget.descriptor.id,
        query: widget.query,
        page: 1,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _rooms
          ..clear()
          ..addAll(_dedupeRooms(response.items));
        _currentPage = response.page;
        _hasMore = response.hasMore;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _rooms.clear();
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || widget.query.trim().isEmpty) {
      return;
    }
    setState(() {
      _loadingMore = true;
    });
    try {
      final requestedPage = _currentPage + 1;
      final response = await widget.bootstrap.searchProviderRooms(
        providerId: widget.descriptor.id,
        query: widget.query,
        page: requestedPage,
      );
      if (!mounted) {
        return;
      }
      final mergedRooms = _mergeRooms(_rooms, response.items);
      final appendedNewRooms = mergedRooms.length > _rooms.length;
      setState(() {
        _rooms
          ..clear()
          ..addAll(mergedRooms);
        _currentPage = requestedPage;
        _hasMore = appendedNewRooms && response.hasMore;
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

  List<LiveRoom> _mergeRooms(List<LiveRoom> current, List<LiveRoom> incoming) {
    return _dedupeRooms([...current, ...incoming]);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (widget.query.trim().isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: EmptyStateCard(
            title: '等待搜索',
            message: '输入关键词后，结果会按平台页签连续展示。',
            icon: Icons.manage_search_outlined,
          ),
        ),
      );
    }

    if (_loading && _rooms.isEmpty) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }

    if (_error != null && _rooms.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: EmptyStateCard(
            title: '搜索失败',
            message: '$_error',
            icon: Icons.error_outline,
            action: FilledButton.tonalIcon(
              onPressed: _runSearch,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ),
        ),
      );
    }

    if (_rooms.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: EmptyStateCard(
            title: '没有找到直播间',
            message: '换个关键词，或者切换到别的平台再试试。',
            icon: Icons.travel_explore_outlined,
          ),
        ),
      );
    }

    return NotificationListener<ScrollNotification>(
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
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 20),
            sliver: SliverGrid(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final room = _rooms[index];
                  return KeyedSubtree(
                    key: Key(
                      'search-room-card-${widget.descriptor.id.value}-${room.roomId}',
                    ),
                    child: LiveRoomGridCard(
                      room: room,
                      descriptor: widget.descriptor,
                      onTap: () => widget.onOpenRoom(room),
                    ),
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
