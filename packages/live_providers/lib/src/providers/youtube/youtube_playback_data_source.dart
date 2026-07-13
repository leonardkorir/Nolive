import 'dart:async';

import 'package:live_core/live_core.dart';

import '../provider_json.dart';
import '../provider_runtime_support.dart';
import 'youtube_api_client.dart';
import 'youtube_decipher_service.dart';
import 'youtube_hls_master_playlist_parser.dart';
import 'youtube_mapper.dart';
import 'youtube_page_parser.dart';
import 'youtube_playback_extractor.dart';
import 'youtube_playback_source.dart';

class YouTubePlaybackDataSource {
  YouTubePlaybackDataSource({
    required YouTubeApiClient apiClient,
    YouTubeHlsMasterPlaylistParser hlsMasterPlaylistParser =
        const YouTubeHlsMasterPlaylistParser(),
    YouTubeNSigSolver? nSigSolver,
  }) : _apiClient = apiClient,
       _hlsMasterPlaylistParser = hlsMasterPlaylistParser,
       _decipherService = YouTubeDecipherService(nSigSolver: nSigSolver);

  final YouTubeApiClient _apiClient;
  final YouTubeHlsMasterPlaylistParser _hlsMasterPlaylistParser;
  final YouTubeDecipherService _decipherService;

  final Map<String, List<YouTubeHlsVariant>> _hlsVariantCache =
      <String, List<YouTubeHlsVariant>>{};
  final Map<String, bool> _hlsUsabilityCache = <String, bool>{};
  static const int _maxHlsCacheEntries = 64;

  static const List<YouTubePlayerClientProfile> _playbackProfiles = [
    YouTubePlayerClientProfile.streamlinkAndroid,
    YouTubePlayerClientProfile.webSafari,
    YouTubePlayerClientProfile.mweb,
    YouTubePlayerClientProfile.ios,
    YouTubePlayerClientProfile.web,
  ];

  static const String _playbackSourcesMetadataKey = 'playbackSources';
  static const String _playbackAudioSourcesMetadataKey = 'playbackAudioSources';

  Future<List<LivePlayQuality>> fetchPlayQualities(
    LiveRoomDetail detail,
  ) async {
    final playbackSources = _readPlaybackSources(detail);
    final allHlsSources = playbackSources.where((item) => item.isHls).toList();
    final hlsSources = await _selectUsableHlsSources(allHlsSources);
    for (final source in hlsSources) {
      try {
        final variants = await _loadHlsVariants(source);
        if (variants.isEmpty) {
          continue;
        }
        return YouTubeMapper.mapPlayQualitiesFromVariants(
          variants: variants,
          manifestUrl: source.url,
          headers: source.headers,
        );
      } catch (error, stackTrace) {
        reportProviderDiagnostic(
          providerId: ProviderId.youtube,
          scope: 'youtube HLS quality probe',
          message: 'failed for source=${source.url}',
          error: error,
          stackTrace: stackTrace,
        );
        continue;
      }
    }

    for (final source in allHlsSources) {
      try {
        final variants = await _loadHlsVariants(source);
        if (variants.isEmpty) {
          continue;
        }
        return YouTubeMapper.mapPlayQualitiesFromVariants(
          variants: variants,
          manifestUrl: source.url,
          headers: source.headers,
        );
      } catch (error, stackTrace) {
        reportProviderDiagnostic(
          providerId: ProviderId.youtube,
          scope: 'youtube HLS quality fallback probe',
          message: 'failed for source=${source.url}',
          error: error,
          stackTrace: stackTrace,
        );
        continue;
      }
    }

    final dashSources = playbackSources.where((item) => item.isDash).toList();
    if (dashSources.isNotEmpty) {
      return [
        LivePlayQuality(
          id: 'auto',
          label: 'Auto',
          isDefault: true,
          metadata: {'playbackMode': 'dash'},
        ),
      ];
    }

    final manifestUrl = await resolveManifestUrl(detail);
    if (manifestUrl.isEmpty) {
      return const [];
    }
    final sourcePageUrl =
        detail.metadata?['sourcePageUrl']?.toString().trim() ??
        detail.sourceUrl?.trim() ??
        'https://www.youtube.com/';
    final headers = _buildLegacyPlaybackHeaders(sourcePageUrl);
    final playlistText = await _apiClient.fetchText(
      manifestUrl,
      headers: headers,
    );
    final variants = _hlsMasterPlaylistParser.parse(
      playlistUrl: manifestUrl,
      source: playlistText,
    );
    return YouTubeMapper.mapPlayQualitiesFromVariants(
      variants: variants,
      manifestUrl: manifestUrl,
      headers: headers,
    );
  }

