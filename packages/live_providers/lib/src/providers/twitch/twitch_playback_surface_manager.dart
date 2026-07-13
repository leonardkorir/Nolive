import 'dart:async';
import 'dart:math';

import 'package:live_core/live_core.dart';

import '../provider_runtime_support.dart';

import 'twitch_api_client.dart';
import 'twitch_graphql_client.dart';
import 'twitch_hls_master_playlist_parser.dart';
import 'twitch_playback_bootstrap.dart';
import 'twitch_playback_manifest.dart';

class TwitchPlayerSurface {
  const TwitchPlayerSurface({
    required this.playerType,
    required this.platform,
    required this.priority,
    required this.lineLabel,
  });

  final String playerType;
  final String platform;
  final int priority;
  final String lineLabel;
}

class TwitchPlaybackSurfaceCandidate {
  const TwitchPlaybackSurfaceCandidate({
    required this.playerType,
    required this.platform,
    required this.lineLabel,
    required this.masterPlaylistUrl,
    required this.headers,
    required this.variants,
  });

  final String playerType;
  final String platform;
  final String lineLabel;
  final String masterPlaylistUrl;
  final Map<String, String> headers;
  final List<TwitchHlsVariant> variants;

  int get priority {
    final surface = TwitchPlaybackSurfaceManager.playerSurfaces.firstWhere(
      (item) => item.playerType == playerType && item.platform == platform,
      orElse: () => TwitchPlaybackSurfaceManager.playerSurfaces[2],
    );
    return surface.priority;
  }
}

class TwitchPlaybackGroupAccumulator {
  TwitchPlaybackGroupAccumulator({
    required this.id,
    required this.label,
    required this.sortOrder,
    required this.bandwidth,
    required this.width,
    required this.height,
    required this.frameRate,
    required this.codecs,
  });

  final String id;
  final String label;
  final int sortOrder;
  final int bandwidth;
  final int? width;
  final int? height;
  final double? frameRate;
  final String? codecs;
  final List<TwitchPlaybackCandidate> candidates = <TwitchPlaybackCandidate>[];
}

class TwitchPlaybackSurfaceManager {
  TwitchPlaybackSurfaceManager({
    required TwitchApiClient apiClient,
    required TwitchGraphQlClient graphQlClient,
    required TwitchHlsMasterPlaylistParser hlsMasterPlaylistParser,
    required Duration alternateSurfaceTimeout,
    required ProviderBrowserProfile browserProfile,
    required String supportedCodecs,
    required String clientIntegrity,
  }) : _apiClient = apiClient,
       _graphQlClient = graphQlClient,
       _hlsMasterPlaylistParser = hlsMasterPlaylistParser,
       _alternateSurfaceTimeout = alternateSurfaceTimeout,
       _browserProfile = browserProfile,
       _supportedCodecs = supportedCodecs,
       _clientIntegrity = clientIntegrity;

  final TwitchApiClient _apiClient;
  final TwitchGraphQlClient _graphQlClient;
  final TwitchHlsMasterPlaylistParser _hlsMasterPlaylistParser;
  final Duration _alternateSurfaceTimeout;
  final ProviderBrowserProfile _browserProfile;
  final String _supportedCodecs;
  final String _clientIntegrity;

  static const String _defaultAcmb =
      'eyJBcHBWZXJzaW9uIjoiNTZiZDRjMDAtNTk1Ny00ODc3LThlNzQtNGQxOTM0NDZi'
      'MjBiIiwiQ2xpZW50QXBwIjoid2ViIn0=';

  static const Duration _alternateSurfacePreferredGrace = Duration(
    milliseconds: 250,
  );

  static const List<TwitchPlayerSurface> playerSurfaces = [
    TwitchPlayerSurface(
      playerType: 'embed',
      platform: 'web',
      priority: 2,
      lineLabel: '备用 Embed',
    ),
    TwitchPlayerSurface(
      playerType: 'site',
      platform: 'web',
      priority: 1,
      lineLabel: '备用 Site',
    ),
    TwitchPlayerSurface(
      playerType: 'popout',
      platform: 'web',
      priority: 0,
      lineLabel: '默认 Popout',
    ),
    TwitchPlayerSurface(
      playerType: 'autoplay',
      platform: 'android',
      priority: 3,
      lineLabel: '备用 Autoplay',
    ),
  ];

