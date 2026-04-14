import 'package:flutter/foundation.dart';
import 'package:nolive_app/src/features/settings/application/manage_follow_preferences_use_case.dart';
import 'package:nolive_app/src/shared/application/provider_catalog_use_cases.dart';

import 'create_tag_use_case.dart';
import 'list_follow_records_use_case.dart';
import 'list_tags_use_case.dart';
import 'load_follow_watchlist_use_case.dart';
import 'remove_follow_room_use_case.dart';
import 'update_follow_tags_use_case.dart';

class LibraryFeatureDependencies {
  const LibraryFeatureDependencies({
    required this.followDataRevision,
    required this.followWatchlistSnapshot,
    required this.listFollowRecords,
    required this.listTags,
    required this.loadFollowPreferences,
    required this.updateFollowPreferences,
    required this.loadFollowWatchlist,
    required this.removeFollowRoom,
    required this.createTag,
    required this.updateFollowTags,
    required this.findProviderDescriptorById,
  });

  final ValueListenable<int> followDataRevision;
  final ValueNotifier<FollowWatchlist?> followWatchlistSnapshot;
  final ListFollowRecordsUseCase listFollowRecords;
  final ListTagsUseCase listTags;
  final LoadFollowPreferencesUseCase loadFollowPreferences;
  final UpdateFollowPreferencesUseCase updateFollowPreferences;
  final LoadFollowWatchlistUseCase loadFollowWatchlist;
  final RemoveFollowRoomUseCase removeFollowRoom;
  final CreateTagUseCase createTag;
  final UpdateFollowTagsUseCase updateFollowTags;
  final FindProviderDescriptorByIdUseCase findProviderDescriptorById;
}
