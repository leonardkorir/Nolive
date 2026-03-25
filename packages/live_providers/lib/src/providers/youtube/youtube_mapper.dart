import 'package:live_core/live_core.dart';

import 'youtube_hls_master_playlist_parser.dart';
import 'youtube_page_parser.dart';

class YouTubeMapper {
  const YouTubeMapper._();

  static LiveRoom mapSearchRoom(YouTubeSearchCandidate candidate) {
    final roomId =
        canonicalRoomIdFromOwnerProfileUrl(candidate.ownerProfileUrl) ??
            candidate.videoId;
    return LiveRoom(
      providerId: ProviderId.youtube.value,
      roomId: roomId,
      title: candidate.title,
      streamerName: candidate.streamerName,
      coverUrl: candidate.coverUrl,
      streamerAvatarUrl: candidate.streamerAvatarUrl,
      viewerCount: candidate.viewerCount,
      isLive: true,
    );
  }

  static LiveRoomDetail mapRoomDetail({
    required String requestedRoomId,
    required String resolvedVideoId,
    required Map<String, dynamic> playerResponse,
    required String sourcePageUrl,
    required String apiKey,
    YouTubeSearchCandidate? pageCandidate,
    Map<String, dynamic> playerClientContext = const {},
    String? playerRolloutToken,
    String? playerPoToken,
    YouTubeLiveChatBootstrap? liveChatBootstrap,
    Map<String, Object?> additionalMetadata = const {},
  }) {
    final videoDetails = _asMap(playerResponse['videoDetails']);
    final microformat = _asMap(
      _asMap(playerResponse['microformat'])['playerMicroformatRenderer'],
    );
    final liveBroadcastDetails = _asMap(microformat['liveBroadcastDetails']);
    final streamingData = _asMap(playerResponse['streamingData']);
    final playabilityStatus = _asMap(playerResponse['playabilityStatus']);
    final ownerProfileUrl = microformat['ownerProfileUrl']?.toString().trim();
    final resolvedRoomId = canonicalRoomId(
      requestedRoomId: requestedRoomId,
      resolvedVideoId: resolvedVideoId,
      ownerProfileUrl: ownerProfileUrl,
    );
    final viewerCount =
        pageCandidate?.viewerCount ?? _asInt(videoDetails['viewCount']);
    final playbackUnavailableReason =
        _playbackUnavailableReason(playabilityStatus);
    return LiveRoomDetail(
      providerId: ProviderId.youtube.value,
      roomId: resolvedRoomId,
      title: _firstNonEmpty([
        normalizeDisplayText(videoDetails['title']?.toString()),
        resolvedRoomId,
      ]),
      streamerName: _firstNonEmpty([
        normalizeDisplayText(videoDetails['author']?.toString()),
        'YouTube Live',
      ]),
      streamerAvatarUrl: pageCandidate?.streamerAvatarUrl,
      coverUrl: _lastThumbnailUrl(
          _asList(_asMap(microformat['thumbnail'])['thumbnails'])),
      areaName: normalizeDisplayText(microformat['category']?.toString()),
      description:
          normalizeDisplayText(videoDetails['shortDescription']?.toString()),
      sourceUrl: 'https://www.youtube.com/watch?v=$resolvedVideoId',
      startedAt: _asDateTime(liveBroadcastDetails['startTimestamp']),
      isLive: _isLive(playerResponse),
      viewerCount: viewerCount,
      danmakuToken: liveChatBootstrap != null && _isLive(playerResponse)
          ? {
              'apiKey': liveChatBootstrap.apiKey,
              'clientVersion': liveChatBootstrap.clientVersion,
              'continuation': liveChatBootstrap.continuation,
              'liveChatPageUrl': liveChatBootstrap.liveChatPageUrl,
              'visitorData': liveChatBootstrap.visitorData,
            }
          : null,
      metadata: {
        'apiKey': apiKey,
        'ownerProfileUrl': ownerProfileUrl,
        'resolvedVideoId': resolvedVideoId,
        'sourcePageUrl': sourcePageUrl,
        'hlsManifestUrl': streamingData['hlsManifestUrl']?.toString(),
        'playabilityStatus': playabilityStatus['status']?.toString(),
        'playabilityReason': playabilityStatus['reason']?.toString(),
        if ((playabilityStatus['status']?.toString().trim() ?? '') ==
            'LOGIN_REQUIRED')
          'requiresLogin': true,
        if ((playabilityStatus['reason']?.toString().toLowerCase() ?? '')
            .contains('not a bot'))
          'antiBotBlocked': true,
        if (playerClientContext.isNotEmpty)
          'playerClientContext': playerClientContext,
        if ((playerRolloutToken?.trim().isNotEmpty ?? false))
          'playerRolloutToken': playerRolloutToken!.trim(),
        if ((playerPoToken?.trim().isNotEmpty ?? false))
          'playerPoToken': playerPoToken!.trim(),
        if (liveChatBootstrap != null) ...{
          'liveChatContinuation': liveChatBootstrap.continuation,
          'liveChatPageUrl': liveChatBootstrap.liveChatPageUrl,
          'liveChatVisitorData': liveChatBootstrap.visitorData,
          'liveChatClientVersion': liveChatBootstrap.clientVersion,
        },
        if (playbackUnavailableReason != null)
          'playbackUnavailableReason': playbackUnavailableReason,
        ...additionalMetadata,
      },
    );
  }

