import 'package:flutter/foundation.dart';

import '../../library/application/load_follow_watchlist_use_case.dart';
import 'room_preview_dependencies.dart';

@immutable
class RoomFollowWatchlistState {
  const RoomFollowWatchlistState({
    required this.watchlist,
    required this.hydrated,
    required this.isLoading,
    required this.error,
  });

  const RoomFollowWatchlistState.initial()
      : watchlist = null,
        hydrated = false,
        isLoading = false,
        error = null;

  factory RoomFollowWatchlistState.fromSnapshot(FollowWatchlist? snapshot) {
    return RoomFollowWatchlistState(
      watchlist: snapshot,
      hydrated: snapshot != null,
      isLoading: false,
      error: null,
    );
  }

  final FollowWatchlist? watchlist;
  final bool hydrated;
  final bool isLoading;
  final Object? error;

  RoomFollowWatchlistState copyWith({
    FollowWatchlist? watchlist,
    bool? hydrated,
    bool? isLoading,
    Object? error = _roomFollowWatchlistSentinel,
  }) {
    return RoomFollowWatchlistState(
      watchlist: watchlist ?? this.watchlist,
      hydrated: hydrated ?? this.hydrated,
      isLoading: isLoading ?? this.isLoading,
      error:
          identical(error, _roomFollowWatchlistSentinel) ? this.error : error,
    );
  }
}

const Object _roomFollowWatchlistSentinel = Object();

class RoomFollowWatchlistController {
  RoomFollowWatchlistController({
    required this.dependencies,
    this.trace,
  }) : _state = ValueNotifier<RoomFollowWatchlistState>(
          RoomFollowWatchlistState.fromSnapshot(
            dependencies.followWatchlistSnapshot.value,
          ),
        ) {
    dependencies.followWatchlistSnapshot.addListener(_handleSnapshotChanged);
  }

  final RoomFollowWatchlistDependencies dependencies;
  final void Function(String message)? trace;
  final ValueNotifier<RoomFollowWatchlistState> _state;
  int _requestId = 0;
  int? _lastTracedSnapshotEntryCount;

  ValueListenable<RoomFollowWatchlistState> get listenable => _state;

  RoomFollowWatchlistState get current => _state.value;

  Future<void> ensureLoaded({bool force = false}) async {
    final currentState = current;
    if (!force && (currentState.isLoading || currentState.hydrated)) {
      return;
    }
    final requestId = ++_requestId;
    _emit(
      currentState.copyWith(
        isLoading: true,
        error: null,
      ),
    );
    _trace('follow watchlist load start force=$force');
    try {
      final watchlist = await dependencies.loadFollowWatchlist();
      if (requestId != _requestId) {
        return;
      }
      dependencies.followWatchlistSnapshot.value = watchlist;
    } catch (error) {
      if (requestId != _requestId) {
        return;
      }
      _trace('follow watchlist load failed: $error');
      _emit(
        current.copyWith(
          isLoading: false,
          error: error,
        ),
      );
    }
  }

  void replaceSnapshot(
    FollowWatchlist? watchlist, {
    required bool hydrated,
  }) {
    _requestId += 1;
    if (dependencies.followWatchlistSnapshot.value != watchlist) {
      dependencies.followWatchlistSnapshot.value = watchlist;
      return;
    }
    _emit(
      RoomFollowWatchlistState(
        watchlist: watchlist,
        hydrated: hydrated,
        isLoading: false,
        error: null,
      ),
    );
  }

  void dispose() {
    dependencies.followWatchlistSnapshot.removeListener(_handleSnapshotChanged);
    _state.dispose();
  }

  void _handleSnapshotChanged() {
    final snapshot = dependencies.followWatchlistSnapshot.value;
    final entryCount = snapshot?.entries.length ?? 0;
    if (_lastTracedSnapshotEntryCount != entryCount) {
      _lastTracedSnapshotEntryCount = entryCount;
      _trace('follow watchlist snapshot updated entries=$entryCount');
    }
    _emit(RoomFollowWatchlistState.fromSnapshot(snapshot));
  }

  void _emit(RoomFollowWatchlistState next) {
    _state.value = next;
  }

  void _trace(String message) {
    trace?.call(message);
  }
}
