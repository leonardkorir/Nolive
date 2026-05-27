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

  test(
      'chaturbate danmaku session retries backup websocket host on ready error',
      () async {
    final attemptedHosts = <String>[];
    final session = ChaturbateDanmakuSession(
      roomId: 'realcest',
      broadcasterUid: 'EZ8KVAC',
      csrfToken: 'fixture-csrf',
      backend: 'a',
      apiClient: _FixtureDanmakuApiClient(
        authResponse: {
          'token': 'fixture-token',
          'channels': {
            'RoomMessageTopic#RoomMessageTopic:EZ8KVAC': 'room:message',
          },
          'settings': {
            'host': 'realtime-primary.example',
            'rest_host': 'realtime-backup.example',
          },
        },
        history: const [],
      ),
      socketClientFactory: (uri) {
        attemptedHosts.add(uri.host);
        return _FixtureSocketClient(
          incomingFrames: uri.host == 'realtime-backup.example'
              ? const ['{"action":4}']
              : const [],
          ready: uri.host == 'realtime-backup.example'
              ? Future<void>.value()
              : Future<void>.error('primary down'),
        );
      },
      presenceId: '+fixture',
    );

    final collected = <LiveMessage>[];
    final subscription = session.messages.listen(collected.add);

    await session.connect();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(
      attemptedHosts,
      ['realtime-primary.example', 'realtime-backup.example'],
    );
    expect(
      collected.any(
        (item) =>
            item.type == LiveMessageType.notice &&
            item.content.contains('实时弹幕已连接'),
      ),
      isTrue,
    );

    await subscription.cancel();
    await session.disconnect();
  });

  test(
      'chaturbate danmaku session keeps realtime connection when room history returns 403',
      () async {
    final socket = _FixtureSocketClient(
      incomingFrames: const ['{"action":4}'],
    );
    final session = ChaturbateDanmakuSession(
      roomId: 'realcest',
      broadcasterUid: 'EZ8KVAC',
      csrfToken: 'fixture-csrf',
      backend: 'a',
      apiClient: _FixtureDanmakuApiClient(
        authResponse: {
          'token': 'fixture-token',
          'channels': {
            'RoomMessageTopic#RoomMessageTopic:EZ8KVAC': 'room:message',
          },
          'settings': {
            'host': 'realtime-primary.example',
          },
        },
        history: const [],
        historyError: ChaturbateRoomHistoryUnavailableException(
          statusCode: 403,
        ),
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
            item.type == LiveMessageType.notice &&
            item.content.contains('仅实时弹幕'),
      ),
      isTrue,
    );
    expect(
      collected.any(
        (item) =>
            item.type == LiveMessageType.notice &&
            item.content.contains('实时弹幕已连接'),
      ),
      isTrue,
    );

    await subscription.cancel();
    await session.disconnect();
  });

  test('chaturbate danmaku session evicts old dedupe ids', () async {
    final session = ChaturbateDanmakuSession(
      roomId: 'realcest',
      broadcasterUid: 'EZ8KVAC',
      csrfToken: 'fixture-csrf',
      backend: 'a',
      apiClient: _FixtureDanmakuApiClient(
        authResponse: const {},
        history: const [],
      ),
      presenceId: '+fixture',
    );

    final collected = <LiveMessage>[];
    final subscription = session.messages.listen(collected.add);
    addTearDown(subscription.cancel);
    addTearDown(session.disconnect);

    for (var index = 0; index < 2050; index += 1) {
      session.debugIngestPayload({
        'RoomMessageTopic#RoomMessageTopic:EZ8KVAC': {
          'id': 'message-$index',
          'message': 'hello $index',
          'from_user': const {'username': 'tester'},
        },
      });
    }
    await Future<void>.delayed(Duration.zero);
    final beforeRepeat = collected.length;
    session.debugIngestPayload({
      'RoomMessageTopic#RoomMessageTopic:EZ8KVAC': {
        'id': 'message-0',
        'message': 'hello again',
        'from_user': const {'username': 'tester'},
      },
    });
    await Future<void>.delayed(Duration.zero);

    expect(session.debugSeenMessageCount, lessThanOrEqualTo(2048));
    expect(collected.length, beforeRepeat + 1);
  });

  test(
      'chaturbate danmaku session clears state on WebSocket error and allows reconnect',
      () async {
    final errorController = StreamController<dynamic>();
    var connectCallCount = 0;
    late _ErrorSocketClient firstSocket;
    final session = ChaturbateDanmakuSession(
      roomId: 'realcest',
      broadcasterUid: 'EZ8KVAC',
      csrfToken: 'fixture-csrf',
      backend: 'a',
      apiClient: _FixtureDanmakuApiClient(
        authResponse: {
          'token': 'fixture-token',
          'channels': {
            'RoomMessageTopic#RoomMessageTopic:EZ8KVAC': 'room:message',
          },
          'settings': {'host': 'realtime-primary.example'},
        },
        history: const [],
      ),
      socketClientFactory: (_) {
        connectCallCount++;
        if (connectCallCount == 1) {
          firstSocket = _ErrorSocketClient(errorController);
          return firstSocket;
        }
        return _FixtureSocketClient(incomingFrames: const ['{"action":4}']);
      },
      presenceId: '+fixture',
    );

    final notices = <String>[];
    session.messages.listen((msg) {
      if (msg.type == LiveMessageType.notice) notices.add(msg.content);
    });

    await session.connect();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(connectCallCount, 1);

    // Simulate WebSocket error — zombie fix clears _connected
    errorController.addError(StateError('unexpected disconnect'));
    await Future<void>.delayed(Duration.zero);
    expect(firstSocket.closed, isTrue);

    // Should allow reconnect (not blocked by _connected == true)
    await session.connect();
    expect(connectCallCount, 2);
    expect(notices.any((n) => n.contains('Chaturbate 弹幕连接异常')), isTrue);

    await session.disconnect();
    await errorController.close();
  });

  test('chaturbate danmaku session closes owned api client on disconnect',
      () async {
    final apiClient = _ClosableDanmakuApiClient(
      authResponse: const {},
      history: const [],
    );
    final session = ChaturbateDanmakuSession(
      roomId: 'realcest',
      broadcasterUid: 'EZ8KVAC',
      csrfToken: 'fixture-csrf',
      backend: 'a',
      apiClient: apiClient,
      disposeOwnedApiClient: apiClient.close,
      presenceId: '+fixture',
    );

    await session.disconnect();

    expect(apiClient.closeCount, 1);
  });

  test(
      'chaturbate danmaku session closes owned api client after connect failure',
      () async {
    final apiClient = _ClosableDanmakuApiClient(
      authResponse: const {},
      history: const [],
      authError: StateError('auth failed'),
    );
    final session = ChaturbateDanmakuSession(
      roomId: 'realcest',
      broadcasterUid: 'EZ8KVAC',
      csrfToken: 'fixture-csrf',
      backend: 'a',
      apiClient: apiClient,
      disposeOwnedApiClient: apiClient.close,
      presenceId: '+fixture',
    );

    await expectLater(session.connect, throwsStateError);
    expect(apiClient.closeCount, 1);
  });
}

