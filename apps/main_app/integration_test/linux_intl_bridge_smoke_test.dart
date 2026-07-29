import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:live_hls_proxy/live_hls_proxy.dart';
import 'package:live_providers/live_providers.dart';
import 'package:nolive_app/src/app/platform/app_platform_capabilities.dart';
import 'package:nolive_app/src/app/runtime_bridges/hls_proxy_platform_adapter_impl.dart';
import 'package:nolive_app/src/app/runtime_bridges/linux_desktop_webview_adapter.dart';
import 'package:nolive_app/src/app/runtime_bridges/youtube_nsig_webview_solver.dart';

HlsProxyPlatformAdapterImpl _linuxAdapter() {
  final caps = AppPlatformCapabilities.current();
  expect(caps.isLinux, isTrue);
  expect(caps.supportsHeadlessWebView, isTrue);
  return HlsProxyPlatformAdapterImpl(
    platformCapabilities: caps,
    linuxCookieJar: LinuxDesktopCookieJar(),
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Linux Twitch WebPlaybackBridge path',
    (tester) async {
      if (!Platform.isLinux) return;
      final adapter = _linuxAdapter();
      final bridge = TwitchWebPlaybackBridge(
        platformAdapter: adapter,
        timeout: const Duration(seconds: 20),
        bootstrapScriptTimeout: const Duration(seconds: 12),
        webViewStartTimeout: const Duration(seconds: 15),
        // Avoid idle dispose during test.
        idleDisposeDelay: const Duration(hours: 1),
      );
      await bridge.warmUp().timeout(const Duration(seconds: 25));
      debugPrint('TW_WARMUP_OK');

      final twitch = TwitchProvider.live(
        playbackBootstrapResolver: (detail) => bridge.call(detail),
      );
      final rooms = await twitch.fetchRecommendRooms(page: 1);
      expect(rooms.items, isNotEmpty);
      final detail = await twitch.fetchRoomDetail(rooms.items.first.roomId);
      expect(detail.isLive, isTrue);
      final qualities = await twitch.fetchPlayQualities(detail);
      expect(qualities, isNotEmpty);
      final urls = await twitch.fetchPlayUrls(
        detail: detail,
        quality: qualities.first,
      );
      expect(urls, isNotEmpty);
      debugPrint(
        'TW_OK room=${detail.roomId} qualities=${qualities.length} urls=${urls.length}',
      );
      // Do not dispose WebView in harness — GTK close can stall tearDown.
      debugPrint('TW_SMOKE_DONE');
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  testWidgets(
    'Linux YouTube nsig-wired play path',
    (tester) async {
      if (!Platform.isLinux) return;
      final adapter = _linuxAdapter();
      final nsig = YouTubeWebViewNSigSolver(platformAdapter: adapter);
      final youtube = YouTubeProvider.live(nSigSolver: nsig);
      var rooms = await youtube.searchRooms('live gaming');
      if (rooms.items.isEmpty) {
        rooms = await youtube.fetchRecommendRooms(page: 1);
      }
      expect(rooms.items, isNotEmpty, reason: 'youtube no rooms');
      final detail = await youtube.fetchRoomDetail(rooms.items.first.roomId);
      final qualities = await youtube.fetchPlayQualities(detail);
      expect(qualities, isNotEmpty);
      final urls = await youtube.fetchPlayUrls(
        detail: detail,
        quality: qualities.first,
      );
      expect(urls, isNotEmpty);
      debugPrint(
        'YT_OK room=${detail.roomId} qualities=${qualities.length} urls=${urls.length}',
      );
      debugPrint('YT_SMOKE_DONE');
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  testWidgets(
    'Linux Chaturbate LL-HLS wrap path',
    (tester) async {
      if (!Platform.isLinux) return;
      final adapter = _linuxAdapter();
      final llhls = ChaturbateLlHlsProxy(platformAdapter: adapter);
      final cb = ChaturbateProvider.live();
      final rooms = await cb.fetchRecommendRooms(page: 1);
      expect(rooms.items, isNotEmpty);
      final detail = await cb.fetchRoomDetail(rooms.items.first.roomId);
      expect(detail.isLive, isTrue);
      final qualities = await cb.fetchPlayQualities(detail);
      expect(qualities, isNotEmpty);
      final rawUrls = await cb.fetchPlayUrls(
        detail: detail,
        quality: qualities.first,
      );
      expect(rawUrls, isNotEmpty);
      final wrapped = await llhls.wrapPlayUrls(
        roomId: detail.roomId,
        quality: qualities.first,
        playUrls: rawUrls,
      );
      expect(wrapped, isNotEmpty);
      final proxied = wrapped.any(
        (u) => u.url.contains('127.0.0.1') || u.url.contains('localhost'),
      );
      debugPrint(
        'CB_OK room=${detail.roomId} urls=${wrapped.length} proxied=$proxied',
      );
      debugPrint('CB_SMOKE_DONE');
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  testWidgets(
    'Linux Stripchat LL-HLS wrap path',
    (tester) async {
      if (!Platform.isLinux) return;
      final adapter = _linuxAdapter();
      final llhls = StripchatLlHlsProxy(
        platformAdapter: adapter,
        enablePdkeyFallback: true,
      );
      final sc = StripchatProvider.live();
      final rooms = await sc.fetchRecommendRooms(page: 1);
      expect(rooms.items, isNotEmpty, reason: 'stripchat recommend empty');
      final detail = await sc.fetchRoomDetail(rooms.items.first.roomId);
      expect(detail.isLive, isTrue);
      final qualities = await sc.fetchPlayQualities(detail);
      expect(qualities, isNotEmpty);
      final rawUrls = await sc.fetchPlayUrls(
        detail: detail,
        quality: qualities.first,
      );
      expect(rawUrls, isNotEmpty);
      final wrapped = await llhls.wrapPlayUrls(
        roomId: detail.roomId,
        quality: qualities.first,
        playUrls: rawUrls,
      );
      expect(wrapped, isNotEmpty);
      final proxied = wrapped.any(
        (u) => u.url.contains('127.0.0.1') || u.url.contains('localhost'),
      );
      debugPrint(
        'SC_OK room=${detail.roomId} urls=${wrapped.length} proxied=$proxied',
      );
      debugPrint('SC_SMOKE_DONE');
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