  Future<List<TwitchPlaybackSurfaceCandidate>> loadPlaybackSurfaceCandidates({
    required String roomId,
    required TwitchPlaybackBootstrap bootstrap,
  }) async {
    final preferredRoomId = bootstrap.roomId.trim().isNotEmpty
        ? bootstrap.roomId.trim().toLowerCase()
        : roomId;
    final preferredHeaders = _buildPlaybackHeaders(
      roomId: preferredRoomId,
      sourceUrl: bootstrap.sourceUrl,
      cookie: bootstrap.cookie,
      userAgent: bootstrap.userAgent,
    );
    final preferredSessionId = bootstrap.clientSessionId.trim().isNotEmpty
        ? bootstrap.clientSessionId.trim()
        : _randomHex(32);
    final preferredMasterPlaylistUrl =
        bootstrap.masterPlaylistUrl.trim().isNotEmpty
        ? bootstrap.masterPlaylistUrl.trim()
        : _buildHlsPlaylistUrl(
            roomId: preferredRoomId,
            sessionId: preferredSessionId,
            signature: bootstrap.signature,
            tokenValue: bootstrap.tokenValue,
            platform: 'web',
          );
    final futures = <Future<TwitchPlaybackSurfaceCandidate?>>[
      _loadPlaybackSurfaceCandidate(
        roomId: preferredRoomId,
        surface: playerSurfaces[0],
        contextBootstrap: bootstrap,
      ).timeout(_alternateSurfaceTimeout, onTimeout: () => null),
      _loadPlaybackSurfaceCandidate(
        roomId: preferredRoomId,
        surface: playerSurfaces[1],
        contextBootstrap: bootstrap,
      ).timeout(_alternateSurfaceTimeout, onTimeout: () => null),
      _loadPlaybackSurfaceCandidate(
        roomId: preferredRoomId,
        surface: playerSurfaces[3],
        contextBootstrap: bootstrap,
      ).timeout(_alternateSurfaceTimeout, onTimeout: () => null),
    ];
    final preferredVariants = _hlsMasterPlaylistParser.parse(
      playlistUrl: preferredMasterPlaylistUrl,
      source: await _withRequestTimeout(
        _apiClient.fetchText(
          preferredMasterPlaylistUrl,
          headers: preferredHeaders,
        ),
        context: 'preferred playback playlist',
      ),
    );
    final candidates = <TwitchPlaybackSurfaceCandidate>[
      if (preferredVariants.isNotEmpty)
        TwitchPlaybackSurfaceCandidate(
          playerType: 'popout',
          platform: 'web',
          lineLabel: playerSurfaces[2].lineLabel,
          masterPlaylistUrl: preferredMasterPlaylistUrl,
          headers: preferredHeaders,
          variants: preferredVariants,
        ),
    ];
    final alternates = await Future.wait(
      futures.map(
        (future) => future.timeout(
          candidates.isNotEmpty
              ? _alternateSurfacePreferredGrace
              : _alternateSurfaceTimeout,
          onTimeout: () => null,
        ),
      ),
    );
    for (final item in alternates) {
      if (item == null || item.variants.isEmpty) {
        continue;
      }
      candidates.add(item);
    }
    candidates.sort((left, right) => left.priority.compareTo(right.priority));
    return candidates;
  }

