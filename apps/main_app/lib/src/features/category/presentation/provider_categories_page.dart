import 'dart:async';

import 'package:flutter/material.dart';
import 'package:live_core/live_core.dart';
import 'package:nolive_app/src/app/bootstrap/bootstrap.dart';
import 'package:nolive_app/src/app/routing/app_routes.dart';
import 'package:nolive_app/src/features/category/application/manage_favorite_category_tags_use_case.dart';
import 'package:nolive_app/src/features/category/application/load_provider_categories_use_case.dart';
import 'package:nolive_app/src/features/category/presentation/category_search_support.dart';
import 'package:nolive_app/src/features/search/presentation/search_page.dart';
import 'package:nolive_app/src/shared/presentation/adaptive/app_adaptive_layout.dart';
import 'package:nolive_app/src/shared/presentation/widgets/empty_state_card.dart';
import 'package:nolive_app/src/shared/presentation/widgets/live_room_grid_card.dart';
import 'package:nolive_app/src/shared/presentation/widgets/persisted_network_image.dart';
import 'package:nolive_app/src/shared/presentation/widgets/provider_badge.dart';

class ProviderCategoriesPage extends StatefulWidget {
  const ProviderCategoriesPage({
    required this.bootstrap,
    required this.providerId,
    this.initialCategoryId,
    super.key,
  });

  final AppBootstrap bootstrap;
  final ProviderId providerId;
  final String? initialCategoryId;

  @override
  State<ProviderCategoriesPage> createState() => _ProviderCategoriesPageState();
}

class _ProviderCategoriesPageState extends State<ProviderCategoriesPage> {
  final ScrollController _scrollController = ScrollController();
  late final TextEditingController _searchController;

