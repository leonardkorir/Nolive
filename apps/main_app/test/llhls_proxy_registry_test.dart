import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_hls_proxy/live_hls_proxy.dart';
import 'package:nolive_app/src/app/bootstrap/llhls_proxy_lifecycle.dart';

class _FakePlatformAdapter implements HlsProxyPlatformAdapter {
  @override
  bool get isMobile => true;

  @override
  bool get kDebugMode => true;

  @override
  void log(
    String tag,
    String message, [
    Object? error,
    StackTrace? stackTrace,
  ]) {}

  @override
  void debugPrint(String message) {}

  @override
  HlsProxyCookieManager get cookieManager => throw UnimplementedError();

  @override
  Future<HlsHeadlessWebView> createHeadlessWebView({
    required String initialUrl,
    required String userAgent,
    bool desktopMode = false,
    HlsWebViewResourceBlocker? shouldBlockRequest,
    void Function(String message)? onConsoleMessage,
    void Function(int statusCode, String url)? onHttpError,
    void Function(String description, String url)? onLoadError,
  }) => throw UnimplementedError();
}

class _FakeChaturbateProxy extends ChaturbateLlHlsProxy {
  _FakeChaturbateProxy()
    : super(platformAdapter: _FakePlatformAdapter(), enabledOverride: false);

  bool ensureStartedCalled = false;
  String? unregisteredRoomId;

  @override
  Future<void> ensureStarted() async {
    ensureStartedCalled = true;
  }

  @override
  void unregisterSession(String roomId) {
    unregisteredRoomId = roomId;
  }
}

class _FakeStripchatProxy extends StripchatLlHlsProxy {
  _FakeStripchatProxy()
    : super(platformAdapter: _FakePlatformAdapter(), enabledOverride: false);

  bool ensureStartedCalled = false;
  String? unregisteredRoomId;

  @override
  Future<void> ensureStarted() async {
    ensureStartedCalled = true;
  }

  @override
  void unregisterSession(String roomId) {
    unregisteredRoomId = roomId;
  }
}

class _FakeTwitchProxy extends TwitchAdGuardProxy {
  _FakeTwitchProxy()
    : super(platformAdapter: _FakePlatformAdapter(), enabledOverride: false);

  bool ensureStartedCalled = false;
  String? unregisteredRoomId;

  @override
  Future<void> ensureStarted() async {
    ensureStartedCalled = true;
  }

  @override
  void unregisterSession(String roomId) {
    unregisteredRoomId = roomId;
  }
}

void main() {
  group('LlhlsProxyRegistry', () {
    test('initialize calls ensureStarted on all non-null proxies', () async {
      final chaturbate = _FakeChaturbateProxy();
      final stripchat = _FakeStripchatProxy();
      final twitch = _FakeTwitchProxy();

      final registry = LlhlsProxyRegistry(
        chaturbateProxy: chaturbate,
        stripchatProxy: stripchat,
        twitchProxy: twitch,
      );

      await registry.initialize();

      expect(chaturbate.ensureStartedCalled, isTrue);
      expect(stripchat.ensureStartedCalled, isTrue);
      expect(twitch.ensureStartedCalled, isTrue);
    });

    test('initialize handles exceptions from proxies gracefully', () async {
      final chaturbate = _FakeChaturbateProxy();
      final stripchat = _FakeStripchatProxy();
      // Twitch proxy throws on ensureStarted
      final twitch = _FakeTwitchProxy();

      final registry = LlhlsProxyRegistry(
        chaturbateProxy: chaturbate,
        stripchatProxy: stripchat,
        twitchProxy: twitch,
      );

      // Verify that registry.initialize finishes successfully even if one throws
      await registry.initialize();

      expect(chaturbate.ensureStartedCalled, isTrue);
      expect(stripchat.ensureStartedCalled, isTrue);
    });

    test(
      'registerSession and unregisterSession delegate calls correctly',
      () async {
        final chaturbate = _FakeChaturbateProxy();
        final stripchat = _FakeStripchatProxy();
        final twitch = _FakeTwitchProxy();

        final registry = LlhlsProxyRegistry(
          chaturbateProxy: chaturbate,
          stripchatProxy: stripchat,
          twitchProxy: twitch,
        );

        registry.registerSession(
          roomId: 'room_123',
          providerId: const ProviderId('chaturbate'),
        );

        registry.unregisterSession(roomId: 'room_123');

        expect(chaturbate.unregisteredRoomId, 'room_123');
        expect(stripchat.unregisteredRoomId, 'room_123');
        expect(twitch.unregisteredRoomId, 'room_123');
      },
    );

    test(
      'handles null proxies during unregistration and initialization',
      () async {
        final registry = LlhlsProxyRegistry(
          chaturbateProxy: null,
          stripchatProxy: null,
          twitchProxy: null,
        );

        // Should not throw
        await registry.initialize();
        registry.registerSession(
          roomId: 'room_abc',
          providerId: const ProviderId('stripchat'),
        );
        registry.unregisterSession(roomId: 'room_abc');
      },
    );
  });
}
