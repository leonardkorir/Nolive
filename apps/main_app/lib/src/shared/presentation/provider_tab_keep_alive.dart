import 'package:flutter/foundation.dart';

/// Bounded LRU cache for provider-tab keep-alive (home / browse).
///
/// Keeps the current tab plus recently visited ones so back-and-forth
/// switching does not immediately dispose and re-fetch. Oldest tabs fall
/// out only after [capacity] distinct tabs have been visited.
class ProviderTabKeepAliveStore {
  ProviderTabKeepAliveStore({this.capacity = 5});

  /// Max tabs retained in memory (including the selected one).
  final int capacity;

  final List<int> _recent = <int>[];
  final List<VoidCallback> _listeners = <VoidCallback>[];

  /// Most-recent-first tab indices currently pinned for keep-alive.
  @visibleForTesting
  List<int> get recentTabIndices => List<int>.unmodifiable(_recent);

  void addListener(VoidCallback listener) {
    _listeners.add(listener);
  }

  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }

  void _notify() {
    for (final listener in List<VoidCallback>.from(_listeners)) {
      listener();
    }
  }

  /// Record that [tabIndex] is now selected / visited.
  void select(int tabIndex) {
    if (tabIndex < 0) {
      return;
    }
    _recent.remove(tabIndex);
    _recent.insert(0, tabIndex);
    while (_recent.length > capacity) {
      _recent.removeLast();
    }
    _notify();
  }

  /// Whether [tabIndex] should keep its [AutomaticKeepAliveClientMixin] state.
  bool shouldKeep(int tabIndex) {
    // Before any selection is recorded, keep all (first frame safety).
    if (_recent.isEmpty) {
      return true;
    }
    return _recent.contains(tabIndex);
  }

  void dispose() {
    _listeners.clear();
    _recent.clear();
  }
}

/// Pure helper for tests — membership in an already-capped recent list.
@visibleForTesting
bool shouldKeepProviderTabAlive({
  required int tabIndex,
  required int selectedIndex,
  List<int> recentTabIndices = const <int>[],
  int capacity = 5,
}) {
  if (tabIndex == selectedIndex) {
    return true;
  }
  if (recentTabIndices.isEmpty) {
    return true;
  }
  final capped = recentTabIndices.take(capacity);
  return capped.contains(tabIndex);
}

/// Shared stores so sibling tab States pin the same LRU set.
final ProviderTabKeepAliveStore homeProviderTabKeepAlive =
    ProviderTabKeepAliveStore(capacity: 5);
final ProviderTabKeepAliveStore browseProviderTabKeepAlive =
    ProviderTabKeepAliveStore(capacity: 5);
