import 'package:nolive_app/src/app/runtime_bridges/chaturbate/chaturbate_llhls_proxy.dart';
import 'package:nolive_app/src/app/runtime_bridges/provider_room_detail_override.dart';
import 'package:nolive_app/src/app/runtime_bridges/stripchat/stripchat_llhls_proxy.dart';
import 'package:nolive_app/src/app/runtime_bridges/twitch/twitch_ad_guard_proxy.dart';
import 'package:nolive_app/src/app/runtime_bridges/twitch/twitch_web_playback_bridge.dart';

class AppRuntimeBridges {
  const AppRuntimeBridges({
    required this.chaturbateLlHlsProxy,
    required this.stripchatLlHlsProxy,
    required this.roomDetailOverride,
    required this.twitchWebPlaybackBridge,
    required this.twitchAdGuardProxy,
    required this.requireChaturbateCookiePreflight,
  });

  final ChaturbateLlHlsProxy? chaturbateLlHlsProxy;
  final StripchatLlHlsProxy? stripchatLlHlsProxy;
  final ProviderRoomDetailOverride? roomDetailOverride;
  final TwitchWebPlaybackBridge? twitchWebPlaybackBridge;
  final TwitchAdGuardProxy? twitchAdGuardProxy;
  final bool requireChaturbateCookiePreflight;

  Future<void> dispose() async {
    final futures = <Future<void>>[
      if (twitchWebPlaybackBridge != null)
        twitchWebPlaybackBridge!.dispose().timeout(const Duration(seconds: 3)).catchError((_) {}),
      if (twitchAdGuardProxy != null)
        twitchAdGuardProxy!.dispose().timeout(const Duration(seconds: 3)).catchError((_) {}),
      if (stripchatLlHlsProxy != null)
        stripchatLlHlsProxy!.dispose().timeout(const Duration(seconds: 3)).catchError((_) {}),
      if (chaturbateLlHlsProxy != null)
        chaturbateLlHlsProxy!.dispose().timeout(const Duration(seconds: 3)).catchError((_) {}),
    ];
    if (futures.isNotEmpty) {
      await Future.wait(futures);
    }
  }
}