  static List<LivePlayQuality> mapPlayQualitiesFromVariants({
    required List<YouTubeHlsVariant> variants,
    required String manifestUrl,
    required Map<String, String> headers,
  }) {
    final qualities = <LivePlayQuality>[
      LivePlayQuality(
        id: 'auto',
        label: 'Auto',
        isDefault: true,
        metadata: {
          'playlistUrl': manifestUrl,
          'headers': headers,
        },
      ),
    ];
    for (final variant in variants) {
      qualities.add(
        LivePlayQuality(
          id: variant.height?.toString() ?? variant.bandwidth.toString(),
          label: variant.label,
          sortOrder: variant.sortOrder,
          metadata: {
            'playlistUrl': variant.url,
            'headers': headers,
            'bandwidth': variant.bandwidth,
            'width': variant.width,
            'height': variant.height,
            'frameRate': variant.frameRate,
          },
        ),
      );
    }
    return qualities;
  }

  static List<LivePlayUrl> mapPlayUrls(
    LiveRoomDetail detail,
    LivePlayQuality quality,
  ) {
    final url = quality.metadata?['playlistUrl']?.toString().trim() ??
        detail.metadata?['hlsManifestUrl']?.toString().trim() ??
        '';
    if (url.isEmpty) {
      return const [];
    }
    return [
      LivePlayUrl(
        url: url,
        headers: _readHeaders(quality.metadata?['headers']),
        metadata: quality.metadata,
      ),
    ];
  }

  static String canonicalRoomId({
    required String requestedRoomId,
    required String resolvedVideoId,
    String? ownerProfileUrl,
  }) {
    final fromOwner = canonicalRoomIdFromOwnerProfileUrl(ownerProfileUrl);
    if (fromOwner != null) {
      return fromOwner;
    }
    final normalizedRequested = normalizeRequestedRoomId(requestedRoomId);
    if (normalizedRequested != null) {
      return normalizedRequested;
    }
    return resolvedVideoId;
  }

  static String? normalizeRequestedRoomId(String requestedRoomId) {
    final normalized = requestedRoomId.trim().replaceFirst(RegExp(r'^/+'), '');
    if (normalized.isEmpty) {
      return null;
    }
    if (normalized.startsWith('@')) {
      return normalized.endsWith('/live') ? normalized : '$normalized/live';
    }
    final match = RegExp(r'^(channel|c|user)/([^/]+)(/live)?$').firstMatch(
      normalized,
    );
    if (match == null) {
      return null;
    }
    return '${match.group(1)}/${match.group(2)}/live';
  }

