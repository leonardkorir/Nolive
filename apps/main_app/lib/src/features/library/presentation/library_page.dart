import 'dart:async';

import 'package:flutter/material.dart';
import 'package:live_core/live_core.dart';
import 'package:live_storage/live_storage.dart';
import 'package:nolive_app/src/app/bootstrap/bootstrap.dart';
import 'package:nolive_app/src/app/routing/app_routes.dart';
import 'package:nolive_app/src/features/library/application/load_follow_watchlist_use_case.dart';
import 'package:nolive_app/src/features/settings/application/manage_follow_preferences_use_case.dart';
import 'package:nolive_app/src/shared/presentation/theme/zh_text.dart';
import 'package:nolive_app/src/shared/presentation/widgets/empty_state_card.dart';
import 'package:nolive_app/src/shared/presentation/widgets/follow_watch_row.dart';
import 'package:nolive_app/src/shared/presentation/widgets/live_room_grid_card.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({required this.bootstrap, super.key});

  final AppBootstrap bootstrap;

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

enum _FollowFilter { all, live, offline }

enum _FollowDisplayMode { list, grid }

enum _FollowSortMode { liveFirst, alphabetical }

enum _LibraryMenuAction { subscribe, toggleMode, sort, settings }

class _LibraryPageState extends State<LibraryPage> {
  Timer? _autoRefreshTimer;
  _FollowFilter _followFilter = _FollowFilter.all;
  _FollowDisplayMode _displayMode = _FollowDisplayMode.list;
  _FollowSortMode _sortMode = _FollowSortMode.liveFirst;
  String? _selectedTag;
  bool _refreshing = false;
  bool _initialLoading = true;
  Object? _loadError;
  int _refreshGeneration = 0;
  int _localLoadGeneration = 0;
  _LibraryPageData? _data;
  FollowPreferences _preferences = FollowPreferences.defaults;

  @override
  void initState() {
    super.initState();
    widget.bootstrap.followDataRevision.addListener(_handleFollowDataRevision);
    unawaited(_bootstrapPage());
  }