class _FixtureDanmakuApiClient implements ChaturbateApiClient {
  _FixtureDanmakuApiClient({
    required this.authResponse,
    required this.history,
    this.authError,
    this.historyError,
  });

  final Map<String, dynamic> authResponse;
  final List<Map<String, dynamic>> history;
  final Object? authError;
  final Object? historyError;

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
    if (authError != null) {
      throw authError!;
    }
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
    if (historyError != null) {
      throw historyError!;
    }
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
  Future<Map<String, dynamic>> fetchRoomContext(
    String roomId, {
    String? cookie,
  }) async {
    fail('Unexpected fetchRoomContext call: $roomId cookie=${cookie ?? ''}');
  }

  @override
  Future<String> fetchHlsPlaylist(
    String url, {
    String? referer,
    String? cookie,
  }) async {
    fail(
      'Unexpected fetchHlsPlaylist call: '
      'url=$url referer=${referer ?? ''} cookie=${cookie ?? ''}',
    );
  }

  @override
  void close() {}
}

class _ClosableDanmakuApiClient extends _FixtureDanmakuApiClient {
  _ClosableDanmakuApiClient({
    required super.authResponse,
    required super.history,
    super.authError,
  });

  int closeCount = 0;

  @override
  void close() {
    closeCount += 1;
  }
}

class _FixtureSocketClient implements ChaturbateSocketClient {
  _FixtureSocketClient({
    required this.incomingFrames,
    Future<void>? ready,
  }) : _ready = ready ?? Future<void>.value() {
    unawaited(_dispatchIncomingFrames());
  }

  final List<String> incomingFrames;
  final Future<void> _ready;
  final StreamController<dynamic> _controller =
      StreamController<dynamic>.broadcast();

  Future<void> _dispatchIncomingFrames() async {
    try {
      await _ready;
      await Future<void>.delayed(Duration.zero);
      for (final frame in incomingFrames) {
        if (_controller.isClosed) {
          return;
        }
        _controller.add(frame);
      }
    } catch (_) {
      // Connection readiness failed before the fixture stream became active.
    }
  }

  @override
  Stream<dynamic> get stream => _controller.stream;

  @override
  Future<void> get ready => _ready;

  @override
  void add(dynamic data) {}

  @override
  Future<void> close() async {
    if (!_controller.isClosed) {
      await _controller.close();
    }
  }
}

class _ErrorSocketClient implements ChaturbateSocketClient {
  _ErrorSocketClient(this._controller);
  final StreamController<dynamic> _controller;
  bool closed = false;

  @override
  Stream<dynamic> get stream => _controller.stream;

  @override
  Future<void> get ready => Future<void>.value();

  @override
  void add(dynamic data) {}

  @override
  Future<void> close() async {
    closed = true;
    if (!_controller.isClosed) {
      await _controller.close();
    }
  }
}
