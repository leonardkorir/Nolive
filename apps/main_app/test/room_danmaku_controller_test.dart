import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:nolive_app/src/app/bootstrap/bootstrap.dart';
import 'package:nolive_app/src/features/room/application/room_preview_dependencies.dart';
import 'package:nolive_app/src/features/room/presentation/room_danmaku_controller.dart';

void main() {
  test('chaturbate room_history 403 is treated as non-retryable', () {
    expect(
      shouldRetryDanmakuConnectionError(
        providerId: ProviderId.chaturbate,
        error: ProviderParseException(
          providerId: ProviderId.chaturbate,
          message:
              'Chaturbate /push_service/room_history/ request failed with status 403.',
        ),
      ),
      isFalse,
    );
    expect(
      shouldRetryDanmakuConnectionError(
        providerId: ProviderId.chaturbate,
        error: ProviderParseException(
          providerId: ProviderId.chaturbate,
          message:
              'Chaturbate /push_service/auth/ request was blocked by Cloudflare challenge.',
        ),
      ),
      isFalse,
    );
    expect(
      shouldRetryDanmakuConnectionError(
        providerId: ProviderId.chaturbate,
        error: ProviderParseException(
          providerId: ProviderId.chaturbate,
          message: 'Chaturbate realtime websocket connect failed.',
        ),
      ),
      isTrue,
    );
  });

  test('room danmaku controller uses extended default timeout for chaturbate',
      () {
    expect(
      resolveDanmakuConnectTimeout(
        providerId: ProviderId.chaturbate,
        configuredTimeout: const Duration(seconds: 6),
      ),
      const Duration(seconds: 20),
    );
    expect(
      resolveDanmakuConnectTimeout(
        providerId: ProviderId.douyu,
        configuredTimeout: const Duration(seconds: 6),
      ),
      const Duration(seconds: 20),
    );
    expect(
      resolveDanmakuConnectTimeout(
        providerId: ProviderId.chaturbate,
        configuredTimeout: const Duration(milliseconds: 20),
      ),
      const Duration(milliseconds: 20),
    );
  });

  test('room danmaku controller exposes messages and clears feed', () async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    bootstrap.providerRegistry.register(
      ProviderRegistration(
        descriptor: _kRoomDanmakuTestDescriptor,
        builder: () => _RoomDanmakuTestProvider(
          createSession: () => _ScriptedDanmakuSession(
            onConnect: (controller) async {
              controller.add(
                LiveMessage(
                  type: LiveMessageType.chat,
                  content: 'chat-message',
                  userName: 'tester',
                  timestamp: DateTime.now(),
                ),
              );
            },
          ),
        ),
      ),
    );
    bootstrap.providerRegistry.clearCache();

    final dependencies = RoomPreviewDependencies.fromBootstrap(bootstrap);
    final controller = RoomDanmakuController(
      dependencies: RoomDanmakuDependencies.fromPreviewDependencies(
        dependencies,
      ),
      providerId: _kRoomDanmakuTestProviderId,
    );

    final snapshot = await bootstrap.loadRoom(
      providerId: _kRoomDanmakuTestProviderId,
      roomId: 'room-1',
    );
    controller.configure(
      blockedKeywords: const <String>[],
      preferNativeBatchMask: false,
      playerSuperChatDisplaySeconds: 3,
    );
    final session = (await dependencies.openRoomDanmaku(
      providerId: _kRoomDanmakuTestProviderId,
      detail: snapshot.detail,
    )) as _ScriptedDanmakuSession?;
    await controller.bindSession(
      activeRoomDetail: snapshot.detail,
      session: session,
    );

    await Future<void>.delayed(Duration.zero);

    expect(controller.current.session, isNotNull);
    expect(
      controller.messages.value.any((item) => item.content == 'chat-message'),
      isTrue,
    );
    controller.clearFeed();

    expect(controller.messages.value, isEmpty);
    expect(controller.superChats.value, isEmpty);
    expect(controller.playerSuperChats.value, isEmpty);
    expect(controller.current.reconnectAttempt, 0);
    expect(controller.current.reconnectScheduled, isFalse);
    await controller.current.session?.disconnect();
    controller.dispose();
    await Future<void>.delayed(Duration.zero);
  });

  test('room danmaku controller reconnects after disconnect notice', () async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    var sessionCreateCount = 0;

    bootstrap.providerRegistry.register(
      ProviderRegistration(
        descriptor: _kRoomDanmakuTestDescriptor,
        builder: () => _RoomDanmakuTestProvider(
          createSession: () {
            sessionCreateCount += 1;
            if (sessionCreateCount == 1) {
              return _ScriptedDanmakuSession(
                onConnect: (controller) async {
                  controller.add(
                    LiveMessage(
                      type: LiveMessageType.notice,
                      content: 'test disconnect notice: 连接已断开',
                      timestamp: DateTime.now(),
                    ),
                  );
                },
              );
            }
            return _ScriptedDanmakuSession(
              onConnect: (controller) async {
                controller.add(
                  LiveMessage(
                    type: LiveMessageType.chat,
                    content: 'reconnected-message',
                    userName: 'tester',
                    timestamp: DateTime.now(),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
    bootstrap.providerRegistry.clearCache();

    final dependencies = RoomPreviewDependencies.fromBootstrap(bootstrap);
    final controller = RoomDanmakuController(
      dependencies: RoomDanmakuDependencies.fromPreviewDependencies(
        dependencies,
      ),
      providerId: _kRoomDanmakuTestProviderId,
    );

    final snapshot = await bootstrap.loadRoom(
      providerId: _kRoomDanmakuTestProviderId,
      roomId: 'reconnect-room',
    );
    controller.configure(
      blockedKeywords: const <String>[],
      preferNativeBatchMask: false,
      playerSuperChatDisplaySeconds: 3,
    );
    final session = await dependencies.openRoomDanmaku(
      providerId: _kRoomDanmakuTestProviderId,
      detail: snapshot.detail,
    ) as _ScriptedDanmakuSession?;
    await controller.bindSession(
      activeRoomDetail: snapshot.detail,
      session: session,
    );

    await Future<void>.delayed(const Duration(seconds: 6));

    expect(sessionCreateCount, 2);
    expect(identical(controller.current.session, session), isFalse);
    await controller.current.session?.disconnect();
    controller.dispose();
    await Future<void>.delayed(Duration.zero);
  });

  test(
      'room danmaku controller swallows connect handshake failures and reconnects',
      () async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    var sessionCreateCount = 0;

    bootstrap.providerRegistry.register(
      ProviderRegistration(
        descriptor: _kRoomDanmakuTestDescriptor,
        builder: () => _RoomDanmakuTestProvider(
          createSession: () {
            sessionCreateCount += 1;
            if (sessionCreateCount == 1) {
              return _ScriptedDanmakuSession(
                onConnect: (_) async {
                  throw HandshakeException('tls failed');
                },
              );
            }
            return _ScriptedDanmakuSession(
              onConnect: (controller) async {
                controller.add(
                  LiveMessage(
                    type: LiveMessageType.chat,
                    content: 'handshake-recovered',
                    userName: 'tester',
                    timestamp: DateTime.now(),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
    bootstrap.providerRegistry.clearCache();

    final dependencies = RoomPreviewDependencies.fromBootstrap(bootstrap);
    final controller = RoomDanmakuController(
      dependencies: RoomDanmakuDependencies.fromPreviewDependencies(
        dependencies,
      ),
      providerId: _kRoomDanmakuTestProviderId,
    );

    final snapshot = await bootstrap.loadRoom(
      providerId: _kRoomDanmakuTestProviderId,
      roomId: 'handshake-room',
    );
    controller.configure(
      blockedKeywords: const <String>[],
      preferNativeBatchMask: false,
      playerSuperChatDisplaySeconds: 3,
    );
    final session = (await dependencies.openRoomDanmaku(
      providerId: _kRoomDanmakuTestProviderId,
      detail: snapshot.detail,
    )) as _ScriptedDanmakuSession?;
    await controller.bindSession(
      activeRoomDetail: snapshot.detail,
      session: session,
    );

    await Future<void>.delayed(const Duration(seconds: 3));

    expect(sessionCreateCount, 2);
    expect(
      controller.messages.value.any(
        (item) => item.content.contains('弹幕连接失败：HandshakeException'),
      ),
      isTrue,
    );
    expect(
      controller.messages.value
          .any((item) => item.content == 'handshake-recovered'),
      isTrue,
    );
    await controller.current.session?.disconnect();
    controller.dispose();
    await Future<void>.delayed(Duration.zero);
  });

  test('room danmaku controller times out stalled connect attempts', () async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    final stalledConnect = Completer<void>();

    bootstrap.providerRegistry.register(
      ProviderRegistration(
        descriptor: _kRoomDanmakuTestDescriptor,
        builder: () => _RoomDanmakuTestProvider(
          createSession: () => _ScriptedDanmakuSession(
            onConnect: (_) => stalledConnect.future,
          ),
        ),
      ),
    );
    bootstrap.providerRegistry.clearCache();

    final dependencies = RoomPreviewDependencies.fromBootstrap(bootstrap);
    final controller = RoomDanmakuController(
      dependencies: RoomDanmakuDependencies.fromPreviewDependencies(
        dependencies,
      ),
      providerId: _kRoomDanmakuTestProviderId,
      connectTimeout: const Duration(milliseconds: 20),
    );

    final snapshot = await bootstrap.loadRoom(
      providerId: _kRoomDanmakuTestProviderId,
      roomId: 'timeout-room',
    );
    controller.configure(
      blockedKeywords: const <String>[],
      preferNativeBatchMask: false,
      playerSuperChatDisplaySeconds: 3,
    );
    final session = await dependencies.openRoomDanmaku(
      providerId: _kRoomDanmakuTestProviderId,
      detail: snapshot.detail,
    );

    await controller.bindSession(
      activeRoomDetail: snapshot.detail,
      session: session,
    );
    await Future<void>.delayed(Duration.zero);

    expect(
      controller.messages.value.any(
        (item) => item.content.contains('弹幕连接失败：TimeoutException'),
      ),
      isTrue,
    );
    expect(controller.current.session, isNull);
    controller.dispose();
    await Future<void>.delayed(Duration.zero);
  });

  test('room danmaku controller drops stale reconnect result after rebind',
      () async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    final staleReconnectSessionCompleter = Completer<DanmakuSession>();
    final staleReconnectSession = _ScriptedDanmakuSession(
      onConnect: (_) async {},
    );
    final reboundSession = _ScriptedDanmakuSession(
      onConnect: (controller) async {
        controller.add(
          LiveMessage(
            type: LiveMessageType.chat,
            content: 'room-2-message',
            userName: 'tester',
            timestamp: DateTime.now(),
          ),
        );
      },
    );
    var sessionCreateCount = 0;

    bootstrap.providerRegistry.register(
      ProviderRegistration(
        descriptor: _kRoomDanmakuTestDescriptor,
        builder: () => _RoomDanmakuTestProvider(
          createSession: () {
            sessionCreateCount += 1;
            if (sessionCreateCount == 1) {
              return _ScriptedDanmakuSession(
                onConnect: (controller) async {
                  controller.add(
                    LiveMessage(
                      type: LiveMessageType.notice,
                      content: 'test disconnect notice: 连接已断开',
                      timestamp: DateTime.now(),
                    ),
                  );
                },
              );
            }
            if (sessionCreateCount == 2) {
              return staleReconnectSessionCompleter.future;
            }
            return reboundSession;
          },
        ),
      ),
    );
    bootstrap.providerRegistry.clearCache();

    final dependencies = RoomPreviewDependencies.fromBootstrap(bootstrap);
    final controller = RoomDanmakuController(
      dependencies: RoomDanmakuDependencies.fromPreviewDependencies(
        dependencies,
      ),
      providerId: _kRoomDanmakuTestProviderId,
    );

    final room1 = await bootstrap.loadRoom(
      providerId: _kRoomDanmakuTestProviderId,
      roomId: 'room-1',
    );
    controller.configure(
      blockedKeywords: const <String>[],
      preferNativeBatchMask: false,
      playerSuperChatDisplaySeconds: 3,
    );
    final session1 = await dependencies.openRoomDanmaku(
      providerId: _kRoomDanmakuTestProviderId,
      detail: room1.detail,
    );
    await controller.bindSession(
      activeRoomDetail: room1.detail,
      session: session1,
    );

    await Future<void>.delayed(const Duration(seconds: 2));

    final room2 = await bootstrap.loadRoom(
      providerId: _kRoomDanmakuTestProviderId,
      roomId: 'room-2',
    );
    final room2Session = await dependencies.openRoomDanmaku(
      providerId: _kRoomDanmakuTestProviderId,
      detail: room2.detail,
    );
    await controller.bindSession(
      activeRoomDetail: room2.detail,
      session: room2Session,
    );

    staleReconnectSessionCompleter.complete(staleReconnectSession);
    await Future<void>.delayed(Duration.zero);

    expect(sessionCreateCount, 3);
    expect(identical(controller.current.session, room2Session), isTrue);
    expect(staleReconnectSession.didDisconnect, isTrue);
    expect(
      controller.messages.value.any((item) => item.content == 'room-2-message'),
      isTrue,
    );
    await controller.current.session?.disconnect();
    controller.dispose();
    await Future<void>.delayed(Duration.zero);
  });

  test('room danmaku controller suspends in background and resumes afterwards',
      () async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    var sessionCreateCount = 0;
    final traces = <String>[];

    bootstrap.providerRegistry.register(
      ProviderRegistration(
        descriptor: _kRoomDanmakuTestDescriptor,
        builder: () => _RoomDanmakuTestProvider(
          createSession: () {
            sessionCreateCount += 1;
            return _ScriptedDanmakuSession(
              onConnect: (controller) async {
                controller.add(
                  LiveMessage(
                    type: LiveMessageType.chat,
                    content: 'session-$sessionCreateCount',
                    userName: 'tester',
                    timestamp: DateTime.now(),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
    bootstrap.providerRegistry.clearCache();

    final dependencies = RoomPreviewDependencies.fromBootstrap(bootstrap);
    final controller = RoomDanmakuController(
      dependencies: RoomDanmakuDependencies.fromPreviewDependencies(
        dependencies,
      ),
      providerId: _kRoomDanmakuTestProviderId,
      trace: traces.add,
    );

    final snapshot = await bootstrap.loadRoom(
      providerId: _kRoomDanmakuTestProviderId,
      roomId: 'lifecycle-room',
    );
    controller.configure(
      blockedKeywords: const <String>[],
      preferNativeBatchMask: false,
      playerSuperChatDisplaySeconds: 3,
    );
    final session = (await dependencies.openRoomDanmaku(
      providerId: _kRoomDanmakuTestProviderId,
      detail: snapshot.detail,
    )) as _ScriptedDanmakuSession?;
    await controller.bindSession(
      activeRoomDetail: snapshot.detail,
      session: session,
    );

    await controller.handleLifecycleState(
      state: AppLifecycleState.hidden,
      backgroundAutoPauseEnabled: true,
      inPictureInPictureMode: false,
      enteringPictureInPicture: false,
    );

    expect(controller.current.session, isNull);
    expect(sessionCreateCount, 1);
    expect(session?.didDisconnect, isTrue);

    await controller.handleLifecycleState(
      state: AppLifecycleState.resumed,
      backgroundAutoPauseEnabled: true,
      inPictureInPictureMode: false,
      enteringPictureInPicture: false,
    );
    await Future<void>.delayed(Duration.zero);

    expect(sessionCreateCount, 2);
    expect(controller.current.session, isNotNull);
    expect(
      traces.any(
        (entry) => entry.contains('danmaku bind start room=lifecycle-room'),
      ),
      isTrue,
    );
    expect(
      traces.any(
        (entry) => entry.contains('danmaku connect ready room=lifecycle-room'),
      ),
      isTrue,
    );
    expect(
      traces.any(
        (entry) => entry.contains(
            'danmaku lifecycle suspend state=hidden room=lifecycle-room'),
      ),
      isTrue,
    );
    expect(
      traces.any(
        (entry) =>
            entry.contains('danmaku lifecycle resume open room=lifecycle-room'),
      ),
      isTrue,
    );
    await controller.current.session?.disconnect();
    controller.dispose();
    await Future<void>.delayed(Duration.zero);
  });

  test('room danmaku controller keeps session active in picture-in-picture',
      () async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);

    bootstrap.providerRegistry.register(
      ProviderRegistration(
        descriptor: _kRoomDanmakuTestDescriptor,
        builder: () => _RoomDanmakuTestProvider(
          createSession: () => _ScriptedDanmakuSession(onConnect: (_) async {}),
        ),
      ),
    );
    bootstrap.providerRegistry.clearCache();

    final dependencies = RoomPreviewDependencies.fromBootstrap(bootstrap);
    final controller = RoomDanmakuController(
      dependencies: RoomDanmakuDependencies.fromPreviewDependencies(
        dependencies,
      ),
      providerId: _kRoomDanmakuTestProviderId,
    );

    final snapshot = await bootstrap.loadRoom(
      providerId: _kRoomDanmakuTestProviderId,
      roomId: 'pip-room',
    );
    controller.configure(
      blockedKeywords: const <String>[],
      preferNativeBatchMask: false,
      playerSuperChatDisplaySeconds: 3,
    );
    final session = await dependencies.openRoomDanmaku(
      providerId: _kRoomDanmakuTestProviderId,
      detail: snapshot.detail,
    );
    await controller.bindSession(
      activeRoomDetail: snapshot.detail,
      session: session,
    );

    await controller.handleLifecycleState(
      state: AppLifecycleState.hidden,
      backgroundAutoPauseEnabled: true,
      inPictureInPictureMode: true,
      enteringPictureInPicture: false,
    );

    expect(controller.current.session, same(session));
    await controller.current.session?.disconnect();
    controller.dispose();
    await Future<void>.delayed(Duration.zero);
  });

  test(
      'room danmaku controller keeps session active while entering picture-in-picture',
      () async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);

    bootstrap.providerRegistry.register(
      ProviderRegistration(
        descriptor: _kRoomDanmakuTestDescriptor,
        builder: () => _RoomDanmakuTestProvider(
          createSession: () => _ScriptedDanmakuSession(onConnect: (_) async {}),
        ),
      ),
    );
    bootstrap.providerRegistry.clearCache();

    final dependencies = RoomPreviewDependencies.fromBootstrap(bootstrap);
    final controller = RoomDanmakuController(
      dependencies: RoomDanmakuDependencies.fromPreviewDependencies(
        dependencies,
      ),
      providerId: _kRoomDanmakuTestProviderId,
    );

    final snapshot = await bootstrap.loadRoom(
      providerId: _kRoomDanmakuTestProviderId,
      roomId: 'pip-entering-room',
    );
    controller.configure(
      blockedKeywords: const <String>[],
      preferNativeBatchMask: false,
      playerSuperChatDisplaySeconds: 3,
    );
    final session = await dependencies.openRoomDanmaku(
      providerId: _kRoomDanmakuTestProviderId,
      detail: snapshot.detail,
    );
    await controller.bindSession(
      activeRoomDetail: snapshot.detail,
      session: session,
    );

    await controller.handleLifecycleState(
      state: AppLifecycleState.hidden,
      backgroundAutoPauseEnabled: true,
      inPictureInPictureMode: false,
      enteringPictureInPicture: true,
    );

    expect(controller.current.session, same(session));
    await controller.current.session?.disconnect();
    controller.dispose();
    await Future<void>.delayed(Duration.zero);
  });

  test(
      'room danmaku controller ignores stale reconnect signals after lifecycle suspend',
      () async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    final lingeringControllerCompleter =
        Completer<StreamController<LiveMessage>>();
    var sessionCreateCount = 0;
    _LingeringDanmakuSession? firstSession;

    bootstrap.providerRegistry.register(
      ProviderRegistration(
        descriptor: _kRoomDanmakuTestDescriptor,
        builder: () => _RoomDanmakuTestProvider(
          createSession: () {
            sessionCreateCount += 1;
            if (sessionCreateCount == 1) {
              firstSession = _LingeringDanmakuSession(
                onConnect: (controller) async {
                  lingeringControllerCompleter.complete(controller);
                },
              );
              return firstSession!;
            }
            return _ScriptedDanmakuSession(onConnect: (_) async {});
          },
        ),
      ),
    );
    bootstrap.providerRegistry.clearCache();

    final dependencies = RoomPreviewDependencies.fromBootstrap(bootstrap);
    final controller = RoomDanmakuController(
      dependencies: RoomDanmakuDependencies.fromPreviewDependencies(
        dependencies,
      ),
      providerId: _kRoomDanmakuTestProviderId,
    );

    final snapshot = await bootstrap.loadRoom(
      providerId: _kRoomDanmakuTestProviderId,
      roomId: 'suspended-room',
    );
    controller.configure(
      blockedKeywords: const <String>[],
      preferNativeBatchMask: false,
      playerSuperChatDisplaySeconds: 3,
    );
    final session = await dependencies.openRoomDanmaku(
      providerId: _kRoomDanmakuTestProviderId,
      detail: snapshot.detail,
    );
    await controller.bindSession(
      activeRoomDetail: snapshot.detail,
      session: session,
    );

    await controller.handleLifecycleState(
      state: AppLifecycleState.hidden,
      backgroundAutoPauseEnabled: true,
      inPictureInPictureMode: false,
      enteringPictureInPicture: false,
    );
    final lingeringController = await lingeringControllerCompleter.future;
    lingeringController.add(
      LiveMessage(
        type: LiveMessageType.notice,
        content: 'test disconnect notice: 连接已断开',
        timestamp: DateTime.now(),
      ),
    );
    await Future<void>.delayed(const Duration(seconds: 3));

    expect(controller.current.session, isNull);
    expect(sessionCreateCount, 1);

    await firstSession?.closeController();
    controller.dispose();
    await Future<void>.delayed(Duration.zero);
  });
}

const _kRoomDanmakuTestProviderId = ProviderId('room_danmaku_test');

const _kRoomDanmakuTestDescriptor = ProviderDescriptor(
  id: _kRoomDanmakuTestProviderId,
  displayName: 'Room Danmaku Test',
  capabilities: {
    ProviderCapability.roomDetail,
    ProviderCapability.playQualities,
    ProviderCapability.playUrls,
    ProviderCapability.danmaku,
  },
  supportedPlatforms: {ProviderPlatform.android},
  maturity: ProviderMaturity.ready,
);

class _RoomDanmakuTestProvider extends LiveProvider
    implements
        SupportsRoomDetail,
        SupportsPlayQualities,
        SupportsPlayUrls,
        SupportsDanmaku {
  _RoomDanmakuTestProvider({required this.createSession});

  final FutureOr<DanmakuSession> Function() createSession;

  @override
  ProviderDescriptor get descriptor => _kRoomDanmakuTestDescriptor;

  @override
  Future<LiveRoomDetail> fetchRoomDetail(String roomId) async {
    return LiveRoomDetail(
      providerId: _kRoomDanmakuTestProviderId.value,
      roomId: roomId,
      title: '$roomId-title',
      streamerName: roomId,
      sourceUrl: 'https://example.com/$roomId',
      isLive: true,
    );
  }

  @override
  Future<List<LivePlayQuality>> fetchPlayQualities(
    LiveRoomDetail detail,
  ) async {
    return const <LivePlayQuality>[
      LivePlayQuality(
        id: 'auto',
        label: 'Auto',
        isDefault: true,
      ),
    ];
  }

  @override
  Future<List<LivePlayUrl>> fetchPlayUrls({
    required LiveRoomDetail detail,
    required LivePlayQuality quality,
  }) async {
    return const <LivePlayUrl>[
      LivePlayUrl(
        url: 'https://example.com/live.m3u8',
      ),
    ];
  }

  @override
  Future<DanmakuSession> createDanmakuSession(LiveRoomDetail detail) async {
    return Future<DanmakuSession>.value(createSession());
  }
}

class _ScriptedDanmakuSession implements DanmakuSession {
  _ScriptedDanmakuSession({
    required this.onConnect,
  });

  final Future<void> Function(StreamController<LiveMessage> controller)
      onConnect;
  final StreamController<LiveMessage> _controller =
      StreamController<LiveMessage>.broadcast();
  bool didDisconnect = false;

  @override
  Stream<LiveMessage> get messages => _controller.stream;

  @override
  Future<void> connect() => onConnect(_controller);

  @override
  Future<void> disconnect() async {
    didDisconnect = true;
    if (!_controller.isClosed) {
      await _controller.close();
    }
  }
}

class _LingeringDanmakuSession implements DanmakuSession {
  _LingeringDanmakuSession({
    required this.onConnect,
  });

  final Future<void> Function(StreamController<LiveMessage> controller)
      onConnect;
  final StreamController<LiveMessage> _controller =
      StreamController<LiveMessage>.broadcast();
  bool didDisconnect = false;

  @override
  Stream<LiveMessage> get messages => _controller.stream;

  @override
  Future<void> connect() => onConnect(_controller);

  @override
  Future<void> disconnect() async {
    didDisconnect = true;
  }

  Future<void> closeController() async {
    if (!_controller.isClosed) {
      await _controller.close();
    }
  }
}
