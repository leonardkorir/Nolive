import 'package:flutter/foundation.dart';
import 'package:nolive_app/src/shared/domain/follow_watch_entry.dart';
import 'package:nolive_app/src/shared/presentation/progressive_ui_coalescer.dart';

/// Generation-aware progressive UI binder for the follow list.
///
/// Ensures a superseded refresh never paints or writes snapshot after a newer
/// generation has started (including delayed coalescer flushes).
class FollowProgressiveUiController {
  FollowProgressiveUiController({
    required this.isMounted,
    required this.currentGeneration,
    required this.writeSnapshot,
    required this.applyWatchlistToPage,
    Duration coalesceInterval = const Duration(milliseconds: 120),
  }) {
    _coalescer = ProgressiveUiCoalescer(
      interval: coalesceInterval,
      onFlush: _flushPending,
    );
  }

  final bool Function() isMounted;
  final int Function() currentGeneration;
  final void Function(FollowWatchlist watchlist) writeSnapshot;
  final void Function(FollowWatchlist watchlist) applyWatchlistToPage;

  late final ProgressiveUiCoalescer _coalescer;
  FollowWatchlist? _pending;
  int? _pendingGeneration;

  @visibleForTesting
  bool get hasPendingFlush => _coalescer.hasPendingFlush;

  @visibleForTesting
  int? get pendingGeneration => _pendingGeneration;

  /// Call when a new refresh generation begins (after incrementing generation).
  void beginGeneration(int generation) {
    _coalescer.cancel();
    _pending = null;
    _pendingGeneration = generation;
  }

  /// Progressive entry resolve: snapshot always if current; page paint coalesced.
  void onEntryResolved(int generation, FollowWatchlist watchlist) {
    if (!_isCurrent(generation)) {
      return;
    }
    writeSnapshot(watchlist);
    _pending = watchlist;
    _pendingGeneration = generation;
    _coalescer.schedule();
  }

  /// Terminal watchlist for this generation: only if still current.
  void commitFinal(int generation, FollowWatchlist watchlist) {
    if (!_isCurrent(generation)) {
      return;
    }
    writeSnapshot(watchlist);
    _pending = watchlist;
    _pendingGeneration = generation;
    _coalescer.flushNow();
  }

  void dispose() {
    _coalescer.dispose();
    _pending = null;
    _pendingGeneration = null;
  }

  bool _isCurrent(int generation) {
    return isMounted() && generation == currentGeneration();
  }

  void _flushPending() {
    final pending = _pending;
    final generation = _pendingGeneration;
    if (pending == null ||
        generation == null ||
        !_isCurrent(generation)) {
      return;
    }
    applyWatchlistToPage(pending);
  }
}
