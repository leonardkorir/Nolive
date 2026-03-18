import 'package:live_core/live_core.dart';

abstract interface class ChaturbateDataSource {
  Future<List<LiveCategory>> fetchCategories();

  Future<PagedResponse<LiveRoom>> fetchCategoryRooms(
    LiveSubCategory category, {
    int page = 1,
  });

  Future<PagedResponse<LiveRoom>> fetchRecommendRooms({int page = 1});

  Future<PagedResponse<LiveRoom>> searchRooms(
    String query, {
    int page = 1,
  });

  Future<LiveRoomDetail> fetchRoomDetail(String roomId);

  Future<List<LivePlayQuality>> fetchPlayQualities(LiveRoomDetail detail);

  Future<List<LivePlayUrl>> fetchPlayUrls({
    required LiveRoomDetail detail,
    required LivePlayQuality quality,
  });
}
