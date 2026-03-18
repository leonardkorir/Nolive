import 'dart:async';

import 'package:live_core/live_core.dart';
import 'package:live_providers/src/danmaku/chaturbate_danmaku_session.dart';
import 'package:live_providers/src/providers/chaturbate/chaturbate_api_client.dart';
import 'package:test/test.dart';

import 'support/chaturbate_fixture_loader.dart';

void main() {
  group(
    'fixture-backed chaturbate danmaku coverage',
    skip: ChaturbateFixtureLoader.skipReason,
    () {
      test('chaturbate danmaku session replays history and websocket fixtures',
          () async {
        final socket = _FixtureSocketClient(
          incomingFrames: const [
            '{"action":4}',
          ],
        );
        final session = ChaturbateDanmakuSession(
          roomId: 'realcest',
          broadcasterUid: 'EZ8KVAC',
          csrfToken: 'fixture-csrf',
          backend: 'a',
          apiClient: _FixtureDanmakuApiClient(
            authResponse: ChaturbateFixtureLoader.loadPushAuthResponse(),
            history: ChaturbateFixtureLoader.loadRoomHistory(),
          ),
          socketClientFactory: (_) => socket,
          presenceId: '+fixture',
        );

        final collected = <LiveMessage>[];
        final subscription = session.messages.listen(collected.add);

        await session.connect();
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(
          collected.any(
            (item) =>
                item.type == LiveMessageType.chat &&
                item.userName == 'nicolasmonzon',
          ),
          isTrue,
        );
        expect(
          collected.any((item) => item.type == LiveMessageType.gift),
          isTrue,
        );
        await subscription.cancel();
        await session.disconnect();
      });
    },
  );
}

class _FixtureDanmakuApiClient implements ChaturbateApiClient {
  _FixtureDanmakuApiClient({
    required this.authResponse,
    required this.history,
  });

  final Map<String, dynamic> authResponse;
  final List<Map<String, dynamic>> history;

  @override
  Future<Map<String, dynamic>> authenticatePushService({
    required String roomId,
    required String csrfToken,
    required String backend,
    required String presenceId,
    required Map<String, dynamic> topics,
  }) async {
    expect(roomId, 'realcest');
    expect(csrfToken, 'fixture-csrf');
    expect(backend, 'a');
    expect(presenceId, '+fixture');
    expect(topics, contains('RoomMessageTopic#RoomMessageTopic:EZ8KVAC'));
    return authResponse;
  }

  @override
  Future<List<Map<String, dynamic>>> fetchRoomHistory({
    required String roomId,
    required String csrfToken,
    required Map<String, dynamic> topics,
  }) async {
    expect(roomId, 'realcest');
    expect(csrfToken, 'fixture-csrf');
    expect(topics, contains('RoomMessageTopic#RoomMessageTopic:EZ8KVAC'));
    return history;
  }

  @override
  Future<Map<String, dynamic>> fetchDiscoverCarousel(
    String carouselId, {
    String genders = '',
  }) async {
    fail('Unexpected fetchDiscoverCarousel call: $carouselId genders=$genders');
  }

  @override
  Future<Map<String, dynamic>> fetchRoomList({
    required String query,
    String? genders,
    int limit = ChaturbateApiClient.searchPageSize,
    int offset = 0,
  }) async {
    fail(
      'Unexpected fetchRoomList call: query=$query genders=${genders ?? ''} offset=$offset',
    );
  }

  @override
  Future<String> fetchRoomPage(String roomId) async {
    fail('Unexpected fetchRoomPage call: $roomId');
  }

  @override
  Future<String> fetchHlsPlaylist(
    String url, {
    String? referer,
  }) async {
    fail('Unexpected fetchHlsPlaylist call: $url referer=${referer ?? ''}');
  }
}

class _FixtureSocketClient implements ChaturbateSocketClient {
  _FixtureSocketClient({required this.incomingFrames}) {
    scheduleMicrotask(() async {
      for (final frame in incomingFrames) {
        if (_controller.isClosed) {
          return;
        }
        _controller.add(frame);
      }
    });
  }

  final List<String> incomingFrames;
  final StreamController<dynamic> _controller =
      StreamController<dynamic>.broadcast();

  @override
  Stream<dynamic> get stream => _controller.stream;

  @override
  void add(dynamic data) {}

  @override
  Future<void> close() async {
    if (!_controller.isClosed) {
      await _controller.close();
    }
  }
}
