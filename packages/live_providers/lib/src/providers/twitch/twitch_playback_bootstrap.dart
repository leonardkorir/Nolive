import 'package:live_core/live_core.dart';

class TwitchPlaybackBootstrap {
  const TwitchPlaybackBootstrap({
    required this.roomId,
    required this.signature,
    required this.tokenValue,
    required this.deviceId,
    required this.clientSessionId,
    this.clientIntegrity = '',
    this.sourceUrl = '',
    this.masterPlaylistUrl = '',
    this.cookie = '',
    this.userAgent = '',
  });

  final String roomId;
  final String signature;
  final String tokenValue;
  final String deviceId;
  final String clientSessionId;
  final String clientIntegrity;
  final String sourceUrl;
  final String masterPlaylistUrl;
  final String cookie;
  final String userAgent;

  bool get isUsable =>
      roomId.trim().isNotEmpty &&
      signature.trim().isNotEmpty &&
      tokenValue.trim().isNotEmpty;
}

typedef TwitchPlaybackBootstrapResolver = Future<TwitchPlaybackBootstrap?>
    Function(LiveRoomDetail detail);