  Future<List<LivePlayUrl>> fetchPlayUrls({
    required LiveRoomDetail detail,
    required LivePlayQuality quality,
  }) async {
    final playbackSources = _readPlaybackSources(detail);
    final playbackAudioSources = _readPlaybackAudioSources(detail);
    if (playbackSources.isEmpty) {
      return YouTubeMapper.mapPlayUrls(detail, quality);
    }

    final mode = quality.metadata?['playbackMode']?.toString().trim() ?? '';
    final urls = <LivePlayUrl>[];
    final seen = <String>{};
    final allHlsSources = playbackSources.where((item) => item.isHls).toList();
    final usableHlsSources = await _selectUsableHlsSources(allHlsSources);
    final hlsSources = usableHlsSources.isNotEmpty
        ? usableHlsSources
        : allHlsSources;

    if (mode != 'direct' && mode != 'dash') {
      if (quality.id == 'auto') {
        for (final source in hlsSources) {
          _appendPlayUrl(
            urls,
            seen: seen,
            candidate: LivePlayUrl(
              url: source.url,
              headers: source.headers,
              lineLabel: source.lineLabel,
              metadata: source.toMetadata(),
            ),
          );
        }
      } else {
        for (final source in hlsSources) {
          try {
            final variant = await _selectHlsVariantForQuality(
              source: source,
              quality: quality,
            );
            if (variant == null) {
              continue;
            }
            final playerJsUrl =
                detail.metadata?['playerJsUrl']?.toString() ?? '';
            var decryptedVariantUrl = variant.url;
            var decryptedAudioUrl = variant.audioUrl?.trim() ?? '';
            if (playerJsUrl.isNotEmpty) {
              try {
                decryptedVariantUrl = await _decipherService.decryptUrl(
                  variant.url,
                  playerJsUrl: playerJsUrl,
                  apiClient: _apiClient,
                );
              } catch (error, stackTrace) {
                reportProviderDiagnostic(
                  providerId: ProviderId.youtube,
                  scope: 'youtube HLS variant video decryption',
                  message: 'failed for variant=${variant.url}',
                  error: error,
                  stackTrace: stackTrace,
                );
              }
              if (decryptedAudioUrl.isNotEmpty) {
                try {
                  decryptedAudioUrl = await _decipherService.decryptUrl(
                    decryptedAudioUrl,
                    playerJsUrl: playerJsUrl,
                    apiClient: _apiClient,
                  );
                } catch (error, stackTrace) {
                  reportProviderDiagnostic(
                    providerId: ProviderId.youtube,
                    scope: 'youtube HLS variant audio decryption',
                    message: 'failed for audio=$decryptedAudioUrl',
                    error: error,
                    stackTrace: stackTrace,
                  );
                }
              }
            }
            _appendPlayUrl(
              urls,
              seen: seen,
              candidate: LivePlayUrl(
                url: decryptedVariantUrl,
                headers: source.headers,
                lineLabel: source.lineLabel,
                metadata: {
                  ...source.toMetadata(),
                  'qualityId': quality.id,
                  'qualityLabel': quality.label,
                  'hlsBitrate': variant.bandwidth.toString(),
                  'resolvedVariantLabel': variant.label,
                  'resolvedVariantUrl': decryptedVariantUrl,
                  if (decryptedAudioUrl.isNotEmpty) ...{
                    'resolvedAudioVariantUrl': decryptedAudioUrl,
                    'audioUrl': decryptedAudioUrl,
                    'audioHeaders': source.headers,
                    'audioLineLabel': '${source.lineLabel} Audio',
                    if (variant.audioAttributes['TYPE'] != null)
                      'audioMimeType': 'application/x-mpegURL',
                  },
                },
              ),
            );
          } catch (error, stackTrace) {
            reportProviderDiagnostic(
              providerId: ProviderId.youtube,
              scope: 'youtube HLS play url resolve',
              message: 'failed for source=${source.url} quality=${quality.id}',
              error: error,
              stackTrace: stackTrace,
            );
            continue;
          }
        }
      }
    }

    if (mode == 'direct') {
      final directSources = playbackSources
          .where((item) => item.isDirect)
          .toList();
      for (final source in _selectDirectSourcesForQuality(
        sources: directSources,
        quality: quality,
      )) {
        _appendPlayUrl(
          urls,
          seen: seen,
          candidate: LivePlayUrl(
            url: source.url,
            headers: source.headers,
            lineLabel: source.lineLabel,
            metadata: source.toMetadata(),
          ),
        );
      }
    }

    if (mode == 'dash' || (mode != 'direct' && urls.isEmpty)) {
      for (final source in playbackSources.where((item) => item.isDash)) {
        _appendPlayUrl(
          urls,
          seen: seen,
          candidate: LivePlayUrl(
            url: source.url,
            headers: source.headers,
            lineLabel: source.lineLabel,
            metadata: source.toMetadata(),
          ),
        );
      }
    }
    _debugLog(
      'fetchPlayUrls room=${detail.roomId} '
      'quality=${quality.id}/${quality.label} '
      'sources=${playbackSources.length} '
      'audioSources=${playbackAudioSources.length} '
      'emitted=${urls.length} '
      'emittedAudio=${urls.where((item) => item.metadata?['audioUrl'] != null).length}',
    );
    return urls;
  }

