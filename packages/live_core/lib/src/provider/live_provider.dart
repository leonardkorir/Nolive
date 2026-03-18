import '../error/nolive_exception.dart';
import '../model/live_category.dart';
import '../model/live_message.dart';
import '../model/live_play_quality.dart';
import '../model/live_play_url.dart';
import '../model/live_room.dart';
import '../model/live_room_detail.dart';
import '../model/paged_response.dart';
import 'provider_capability.dart';
import 'provider_descriptor.dart';

abstract class LiveProvider {
  ProviderDescriptor get descriptor;

  bool supports(ProviderCapability capability) {
    return descriptor.supports(capability);
  }

  void requireCapability(ProviderCapability capability) {
    if (!supports(capability)) {
      throw ProviderCapabilityException.unsupported(
        providerId: descriptor.id,
        capability: capability,
      );
    }
  }

  T requireContract<T>(ProviderCapability capability) {
    requireCapability(capability);
    if (this is! T) {
      throw ProviderContractException.misaligned(
        providerId: descriptor.id,
        capability: capability,
        expectedContract: '$T',
      );
    }
    return this as T;
  }
}

abstract class SupportsCategories {
  Future<List<LiveCategory>> fetchCategories();
}

abstract class SupportsCategoryRooms {
  Future<PagedResponse<LiveRoom>> fetchCategoryRooms(
    LiveSubCategory category, {
    int page = 1,
  });
}

abstract class SupportsRecommendRooms {
  Future<PagedResponse<LiveRoom>> fetchRecommendRooms({int page = 1});
}

abstract class SupportsRoomSearch {
  Future<PagedResponse<LiveRoom>> searchRooms(
    String query, {
    int page = 1,
  });
}

abstract class SupportsAnchorSearch {
  Future<PagedResponse<LiveRoom>> searchAnchors(
    String query, {
    int page = 1,
  });
}

abstract class SupportsRoomDetail {
  Future<LiveRoomDetail> fetchRoomDetail(String roomId);
}

abstract class SupportsPlayQualities {
  Future<List<LivePlayQuality>> fetchPlayQualities(LiveRoomDetail detail);
}

abstract class SupportsPlayUrls {
  Future<List<LivePlayUrl>> fetchPlayUrls({
    required LiveRoomDetail detail,
    required LivePlayQuality quality,
  });
}

abstract class DanmakuSession {
  Stream<LiveMessage> get messages;

  Future<void> connect();

  Future<void> disconnect();
}

abstract class SupportsDanmaku {
  Future<DanmakuSession> createDanmakuSession(LiveRoomDetail detail);
}
