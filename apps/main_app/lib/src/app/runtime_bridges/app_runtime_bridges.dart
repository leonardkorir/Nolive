import 'package:live_hls_proxy/live_hls_proxy.dart';
import 'package:live_providers/live_providers.dart';
import 'package:nolive_app/src/app/runtime_bridges/provider_room_detail_override.dart';
import 'package:nolive_app/src/app/runtime_bridges/youtube_nsig_webview_solver.dart';

class AppRuntimeBridges {
  const AppRuntimeBridges({
    required this.chaturbateLlHlsProxy,
    required this.stripchatLlHlsProxy,
    required this.roomDetailOverride,
    required this.twitchWebPlaybackBridge,
    required this.twitchAdGuardProxy,
    required this.youtubeNSigSolver,
  });

  final ChaturbateLlHlsProxy? chaturbateLlHlsProxy;
  final StripchatLlHlsProxy? stripchatLlHlsProxy;
  final ProviderRoomDetailOverride? roomDetailOverride;
  final TwitchWebPlaybackBridge? twitchWebPlaybackBridge;
  final TwitchAdGuardProxy? twitchAdGuardProxy;
  final YouTubeNSigSolver? youtubeNSigSolver;

  Future<void> dispose() async {
    final futures = <Future<void>>[
      if (twitchWebPlaybackBridge != null)
        twitchWebPlaybackBridge!
            .dispose()
            .timeout(const Duration(seconds: 3))
            .catchError((_) {}),
      if (twitchAdGuardProxy != null)
        twitchAdGuardProxy!
            .dispose()
            .timeout(const Duration(seconds: 3))
            .catchError((_) {}),
      if (youtubeNSigSolver is YouTubeWebViewNSigSolver)
        (youtubeNSigSolver as YouTubeWebViewNSigSolver)
            .dispose()
            .timeout(const Duration(seconds: 3))
            .catchError((_) {}),
      if (stripchatLlHlsProxy != null)
        stripchatLlHlsProxy!
            .dispose()
            .timeout(const Duration(seconds: 3))
            .catchError((_) {}),
      if (chaturbateLlHlsProxy != null)
        chaturbateLlHlsProxy!
            .dispose()
            .timeout(const Duration(seconds: 3))
            .catchError((_) {}),
    ];
    if (futures.isNotEmpty) {
      await Future.wait(futures);
    }
  }
}