  Future<YouTubePlaybackBundle> loadPlaybackBundle({
    required YouTubePageBootstrap bootstrap,
    required String resolvedVideoId,
    required String sourcePageUrl,
  }) async {
    final pageResponse = _asMap(bootstrap.initialPlayerResponse);
    final baseClientContext =
        YouTubePlaybackExtractor.extractPlayerClientContext(bootstrap);
    final candidates = <YouTubePlayerResponseCandidate>[];
    Object? firstError;

    for (final profile in _playbackProfiles) {
      try {
        final apiResponse = await _apiClient.postPlayer(
          apiKey: bootstrap.apiKey,
          videoId: resolvedVideoId,
          originalUrl: sourcePageUrl,
          innertubeContext: baseClientContext,
          rolloutToken: bootstrap.rolloutToken ?? '',
          poToken: bootstrap.poToken ?? '',
          clientProfile: profile,
        );
        final merged = _mergePlayerResponseDetails(
          pageResponse: pageResponse,
          apiResponse: apiResponse,
        );
        if (merged.isEmpty) {
          continue;
        }
        candidates.add(
          YouTubePlayerResponseCandidate(
            profile: profile,
            sourcePageUrl: profile.rewriteOriginalUrl(sourcePageUrl),
            playerResponse: merged,
            requestClientContext:
                YouTubePlaybackExtractor.buildPlayerClientContext(
                  baseContext: baseClientContext,
                  clientProfile: profile,
                  sourcePageUrl: sourcePageUrl,
                ),
          ),
        );
      } catch (error, stackTrace) {
        reportProviderDiagnostic(
          providerId: ProviderId.youtube,
          scope: 'youtube player profile request',
          message: 'failed for profile=${profile.id}',
          error: error,
          stackTrace: stackTrace,
        );
        firstError ??= error;
      }
    }

    if (candidates.isEmpty && pageResponse.isNotEmpty) {
      final profile = YouTubePlayerClientProfile.web;
      candidates.add(
        YouTubePlayerResponseCandidate(
          profile: profile,
          sourcePageUrl: sourcePageUrl,
          playerResponse: pageResponse,
          requestClientContext:
              YouTubePlaybackExtractor.buildPlayerClientContext(
                baseContext: baseClientContext,
                clientProfile: profile,
                sourcePageUrl: sourcePageUrl,
              ),
        ),
      );
    }
    if (candidates.isEmpty) {
      if (firstError != null) {
        throw firstError;
      }
      throw ProviderParseException(
        providerId: ProviderId.youtube,
        message: 'YouTube 当前未返回可用播放器响应。',
      );
    }

    final hlsSources = <YouTubePlaybackSource>[];
    final directSources = <YouTubePlaybackSource>[];
    final dashSources = <YouTubePlaybackSource>[];
    final audioSources = <YouTubePlaybackAudioSource>[];
    final seenSourceKeys = <String>{};
    final seenAudioSourceKeys = <String>{};
    YouTubePlayerResponseCandidate? primaryCandidate;

    for (final candidate in candidates) {
      final candidateHls = YouTubePlaybackExtractor.extractHlsSources(
        candidate,
        buildPlaybackHeaders,
      );
      final candidateDirect = YouTubePlaybackExtractor.extractDirectSources(
        candidate,
        buildPlaybackHeaders,
      );
      final candidateDash = YouTubePlaybackExtractor.extractDashSources(
        candidate,
        buildPlaybackHeaders,
      );
      final candidateAudio = YouTubePlaybackExtractor.extractAudioSources(
        candidate,
        buildPlaybackHeaders,
        _debugLog,
      );
      _debugLog(
        'playback bundle profile=${candidate.profile.id} '
        'hls=${candidateHls.length} '
        'direct=${candidateDirect.length} '
        'dash=${candidateDash.length} '
        'audio=${candidateAudio.length}',
      );
      if (primaryCandidate == null && candidateHls.isNotEmpty) {
        primaryCandidate = candidate;
      } else if (primaryCandidate == null && candidateDash.isNotEmpty) {
        primaryCandidate = candidate;
      }
      _appendUniqueSources(hlsSources, candidateHls, seenSourceKeys);
      _appendUniqueSources(directSources, candidateDirect, seenSourceKeys);
      _appendUniqueSources(dashSources, candidateDash, seenSourceKeys);
      _appendUniqueAudioSources(
        audioSources,
        candidateAudio,
        seenAudioSourceKeys,
      );
    }
    primaryCandidate ??= candidates.first;

    final playerJsUrl = bootstrap.playerJsUrl;
    if (playerJsUrl != null && playerJsUrl.isNotEmpty) {
      try {
        for (var i = 0; i < hlsSources.length; i++) {
          final decryptedUrl = await _decipherService.decryptUrl(
            hlsSources[i].url,
            playerJsUrl: playerJsUrl,
            apiClient: _apiClient,
          );
          if (decryptedUrl != hlsSources[i].url) {
            hlsSources[i] = hlsSources[i].copyWith(url: decryptedUrl);
          }
        }
        for (var i = 0; i < directSources.length; i++) {
          final decryptedUrl = await _decipherService.decryptUrl(
            directSources[i].url,
            playerJsUrl: playerJsUrl,
            apiClient: _apiClient,
          );
          final audioUrl = directSources[i].audioUrl?.trim() ?? '';
          var decryptedAudioUrl = audioUrl;
          if (audioUrl.isNotEmpty) {
            decryptedAudioUrl = await _decipherService.decryptUrl(
              audioUrl,
              playerJsUrl: playerJsUrl,
              apiClient: _apiClient,
            );
          }
          if (decryptedUrl != directSources[i].url ||
              decryptedAudioUrl != audioUrl) {
            directSources[i] = directSources[i].copyWith(
              url: decryptedUrl,
              audioUrl: decryptedAudioUrl.isEmpty ? null : decryptedAudioUrl,
            );
          }
        }
        for (var i = 0; i < dashSources.length; i++) {
          final decryptedUrl = await _decipherService.decryptUrl(
            dashSources[i].url,
            playerJsUrl: playerJsUrl,
            apiClient: _apiClient,
          );
          if (decryptedUrl != dashSources[i].url) {
            dashSources[i] = dashSources[i].copyWith(url: decryptedUrl);
          }
        }
        for (var i = 0; i < audioSources.length; i++) {
          final decryptedUrl = await _decipherService.decryptUrl(
            audioSources[i].url,
            playerJsUrl: playerJsUrl,
            apiClient: _apiClient,
          );
          if (decryptedUrl != audioSources[i].url) {
            audioSources[i] = audioSources[i].copyWith(url: decryptedUrl);
          }
        }
      } catch (error, stackTrace) {
        reportProviderDiagnostic(
          providerId: ProviderId.youtube,
          scope: 'youtube playback bundle decryption',
          message: 'Failed to decrypt stream urls',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }

    final playbackUnavailableReason = hlsSources.isEmpty
        ? _buildMissingHlsDiagnostic(candidates)
        : null;
    final playbackDiagnostics = hlsSources.isEmpty
        ? _buildPlaybackDiagnostics(candidates)
        : const <Map<String, Object?>>[];

    return YouTubePlaybackBundle(
      detailPlayerResponse: primaryCandidate.playerResponse,
      playerClientContext: primaryCandidate.requestClientContext,
      playbackAudioSources: audioSources,
      playbackSources: [...hlsSources, ...dashSources, ...directSources],
      primarySource: hlsSources.isNotEmpty
          ? hlsSources.first
          : dashSources.isNotEmpty
          ? dashSources.first
          : null,
      playbackUnavailableReason: playbackUnavailableReason,
      playbackDiagnostics: playbackDiagnostics,
    );
  }

  Map<String, dynamic> _mergePlayerResponseDetails({
    required Map<String, dynamic> pageResponse,
    required Map<String, dynamic> apiResponse,
  }) {
    if (pageResponse.isEmpty) {
      return apiResponse;
    }
    final merged = YouTubePlaybackExtractor.mergeMaps(
      pageResponse,
      apiResponse,
    );

    // The page response is useful for title/category/thumbnail metadata, but
    // stream availability must come from the explicit profile request. Keeping
    // page streamingData here can make a failed profile look playable.
    if (apiResponse.containsKey('streamingData')) {
      merged['streamingData'] = apiResponse['streamingData'];
    } else {
      merged.remove('streamingData');
    }
    if (apiResponse.containsKey('playabilityStatus')) {
      merged['playabilityStatus'] = apiResponse['playabilityStatus'];
    }
    return merged;
  }

  String _buildMissingHlsDiagnostic(
    List<YouTubePlayerResponseCandidate> candidates,
  ) {
    if (candidates.isEmpty) {
      return 'YouTube 当前未返回 HLS manifest：没有可用 player profile 响应。';
    }
    final diagnostics = _buildPlaybackDiagnostics(candidates);
    final summaries = diagnostics
        .map((item) {
          final profile = item['profile']?.toString() ?? '-';
          final status = item['playabilityStatus']?.toString() ?? '-';
          final keys =
              (item['streamingDataKeys'] as List?)
                  ?.map((value) => value.toString())
                  .join('|') ??
              '-';
          final protected = item['protected'] == true ? 'yes' : 'no';
          final formats = item['formats']?.toString() ?? '0';
          final adaptive = item['adaptiveFormats']?.toString() ?? '0';
          return '$profile(status=$status keys=$keys formats=$formats adaptive=$adaptive protected=$protected)';
        })
        .join('; ');
    return 'YouTube 当前未返回 HLS manifest；$summaries。'
        '默认播放不会自动降级到 direct adaptive。';
  }

  List<Map<String, Object?>> _buildPlaybackDiagnostics(
    List<YouTubePlayerResponseCandidate> candidates,
  ) {
    return [
      for (final candidate in candidates)
        _candidatePlaybackDiagnostic(candidate),
    ];
  }

  Map<String, Object?> _candidatePlaybackDiagnostic(
    YouTubePlayerResponseCandidate candidate,
  ) {
    final streamingData = _asMap(candidate.playerResponse['streamingData']);
    final playabilityStatus = _asMap(
      candidate.playerResponse['playabilityStatus'],
    );
    final formats = _asList(streamingData['formats']);
    final adaptiveFormats = _asList(streamingData['adaptiveFormats']);
    return <String, Object?>{
      'profile': candidate.profile.id,
      'playabilityStatus': playabilityStatus['status']?.toString().trim() ?? '',
      'playabilityReason': playabilityStatus['reason']?.toString().trim() ?? '',
      'streamingDataKeys': streamingData.keys.toList(growable: false),
      'hasHlsManifest':
          (streamingData['hlsManifestUrl']?.toString().trim() ?? '').isNotEmpty,
      'hasDashManifest':
          (streamingData['dashManifestUrl']?.toString().trim() ?? '')
              .isNotEmpty,
      'formats': formats.length,
      'adaptiveFormats': adaptiveFormats.length,
      'protected': _hasProtectedFormats([...formats, ...adaptiveFormats]),
    };
  }

  bool _hasProtectedFormats(List<dynamic> formats) {
    for (final item in formats) {
      final format = _asMap(item);
      if (format.isEmpty) {
        continue;
      }
      final url = format['url']?.toString().trim() ?? '';
      if (url.isNotEmpty) {
        continue;
      }
      return true;
    }
    return false;
  }

  Future<String> resolveManifestUrl(LiveRoomDetail detail) async {
    final playbackSources = _readPlaybackSources(detail);
    final hlsSource = playbackSources.cast<YouTubePlaybackSource?>().firstWhere(
      (item) => item?.isHls == true,
      orElse: () => null,
    );
    if (hlsSource != null) {
      return hlsSource.url;
    }
    final direct = detail.metadata?['hlsManifestUrl']?.toString().trim() ?? '';
    if (direct.isNotEmpty) {
      return direct;
    }
    if (!detail.isLive) {
      return '';
    }
    final apiKey = detail.metadata?['apiKey']?.toString().trim() ?? '';
    final resolvedVideoId =
        detail.metadata?['resolvedVideoId']?.toString().trim() ?? '';
    final sourcePageUrl =
        detail.metadata?['sourcePageUrl']?.toString().trim() ??
        detail.sourceUrl?.trim() ??
        '';
    if (apiKey.isEmpty || resolvedVideoId.isEmpty || sourcePageUrl.isEmpty) {
      return '';
    }
    final playerResponse = await _apiClient.postPlayer(
      apiKey: apiKey,
      videoId: resolvedVideoId,
      originalUrl: sourcePageUrl,
      innertubeContext: _asMap(detail.metadata?['playerClientContext']),
      rolloutToken: detail.metadata?['playerRolloutToken']?.toString() ?? '',
      poToken: detail.metadata?['playerPoToken']?.toString() ?? '',
      clientProfile: _readPlayerClientProfile(detail),
    );
    return _asMap(
          playerResponse['streamingData'],
        )['hlsManifestUrl']?.toString().trim() ??
        '';
  }

  Map<String, String> buildPlaybackHeaders(
    YouTubePlayerClientProfile clientProfile,
    String sourcePageUrl,
  ) {
    return {
      'accept':
          'application/x-mpegURL, application/vnd.apple.mpegurl, '
          'application/json, text/plain',
      'accept-language': 'en-US,en;q=0.9',
      'origin': clientProfile.origin,
      'referer': clientProfile.rewriteOriginalUrl(sourcePageUrl),
      'user-agent': clientProfile.userAgent,
    };
  }

  Map<String, String> _buildLegacyPlaybackHeaders(String referer) {
    return {
      'accept':
          'application/x-mpegURL, application/vnd.apple.mpegurl, '
          'application/json, text/plain',
      'accept-language': 'en-US,en;q=0.9',
      'origin': 'https://www.youtube.com',
      'referer': referer,
      'user-agent': YouTubeApiClient.browserUserAgent,
    };
  }

  Future<List<YouTubeHlsVariant>> _loadHlsVariants(
    YouTubePlaybackSource source,
  ) async {
    final cached = _hlsVariantCache[source.url];
    if (cached != null) {
      _rememberCachedValue(_hlsVariantCache, source.url, cached);
      return cached;
    }
    final playlistText = await _apiClient.fetchText(
      source.url,
      headers: source.headers,
    );
    final variants = _hlsMasterPlaylistParser.parse(
      playlistUrl: source.url,
      source: playlistText,
    );
    _rememberCachedValue(_hlsVariantCache, source.url, variants);
    return variants;
  }

  Future<List<YouTubePlaybackSource>> _selectUsableHlsSources(
    List<YouTubePlaybackSource> sources,
  ) async {
    if (sources.isEmpty) {
      return const [];
    }
    final usable = await Future.wait(
      sources.map((source) async {
        return await _isHlsSourceUsable(source) ? source : null;
      }),
    );
    return usable.whereType<YouTubePlaybackSource>().toList(growable: false);
  }

  Future<bool> _isHlsSourceUsable(YouTubePlaybackSource source) async {
    final cached = _hlsUsabilityCache[source.url];
    if (cached != null) {
      _rememberCachedValue(_hlsUsabilityCache, source.url, cached);
      return cached;
    }
    try {
      // Only verify that the manifest can be parsed and yields at least one
      // variant. Skip the media-playlist fetch and segment HEAD probe —
      // those extra requests risk triggering YouTube CDN bot detection and
      // waste the short-lived streaming URL lifetime. If the n-challenge has
      // been solved, the manifest is already usable; if it fails, the player
      // will surface the error directly.
      final variants = await _loadHlsVariants(source);
      final usable = variants.isNotEmpty;
      _rememberCachedValue(_hlsUsabilityCache, source.url, usable);
      return usable;
    } catch (error, stackTrace) {
      reportProviderDiagnostic(
        providerId: ProviderId.youtube,
        scope: 'youtube HLS source usability probe',
        message: 'failed for source=${source.url}',
        error: error,
        stackTrace: stackTrace,
      );
      _rememberCachedValue(_hlsUsabilityCache, source.url, false);
      return false;
    }
  }

  void _rememberCachedValue<T>(Map<String, T> cache, String key, T value) {
    cache.remove(key);
    cache[key] = value;
    if (cache.length <= _maxHlsCacheEntries) {
      return;
    }
    cache.remove(cache.keys.first);
  }

  int get debugHlsVariantCacheSize => _hlsVariantCache.length;

  int get debugHlsUsabilityCacheSize => _hlsUsabilityCache.length;

  void debugRememberHlsVariantCache(
    String url,
    List<YouTubeHlsVariant> variants,
  ) {
    _rememberCachedValue(_hlsVariantCache, url, variants);
  }

  void debugRememberHlsUsabilityCache(String url, bool usable) {
    _rememberCachedValue(_hlsUsabilityCache, url, usable);
  }

  Future<YouTubeHlsVariant?> _selectHlsVariantForQuality({
    required YouTubePlaybackSource source,
    required LivePlayQuality quality,
  }) async {
    final variants = await _loadHlsVariants(source);
    if (variants.isEmpty) {
      return null;
    }
    final requestedRank = YouTubePlaybackExtractor.parseQualityRank(
      quality.id,
      fallbackLabel: quality.label,
    );
    if (requestedRank == null) {
      return variants.first;
    }
    final exact = variants.firstWhere(
      (item) =>
          item.height?.toString() == quality.id ||
          item.label.trim().toLowerCase() == quality.label.trim().toLowerCase(),
      orElse: () => const YouTubeHlsVariant(url: '', bandwidth: 0, label: ''),
    );
    if (exact.url.isNotEmpty) {
      return exact;
    }
    final sorted = [...variants]
      ..sort((left, right) {
        final leftRank = left.height ?? left.bandwidth;
        final rightRank = right.height ?? right.bandwidth;
        final diff = (leftRank - requestedRank).abs().compareTo(
          (rightRank - requestedRank).abs(),
        );
        if (diff != 0) {
          return diff;
        }
        final compatibilityDiff = right.compatibilityScore.compareTo(
          left.compatibilityScore,
        );
        if (compatibilityDiff != 0) {
          return compatibilityDiff;
        }
        return rightRank.compareTo(leftRank);
      });
    return sorted.first;
  }

  List<YouTubePlaybackSource> _selectDirectSourcesForQuality({
    required List<YouTubePlaybackSource> sources,
    required LivePlayQuality quality,
  }) {
    final matched = sources
        .where(
          (item) =>
              item.qualityId == quality.id ||
              item.qualityLabel?.trim().toLowerCase() ==
                  quality.label.trim().toLowerCase(),
        )
        .toList();
    if (matched.isNotEmpty) {
      return matched;
    }
    final requestedRank = YouTubePlaybackExtractor.parseQualityRank(
      quality.id,
      fallbackLabel: quality.label,
    );
    if (requestedRank == null || sources.isEmpty) {
      return const [];
    }
    final sorted = [...sources]
      ..sort((left, right) {
        final leftRank = left.sortOrder;
        final rightRank = right.sortOrder;
        final diff = (leftRank - requestedRank).abs().compareTo(
          (rightRank - requestedRank).abs(),
        );
        if (diff != 0) {
          return diff;
        }
        return rightRank.compareTo(leftRank);
      });
    final targetRank = sorted.first.sortOrder;
    return sources.where((item) => item.sortOrder == targetRank).toList();
  }

  String buildSelectedHlsMasterPlaylistContentForTesting({
    required YouTubeHlsVariant variant,
    required String variantUrl,
    required String audioUrl,
  }) {
    final attributes = <String, String>{
      ...variant.streamInfAttributes,
      'BANDWIDTH': (variant.bandwidth > 0 ? variant.bandwidth : 1).toString(),
    };
    if (variant.width != null && variant.height != null) {
      attributes['RESOLUTION'] = '${variant.width}x${variant.height}';
    }
    if (variant.frameRate != null) {
      attributes['FRAME-RATE'] = '${variant.frameRate}';
    }
    if (audioUrl.isNotEmpty) {
      attributes['AUDIO'] = 'audio';
    } else {
      attributes.remove('AUDIO');
    }
    final audioAttributes = <String, String>{
      ...variant.audioAttributes,
      if (audioUrl.isNotEmpty) ...{
        'TYPE': 'AUDIO',
        'GROUP-ID': 'audio',
        'URI': audioUrl,
      },
    };
    if (audioUrl.isNotEmpty) {
      audioAttributes.putIfAbsent('NAME', () => 'Default');
      audioAttributes.putIfAbsent('DEFAULT', () => 'YES');
      audioAttributes.putIfAbsent('AUTOSELECT', () => 'YES');
    }
    return <String>[
      '#EXTM3U',
      '#EXT-X-VERSION:6',
      if (audioUrl.isNotEmpty)
        _buildHlsAttributeLine('#EXT-X-MEDIA', audioAttributes),
      _buildHlsAttributeLine('#EXT-X-STREAM-INF', attributes),
      variantUrl,
    ].join('\n');
  }

  String _buildHlsAttributeLine(String prefix, Map<String, String> attributes) {
    return '$prefix:${attributes.entries.map(_formatHlsAttribute).join(',')}';
  }

  String _formatHlsAttribute(MapEntry<String, String> entry) {
    final key = entry.key.trim();
    final value = entry.value.trim();
    if (_shouldQuoteHlsAttribute(key, value)) {
      return '$key="${_escapeHlsQuotedString(value)}"';
    }
    return '$key=$value';
  }

  bool _shouldQuoteHlsAttribute(String key, String value) {
    if (value.contains(',') || value.contains('"')) {
      return true;
    }
    return const <String>{
      'URI',
      'GROUP-ID',
      'NAME',
      'LANGUAGE',
      'ASSOC-LANGUAGE',
      'INSTREAM-ID',
      'AUDIO',
      'VIDEO',
      'SUBTITLES',
      'CLOSED-CAPTIONS',
      'CODECS',
      'CHARACTERISTICS',
      'CHANNELS',
      'STABLE-RENDITION-ID',
    }.contains(key);
  }

  String _escapeHlsQuotedString(String value) {
    return value.replaceAll('\\', '\\\\').replaceAll('"', '\\"');
  }

  List<YouTubePlaybackSource> _readPlaybackSources(LiveRoomDetail detail) {
    final list = detail.metadata?[_playbackSourcesMetadataKey];
    if (list is! List) {
      return const [];
    }
    return list
        .map((item) => _asMap(item))
        .map((item) => YouTubePlaybackSource.fromMetadata(item))
        .toList(growable: false);
  }

  List<YouTubePlaybackAudioSource> _readPlaybackAudioSources(
    LiveRoomDetail detail,
  ) {
    final list = detail.metadata?[_playbackAudioSourcesMetadataKey];
    if (list is! List) {
      return const [];
    }
    return list
        .map((item) => _asMap(item))
        .map((item) => YouTubePlaybackAudioSource.fromMetadata(item))
        .toList(growable: false);
  }

  YouTubePlayerClientProfile _readPlayerClientProfile(LiveRoomDetail detail) {
    final raw =
        detail.metadata?['playerClientProfile']?.toString().trim() ?? '';
    for (final profile in YouTubePlayerClientProfile.values) {
      if (profile.id == raw) {
        return profile;
      }
    }
    return YouTubePlayerClientProfile.streamlinkAndroid;
  }

  void _appendPlayUrl(
    List<LivePlayUrl> list, {
    required Set<String> seen,
    required LivePlayUrl candidate,
  }) {
    final key = '${candidate.url}|${candidate.lineLabel}';
    if (seen.add(key)) {
      list.add(candidate);
    }
  }

  void _appendUniqueSources(
    List<YouTubePlaybackSource> destination,
    List<YouTubePlaybackSource> candidates,
    Set<String> keys,
  ) {
    for (final item in candidates) {
      final key =
          '${item.strategy}|${item.clientProfile.id}|${item.qualityId ?? ''}';
      if (keys.add(key)) {
        destination.add(item);
      }
    }
  }

  void _appendUniqueAudioSources(
    List<YouTubePlaybackAudioSource> destination,
    List<YouTubePlaybackAudioSource> candidates,
    Set<String> keys,
  ) {
    for (final item in candidates) {
      final key = '${item.clientProfile.id}|${item.bitrate}';
      if (keys.add(key)) {
        destination.add(item);
      }
    }
  }

  Map<String, dynamic> _asMap(Object? value) {
    return ProviderJson.asMap(value);
  }

  List<dynamic> _asList(Object? value) {
    return ProviderJson.asList(value);
  }

  void _debugLog(String message) {
    assert(() {
      print('[YouTubePlaybackDataSource] $message');
      return true;
    }());
  }
}