  @override
  void didUpdateWidget(covariant LibraryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bootstrap.followDataRevision !=
        widget.bootstrap.followDataRevision) {
      oldWidget.bootstrap.followDataRevision
          .removeListener(_handleFollowDataRevision);
      widget.bootstrap.followDataRevision
          .addListener(_handleFollowDataRevision);
    }
  }

  @override
  void dispose() {
    widget.bootstrap.followDataRevision
        .removeListener(_handleFollowDataRevision);
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _bootstrapPage() async {
    final localData = await _reloadLocalState();
    if (!mounted || localData == null) {
      return;
    }
    final snapshot = widget.bootstrap.followWatchlistSnapshot.value;
    if (snapshot == null && localData.watchlist.entries.isNotEmpty) {
      unawaited(_refresh(showErrorSnackBar: false));
    }
  }

  void _handleFollowDataRevision() {
    unawaited(_reloadAfterFollowDataRevision());
  }

  Future<void> _reloadAfterFollowDataRevision() async {
    final localData = await _reloadLocalState();
    if (!mounted || localData == null) {
      return;
    }
    if (localData.watchlist.entries.isEmpty) {
      widget.bootstrap.followWatchlistSnapshot.value =
          const FollowWatchlist(entries: <FollowWatchEntry>[]);
      return;
    }
    unawaited(_refresh(showErrorSnackBar: false));
  }

  Future<_LibraryPageData?> _reloadLocalState({
    bool showErrorSnackBar = false,
  }) async {
    final generation = ++_localLoadGeneration;
    try {
      final localData = await _loadLocalData();
      if (!mounted || generation != _localLoadGeneration) {
        return null;
      }
      setState(() {
        _replaceData(localData);
      });
      return localData;
    } catch (error) {
      if (!mounted || generation != _localLoadGeneration) {
        return null;
      }
      if (_data == null) {
        setState(() {
          _loadError = error;
          _initialLoading = false;
        });
      }
      if (showErrorSnackBar) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('关注列表读取失败：$error')),
        );
      }
      return null;
    }
  }

  Future<_LibraryPageData> _loadLocalData() async {
    final follows = await widget.bootstrap.followRepository.listAll();
    final tags = await widget.bootstrap.listTags();
    final preferences = await widget.bootstrap.loadFollowPreferences();
    final snapshotEntries = {
      for (final entry
          in widget.bootstrap.followWatchlistSnapshot.value?.entries ??
              const <FollowWatchEntry>[])
        '${entry.record.providerId}:${entry.record.roomId}': entry,
    };
    final previousEntries = {
      for (final entry
          in _data?.watchlist.entries ?? const <FollowWatchEntry>[])
        '${entry.record.providerId}:${entry.record.roomId}': entry,
    };
    final watchlist = FollowWatchlist(
      entries: follows.map((record) {
        final key = '${record.providerId}:${record.roomId}';
        final cached = snapshotEntries[key] ?? previousEntries[key];
        return FollowWatchEntry(
          record: record,
          detail: cached?.detail,
          error: cached?.error,
        );
      }).toList(growable: false),
    );
    return _LibraryPageData(
      watchlist: watchlist,
      tags: tags,
      preferences: preferences,
    );
  }

  Future<_LibraryPageData> _loadRemoteData({required int generation}) async {
    final localData = _data;
    if (localData == null) {
      return _loadLocalData();
    }
    if (localData.watchlist.entries.isEmpty) {
      widget.bootstrap.followWatchlistSnapshot.value =
          const FollowWatchlist(entries: []);
      return localData;
    }
    final progressiveEntries = List<FollowWatchEntry>.from(
      localData.watchlist.entries,
    );
    final watchlist = await widget.bootstrap.loadFollowWatchlist(
      onEntryResolved: (index, entry) {
        if (!mounted ||
            generation != _refreshGeneration ||
            index < 0 ||
            index >= progressiveEntries.length) {
          return;
        }
        progressiveEntries[index] = entry;
        final partialWatchlist = FollowWatchlist(
          entries: List<FollowWatchEntry>.from(
            progressiveEntries,
            growable: false,
          ),
        );
        widget.bootstrap.followWatchlistSnapshot.value = partialWatchlist;
        setState(() {
          _replaceWatchlist(partialWatchlist);
        });
      },
    );
    widget.bootstrap.followWatchlistSnapshot.value = watchlist;
    return localData.copyWith(watchlist: watchlist);
  }

  void _applyLoadedData(_LibraryPageData data) {
    _preferences = data.preferences;
    _displayMode = _preferences.displayMode == FollowDisplayModePreference.grid
        ? _FollowDisplayMode.grid
        : _FollowDisplayMode.list;
    if (_selectedTag != null && !data.tags.contains(_selectedTag)) {
      _selectedTag = null;
    }
    _configureAutoRefresh();
  }

  void _replaceData(_LibraryPageData data) {
    _loadError = null;
    _initialLoading = false;
    _data = data;
    _applyLoadedData(data);
  }

  void _replaceWatchlist(FollowWatchlist watchlist) {
    final data = _data;
    if (data == null) {
      return;
    }
    _loadError = null;
    _initialLoading = false;
    _data = data.copyWith(watchlist: watchlist);
  }

  void _configureAutoRefresh() {
    _autoRefreshTimer?.cancel();
    if (!_preferences.autoRefreshEnabled) {
      return;
    }
    _autoRefreshTimer = Timer.periodic(
      Duration(minutes: _preferences.autoRefreshIntervalMinutes),
      (_) {
        if (mounted && !_refreshing) {
          _refresh();
        }
      },
    );
  }

  Future<void> _updateFollowPreferences(FollowPreferences preferences) async {
    await UpdateFollowPreferencesUseCase(
      widget.bootstrap.settingsRepository,
    ).call(preferences);
    if (!mounted) {
      return;
    }
    setState(() {
      _preferences = preferences;
      _displayMode = preferences.displayMode == FollowDisplayModePreference.grid
          ? _FollowDisplayMode.grid
          : _FollowDisplayMode.list;
    });
    _configureAutoRefresh();
  }

  Future<void> _persistDisplayMode(_FollowDisplayMode displayMode) async {
    await _updateFollowPreferences(
      _preferences.copyWith(
        displayMode: displayMode == _FollowDisplayMode.grid
            ? FollowDisplayModePreference.grid
            : FollowDisplayModePreference.list,
      ),
    );
  }

  Future<void> _refresh({bool showErrorSnackBar = true}) async {
    final generation = ++_refreshGeneration;
    if (mounted) {
      setState(() {
        _refreshing = true;
      });
    }
    try {
      if (_data == null) {
        final localData = await _loadLocalData();
        if (!mounted || generation != _refreshGeneration) {
          return;
        }
        setState(() {
          _replaceData(localData);
        });
      }
      final data = await _loadRemoteData(generation: generation);
      if (!mounted || generation != _refreshGeneration) {
        return;
      }
      setState(() {
        _replaceData(data);
      });
    } catch (error) {
      if (!mounted || generation != _refreshGeneration) {
        return;
      }
      if (_data == null) {
        setState(() {
          _loadError = error;
          _initialLoading = false;
        });
      }
      if (showErrorSnackBar) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('关注状态刷新失败：$error')),
        );
      }
    } finally {
      if (mounted && generation == _refreshGeneration) {
        setState(() {
          _refreshing = false;
        });
      }
    }
  }

  Future<void> _removeFollow(FollowRecord record) async {
    await widget.bootstrap.removeFollowRoom(
      providerId: record.providerId,
      roomId: record.roomId,
    );
    final snapshot = widget.bootstrap.followWatchlistSnapshot.value;
    if (snapshot != null) {
      widget.bootstrap.followWatchlistSnapshot.value = FollowWatchlist(
        entries: snapshot.entries
            .where(
              (entry) =>
                  entry.record.providerId != record.providerId ||
                  entry.record.roomId != record.roomId,
            )
            .toList(growable: false),
      );
    }
    await _reloadLocalState();
  }

  Future<void> _confirmRemoveFollow(FollowRecord record) async {
    final displayName = _displayFollowName(record);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('取消关注'),
        content: Text('确认取消关注“$displayName”吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('保留关注'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确认取消'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _removeFollow(record);
    }
  }

  String _displayFollowName(FollowRecord record) {
    final streamerName = record.streamerName.trim();
    if (streamerName.isNotEmpty) {
      return streamerName;
    }
    final title = record.lastTitle?.trim();
    if (title != null && title.isNotEmpty) {
      return title;
    }
    return record.roomId;
  }

  Future<void> _showCreateTagDialog() async {
    final controller = TextEditingController();
    final created = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新建标签'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '例如：FPS'),
          onSubmitted: (_) => Navigator.of(context).pop(true),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    if (created == true && controller.text.trim().isNotEmpty) {
      await widget.bootstrap.createTag(controller.text.trim());
      await _reloadLocalState();
    }
  }

  Future<void> _showEditTagsDialog(
    FollowRecord record,
    List<String> availableTags,
  ) async {
    final selected = record.tags.toSet();
    final inputController = TextEditingController();
    final updated = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title:
                  Text('编辑标签 · ${normalizeDisplayText(record.streamerName)}'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final tag in availableTags)
                          FilterChip(
                            label: Text(tag),
                            selected: selected.contains(tag),
                            onSelected: (value) {
                              setState(() {
                                if (value) {
                                  selected.add(tag);
                                } else {
                                  selected.remove(tag);
                                }
                              });
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: inputController,
                      decoration: const InputDecoration(hintText: '输入新标签后回车'),
                      onSubmitted: (value) {
                        final normalized = value.trim();
                        if (normalized.isEmpty) {
                          return;
                        }
                        setState(() {
                          selected.add(normalized);
                        });
                        inputController.clear();
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('保存'),
                ),
              ],
            );
          },
        );
      },
    );
    if (updated == true) {
      await widget.bootstrap.updateFollowTags(
        providerId: record.providerId,
        roomId: record.roomId,
        tags: selected.toList(growable: false),
      );
      await _reloadLocalState();
    }
  }

  Future<void> _showFollowActions(
    FollowWatchEntry entry,
    List<String> availableTags,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.sell_outlined),
                  title: const Text('编辑标签'),
                  onTap: () async {
                    Navigator.of(context).pop();
                    await _showEditTagsDialog(entry.record, availableTags);
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.add_outlined),
                  title: const Text('新建标签'),
                  onTap: () async {
                    Navigator.of(context).pop();
                    await _showCreateTagDialog();
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.favorite_outline),
                  title: const Text('取消关注'),
                  onTap: () async {
                    Navigator.of(context).pop();
                    await _confirmRemoveFollow(entry.record);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showSortSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: RadioGroup<_FollowSortMode>(
            groupValue: _sortMode,
            onChanged: (value) {
              if (value == null) {
                return;
              }
              Navigator.of(context).pop();
              setState(() {
                _sortMode = value;
              });
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                RadioListTile<_FollowSortMode>(
                  value: _FollowSortMode.liveFirst,
                  title: Text('直播优先'),
                ),
                RadioListTile<_FollowSortMode>(
                  value: _FollowSortMode.alphabetical,
                  title: Text('按名称排序'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _handleMenuAction(_LibraryMenuAction action) async {
    switch (action) {
      case _LibraryMenuAction.subscribe:
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('赛事订阅暂未开放')),
        );
        return;
      case _LibraryMenuAction.toggleMode:
        await _persistDisplayMode(
          _displayMode == _FollowDisplayMode.list
              ? _FollowDisplayMode.grid
              : _FollowDisplayMode.list,
        );
        return;
      case _LibraryMenuAction.sort:
        await _showSortSheet();
        return;
      case _LibraryMenuAction.settings:
        if (!mounted) return;
        await Navigator.of(context).pushNamed(AppRoutes.followSettings);
        if (!mounted) {
          return;
        }
        await _reloadLocalState();
        return;
    }
  }

  void _openRoom(String providerId, String roomId) {
    Navigator.of(context).pushNamed(
      AppRoutes.room,
      arguments: RoomRouteArguments(
        providerId: ProviderId(providerId),
        roomId: roomId,
      ),
    );
  }

  ProviderDescriptor _descriptorForProvider(String providerId) {
    return widget.bootstrap.providerRegistry.findDescriptorById(providerId) ??
        ProviderDescriptor(
          id: ProviderId(providerId),
          displayName: providerId,
          capabilities: const <ProviderCapability>{},
          supportedPlatforms: const {ProviderPlatform.android},
        );
  }

  List<FollowWatchEntry> _filteredEntries(FollowWatchlist watchlist) {
    final entries = watchlist.entries.where((entry) {
      final matchesFilter = switch (_followFilter) {
        _FollowFilter.all => true,
        _FollowFilter.live => entry.isLive,
        _FollowFilter.offline => entry.isOffline,
      };
      final matchesTag =
          _selectedTag == null || entry.record.tags.contains(_selectedTag);
      return matchesFilter && matchesTag;
    }).toList(growable: false);

    entries.sort((left, right) {
      if (_sortMode == _FollowSortMode.liveFirst) {
        final leftLive = left.isLive ? 1 : 0;
        final rightLive = right.isLive ? 1 : 0;
        final status = rightLive.compareTo(leftLive);
        if (status != 0) {
          return status;
        }
      }
      return left.displayStreamerName.toLowerCase().compareTo(
            right.displayStreamerName.toLowerCase(),
          );
    });
    return entries;
  }

  Widget _buildFilters(List<String> tags) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _FilterChip(
            label: '全部',
            selected:
                _followFilter == _FollowFilter.all && _selectedTag == null,
            onTap: () {
              setState(() {
                _followFilter = _FollowFilter.all;
                _selectedTag = null;
              });
            },
          ),
          _FilterChip(
            label: '直播中',
            selected: _followFilter == _FollowFilter.live,
            onTap: () {
              setState(() {
                _followFilter = _FollowFilter.live;
                _selectedTag = null;
              });
            },
          ),
          _FilterChip(
            label: '未开播',
            selected: _followFilter == _FollowFilter.offline,
            onTap: () {
              setState(() {
                _followFilter = _FollowFilter.offline;
                _selectedTag = null;
              });
            },
          ),
          for (final tag in tags)
            _FilterChip(
              label: tag,
              selected: _selectedTag == tag,
              onTap: () {
                setState(() {
                  _followFilter = _FollowFilter.all;
                  _selectedTag = _selectedTag == tag ? null : tag;
                });
              },
            ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final data = _data;
    if (_initialLoading && data == null) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }
    if (data == null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        children: [
          EmptyStateCard(
            title: '关注页加载失败',
            message: '${_loadError ?? '未知错误'}',
            icon: Icons.error_outline,
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () => _refresh(showErrorSnackBar: false),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('重试'),
          ),
        ],
      );
    }

    final entries = _filteredEntries(data.watchlist);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          key: const Key('library-filter-bar'),
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
          child: _buildFilters(data.tags),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: RefreshIndicator.noSpinner(
            onRefresh: () => _refresh(),
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                if (data.watchlist.entries.isEmpty)
                  const SliverPadding(
                    padding: EdgeInsets.fromLTRB(12, 0, 12, 96),
                    sliver: SliverToBoxAdapter(
                      child: EmptyStateCard(
                        title: '暂无关注',
                        message: '在直播间点一次关注，这里会立刻出现。',
                        icon: Icons.favorite_outline,
                      ),
                    ),
                  )
                else if (entries.isEmpty)
                  const SliverPadding(
                    padding: EdgeInsets.fromLTRB(12, 0, 12, 96),
                    sliver: SliverToBoxAdapter(
                      child: EmptyStateCard(
                        title: '当前筛选下没有结果',
                        message: '换个筛选条件，或者刷新一次关注状态。',
                        icon: Icons.filter_alt_off_outlined,
                      ),
                    ),
                  )
                else if (_displayMode == _FollowDisplayMode.grid)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 96),
                    sliver: SliverLayoutBuilder(
                      builder: (context, constraints) {
                        final width = constraints.crossAxisExtent;
                        final crossAxisCount = width >= 900
                            ? 4
                            : width >= 640
                                ? 3
                                : 2;
                        return SliverGrid(
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: crossAxisCount,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                            mainAxisExtent: liveRoomGridMainAxisExtentForWidth(
                              width,
                              crossAxisCount,
                            ),
                          ),
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              final entry = entries[index];
                              final descriptor = _descriptorForProvider(
                                  entry.record.providerId);
                              return LiveRoomGridCard(
                                key: Key(
                                  'library-follow-card-${entry.record.providerId}-${entry.roomId}',
                                ),
                                room: entry.toLiveRoom(),
                                descriptor: descriptor,
                                onTap: () => _openRoom(
                                  entry.record.providerId,
                                  entry.roomId,
                                ),
                              );
                            },
                            childCount: entries.length,
                          ),
                        );
                      },
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(0, 0, 0, 96),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final entry = entries[index];
                          return FollowWatchRow(
                            key: Key(
                              'library-follow-card-${entry.record.providerId}-${entry.roomId}',
                            ),
                            entry: entry,
                            providerDescriptor:
                                _descriptorForProvider(entry.record.providerId),
                            showSurface: false,
                            onTap: () => _openRoom(
                                entry.record.providerId, entry.roomId),
                            onRemove: () => _confirmRemoveFollow(entry.record),
                            onLongPress: () =>
                                _showFollowActions(entry, data.tags),
                          );
                        },
                        childCount: entries.length,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: _refreshing
            ? const IconButton(
                onPressed: null,
                icon: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : IconButton(
                tooltip: '刷新',
                onPressed: () => _refresh(),
                icon: const Icon(Icons.refresh_rounded),
              ),
        title: const Text('关注用户'),
        actions: [
          PopupMenuButton<_LibraryMenuAction>(
            key: const Key('library-menu-button'),
            onSelected: _handleMenuAction,
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _LibraryMenuAction.subscribe,
                child:
                    _PopupRow(icon: Icons.emoji_events_outlined, label: '赛事订阅'),
              ),
              PopupMenuItem(
                value: _LibraryMenuAction.toggleMode,
                child:
                    _PopupRow(icon: Icons.visibility_outlined, label: '模式切换'),
              ),
              PopupMenuItem(
                value: _LibraryMenuAction.sort,
                child: _PopupRow(icon: Icons.sort_rounded, label: '按序排列'),
              ),
              PopupMenuItem(
                value: _LibraryMenuAction.settings,
                child: _PopupRow(
                    icon: Icons.favorite_border_rounded, label: '关注设置'),
              ),
            ],
          ),
        ],
      ),
      body: _buildBody(),
    );
  }
}

