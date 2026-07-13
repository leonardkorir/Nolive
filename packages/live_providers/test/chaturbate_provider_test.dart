import 'package:live_core/live_core.dart';
import 'package:live_providers/live_providers.dart';
import 'package:live_providers/src/danmaku/chaturbate_danmaku_session.dart';
import 'package:live_providers/src/providers/chaturbate/chaturbate_api_client.dart';
import 'package:live_providers/src/providers/chaturbate/chaturbate_request_scheduler.dart';
import 'package:test/test.dart';

void main() {
  test(
    'chaturbate provider returns deterministic preview migration slice',
    () async {
      final provider = ChaturbateProvider.preview();

      final categories = await provider.fetchCategories();
      expect(categories, isNotEmpty);
      expect(categories.single.children, isNotEmpty);

      final categoryRooms = await provider.fetchCategoryRooms(
        categories.single.children.first,
      );
      expect(categoryRooms.items, isNotEmpty);

      final rooms = await provider.searchRooms('kitt');
      expect(rooms.items, isNotEmpty);
      expect(rooms.items.first.providerId.value, 'chaturbate');

      final detail = await provider.fetchRoomDetail(rooms.items.first.roomId);
      expect(detail.providerId.value, 'chaturbate');
      expect(detail.sourceUrl, 'https://chaturbate.com/${detail.roomId}/');

      final qualities = await provider.fetchPlayQualities(detail);
      expect(qualities, isNotEmpty);

      final urls = await provider.fetchPlayUrls(
        detail: detail,
        quality: qualities.firstWhere((item) => item.isDefault),
      );
      expect(urls, isNotEmpty);
      expect(urls.first.url, contains('${detail.roomId}-sd-preview'));
    },
  );

  test(
    'chaturbate provider uses a transient danmaku api client for request cookies',
    () async {
      final sharedApiClient = _NoopChaturbateApiClient();
      final provider = ChaturbateProvider(danmakuApiClient: sharedApiClient);
      final detail = LiveRoomDetail(
        providerId: ProviderId.chaturbate,
        roomId: 'realcest',
        title: 'Fixture',
        streamerName: 'fixture',
        danmakuToken: const ChaturbateDanmakuToken(
          roomId: 'realcest',
          roomUid: '',
          broadcasterUid: 'EZ8KVAC',
          csrfToken: 'fixture-csrf',
          backend: 'a',
        ),
        metadata: const {'requestCookie': 'cf_clearance=test'},
      );

      final session =
          await provider.createDanmakuSession(detail)
              as ChaturbateDanmakuSession;

      expect(identical(session.apiClient, sharedApiClient), isFalse);
      await session.disconnect();
    },
  );
}

class _NoopChaturbateApiClient implements ChaturbateApiClient {
  @override
  Future<Map<String, dynamic>> authenticatePushService({
    required String roomId,
    required String csrfToken,
    required String backend,
    required String presenceId,
    required Map<String, dynamic> topics,
  }) async {
    throw UnimplementedError();
  }

  @override
  void close() {}

  @override
  Future<Map<String, dynamic>> fetchDiscoverCarousel(
    String carouselId, {
    String genders = '',
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<String> fetchHlsPlaylist(
    String url, {
    String? referer,
    String? cookie,
    ChaturbateRequestPriority priority = ChaturbateRequestPriority.normal,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<List<Map<String, dynamic>>> fetchRoomHistory({
    required String roomId,
    required String csrfToken,
    required Map<String, dynamic> topics,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<Map<String, dynamic>> fetchRoomContext(
    String roomId, {
    String? cookie,
    ChaturbateRequestPriority priority = ChaturbateRequestPriority.normal,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<Map<String, dynamic>> fetchRoomList({
    required String query,
    String? genders,
    int limit = ChaturbateApiClient.searchPageSize,
    int offset = 0,
    bool requireFingerprint = true,
    String? cookie,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<String> fetchRoomPage(
    String roomId, {
    String? cookie,
    ChaturbateRequestPriority priority = ChaturbateRequestPriority.normal,
  }) async {
    throw UnimplementedError();
  }
}