  Future<TwitchPlaybackSurfaceCandidate?> _loadPlaybackSurfaceCandidate({
    required String roomId,
    required TwitchPlayerSurface surface,
    required TwitchPlaybackBootstrap contextBootstrap,
  }) async {
    try {
      final bootstrap = await _graphQlClient.requestPlaybackBootstrap(
        roomId: roomId,
        playerType: surface.playerType,
        platform: surface.platform,
        contextBootstrap: contextBootstrap,
        clientIntegrity: _clientIntegrity,
      );
      final resolvedRoomId = bootstrap.roomId.trim().isNotEmpty
          ? bootstrap.roomId.trim().toLowerCase()
          : roomId;
      final sessionId = bootstrap.clientSessionId.trim().isNotEmpty
          ? bootstrap.clientSessionId.trim()
          : _randomHex(32);
      final masterPlaylistUrl = _buildHlsPlaylistUrl(
        roomId: resolvedRoomId,
        sessionId: sessionId,
        signature: bootstrap.signature,
        tokenValue: bootstrap.tokenValue,
        platform: surface.platform,
      );
      final headers = _buildPlaybackHeaders(
        roomId: resolvedRoomId,
        sourceUrl: bootstrap.sourceUrl,
        cookie: bootstrap.cookie,
        userAgent: bootstrap.userAgent,
      );
      final playlistText = await _withRequestTimeout(
        _apiClient.fetchText(masterPlaylistUrl, headers: headers),
        context: '${surface.playerType} playback playlist',
      );
      return TwitchPlaybackSurfaceCandidate(
        playerType: surface.playerType,
        platform: surface.platform,
        lineLabel: surface.lineLabel,
        masterPlaylistUrl: masterPlaylistUrl,
        headers: headers,
        variants: _hlsMasterPlaylistParser.parse(
          playlistUrl: masterPlaylistUrl,
          source: playlistText,
        ),
      );
    } catch (error, stackTrace) {
      reportProviderDiagnostic(
        providerId: ProviderId.twitch,
        scope: 'twitch playback surface candidate',
        message: 'failed for surface ${surface.playerType}/${surface.platform}',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  List<TwitchPlaybackQualityGroup> mergeQualityGroups(
    List<TwitchPlaybackSurfaceCandidate> playbackSurfaces,
  ) {
    final groups = <String, TwitchPlaybackGroupAccumulator>{};
    for (final surface in playbackSurfaces) {
      for (final variant in surface.variants) {
        final key = _groupKeyForVariant(variant);
        final group = groups.putIfAbsent(
          key,
          () => TwitchPlaybackGroupAccumulator(
            id: key,
            label: variant.label,
            sortOrder: variant.sortOrder,
            bandwidth: variant.bandwidth,
            width: variant.width,
            height: variant.height,
            frameRate: variant.frameRate,
            codecs: variant.codecs,
          ),
        );
        final candidate = TwitchPlaybackCandidate(
          playlistUrl: variant.url,
          headers: surface.headers,
          playerType: surface.playerType,
          platform: surface.platform,
          lineLabel: surface.lineLabel,
          source: variant.source,
          bandwidth: variant.bandwidth,
          width: variant.width,
          height: variant.height,
          frameRate: variant.frameRate,
          codecs: variant.codecs,
        );
        if (!group.candidates.any(
          (item) =>
              item.playlistUrl == candidate.playlistUrl &&
              item.playerType == candidate.playerType,
        )) {
          group.candidates.add(candidate);
        }
      }
    }
    final results = groups.values
        .map(
          (group) => TwitchPlaybackQualityGroup(
            id: group.id,
            label: group.label,
            sortOrder: group.sortOrder,
            bandwidth: group.bandwidth,
            width: group.width,
            height: group.height,
            frameRate: group.frameRate,
            codecs: group.codecs,
            candidates: group.candidates,
          ),
        )
        .toList(growable: false);
    results.sort((left, right) => right.sortOrder.compareTo(left.sortOrder));
    return results;
  }

  String _buildHlsPlaylistUrl({
    required String roomId,
    required String sessionId,
    required String signature,
    required String tokenValue,
    String platform = 'web',
  }) {
    return Uri.https('usher.ttvnw.net', '/api/v2/channel/hls/$roomId.m3u8', {
      'acmb': _defaultAcmb,
      'allow_source': 'true',
      'browser_family': _browserProfile.browserName.toLowerCase(),
      'browser_version': _browserProfile.browserVersion,
      'cdm': 'wv',
      'enable_score': 'true',
      'fast_bread': 'true',
      'include_unavailable': 'true',
      'lang': 'zh-cn',
      'multigroup_video': 'false',
      'os_name': _browserProfile.osName,
      'os_version': _browserProfile.osVersion.isEmpty
          ? 'undefined'
          : _browserProfile.osVersion,
      'p': '${Random().nextInt(900000) + 100000}',
      'platform': platform,
      'play_session_id': sessionId,
      'player_backend': 'mediaplayer',
      'player_version': '1.50.0-rc.4',
      'playlist_include_framerate': 'true',
      'reassignments_supported': 'true',
      'sig': signature,
      'supported_codecs': _supportedCodecs,
      'token': tokenValue,
      'transcode_mode': 'cbr_v1',
    }).toString();
  }

  Map<String, String> _buildPlaybackHeaders({
    required String roomId,
    String? sourceUrl,
    String? cookie,
    String? userAgent,
  }) {
    final headers = <String, String>{
      'accept':
          'application/x-mpegURL, application/vnd.apple.mpegurl, '
          'application/json, text/plain',
      'referer': sourceUrl?.trim().isNotEmpty == true
          ? sourceUrl!.trim()
          : 'https://www.twitch.tv/$roomId',
      'user-agent': userAgent?.trim().isNotEmpty == true
          ? userAgent!.trim()
          : _browserProfile.userAgent,
    };
    final normalizedCookie = cookie?.trim() ?? '';
    if (normalizedCookie.isNotEmpty) {
      headers['cookie'] = normalizedCookie;
    }
    return headers;
  }

  String _groupKeyForVariant(TwitchHlsVariant variant) {
    final stableVariantId = variant.stableVariantId?.trim() ?? '';
    if (stableVariantId.isNotEmpty) {
      return stableVariantId;
    }
    final height = variant.height;
    if (height != null && height > 0) {
      final roundedFrameRate = variant.frameRate?.round() ?? 0;
      return roundedFrameRate > 0
          ? '${height}p$roundedFrameRate'
          : '${height}p';
    }
    return variant.label.trim().isNotEmpty
        ? variant.label.trim()
        : variant.bandwidth.toString();
  }

  String _randomHex(int length) {
    final buffer = StringBuffer();
    final random = Random();
    while (buffer.length < length) {
      buffer.write(random.nextInt(16).toRadixString(16));
    }
    return buffer.toString().substring(0, length);
  }

  Future<T> _withRequestTimeout<T>(
    Future<T> future, {
    required String context,
  }) async {
    try {
      return await future.timeout(_alternateSurfaceTimeout);
    } on TimeoutException {
      throw ProviderParseException(
        providerId: ProviderId.twitch,
        message: 'Twitch $context 请求超时。',
      );
    }
  }
}
