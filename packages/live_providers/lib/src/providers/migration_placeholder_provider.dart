import 'package:live_core/live_core.dart';

class MigrationPlaceholderProvider extends LiveProvider
    implements
        SupportsCategories,
        SupportsRoomSearch,
        SupportsAnchorSearch,
        SupportsRoomDetail,
        SupportsPlayQualities,
        SupportsPlayUrls,
        SupportsDanmaku {
  MigrationPlaceholderProvider({required this.providerDescriptor});

  final ProviderDescriptor providerDescriptor;

  @override
  ProviderDescriptor get descriptor => providerDescriptor;

  @override
  Future<List<LiveCategory>> fetchCategories() {
    throw ProviderNotImplementedException.migration(
      providerId: descriptor.id,
      feature: 'fetchCategories',
    );
  }

  @override
  Future<PagedResponse<LiveRoom>> searchRooms(String query, {int page = 1}) {
    throw ProviderNotImplementedException.migration(
      providerId: descriptor.id,
      feature: 'searchRooms',
    );
  }

  @override
  Future<PagedResponse<LiveRoom>> searchAnchors(String query, {int page = 1}) {
    throw ProviderNotImplementedException.migration(
      providerId: descriptor.id,
      feature: 'searchAnchors',
    );
  }

  @override
  Future<LiveRoomDetail> fetchRoomDetail(String roomId) {
    throw ProviderNotImplementedException.migration(
      providerId: descriptor.id,
      feature: 'fetchRoomDetail',
    );
  }

  @override
  Future<List<LivePlayQuality>> fetchPlayQualities(LiveRoomDetail detail) {
    throw ProviderNotImplementedException.migration(
      providerId: descriptor.id,
      feature: 'fetchPlayQualities',
    );
  }

  @override
  Future<List<LivePlayUrl>> fetchPlayUrls({
    required LiveRoomDetail detail,
    required LivePlayQuality quality,
  }) {
    throw ProviderNotImplementedException.migration(
      providerId: descriptor.id,
      feature: 'fetchPlayUrls',
    );
  }

  @override
  Future<DanmakuSession> createDanmakuSession(LiveRoomDetail detail) {
    throw ProviderNotImplementedException.migration(
      providerId: descriptor.id,
      feature: 'createDanmakuSession',
    );
  }
}