class _LibraryPageData {
  const _LibraryPageData({
    required this.watchlist,
    required this.tags,
    required this.preferences,
  });

  final FollowWatchlist watchlist;
  final List<String> tags;
  final FollowPreferences preferences;

  _LibraryPageData copyWith({
    FollowWatchlist? watchlist,
    List<String>? tags,
    FollowPreferences? preferences,
  }) {
    return _LibraryPageData(
      watchlist: watchlist ?? this.watchlist,
      tags: tags ?? this.tags,
      preferences: preferences ?? this.preferences,
    );
  }
}

class _PopupRow extends StatelessWidget {
  const _PopupRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon),
        const SizedBox(width: 8),
        Text(
          label,
          style: applyZhTextStyleOrNull(Theme.of(context).textTheme.bodyMedium),
        ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 8, bottom: 2),
      child: Material(
        color: selected
            ? theme.cardColor
            : colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
        shape: StadiumBorder(
          side: BorderSide(
            color:
                selected ? const Color(0xFFD7DEE8) : colorScheme.outlineVariant,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            child: Text(
              label,
              style: applyZhTextStyleOrNull(
                theme.textTheme.labelLarge?.copyWith(
                  fontSize: 11.8,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  color: selected
                      ? colorScheme.onSurface
                      : colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
