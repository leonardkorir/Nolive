import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_hls_proxy/live_hls_proxy.dart';
import 'package:live_storage/live_storage.dart';
import 'package:nolive_app/src/app/bootstrap/bootstrap.dart';
import 'package:nolive_app/src/app/platform/app_platform_capabilities.dart';
import 'package:nolive_app/src/app/runtime_bridges/hls_proxy_platform_adapter_impl.dart';
import 'package:nolive_app/src/app/runtime_bridges/linux_desktop_webview_adapter.dart';
import 'package:nolive_app/src/features/settings/application/manage_provider_accounts_use_case.dart';
import 'package:nolive_app/src/shared/application/secure_credential_store.dart';

LoadProviderAccountSettingsUseCase _emptyAccountLoader() {
  return LoadProviderAccountSettingsUseCase(
    InMemorySettingsRepository(),
    InMemorySecureCredentialStore(),
  );
}

void main() {
  group('bootstrap international bridge assembly (shipped path)', () {
    const android = AppPlatformCapabilities(
      isWeb: false,
      isAndroid: true,
      isIOS: false,
      isLinux: false,
      isMacOS: false,
      isWindows: false,
      targetPlatform: TargetPlatform.android,
      operatingSystem: 'android',
      operatingSystemVersion: '14',
    );

    const linuxReady = AppPlatformCapabilities(
      isWeb: false,
      isAndroid: false,
      isIOS: false,
      isLinux: true,
      isMacOS: false,
      isWindows: false,
      targetPlatform: TargetPlatform.linux,
      operatingSystem: 'linux',
      operatingSystemVersion: '6.8',
      linuxWebViewAvailable: true,
    );

    const linuxNoWebView = AppPlatformCapabilities(
      isWeb: false,
      isAndroid: false,
      isIOS: false,
      isLinux: true,
      isMacOS: false,
      isWindows: false,
      targetPlatform: TargetPlatform.linux,
      operatingSystem: 'linux',
      operatingSystemVersion: '6.8',
      linuxWebViewAvailable: false,
    );

    test('live + Android assembles TW/CB/SC/YT bridges', () {
      final bridges = buildAppRuntimeBridgesForTesting(
        mode: AppRuntimeMode.live,
        platformCapabilities: android,
        loadProviderAccountSettings: _emptyAccountLoader(),
      );
      expect(bridges.twitchWebPlaybackBridge, isNotNull);
      expect(bridges.twitchAdGuardProxy, isNotNull);
      expect(bridges.chaturbateLlHlsProxy, isNotNull);
      expect(bridges.stripchatLlHlsProxy, isNotNull);
      expect(bridges.youtubeNSigSolver, isNotNull);
      expect(bridges.roomDetailOverride, isNotNull);
    });

    test(
      'live + Linux with WebView assembles bridges (not isMobile-gated)',
      () {
        expect(linuxReady.isMobile, isFalse);
        expect(linuxReady.supportsHeadlessWebView, isTrue);
        final bridges = buildAppRuntimeBridgesForTesting(
          mode: AppRuntimeMode.live,
          platformCapabilities: linuxReady,
          loadProviderAccountSettings: _emptyAccountLoader(),
        );
        expect(bridges.twitchWebPlaybackBridge, isNotNull);
        expect(bridges.twitchAdGuardProxy, isNotNull);
        expect(bridges.chaturbateLlHlsProxy, isNotNull);
        expect(bridges.stripchatLlHlsProxy, isNotNull);
        expect(bridges.youtubeNSigSolver, isNotNull);
      },
    );

    test('live + Linux without WebView yields null international bridges', () {
      final bridges = buildAppRuntimeBridgesForTesting(
        mode: AppRuntimeMode.live,
        platformCapabilities: linuxNoWebView,
        loadProviderAccountSettings: _emptyAccountLoader(),
      );
      expect(bridges.twitchWebPlaybackBridge, isNull);
      expect(bridges.twitchAdGuardProxy, isNull);
      expect(bridges.chaturbateLlHlsProxy, isNull);
      expect(bridges.stripchatLlHlsProxy, isNull);
      expect(bridges.youtubeNSigSolver, isNull);
      expect(bridges.roomDetailOverride, isNull);
    });

    test('non-live mode never assembles international bridges', () {
      final bridges = buildAppRuntimeBridgesForTesting(
        mode: AppRuntimeMode.preview,
        platformCapabilities: linuxReady,
        loadProviderAccountSettings: _emptyAccountLoader(),
      );
      expect(bridges.twitchWebPlaybackBridge, isNull);
      expect(bridges.youtubeNSigSolver, isNull);
    });
  });

  group('shipped bridge entry short-circuit on supportsHeadlessWebView', () {
    test(
      'TwitchWebPlaybackBridge.call returns null without webview support',
      () async {
        final bridge = TwitchWebPlaybackBridge(
          platformAdapter: _GateAdapter(supports: false),
        );
        final result = await bridge.call(
          const LiveRoomDetail(
            providerId: ProviderId.twitch,
            roomId: 'some_streamer',
            title: 't',
            streamerName: 's',
            isLive: true,
          ),
        );
        expect(result, isNull);
      },
    );

    test(
      'ChaturbateWebRoomDetailLoader.call returns null without webview',
      () async {
        final loader = ChaturbateWebRoomDetailLoader(
          platformAdapter: _GateAdapter(supports: false),
        );
        final result = await loader.call(
          providerId: ProviderId.chaturbate,
          roomId: 'model',
        );
        expect(result, isNull);
      },
    );

    test('adapter surfaces supportsHeadlessWebView from capabilities', () {
      final adapter = HlsProxyPlatformAdapterImpl(
        platformCapabilities: const AppPlatformCapabilities(
          isWeb: false,
          isAndroid: false,
          isIOS: false,
          isLinux: true,
          isMacOS: false,
          isWindows: false,
          targetPlatform: TargetPlatform.linux,
          operatingSystem: 'linux',
          operatingSystemVersion: '6.8',
          linuxWebViewAvailable: true,
        ),
        linuxCookieJar: LinuxDesktopCookieJar(),
      );
      expect(adapter.supportsHeadlessWebView, isTrue);
      expect(adapter.isMobile, isFalse);

      final disabled = HlsProxyPlatformAdapterImpl(
        platformCapabilities: const AppPlatformCapabilities(
          isWeb: false,
          isAndroid: false,
          isIOS: false,
          isLinux: true,
          isMacOS: false,
          isWindows: false,
          targetPlatform: TargetPlatform.linux,
          operatingSystem: 'linux',
          operatingSystemVersion: '6.8',
          linuxWebViewAvailable: false,
        ),
        linuxCookieJar: LinuxDesktopCookieJar(),
      );
      expect(disabled.supportsHeadlessWebView, isFalse);
    });
  });
}

class _GateAdapter implements HlsProxyPlatformAdapter {
  _GateAdapter({required this.supports});

  final bool supports;

  @override
  bool get isMobile => false;

  @override
  bool get supportsHeadlessWebView => supports;

  @override
  bool get kDebugMode => false;

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