  static String? canonicalRoomIdFromOwnerProfileUrl(String? ownerProfileUrl) {
    final normalized = ownerProfileUrl?.trim() ?? '';
    if (normalized.isEmpty) {
      return null;
    }
    final path = Uri.tryParse(
          normalized.startsWith('http')
              ? normalized
              : 'https://www.youtube.com$normalized',
        )?.path ??
        normalized;
    final trimmed = path.replaceFirst(RegExp(r'^/+'), '').trim();
    if (trimmed.isEmpty) {
      return null;
    }
    if (trimmed.startsWith('@')) {
      final handle = trimmed.split('/').first;
      return '$handle/live';
    }
    final segments = trimmed.split('/');
    if (segments.length >= 2 &&
        const {'channel', 'c', 'user'}.contains(segments.first)) {
      return '${segments.first}/${segments[1]}/live';
    }
    return null;
  }

  static bool _isLive(Map<String, dynamic> playerResponse) {
    final videoDetails = _asMap(playerResponse['videoDetails']);
    final microformat = _asMap(
      _asMap(playerResponse['microformat'])['playerMicroformatRenderer'],
    );
    final liveBroadcastDetails = _asMap(microformat['liveBroadcastDetails']);
    return liveBroadcastDetails['isLiveNow'] == true ||
        videoDetails['isLive'] == true ||
        videoDetails['isLiveContent'] == true;
  }

  static String? _playbackUnavailableReason(
    Map<String, dynamic> playabilityStatus,
  ) {
    final status = playabilityStatus['status']?.toString().trim() ?? '';
    if (status.isEmpty || status == 'OK') {
      return null;
    }
    final reason = playabilityStatus['reason']?.toString().trim() ?? '';
    final normalizedReason = reason.toLowerCase();
    if (status == 'LOGIN_REQUIRED' && normalizedReason.contains('not a bot')) {
      return 'YouTube 当前触发风控校验，需要有效浏览器登录态 / Cookie 才能继续拿到可播流。';
    }
    if (status == 'LOGIN_REQUIRED') {
      return 'YouTube 当前需要额外登录态，匿名 provider 暂时无法拿到可播流。';
    }
    if (reason.isNotEmpty) {
      return 'YouTube 当前未返回可播 HLS：$reason';
    }
    return 'YouTube 当前播放状态为 $status，未返回可播 HLS。';
  }

  static Map<String, String> _readHeaders(Object? raw) {
    if (raw is Map<String, String>) {
      return raw;
    }
    if (raw is Map) {
      final headers = <String, String>{};
      for (final entry in raw.entries) {
        final key = entry.key.toString().trim();
        final value = entry.value?.toString().trim() ?? '';
        if (key.isEmpty || value.isEmpty) {
          continue;
        }
        headers[key] = value;
      }
      return headers;
    }
    return const {};
  }

  static String? _lastThumbnailUrl(List<dynamic> thumbnails) {
    for (var index = thumbnails.length - 1; index >= 0; index -= 1) {
      final url = _asMap(thumbnails[index])['url']?.toString().trim() ?? '';
      if (url.isNotEmpty) {
        return url;
      }
    }
    return null;
  }

  static String _firstNonEmpty(List<String?> values) {
    for (final value in values) {
      final normalized = value?.trim() ?? '';
      if (normalized.isNotEmpty) {
        return normalized;
      }
    }
    return '';
  }

  static DateTime? _asDateTime(Object? value) {
    final raw = value?.toString().trim() ?? '';
    if (raw.isEmpty) {
      return null;
    }
    return DateTime.tryParse(raw)?.toLocal();
  }

  static int? _asInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '');
  }

  static Map<String, dynamic> _asMap(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.cast<String, dynamic>();
    }
    return const {};
  }

  static List<dynamic> _asList(Object? value) {
    if (value is List) {
      return value;
    }
    return const [];
  }
}
