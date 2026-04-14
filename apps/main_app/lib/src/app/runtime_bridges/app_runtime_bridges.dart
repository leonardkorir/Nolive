import 'package:nolive_app/src/app/runtime_bridges/provider_room_detail_override.dart';
import 'package:nolive_app/src/app/runtime_bridges/twitch/twitch_ad_guard_proxy.dart';
import 'package:nolive_app/src/app/runtime_bridges/twitch/twitch_web_playback_bridge.dart';

class AppRuntimeBridges {
  const AppRuntimeBridges({
    required this.roomDetailOverride,
    required this.twitchWebPlaybackBridge,
    required this.twitchAdGuardProxy,
    required this.requireChaturbateCookiePreflight,
  });

  final ProviderRoomDetailOverride? roomDetailOverride;
  final TwitchWebPlaybackBridge? twitchWebPlaybackBridge;
  final TwitchAdGuardProxy? twitchAdGuardProxy;
  final bool requireChaturbateCookiePreflight;
}