  ProviderCategoriesPayload? _payload;
  LiveCategory? _selectedGroup;
  LiveSubCategory? _selectedCategory;
  List<FavoriteCategoryTag> _favoriteTags = const <FavoriteCategoryTag>[];
  List<LiveRoom> _rooms = const [];
  String _categoryQuery = '';
  bool _loadingCategories = true;
  bool _loadingRooms = false;
  bool _loadingMore = false;
  bool _hasMore = false;
  int _currentPage = 1;
  Object? _categoriesError;
  Object? _roomsError;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _scrollController.addListener(_handleScroll);
    _loadCategories();
    unawaited(_reloadFavoriteTags());
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (!_scrollController.hasClients || _loadingRooms || _loadingMore) {
      return;
    }
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 360) {
      _loadMore();
    }
  }

  Future<void> _loadCategories() async {
    setState(() {
      _loadingCategories = true;
      _categoriesError = null;
    });
    try {
      final payload = await widget.bootstrap.loadProviderCategories(
        widget.providerId,
      );
      final initialCategory = _resolveInitialCategory(payload.categories);
      final initialGroup = initialCategory == null
          ? (payload.categories.isEmpty ? null : payload.categories.first)
          : _resolveGroupForCategory(payload.categories, initialCategory);
      if (!mounted) {
        return;
      }
      setState(() {
        _payload = payload;
        _selectedCategory = initialCategory;
        _selectedGroup = initialGroup;
        _loadingCategories = false;
      });
      if (initialCategory != null) {
        await _loadRooms(category: initialCategory);
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _categoriesError = error;
        _loadingCategories = false;
      });
    }
  }

  Future<void> _reloadFavoriteTags() async {
    final tags = await widget.bootstrap.loadFavoriteCategoryTags();
    if (!mounted) {
      return;
    }
    setState(() {
      _favoriteTags = tags
          .where((item) => item.providerId == widget.providerId)
          .toList(growable: false);
    });
  }

  Future<void> _loadRooms({
    required LiveSubCategory category,
    int page = 1,
    bool append = false,
    int attempt = 0,
  }) async {
    setState(() {
      _selectedCategory = category;
      _roomsError = null;
      if (append) {
        _loadingMore = true;
      } else {
        _loadingRooms = true;
      }
    });
    try {
      final response = await widget.bootstrap.loadCategoryRooms(
        providerId: widget.providerId,
        category: category,
        page: page,
      );
      if (!mounted) {
        return;
      }
      final mergedRooms = append
          ? _mergeRooms(_rooms, response.items)
          : _dedupeRooms(response.items);
      setState(() {
        _rooms = mergedRooms;
        _currentPage = response.page;
        _hasMore = response.hasMore;
        _loadingRooms = false;
        _loadingMore = false;
      });
      _scheduleAutoLoadMoreIfNeeded();
    } catch (error) {
      if (_shouldRetryRoomsLoad(
        category: category,
        page: page,
        append: append,
        attempt: attempt,
      )) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
        if (!mounted) {
          return;
        }
        await _loadRooms(
          category: category,
          page: page,
          append: append,
          attempt: attempt + 1,
        );
        return;
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _roomsError = error;
        _loadingRooms = false;
        _loadingMore = false;
      });
    }
  }

  bool _shouldRetryRoomsLoad({
    required LiveSubCategory category,
    required int page,
    required bool append,
    required int attempt,
  }) {
    if (widget.providerId != ProviderId.chaturbate ||
        append ||
        page != 1 ||
        attempt >= 1) {
      return false;
    }
    final selectedCategoryId = _selectedCategory?.id;
    return selectedCategoryId == null || selectedCategoryId == category.id;
  }

  Future<void> _loadMore() async {
    final category = _selectedCategory;
    if (category == null || _loadingMore || !_hasMore) {
      return;
    }

    setState(() {
      _roomsError = null;
      _loadingMore = true;
    });

    try {
      final requestedPage = _currentPage + 1;
      final response = await widget.bootstrap.loadCategoryRooms(
        providerId: widget.providerId,
        category: category,
        page: requestedPage,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _rooms = _mergeRooms(_rooms, response.items);
        _currentPage = response.page;
        _hasMore = response.hasMore;
        _loadingMore = false;
      });
      _scheduleAutoLoadMoreIfNeeded();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _roomsError = error;
        _loadingMore = false;
      });
    }
  }

  void _scheduleAutoLoadMoreIfNeeded() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          _loadingCategories ||
          _loadingRooms ||
          _loadingMore ||
          !_hasMore) {
        return;
      }
      if (!_scrollController.hasClients) {
        unawaited(_loadMore());
        return;
      }
      final position = _scrollController.position;
      if (position.maxScrollExtent <= 0 ||
          position.pixels >= position.maxScrollExtent - 360) {
        unawaited(_loadMore());
      }
    });
  }

  Future<void> _refresh() async {
    if (_payload == null) {
      await _loadCategories();
      return;
    }
    final selected =
        _selectedCategory ?? _resolveInitialCategory(_payload!.categories);
    if (selected == null) {
      return;
    }
    await _loadRooms(category: selected);
  }

  LiveSubCategory? _resolveInitialCategory(List<LiveCategory> categories) {
    final initialCategoryId = widget.initialCategoryId;
    if (initialCategoryId != null) {
      for (final category in categories) {
        for (final subCategory in _childrenOf(category)) {
          if (subCategory.id == initialCategoryId) {
            return subCategory;
          }
        }
      }
    }
    for (final category in categories) {
      final children = _childrenOf(category);
      if (children.isNotEmpty) {
        return children.first;
      }
    }
    return null;
  }

  LiveCategory? _resolveGroupForCategory(
    List<LiveCategory> categories,
    LiveSubCategory selected,
  ) {
    for (final category in categories) {
      if (_childrenOf(category).any((item) => item.id == selected.id)) {
        return category;
      }
    }
    return categories.isEmpty ? null : categories.first;
  }

  List<LiveSubCategory> _childrenOf(LiveCategory category) {
    final children = category.children.isNotEmpty
        ? category.children
        : [
            LiveSubCategory(
              id: category.id,
              parentId: category.id,
              name: category.name,
            ),
          ];
    if (widget.providerId != ProviderId.bilibili) {
      return children;
    }

    final filtered =
        children.where((item) => item.id != '0').toList(growable: false);
    return filtered.isEmpty ? children : filtered;
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

  Future<void> _showGroupPicker(List<LiveCategory> categories) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              for (final category in categories)
                ListTile(
                  title: Text(category.name),
                  trailing: _selectedGroup?.id == category.id
                      ? const Icon(Icons.check_rounded)
                      : null,
                  onTap: () {
                    Navigator.of(context).pop();
                    final children = _childrenOf(category);
                    setState(() {
                      _selectedGroup = category;
                    });
                    if (children.isNotEmpty) {
                      _loadRooms(category: children.first);
                    }
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  FavoriteCategoryTag? _currentFavoriteTag() {
    final category = _selectedCategory;
    final group = _selectedGroup;
    if (category == null || group == null) {
      return null;
    }
    for (final item in _favoriteTags) {
      if (item.matches(
          providerId: widget.providerId, categoryId: category.id)) {
        return item;
      }
    }
    return FavoriteCategoryTag(
      providerId: widget.providerId,
      categoryId: category.id,
      groupName: group.name,
      label: category.name,
      imageUrl: category.pic,
    );
  }

  bool _selectedCategoryIsFavorite() {
    final category = _selectedCategory;
    if (category == null) {
      return false;
    }
    return _favoriteTags.any(
      (item) => item.matches(
        providerId: widget.providerId,
        categoryId: category.id,
      ),
    );
  }

  Future<void> _toggleSelectedFavorite() async {
    final tag = _currentFavoriteTag();
    if (tag == null) {
      return;
    }
    final next = await widget.bootstrap.toggleFavoriteCategoryTag(tag);
    if (!mounted) {
      return;
    }
    setState(() {
      _favoriteTags = next
          .where((item) => item.providerId == widget.providerId)
          .toList(growable: false);
    });
  }

  Future<void> _selectCategory(
    LiveSubCategory category, {
    LiveCategory? group,
    bool clearQuery = false,
  }) async {
    if (clearQuery) {
      _searchController.clear();
    }
    setState(() {
      _selectedGroup = group ?? _selectedGroup;
      if (clearQuery) {
        _categoryQuery = '';
      }
    });
    await _loadRooms(category: category);
  }

  void _openProviderSearch() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => SearchPage(
          bootstrap: widget.bootstrap,
          standalone: true,
          initialProviderId: widget.providerId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final payload = _payload;
    final adaptive = AppAdaptiveLayoutSpec.of(context);
    final fallbackCategory = payload == null
        ? null
        : (_selectedCategory ?? _resolveInitialCategory(payload.categories));
    final group = payload == null
        ? null
        : fallbackCategory == null
            ? (payload.categories.isEmpty ? null : payload.categories.first)
            : (_selectedGroup ??
                _resolveGroupForCategory(payload.categories, fallbackCategory));
    final chips =
        group == null ? const <LiveSubCategory>[] : _childrenOf(group);
    final filteredGroups = payload == null
        ? const <FilteredCategoryGroup>[]
        : filterCategoryGroups(
            payload.categories,
            _categoryQuery,
            childrenOf: _childrenOf,
          );
    final queryActive = _categoryQuery.trim().isNotEmpty;
    final searchHorizontalPadding = adaptive.pageHorizontalPadding;

    return Scaffold(
      appBar: AppBar(
        title: Text(_selectedCategory?.name ?? '分区浏览'),
        actions: [
          IconButton(
            key: const Key('provider-category-search-button'),
            tooltip: '搜索直播间',
            onPressed: _openProviderSearch,
            icon: const Icon(Icons.search_rounded),
          ),
          if (_selectedCategory != null)
            IconButton(
              key: const Key('provider-category-favorite-button'),
              tooltip: _selectedCategoryIsFavorite() ? '取消收藏分类' : '收藏分类',
              onPressed: _toggleSelectedFavorite,
              icon: Icon(
                _selectedCategoryIsFavorite()
                    ? Icons.star_rounded
                    : Icons.star_border_rounded,
              ),
            ),
          if (payload != null)
            IconButton(
              tooltip: '切换分组',
              onPressed: () => _showGroupPicker(payload.categories),
              icon: const Icon(Icons.grid_view_rounded),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: _loadingCategories
            ? const Center(child: CircularProgressIndicator.adaptive())
            : _categoriesError != null || payload == null
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.all(searchHorizontalPadding),
                    children: [
                      EmptyStateCard(
                        title: '分区加载失败',
                        message: '$_categoriesError',
                        icon: Icons.error_outline,
                      ),
                    ],
                  )
                : NotificationListener<ScrollNotification>(
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
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(
                              searchHorizontalPadding,
                              8,
                              searchHorizontalPadding,
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
                                    'provider-category-search-field-${widget.providerId.value}',
                                  ),
                                  controller: _searchController,
                                  decoration: InputDecoration(
                                    hintText: '搜索分类',
                                    prefixIcon:
                                        const Icon(Icons.search_rounded),
                                    suffixIcon: queryActive
                                        ? IconButton(
                                            tooltip: '清空',
                                            onPressed: () {
                                              _searchController.clear();
                                              setState(() {
                                                _categoryQuery = '';
                                              });
                                            },
                                            icon: const Icon(
                                              Icons.close_rounded,
                                            ),
                                          )
                                        : null,
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
                        ),
                        if (_favoriteTags.isNotEmpty)
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: EdgeInsets.fromLTRB(
                                searchHorizontalPadding,
                                0,
                                searchHorizontalPadding,
                                8,
                              ),
                              child: Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  for (final tag in _favoriteTags)
                                    ActionChip(
                                      key: Key(
                                        'provider-category-favorite-chip-'
                                        '${widget.providerId.value}-${tag.categoryId}',
                                      ),
                                      avatar: _FavoriteCategoryAvatar(
                                        providerId: widget.providerId,
                                        imageUrl: tag.imageUrl,
                                      ),
                                      label: Text(tag.label),
                                      onPressed: () {
                                        final nextGroup =
                                            _resolveGroupForCategory(
                                          payload.categories,
                                          LiveSubCategory(
                                            id: tag.categoryId,
                                            parentId: tag.categoryId,
                                            name: tag.label,
                                            pic: tag.imageUrl,
                                          ),
                                        );
                                        _selectCategory(
                                          LiveSubCategory(
                                            id: tag.categoryId,
                                            parentId: tag.categoryId,
                                            name: tag.label,
                                            pic: tag.imageUrl,
                                          ),
                                          group: nextGroup,
                                          clearQuery: true,
                                        );
                                      },
                                    ),
                                ],
                              ),
                            ),
                          ),
                        if (queryActive)
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: EdgeInsets.fromLTRB(
                                searchHorizontalPadding,
                                0,
                                searchHorizontalPadding,
                                12,
                              ),
                              child: filteredGroups.isEmpty
                                  ? const EmptyStateCard(
                                      title: '没有找到匹配分类',
                                      message: '换个关键词再试试。',
                                      icon: Icons.search_off_rounded,
                                    )
                                  : Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        for (final group in filteredGroups) ...[
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              top: 8,
                                              bottom: 6,
                                            ),
                                            child: Text(
                                              group.group.name,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleSmall
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                            ),
                                          ),
                                          Wrap(
                                            spacing: 6,
                                            runSpacing: 6,
                                            children: [
                                              for (final subCategory
                                                  in group.items)
                                                ChoiceChip(
                                                  visualDensity:
                                                      VisualDensity.compact,
                                                  materialTapTargetSize:
                                                      MaterialTapTargetSize
                                                          .shrinkWrap,
                                                  key: Key(
                                                    'provider-category-search-chip-'
                                                    '${widget.providerId.value}-${subCategory.id}',
                                                  ),
                                                  label: Text(subCategory.name),
                                                  selected:
                                                      _selectedCategory?.id ==
                                                          subCategory.id,
                                                  onSelected: (_) {
                                                    _selectCategory(
                                                      subCategory,
                                                      group: group.group,
                                                      clearQuery: true,
                                                    );
                                                  },
                                                ),
                                            ],
                                          ),
                                        ],
                                      ],
                                    ),
                            ),
                          )
                        else if (chips.isNotEmpty)
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: EdgeInsets.fromLTRB(
                                searchHorizontalPadding * 0.75,
                                6,
                                searchHorizontalPadding * 0.75,
                                6,
                              ),
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: [
                                    for (final subCategory in chips) ...[
                                      ChoiceChip(
                                        visualDensity: VisualDensity.compact,
                                        materialTapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                        key: Key(
                                          'provider-category-chip-${widget.providerId.value}-${subCategory.id}',
                                        ),
                                        label: Text(
                                          subCategory.name,
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelLarge
                                              ?.copyWith(
                                                fontSize: adaptive
                                                    .categoryTileTextSize,
                                                fontWeight: FontWeight.w500,
                                              ),
                                        ),
                                        selected: _selectedCategory?.id ==
                                            subCategory.id,
                                        onSelected: (_) {
                                          _selectCategory(
                                            subCategory,
                                            group: group,
                                          );
                                        },
                                      ),
                                      const SizedBox(width: 6),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        if (_loadingRooms)
                          const SliverFillRemaining(
                            hasScrollBody: false,
                            child: Center(
                              child: CircularProgressIndicator.adaptive(),
                            ),
                          )
                        else if (_roomsError != null)
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: EdgeInsets.fromLTRB(
                                searchHorizontalPadding,
                                8,
                                searchHorizontalPadding,
                                120,
                              ),
                              child: EmptyStateCard(
                                title: '分区房间加载失败',
                                message: '$_roomsError',
                                icon: Icons.error_outline,
                                action: FilledButton.tonalIcon(
                                  onPressed: () {
                                    final category = _selectedCategory;
                                    if (category != null) {
                                      _loadRooms(category: category);
                                    }
                                  },
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('重试'),
                                ),
                              ),
                            ),
                          )
                        else if (_rooms.isEmpty)
                          const SliverFillRemaining(
                            hasScrollBody: false,
                            child: Padding(
                              padding: EdgeInsets.fromLTRB(16, 8, 16, 120),
                              child: EmptyStateCard(
                                title: '暂无房间',
                                message: '当前分区没有拿到直播间，稍后刷新再试。',
                                icon: Icons.live_tv_outlined,
                              ),
                            ),
                          )
                        else ...[
                          SliverPadding(
                            padding: EdgeInsets.fromLTRB(
                              searchHorizontalPadding / 2,
                              0,
                              searchHorizontalPadding / 2,
                              20,
                            ),
                            sliver: SliverGrid(
                              delegate: SliverChildBuilderDelegate(
                                (context, index) {
                                  final room = _rooms[index];
                                  return KeyedSubtree(
                                    key: Key(
                                      'provider-category-room-${widget.providerId.value}-${room.roomId}',
                                    ),
                                    child: LiveRoomGridCard(
                                      room: room,
                                      descriptor: payload.descriptor,
                                      onTap: () {
                                        Navigator.of(context).pushNamed(
                                          AppRoutes.room,
                                          arguments: RoomRouteArguments(
                                            providerId: widget.providerId,
                                            roomId: room.roomId,
                                          ),
                                        );
                                      },
                                    ),
                                  );
                                },
                                childCount: _rooms.length,
                              ),
                              gridDelegate: buildLiveRoomGridDelegate(
                                context,
                              ),
                            ),
                          ),
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: EdgeInsets.fromLTRB(
                                searchHorizontalPadding,
                                0,
                                searchHorizontalPadding,
                                96,
                              ),
                              child: Center(
                                child: _loadingMore
                                    ? const Padding(
                                        padding:
                                            EdgeInsets.symmetric(vertical: 12),
                                        child: CircularProgressIndicator
                                            .adaptive(),
                                      )
                                    : _hasMore
                                        ? Text(
                                            '继续滑动自动加载更多',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .onSurfaceVariant,
                                                ),
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
                      ],
                    ),
                  ),
      ),
    );
  }
}

class _FavoriteCategoryAvatar extends StatelessWidget {
  const _FavoriteCategoryAvatar({
    required this.providerId,
    required this.imageUrl,
  });

  final ProviderId providerId;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final accent = ProviderBadge.accentColorOf(providerId);
    return SizedBox.square(
      dimension: 18,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: ColoredBox(
          color: accent.withValues(alpha: 0.08),
          child: PersistedNetworkImage(
            imageUrl: imageUrl ?? '',
            bucket: PersistedImageBucket.categoryIcon,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.high,
            fallback: Icon(
              ProviderBadge.iconOf(providerId),
              size: 14,
              color: accent,
            ),
          ),
        ),
      ),
    );
  }
}
