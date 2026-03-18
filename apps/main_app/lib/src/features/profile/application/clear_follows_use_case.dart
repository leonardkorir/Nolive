import 'package:flutter/foundation.dart';
import 'package:live_storage/live_storage.dart';
import 'package:nolive_app/src/features/library/application/load_follow_watchlist_use_case.dart';

class ClearFollowsUseCase {
  const ClearFollowsUseCase(
    this.followRepository, {
    this.followWatchlistSnapshot,
    this.followDataRevision,
  });

  final FollowRepository followRepository;
  final ValueNotifier<FollowWatchlist?>? followWatchlistSnapshot;
  final ValueNotifier<int>? followDataRevision;

  Future<void> call() async {
    await followRepository.clear();
    followWatchlistSnapshot?.value = const FollowWatchlist(entries: []);
    if (followDataRevision != null) {
      followDataRevision!.value += 1;
    }
  }
}
