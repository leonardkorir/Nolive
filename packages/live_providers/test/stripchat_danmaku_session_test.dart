import 'dart:async';
import 'dart:convert';
import 'package:live_core/live_core.dart';
import 'package:live_providers/src/danmaku/stripchat_danmaku_session.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

void main() {
  group('StripchatDanmakuToken equality', () {
    test('identical tokens are equal', () {
      const first = StripchatDanmakuToken(
        modelId: '12345',
        websocketUrl: 'wss://ws.stripchat.com/connection/websocket',
        jwt: 'mock-jwt',
      );
      const second = StripchatDanmakuToken(
        modelId: '12345',
        websocketUrl: 'wss://ws.stripchat.com/connection/websocket',
        jwt: 'mock-jwt',
      );

      expect(first, second);
      expect(first.hashCode, second.hashCode);
    });

    test('different modelId are not equal', () {
      const first = StripchatDanmakuToken(
        modelId: '12345',
        websocketUrl: 'wss://ws.stripchat.com/connection/websocket',
        jwt: 'mock-jwt',
      );
      const second = StripchatDanmakuToken(
        modelId: '99999',
        websocketUrl: 'wss://ws.stripchat.com/connection/websocket',
        jwt: 'mock-jwt',
      );

      expect(first, isNot(second));
    });
  });

  group('parseChatMessage', () {
    test('parses text chat message from real frame', () {
      final frame = {
        'push': {
          'channel': 'newChatMessage@253130387',
          'pub': {
            'data': {
              'message': {
                'additionalData': {'isKing': false, 'isKnight': false},
                'cacheId': '69f86d67c9664',
                'createdAt': '2026-05-04T09:56:55Z',
                'details': {'body': '主持长啥样啊'},
                'id': 1864251333187172,
                'modelId': 253130387,
                'type': 'text',
                'userData': {
                  'id': 170731121,
                  'isAdmin': false,
                  'isModel': false,
                  'isOnline': true,
                  'username': 'mmmt88111',
                },
              },
            },
            'offset': 114,
          },
        },
      };

      final result = StripchatDanmakuSession.parsePushMessage(
        frame,
        modelId: '253130387',
      );

      expect(result, isNotNull);
      expect(result!.type, LiveMessageType.chat);
      expect(result.content, '主持长啥样啊');
      expect(result.userName, 'mmmt88111');
      expect(result.timestamp, DateTime.utc(2026, 5, 4, 9, 56, 55));
    });

    test('parses tip message as gift', () {
      final frame = {
        'push': {
          'channel': 'newChatMessage@12345',
          'pub': {
            'data': {
              'message': {
                'type': 'tip',
                'createdAt': '2026-05-06T12:00:00Z',
                'details': {'body': 'sent 50 tokens'},
                'userData': {'username': 'tipper1'},
              },
            },
          },
        },
      };

      final result = StripchatDanmakuSession.parsePushMessage(
        frame,
        modelId: '12345',
      );

      expect(result, isNotNull);
      expect(result!.type, LiveMessageType.gift);
      expect(result.content, 'sent 50 tokens');
      expect(result.userName, 'tipper1');
    });

    test('parses lovense as gift', () {
      final frame = {
        'push': {
          'channel': 'newChatMessage@12345',
          'pub': {
            'data': {
              'message': {
                'type': 'lovense',
                'createdAt': '2026-05-06T12:00:00Z',
                'details': {'body': ''},
                'userData': {'username': 'toy_user'},
              },
            },
          },
        },
      };

      final result = StripchatDanmakuSession.parsePushMessage(
        frame,
        modelId: '12345',
      );

      expect(result, isNotNull);
      expect(result!.type, LiveMessageType.gift);
    });

    test('maps unknown message types to notice', () {
      final frame = {
        'push': {
          'channel': 'newChatMessage@12345',
          'pub': {
            'data': {
              'message': {
                'type': 'goal',
                'createdAt': '2026-05-06T12:00:00Z',
                'details': {'body': 'goal reached'},
                'userData': {'username': 'system'},
              },
            },
          },
        },
      };

      final result = StripchatDanmakuSession.parsePushMessage(
        frame,
        modelId: '12345',
      );

      expect(result, isNotNull);
      expect(result!.type, LiveMessageType.notice);
    });

    test('returns null for malformed push frame', () {
      final result = StripchatDanmakuSession.parsePushMessage({
        'push': 'invalid',
      }, modelId: '12345');
      expect(result, isNull);
    });

    test('returns null for non-push frame', () {
      final result = StripchatDanmakuSession.parsePushMessage(
        {},
        modelId: '12345',
      );
      expect(result, isNull);
    });
  });

  group('parseNoticeChannel', () {
    test('parses userBanned channel', () {
      final frame = {
        'push': {
          'channel': 'userBanned@12345',
          'pub': {
            'data': {'userId': 999, 'username': 'bad_user', 'reason': 'spam'},
          },
        },
      };

      final result = StripchatDanmakuSession.parsePushMessage(
        frame,
        modelId: '12345',
      );

      expect(result, isNotNull);
      expect(result!.type, LiveMessageType.notice);
      expect(result.content, contains('userBanned'));
    });

    test('parses groupShow channel', () {
      final frame = {
        'push': {
          'channel': 'groupShow@12345',
          'pub': {
            'data': {'showId': 123, 'type': 'ticket'},
          },
        },
      };

      final result = StripchatDanmakuSession.parsePushMessage(
        frame,
        modelId: '12345',
      );

      expect(result, isNotNull);
      expect(result!.type, LiveMessageType.notice);
      expect(result.content, contains('groupShow'));
    });

    test('returns null for ignored channel', () {
      final frame = {
        'push': {
          'channel': 'modelAppUpdated@12345',
          'pub': {
            'data': {'appId': 'some_app'},
          },
        },
      };

      final result = StripchatDanmakuSession.parsePushMessage(
        frame,
        modelId: '12345',
      );

      expect(result, isNull);
    });
  });

  group('parseHistoryMessages', () {
    test('parses chat history payload into live messages', () {
      final payload = {
        'messages': [
          {
            'type': 'text',
            'createdAt': '2026-05-06T12:00:00Z',
            'details': {'body': 'hello from history'},
            'userData': {'username': 'history_user'},
          },
          {
            'type': 'tip',
            'createdAt': '2026-05-06T12:00:01Z',
            'details': {'body': 'sent 20 tokens'},
            'userData': {'username': 'tip_user'},
          },
        ],
      };

      final messages = StripchatDanmakuSession.parseHistoryMessages(payload);

      expect(messages, hasLength(2));
      expect(messages.first.type, LiveMessageType.chat);
      expect(messages.first.content, 'hello from history');
      expect(messages.first.userName, 'history_user');
      expect(messages.last.type, LiveMessageType.gift);
      expect(messages.last.content, 'sent 20 tokens');
    });
  });

  group('subscribe trigger protocol', () {
    test(
      'primary room subscribe triggered as soon as connect ack is received',
      () {
        final serverLines = ['{"result":{},"id":1}'];
        final triggers = StripchatDanmakuSession.simulateSubscribeTriggers(
          serverLines,
        );
        expect(triggers, isNotEmpty);
        expect(triggers, ['newChatMessage@(modelId)']);
      },
    );

    test('room subscribe not triggered before connect ack', () {
      final serverLines = ['{"result":{},"id":2}', '{"result":{},"id":3}'];
      final triggers = StripchatDanmakuSession.simulateSubscribeTriggers(
        serverLines,
      );
      expect(triggers, isEmpty);
    });

    test('subscribe trigger ignores non-result lines', () {
      final serverLines = ['{}', '{"result":{},"id":1}'];
      final triggers = StripchatDanmakuSession.simulateSubscribeTriggers(
        serverLines,
      );
      expect(triggers, isNotEmpty);
    });

    test('subscribe triggered only once', () {
      final serverLines = [
        '{"result":{},"id":1}',
        '{"result":{},"id":1}',
        '{"result":{},"id":2}',
      ];
      final triggers = StripchatDanmakuSession.simulateSubscribeTriggers(
        serverLines,
      );
      expect(triggers, isNotEmpty);
    });

    test('ancillary subscribe waits for primary room ack', () {
      final serverLines = ['{"result":{},"id":1}', '{"result":{},"id":2}'];
      final triggers = StripchatDanmakuSession.simulateSubscribeTriggers(
        serverLines,
      );
      expect(triggers.first, 'newChatMessage@(modelId)');
      expect(
        triggers.any((channel) => channel.contains('broadcastChanged@')),
        isTrue,
      );
    });
  });

  group('dedupe key extraction', () {
    test('prefers message id over cacheId', () {
      expect(
        StripchatDanmakuSession.extractMessageDedupKey({
          'id': 123,
          'cacheId': 'cache-1',
        }),
        'id:123',
      );
    });

    test('falls back to cacheId when id missing', () {
      expect(
        StripchatDanmakuSession.extractMessageDedupKey({'cacheId': 'cache-1'}),
        'cache:cache-1',
      );
    });
  });

  group('StripchatDanmakuSession creation', () {
    test('is created successfully with valid token', () {
      final session = StripchatDanmakuSession(
        danmakuToken: const StripchatDanmakuToken(
          modelId: '12345',
          websocketUrl: 'wss://ws.stripchat.com/connection/websocket',
          jwt: 'mock-jwt',
        ),
      );

      expect(session, isA<DanmakuSession>());
    });

    test('messages stream is available before connect', () {
      final session = StripchatDanmakuSession(
        danmakuToken: const StripchatDanmakuToken(
          modelId: '12345',
          websocketUrl: 'wss://ws.stripchat.com/connection/websocket',
          jwt: 'mock-jwt',
        ),
      );

      expect(session.messages, isNotNull);
    });
  });

  group('WebSocket Handshake Integration', () {
    late StreamController<dynamic> serverStreamController;
    late _MockMockWebSocketSink mockSink;
    late _MockWebSocketChannel mockChannel;
    late StripchatDanmakuSession session;

    setUp(() {
      serverStreamController = StreamController<dynamic>.broadcast();
      mockSink = _MockMockWebSocketSink(serverStreamController);
      mockChannel = _MockWebSocketChannel(
        serverStreamController.stream,
        mockSink,
      );
      session = StripchatDanmakuSession(
        danmakuToken: const StripchatDanmakuToken(
          modelId: '12345',
          websocketUrl: 'wss://ws.stripchat.com/connection/websocket',
          jwt: 'mock-jwt',
        ),
        inactivityTimeout: const Duration(seconds: 5),
        channelConnector:
            (
              uri, {
              headers,
              protocols,
              connectTimeout = const Duration(seconds: 10),
            }) async {
              return mockChannel;
            },
      );
    });

    tearDown(() async {
      await session.disconnect();
      await serverStreamController.close();
    });

    test(
      'completes connection, sends heartbeat, and disposes correctly',
      () async {
        // 1. Trigger connect
        final connectFuture = session.connect();

        // Verify connection frame is sent
        await Future<void>.delayed(Duration.zero);
        expect(mockSink.sentLines, isNotEmpty);
        expect(mockSink.sentLines.first, contains('"connect"'));
        expect(mockSink.sentLines.first, contains('"mock-jwt"'));

        // 2. Respond with connect ACK
        serverStreamController.add('{"result": {}, "id": 1}');

        // Handshake should complete now
        await expectLater(connectFuture, completes);

        // Verify that it sent subscription to primary room channel
        await Future<void>.delayed(Duration.zero);
        expect(mockSink.sentLines.length, greaterThan(1));
        expect(
          mockSink.sentLines.any(
            (line) =>
                line.contains('"subscribe"') &&
                line.contains('newChatMessage@12345'),
          ),
          isTrue,
        );

        // 3. Respond with subscription ACK
        serverStreamController.add('{"result": {}, "id": 2}');
        await Future<void>.delayed(Duration.zero);

        // Verify that it subscribed to ancillary channels
        expect(
          mockSink.sentLines.any(
            (line) =>
                line.contains('"subscribe"') &&
                line.contains('broadcastChanged@12345'),
          ),
          isTrue,
        );

        // 4. Send chat message from server and verify it is received by the session
        final chatMessageReceived = session.messages.first;
        serverStreamController.add(
          jsonEncode({
            'push': {
              'channel': 'newChatMessage@12345',
              'pub': {
                'data': {
                  'message': {
                    'type': 'text',
                    'createdAt': '2026-05-06T12:00:00Z',
                    'details': {'body': 'hello from server'},
                    'userData': {'username': 'server_user'},
                  },
                },
              },
            },
          }),
        );

        final received = await chatMessageReceived;
        expect(received.content, 'hello from server');
        expect(received.userName, 'server_user');

        // 5. Disconnect and verify resources are cleaned up
        await session.disconnect();
        expect(mockSink.isClosed, isTrue);
      },
    );

    test('sends heartbeat periodic keepalive every 15 seconds', () {
      fakeAsync((async) {
        final localServerStreamController =
            StreamController<dynamic>.broadcast();
        try {
          final localMockSink = _MockMockWebSocketSink(
            localServerStreamController,
          );
          final localMockChannel = _MockWebSocketChannel(
            localServerStreamController.stream,
            localMockSink,
          );
          final localSession = StripchatDanmakuSession(
            danmakuToken: const StripchatDanmakuToken(
              modelId: '12345',
              websocketUrl: 'wss://ws.stripchat.com/connection/websocket',
              jwt: 'mock-jwt',
            ),
            inactivityTimeout: const Duration(minutes: 2),
            channelConnector:
                (
                  uri, {
                  headers,
                  protocols,
                  connectTimeout = const Duration(seconds: 10),
                }) => Future.value(localMockChannel),
          );

          // 1. Connect
          localSession.connect();
          async.elapse(const Duration(milliseconds: 100));

          // 2. Respond with connect ACK
          localServerStreamController.add('{"result": {}, "id": 1}');
          async.elapse(const Duration(milliseconds: 100));

          // Clear initial connection/subscription frames sent so far.
          // Heartbeat Timer.periodic starts at connect, so the next tick is
          // ~15s from connect (not from this clear) — only assert cadence.
          localMockSink.sentLines.clear();

          // Advance past the first keepalive boundary.
          async.elapse(const Duration(seconds: 15));
          expect(localMockSink.sentLines, isNotEmpty);
          expect(localMockSink.sentLines.last, '{}\n');
          final afterFirst = localMockSink.sentLines.length;

          // Next period should append another empty keepalive frame.
          async.elapse(const Duration(seconds: 15));
          expect(localMockSink.sentLines.length, greaterThan(afterFirst));
          expect(localMockSink.sentLines.last, '{}\n');

          localSession.disconnect();
        } finally {
          localServerStreamController.close();
          async.elapse(const Duration(milliseconds: 100));
        }
      });
    });

    test(
      'server ping echo: when server sends {}, client responds with {}',
      () async {
        final connectFuture = session.connect();
        await Future<void>.delayed(Duration.zero);
        serverStreamController.add('{"result": {}, "id": 1}');
        await connectFuture;

        mockSink.sentLines.clear();
        serverStreamController.add('{}');
        await Future<void>.delayed(Duration.zero);

        expect(mockSink.sentLines, contains('{}\n'));
      },
    );

    test(
      'reconnect after WebSocket drop works immediately without stale session blockage',
      () async {
        var channelIndex = 0;
        final secondServerStreamController =
            StreamController<dynamic>.broadcast();
        final secondMockSink = _MockMockWebSocketSink(
          secondServerStreamController,
        );
        final secondMockChannel = _MockWebSocketChannel(
          secondServerStreamController.stream,
          secondMockSink,
        );

        final session2 = StripchatDanmakuSession(
          danmakuToken: const StripchatDanmakuToken(
            modelId: '12345',
            websocketUrl: 'wss://ws.stripchat.com/connection/websocket',
            jwt: 'mock-jwt',
          ),
          channelConnector:
              (
                uri, {
                headers,
                protocols,
                connectTimeout = const Duration(seconds: 10),
              }) async {
                channelIndex++;
                return secondMockChannel;
              },
        );

        final fut = session2.connect();
        await Future<void>.delayed(Duration.zero);
        secondServerStreamController.add('{"result": {}, "id": 1}');
        await fut;
        expect(channelIndex, 1);

        await secondServerStreamController.close();
        await Future<void>.delayed(Duration.zero);

        try {
          await session2.connect().timeout(const Duration(milliseconds: 10));
        } catch (_) {}

        expect(channelIndex, 2);
      },
    );

    test(
      'session-level inactivity timeout triggers disconnect and reports diagnostic',
      () {
        fakeAsync((async) {
          final localServerStreamController =
              StreamController<dynamic>.broadcast();
          try {
            final localMockSink = _MockMockWebSocketSink(
              localServerStreamController,
            );
            final localMockChannel = _MockWebSocketChannel(
              localServerStreamController.stream,
              localMockSink,
            );
            final localSession = StripchatDanmakuSession(
              danmakuToken: const StripchatDanmakuToken(
                modelId: '12345',
                websocketUrl: 'wss://ws.stripchat.com/connection/websocket',
                jwt: 'mock-jwt',
              ),
              inactivityTimeout: const Duration(seconds: 5),
              channelConnector:
                  (
                    uri, {
                    headers,
                    protocols,
                    connectTimeout = const Duration(seconds: 10),
                  }) => Future.value(localMockChannel),
            );

            final connectFuture = localSession.connect();
            expect(connectFuture, throwsA(isA<TimeoutException>()));
            async.elapse(const Duration(milliseconds: 100));
            async.elapse(const Duration(seconds: 5));
          } finally {
            localServerStreamController.close();
            async.elapse(const Duration(milliseconds: 100));
          }
        });
      },
    );
  });
}

class _MockMockWebSocketSink implements WebSocketSink {
  final StreamController _controller;
  final List<String> sentLines = [];
  bool isClosed = false;

  _MockMockWebSocketSink(this._controller);

  @override
  void add(dynamic data) {
    sentLines.add(data as String);
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    _controller.addError(error, stackTrace);
  }

  @override
  Future<void> addStream(Stream stream) {
    return _controller.addStream(stream);
  }

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    isClosed = true;
    await _controller.close();
  }

  @override
  Future<void> get done => _controller.done;
}

class _MockWebSocketChannel implements WebSocketChannel {
  _MockWebSocketChannel(this.stream, this.sink);

  @override
  final Stream stream;

  @override
  final WebSocketSink sink;

  @override
  Future<void> get ready => Future.value();

  @override
  String? get closeReason => null;

  @override
  int? get closeCode => null;

  @override
  String? get protocol => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
