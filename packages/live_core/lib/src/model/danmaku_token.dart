import 'model_equality.dart';

sealed class DanmakuToken {
  const DanmakuToken();

  List<Object?> get props;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other.runtimeType == runtimeType &&
            modelListEquals((other as DanmakuToken).props, props);
  }

  @override
  int get hashCode => Object.hash(runtimeType, modelListHash(props));
}

final class PreviewDanmakuToken extends DanmakuToken {
  const PreviewDanmakuToken();

  @override
  List<Object?> get props => const [];
}

final class UnavailableDanmakuToken extends DanmakuToken {
  const UnavailableDanmakuToken({
    required this.reason,
    this.cause,
  });

  final String reason;
  final String? cause;

  @override
  List<Object?> get props => [reason, cause];
}

final class BilibiliDanmakuToken extends DanmakuToken {
  const BilibiliDanmakuToken({
    required this.roomId,
    required this.uid,
    required this.token,
    required this.serverHost,
    required this.buvid,
    required this.cookie,
  });

  final int roomId;
  final int uid;
  final String token;
  final String serverHost;
  final String buvid;
  final String cookie;

  @override
  List<Object?> get props => [roomId, uid, token, serverHost, buvid, cookie];
}

final class DouyinDanmakuToken extends DanmakuToken {
  const DouyinDanmakuToken({
    required this.webRid,
    required this.roomId,
    required this.cookie,
    required this.userUniqueId,
    this.websocketUris = const [],
  });

  final String webRid;
  final String roomId;
  final String cookie;
  final String userUniqueId;
  final List<Uri> websocketUris;

  @override
  List<Object?> get props =>
      [webRid, roomId, cookie, userUniqueId, websocketUris];
}

final class DouyuDanmakuToken extends DanmakuToken {
  const DouyuDanmakuToken({
    required this.roomId,
    this.socketUrls = const [],
  });

  final String roomId;
  final List<String> socketUrls;

  @override
  List<Object?> get props => [roomId, socketUrls];
}

final class HuyaDanmakuToken extends DanmakuToken {
  const HuyaDanmakuToken({
    required this.ayyuid,
    required this.topSid,
    required this.subSid,
  });

  final int ayyuid;
  final int topSid;
  final int subSid;

  @override
  List<Object?> get props => [ayyuid, topSid, subSid];
}

final class TwitchDanmakuToken extends DanmakuToken {
  const TwitchDanmakuToken({
    required this.roomId,
    this.oauthToken = '',
  });

  final String roomId;
  final String oauthToken;

  @override
  List<Object?> get props => [roomId, oauthToken];
}

final class YouTubeDanmakuToken extends DanmakuToken {
  const YouTubeDanmakuToken({
    required this.apiKey,
    required this.clientVersion,
    required this.continuation,
    required this.liveChatPageUrl,
    required this.visitorData,
  });

  final String apiKey;
  final String clientVersion;
  final String continuation;
  final String liveChatPageUrl;
  final String visitorData;

  @override
  List<Object?> get props => [
        apiKey,
        clientVersion,
        continuation,
        liveChatPageUrl,
        visitorData,
      ];
}

final class StripchatDanmakuToken extends DanmakuToken {
  const StripchatDanmakuToken({
    required this.modelId,
    required this.websocketUrl,
    required this.jwt,
    this.historyUrl = '',
    this.requestCookie = '',
    this.roomUrl = '',
  });

  final String modelId;
  final String websocketUrl;
  final String jwt;
  final String historyUrl;
  final String requestCookie;
  final String roomUrl;

  @override
  List<Object?> get props => [
        modelId,
        websocketUrl,
        jwt,
        historyUrl,
        requestCookie,
        roomUrl,
      ];
}

final class ChaturbateDanmakuToken extends DanmakuToken {
  const ChaturbateDanmakuToken({
    required this.roomId,
    required this.roomUid,
    required this.broadcasterUid,
    required this.csrfToken,
    required this.backend,
    this.host,
    this.restHost,
    this.fallbackHosts = const [],
  });

  final String roomId;
  final String roomUid;
  final String broadcasterUid;
  final String csrfToken;
  final String backend;
  final String? host;
  final String? restHost;
  final List<String> fallbackHosts;

  @override
  List<Object?> get props => [
        roomId,
        roomUid,
        broadcasterUid,
        csrfToken,
        backend,
        host,
        restHost,
        fallbackHosts,
      ];
}
