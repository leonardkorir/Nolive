import 'package:live_core/live_core.dart';
import 'package:test/test.dart';

void main() {
  test('core data models compare by value', () {
    expect(
      const LiveCategory(
        id: 'games',
        name: 'Games',
        children: [LiveSubCategory(id: 'fps', parentId: 'games', name: 'FPS')],
      ),
      const LiveCategory(
        id: 'games',
        name: 'Games',
        children: [LiveSubCategory(id: 'fps', parentId: 'games', name: 'FPS')],
      ),
    );
    expect(
      const LiveRoom(
        providerId: ProviderId.douyu,
        roomId: '1000',
        title: 'Title',
        streamerName: 'Streamer',
      ),
      const LiveRoom(
        providerId: ProviderId.douyu,
        roomId: '1000',
        title: 'Title',
        streamerName: 'Streamer',
      ),
    );
    expect(
      LivePlayQuality(id: 'hd', label: 'HD', metadata: {'height': 720}),
      LivePlayQuality(id: 'hd', label: 'HD', metadata: {'height': 720}),
    );
    expect(
      const LivePlayUrl(
        url: 'https://example.test/live.m3u8',
        headers: {'cookie': 'demo'},
        metadata: {
          'lines': ['main', 'backup'],
        },
      ),
      const LivePlayUrl(
        url: 'https://example.test/live.m3u8',
        headers: {'cookie': 'demo'},
        metadata: {
          'lines': ['main', 'backup'],
        },
      ),
    );
    expect(
      LiveRoomDetail(
        providerId: ProviderId.bilibili,
        roomId: '2000',
        title: 'Room',
        streamerName: 'Anchor',
        startedAt: DateTime(2026, 5, 1),
        metadata: const {
          'nested': {'key': 'value'},
        },
      ),
      LiveRoomDetail(
        providerId: ProviderId.bilibili,
        roomId: '2000',
        title: 'Room',
        streamerName: 'Anchor',
        startedAt: DateTime(2026, 5, 1),
        metadata: const {
          'nested': {'key': 'value'},
        },
      ),
    );
    expect(
      const PagedResponse<LiveRoom>(
        items: [
          LiveRoom(
            providerId: ProviderId.douyu,
            roomId: '1000',
            title: 'Title',
            streamerName: 'Streamer',
          ),
        ],
        hasMore: false,
      ),
      const PagedResponse<LiveRoom>(
        items: [
          LiveRoom(
            providerId: ProviderId.douyu,
            roomId: '1000',
            title: 'Title',
            streamerName: 'Streamer',
          ),
        ],
        hasMore: false,
      ),
    );
  });

  test('live message payload is generic and compares deeply', () {
    const message = LiveMessage<Map<String, Object?>>(
      type: LiveMessageType.gift,
      content: 'gift',
      payload: {
        'gift': {'id': 'rose'},
      },
    );

    const sameMessage = LiveMessage<Map<String, Object?>>(
      type: LiveMessageType.gift,
      content: 'gift',
      payload: {
        'gift': {'id': 'rose'},
      },
    );

    expect(message, sameMessage);
    expect(message.payload?['gift'], {'id': 'rose'});
  });

  test('LiveRoomDetail compares an out-of-package token by value', () {
    final first = LiveRoomDetail(
      providerId: ProviderId.douyin,
      roomId: '2000',
      title: 'Room',
      streamerName: 'Anchor',
      danmakuToken: _ExternalDanmakuToken(
        roomId: '2000',
        endpoints: [
          Uri.parse('wss://webcast3-ws-web-lq.douyin.com/webcast/im/push/v2/'),
        ],
      ),
    );
    final second = LiveRoomDetail(
      providerId: ProviderId.douyin,
      roomId: '2000',
      title: 'Room',
      streamerName: 'Anchor',
      danmakuToken: _ExternalDanmakuToken(
        roomId: '2000',
        endpoints: [
          Uri.parse('wss://webcast3-ws-web-lq.douyin.com/webcast/im/push/v2/'),
        ],
      ),
    );

    expect(first, second);
    expect(first.hashCode, second.hashCode);
  });

  test(
    'map payload hashes are stable for equal maps with ambiguous key text',
    () {
      const first = LiveMessage<Object?>(
        type: LiveMessageType.notice,
        content: 'payload',
        payload: <Object?, Object?>{1: 'int-key', '1': 'string-key'},
      );
      const second = LiveMessage<Object?>(
        type: LiveMessageType.notice,
        content: 'payload',
        payload: <Object?, Object?>{'1': 'string-key', 1: 'int-key'},
      );

      expect(first, second);
      expect(first.hashCode, second.hashCode);
    },
  );

  test('LivePlayQuality defensively copies metadata deeply', () {
    final urls = <String>['https://example.test/720.m3u8'];
    final headers = <String, Object?>{'cookie': 'demo'};
    final source = <String, Object?>{
      'height': 720,
      'urls': urls,
      'headers': headers,
    };
    final quality = LivePlayQuality(id: 'hd', label: 'HD', metadata: source);

    source['height'] = 1080;
    urls.add('https://example.test/1080.m3u8');
    headers['cookie'] = 'changed';

    expect(quality.metadata?['height'], 720);
    expect(quality.metadata?['urls'], ['https://example.test/720.m3u8']);
    expect(quality.metadata?['headers'], {'cookie': 'demo'});
    expect(() => quality.metadata!['height'] = 480, throwsUnsupportedError);
    expect(
      () => (quality.metadata!['urls']! as List<Object?>).add('later'),
      throwsUnsupportedError,
    );
    expect(
      () => (quality.metadata!['headers']! as Map<Object?, Object?>)['cookie'] =
          'later',
      throwsUnsupportedError,
    );
  });

  test(
    'core data models sanitize malformed UTF-16 surrogates to well-formed strings',
    () {
      const malformed = 'Hello \uD83D World';
      final expected = malformed.toWellFormed();

      const room = LiveRoom(
        providerId: ProviderId.douyu,
        roomId: '1000',
        title: malformed,
        streamerName: malformed,
        areaName: malformed,
      );
      expect(room.title, expected);
      expect(room.streamerName, expected);
      expect(room.areaName, expected);

      const roomDetail = LiveRoomDetail(
        providerId: ProviderId.douyu,
        roomId: '1000',
        title: malformed,
        streamerName: malformed,
        areaName: malformed,
        description: malformed,
      );
      expect(roomDetail.title, expected);
      expect(roomDetail.streamerName, expected);
      expect(roomDetail.areaName, expected);
      expect(roomDetail.description, expected);

      const message = LiveMessage(
        type: LiveMessageType.chat,
        content: malformed,
        userName: malformed,
      );
      expect(message.content, expected);
      expect(message.userName, expected);
    },
  );
}

/// A [DanmakuToken] declared outside `live_core`, the way every real provider
/// declares its own. Its presence here is the point: the core contract must not
/// need to know the concrete type.
final class _ExternalDanmakuToken extends DanmakuToken {
  const _ExternalDanmakuToken({
    required this.roomId,
    this.endpoints = const [],
  });

  final String roomId;
  final List<Uri> endpoints;

  @override
  List<Object?> get props => [roomId, endpoints];
}
