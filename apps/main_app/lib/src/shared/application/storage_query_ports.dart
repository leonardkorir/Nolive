import 'package:live_storage/live_storage.dart';
import 'package:live_sync/live_sync.dart';

/// Tear-off friendly ports for pure repository / snapshot reads.
/// Replaces one-line UseCase wrappers (ponytail F04).

typedef ListFollowRecords = Future<List<FollowRecord>> Function();

typedef IsFollowedRoom =
    Future<bool> Function({required String providerId, required String roomId});

typedef ListTags = Future<List<String>> Function();

typedef RemoveHistoryRecord =
    Future<void> Function({required String providerId, required String roomId});

typedef ClearHistory = Future<void> Function();

typedef LoadSyncSnapshot = Future<SyncSnapshot> Function();
