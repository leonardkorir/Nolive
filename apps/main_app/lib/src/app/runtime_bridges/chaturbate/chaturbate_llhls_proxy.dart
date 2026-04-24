import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:live_core/live_core.dart';
import 'package:live_providers/live_providers.dart'
    show ChaturbateHlsMasterPlaylistParser, ChaturbateHlsVariant;

import '../../../shared/application/app_log.dart';

const _blockedLlHlsTags = <String>[
  '#EXT-X-SERVER-CONTROL:',
  '#EXT-X-PART-INF:',
  '#EXT-X-PART:',
  '#EXT-X-PRELOAD-HINT:',
  '#EXT-X-RENDITION-REPORT:',
  '#EXT-X-SKIP:',
];

const _historySegmentLimit = 48;
const _stableWindowSegmentLimit = 8;
const _stableWindowMinimumSegments = 3;
const _stableEdgeTrimSegments = 1;
const _startupWindowSegmentLimit = 8;
const _startupEdgeTrimSegments = 1;
const _startupWarmSegmentCount = 6;
const _stableCbStartupWarmSegmentCount = 8;
const _deepCbStartupWarmSegmentCount = 10;
const _minimumStartupImmediateServeSegmentCount = 3;
const _stableCbMinimumStartupImmediateServeSegmentCount = 4;
const _deepCbMinimumStartupImmediateServeSegmentCount = 5;
const _minimumStartupPlayableSegmentCount = 4;
const _stableCbMinimumStartupPlayableSegmentCount = 5;
const _deepCbMinimumStartupPlayableSegmentCount = 6;
const _urgentEdgePrefetchSegmentCount = 3;
// Wider batch so the concurrent prefetch covers the next window in one round.
const _assetPrefetchBatchSize = 12;
const _assetPrefetchPollInterval = Duration(milliseconds: 250);
const _minimumRefreshInterval = Duration(milliseconds: 250);
// Keep the background prime generous enough for mmcdn jitter, but shorter than
// the older deep-startup path because the desired startup window is now
// smaller.
const _initialSessionPrimeTimeout = Duration(seconds: 12);
const _initialPlaylistStartupWaitTimeout = Duration(milliseconds: 1400);
const _stableCbInitialPlaylistStartupWaitTimeout = Duration(milliseconds: 2200);
const _deepCbInitialPlaylistStartupWaitTimeout = Duration(milliseconds: 2600);
const _playlistAdvanceWaitTimeout = Duration(milliseconds: 1200);
const _playlistAdvancePollInterval = Duration(milliseconds: 120);
const _playlistSnapshotFreshWindow = Duration(seconds: 2);
const _lateAssetAvailabilityWaitTimeout = Duration(milliseconds: 900);
const _initAssetAvailabilityWaitTimeout = Duration(milliseconds: 250);
const _playlistMapDecisionSniffTimeout = Duration(milliseconds: 450);
const _assetAvailabilityPollInterval = Duration(milliseconds: 120);

@visibleForTesting
bool shouldServeChaturbateStartupPlaylistEarly({
  required int startupSegmentCount,
  required int cachedStartupPrefixCount,
  int minimumStartupPlayableSegmentCount = _minimumStartupPlayableSegmentCount,
  int minimumStartupImmediateServeSegmentCount =
      _minimumStartupImmediateServeSegmentCount,
}) {
  return startupSegmentCount >= minimumStartupPlayableSegmentCount &&
      cachedStartupPrefixCount >= minimumStartupImmediateServeSegmentCount;
}

@visibleForTesting
bool chaturbateMp4BytesContainInitialization(Uint8List bytes) {
  return _mp4BytesContainBox(bytes, 'moov');
}

bool _mp4BytesContainBox(Uint8List bytes, String boxType) {
  if (boxType.length != 4 || bytes.lengthInBytes < 8) {
    return false;
  }
  final expected = ascii.encode(boxType);
  for (var index = 4; index <= bytes.lengthInBytes - 4; index += 1) {
    if (bytes[index] == expected[0] &&
        bytes[index + 1] == expected[1] &&
        bytes[index + 2] == expected[2] &&
        bytes[index + 3] == expected[3]) {
      return true;
    }
  }
  return false;
}

@visibleForTesting
({
  int warmSegmentCount,
  int minimumStartupPlayableSegmentCount,
  int minimumStartupImmediateServeSegmentCount,
  Duration initialPlaylistStartupWaitTimeout,
}) resolveChaturbateLlHlsStartupPolicy({
  required int bandwidth,
  int? height,
}) {
  final normalizedHeight = height ?? 0;
  if (bandwidth >= 4500000 || normalizedHeight >= 1080) {
    return (
      warmSegmentCount: _deepCbStartupWarmSegmentCount,
      minimumStartupPlayableSegmentCount:
          _deepCbMinimumStartupPlayableSegmentCount,
      minimumStartupImmediateServeSegmentCount:
          _deepCbMinimumStartupImmediateServeSegmentCount,
      initialPlaylistStartupWaitTimeout:
          _deepCbInitialPlaylistStartupWaitTimeout,
    );
  }
  if (bandwidth >= 2000000 || normalizedHeight >= 540) {
    return (
      warmSegmentCount: _stableCbStartupWarmSegmentCount,
      minimumStartupPlayableSegmentCount:
          _stableCbMinimumStartupPlayableSegmentCount,
      minimumStartupImmediateServeSegmentCount:
          _stableCbMinimumStartupImmediateServeSegmentCount,
      initialPlaylistStartupWaitTimeout:
          _stableCbInitialPlaylistStartupWaitTimeout,
    );
  }
  return (
    warmSegmentCount: _startupWarmSegmentCount,
    minimumStartupPlayableSegmentCount: _minimumStartupPlayableSegmentCount,
    minimumStartupImmediateServeSegmentCount:
        _minimumStartupImmediateServeSegmentCount,
    initialPlaylistStartupWaitTimeout: _initialPlaylistStartupWaitTimeout,
  );
}

class ChaturbateLlHlsProxy {
  ChaturbateLlHlsProxy({
    HttpClient? client,
    Duration sessionTtl = const Duration(minutes: 8),
    bool? enabledOverride,
  })  : _client = client ?? HttpClient(),
        _sessionTtl = sessionTtl,
        _enabledOverride = enabledOverride {
    _client.connectionTimeout = const Duration(seconds: 15);
    _client.idleTimeout = const Duration(seconds: 15);
    _client.maxConnectionsPerHost = 32;
  }

  static const String _routePrefix = 'chaturbate-llhls';

  final HttpClient _client;
  final Duration _sessionTtl;
  final bool? _enabledOverride;
  final Map<String, _ChaturbateLlHlsSession> _sessions =
      <String, _ChaturbateLlHlsSession>{};

  HttpServer? _server;
  Uri? _endpoint;

  Future<List<LivePlayUrl>> wrapPlayUrls({
    required LivePlayQuality quality,
    required List<LivePlayUrl> playUrls,
  }) async {
    if (!_supportsPlatform || playUrls.isEmpty) {
      return playUrls;
    }
    if (!playUrls.any(_looksLikeProxyCandidate)) {
      return playUrls;
    }
    await _ensureStarted();
    _purgeExpiredSessions();
    final wrapped = <LivePlayUrl>[];
    for (final playUrl in playUrls) {
      final proxyPlayUrl = await _resolveProxyPlayUrl(
        quality: quality,
        playUrl: playUrl,
      );
      if (proxyPlayUrl == null) {
        wrapped.add(playUrl);
        continue;
      }
      final session = _createSession(
        quality: quality,
        playUrl: proxyPlayUrl,
      );
      _sessions[session.id] = session;
      wrapped.add(
        LivePlayUrl(
          url: _sessionMasterUri(session.id).toString(),
          headers: const {},
          lineLabel: playUrl.lineLabel,
          metadata: _buildWrappedMetadata(
            originalPlayUrl: playUrl,
            proxiedPlayUrl: proxyPlayUrl,
          ),
        ),
      );
      _startSessionPrimeIfNeeded(session);
    }
    return wrapped;
  }

  Future<void> dispose() async {
    await _server?.close(force: true);
    _server = null;
    _endpoint = null;
    _sessions.clear();
    _client.close(force: true);
  }

  Future<LivePlayUrl?> _resolveProxyPlayUrl({
    required LivePlayQuality quality,
    required LivePlayUrl playUrl,
  }) async {
    if (_supportsSplitProxy(playUrl)) {
      return playUrl;
    }
    return _resolveMasterOnlyPlayUrl(
      quality: quality,
      playUrl: playUrl,
    );
  }

  bool _supportsSplitProxy(LivePlayUrl playUrl) {
    final audioUrl = playUrl.metadata?['audioUrl']?.toString().trim() ?? '';
    if (audioUrl.isEmpty) {
      return false;
    }
    if (_looksLikeLocalProxyUrl(playUrl.url)) {
      return false;
    }
    return _looksLikeMmcdnLlHlsPlaylist(playUrl.url) &&
        _looksLikeMmcdnLlHlsPlaylist(audioUrl);
  }

  bool _looksLikeProxyCandidate(LivePlayUrl playUrl) {
    if (_supportsSplitProxy(playUrl)) {
      return true;
    }
    return !_looksLikeLocalProxyUrl(playUrl.url) &&
        _looksLikeMmcdnLlHlsPlaylist(playUrl.url);
  }

  Future<LivePlayUrl?> _resolveMasterOnlyPlayUrl({
    required LivePlayQuality quality,
    required LivePlayUrl playUrl,
  }) async {
    if (_looksLikeLocalProxyUrl(playUrl.url) ||
        !_looksLikeMmcdnLlHlsPlaylist(playUrl.url)) {
      return null;
    }
    final metadata = playUrl.metadata ?? const <String, Object?>{};
    final masterPlaylistUrl = _firstNonEmpty(
        [metadata['masterPlaylistUrl']?.toString(), playUrl.url]);
    if (masterPlaylistUrl.isEmpty) {
      return null;
    }
    var masterPlaylistContent =
        metadata['masterPlaylistContent']?.toString().trim() ?? '';
    if (masterPlaylistContent.isEmpty) {
      try {
        masterPlaylistContent = await _fetchText(
          masterPlaylistUrl,
          headers: playUrl.headers,
        );
      } catch (_) {
        return null;
      }
    }
    final variants = const ChaturbateHlsMasterPlaylistParser().parse(
      playlistUrl: masterPlaylistUrl,
      source: masterPlaylistContent,
    );
    final variant = _selectVariantForQuality(
      quality: quality,
      variants: variants,
    );
    final audioUrl = variant?.audioUrl?.trim() ?? '';
    if (variant == null || audioUrl.isEmpty) {
      return null;
    }
    return LivePlayUrl(
      url: variant.url,
      headers: playUrl.headers,
      lineLabel: playUrl.lineLabel,
      metadata: {
        ...metadata,
        'playlistUrl': variant.url,
        'masterPlaylistUrl': masterPlaylistUrl,
        'masterPlaylistContent': masterPlaylistContent,
        'audioUrl': audioUrl,
        'audioHeaders': _readHeadersMap(metadata['audioHeaders']).isEmpty
            ? playUrl.headers
            : _readHeadersMap(metadata['audioHeaders']),
        'audioMimeType': metadata['audioMimeType'] ?? 'application/x-mpegURL',
        'audioGroupId': variant.audioGroupId,
        'bandwidth': _readFirstPositiveInt([
              metadata['bandwidth'],
              variant.bandwidth,
            ]) ??
            variant.bandwidth,
        'width': _readFirstPositiveInt([
          metadata['width'],
          variant.width,
        ]),
        'height': _readFirstPositiveInt([
          metadata['height'],
          variant.height,
        ]),
        'hlsBitrate': _resolveHlsBitrateForVariant(
          quality: quality,
          variant: variant,
        ),
        'resolvedFromMasterFallback': true,
      },
    );
  }

  Map<String, Object?> _buildWrappedMetadata({
    required LivePlayUrl originalPlayUrl,
    required LivePlayUrl proxiedPlayUrl,
  }) {
    final metadata = <String, Object?>{
      'proxied': true,
      'proxyKind': 'chaturbate-llhls',
      'upstreamUrl': originalPlayUrl.url,
    };
    final originalMetadata =
        proxiedPlayUrl.metadata ?? const <String, Object?>{};
    for (final key in const [
      'bandwidth',
      'width',
      'height',
      'codecs',
      'bitrate',
      'averageBitrate',
      'source',
      'platform',
      'playerType',
    ]) {
      if (originalMetadata.containsKey(key)) {
        metadata[key] = originalMetadata[key];
      }
    }
    return metadata;
  }

  Future<void> _ensureStarted() async {
    if (_server != null && _endpoint != null) {
      return;
    }
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    _endpoint = Uri.parse(
      'http://${InternetAddress.loopbackIPv4.address}:${server.port}/$_routePrefix',
    );
    server.listen(_handleRequest);
  }

  Uri _sessionMasterUri(String sessionId) {
    final endpoint = _endpoint;
    if (endpoint == null) {
      throw StateError('ChaturbateLlHlsProxy has not been started.');
    }
    return endpoint.replace(path: '${endpoint.path}/$sessionId/stream.m3u8');
  }

  _ChaturbateLlHlsSession _createSession({
    required LivePlayQuality quality,
    required LivePlayUrl playUrl,
  }) {
    final metadata = playUrl.metadata ?? const <String, Object?>{};
    final audioUrl = metadata['audioUrl']?.toString().trim() ?? '';
    final audioHeaders = _readHeadersMap(metadata['audioHeaders']);
    return _ChaturbateLlHlsSession(
      id: _randomToken(18),
      videoPlaylistUrl: playUrl.url,
      videoHeaders: playUrl.headers,
      audioPlaylistUrl: audioUrl,
      audioHeaders: audioHeaders.isEmpty ? playUrl.headers : audioHeaders,
      bandwidth: _readFirstPositiveInt([
            metadata['bandwidth'],
            metadata['bitrate'],
            quality.metadata?['bandwidth'],
            quality.id,
          ]) ??
          0,
      width: _readFirstPositiveInt([
        metadata['width'],
        quality.metadata?['width'],
      ]),
      height: _readFirstPositiveInt([
        metadata['height'],
        quality.metadata?['height'],
      ]),
      codecs: metadata['codecs']?.toString().trim(),
    );
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final response = request.response;
    try {
      _purgeExpiredSessions();
      final segments = request.uri.pathSegments;
      if (segments.length < 3 || segments.first != _routePrefix) {
        response.statusCode = HttpStatus.notFound;
        await response.close();
        return;
      }
      final session = _sessions[segments[1]];
      if (session == null) {
        response.statusCode = HttpStatus.gone;
        await response.close();
        return;
      }
      session.touch();
      final action = segments[2];
      switch (action) {
        case 'stream.m3u8':
          await _writeSyntheticMasterPlaylist(response, session);
          return;
        case 'video.m3u8':
          await _writeMediaPlaylist(
            response,
            session: session,
            mediaKind: _ChaturbateLlHlsMediaKind.video,
          );
          return;
        case 'audio.m3u8':
          await _writeMediaPlaylist(
            response,
            session: session,
            mediaKind: _ChaturbateLlHlsMediaKind.audio,
          );
          return;
        case 'asset':
          if (segments.length < 4) {
            response.statusCode = HttpStatus.notFound;
            await response.close();
            return;
          }
          final assetId = segments[3];
          if (!session.assets.containsKey(assetId)) {
            response.statusCode = HttpStatus.notFound;
            await response.close();
            return;
          }
          await _pipeAsset(
            response,
            session: session,
            assetId: assetId,
          );
          return;
      }
      response.statusCode = HttpStatus.notFound;
      await response.close();
    } catch (error) {
      if (kDebugMode) {
        debugPrint('ChaturbateLlHlsProxy request failed: $error');
      }
      response.statusCode = HttpStatus.internalServerError;
      await response.close();
    }
  }

  Future<void> _writeSyntheticMasterPlaylist(
    HttpResponse response,
    _ChaturbateLlHlsSession session,
  ) async {
    final endpoint = _endpoint;
    if (endpoint == null) {
      response.statusCode = HttpStatus.internalServerError;
      await response.close();
      return;
    }
    final audioUri = endpoint.replace(
      path: '${endpoint.path}/${session.id}/audio.m3u8',
    );
    final videoUri = endpoint.replace(
      path: '${endpoint.path}/${session.id}/video.m3u8',
    );
    final attributes = <String>[
      if (session.bandwidth > 0) 'BANDWIDTH=${session.bandwidth}',
      if (session.width != null && session.height != null)
        'RESOLUTION=${session.width}x${session.height}',
      if (session.codecs?.trim().isNotEmpty == true)
        'CODECS="${session.codecs!.trim()}"',
      'AUDIO="audio"',
    ];
    response.headers.contentType =
        ContentType('application', 'vnd.apple.mpegurl', charset: 'utf-8');
    response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    response.write(
      <String>[
        '#EXTM3U',
        '#EXT-X-VERSION:6',
        '#EXT-X-INDEPENDENT-SEGMENTS',
        '#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",NAME="Audio",DEFAULT=YES,AUTOSELECT=YES,CHANNELS="2",URI="${audioUri.toString()}"',
        '#EXT-X-STREAM-INF:${attributes.join(',')}',
        videoUri.toString(),
      ].join('\n'),
    );
    _startSessionRefreshIfNeeded(session);
    await response.close();
  }

  Future<void> _writeMediaPlaylist(
    HttpResponse response, {
    required _ChaturbateLlHlsSession session,
    required _ChaturbateLlHlsMediaKind mediaKind,
  }) async {
    try {
      await _ensureTimelineDataForRequest(
        session,
        mediaKind: mediaKind,
      );
      final timeline = session.timelineFor(mediaKind);
      final segments = await _resolvePlayableSegmentsForRequest(
        session: session,
        mediaKind: mediaKind,
        timeline: timeline,
      );
      await _sniffPlaylistWindowForMapDecision(
        session: session,
        segments: segments,
      );
      final playlistSegments = _trimSegmentsForMapDecision(
        session: session,
        timeline: timeline,
        segments: segments,
      );
      _logSyntheticPlaylistDecision(
        session: session,
        mediaKind: mediaKind,
        timeline: timeline,
        originalSegments: segments,
        playlistSegments: playlistSegments,
      );
      final rewritten = _buildSyntheticMediaPlaylist(
        session: session,
        timeline: timeline,
        segments: playlistSegments,
      );
      session.recordServedPlaylist(
        mediaKind: mediaKind,
        segments: playlistSegments,
        playlistBody: rewritten,
      );
      await _writePlaylistResponse(response, rewritten);
    } catch (error) {
      final cachedPlaylist =
          session.playlistSnapshotFor(mediaKind)?.playlistBody;
      if (cachedPlaylist != null) {
        if (kDebugMode) {
          debugPrint(
            'ChaturbateLlHlsProxy fallback to cached ${mediaKind.name} playlist '
            'after error: $error',
          );
        }
        await _writePlaylistResponse(response, cachedPlaylist);
        return;
      }
      rethrow;
    }
  }

  Future<void> _writePlaylistResponse(
    HttpResponse response,
    String playlistBody,
  ) async {
    response.headers.contentType =
        ContentType('application', 'vnd.apple.mpegurl', charset: 'utf-8');
    response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    response.write(playlistBody);
    await response.close();
  }

  Future<void> _ensureTimelineDataForRequest(
    _ChaturbateLlHlsSession session, {
    required _ChaturbateLlHlsMediaKind mediaKind,
  }) async {
    final timeline = session.timelineFor(mediaKind);
    if (timeline.hasSegments) {
      return;
    }
    _startSessionPrimeIfNeeded(session);
    final hasRequestedTimeline = await _waitForRequestedTimelineData(
      session,
      mediaKind: mediaKind,
      timeout:
          _startupPolicyForSession(session).initialPlaylistStartupWaitTimeout,
    );
    if (hasRequestedTimeline) {
      return;
    }
    await _refreshTimelineForRequest(
      session: session,
      mediaKind: mediaKind,
    );
  }

  Future<bool> _waitForRequestedTimelineData(
    _ChaturbateLlHlsSession session, {
    required _ChaturbateLlHlsMediaKind mediaKind,
    required Duration timeout,
  }) async {
    final timeline = session.timelineFor(mediaKind);
    if (timeline.hasSegments) {
      return true;
    }
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) {
        break;
      }
      await _waitForSessionProgress(
        session,
        remaining < _playlistAdvancePollInterval
            ? remaining
            : _playlistAdvancePollInterval,
      );
      if (timeline.hasSegments) {
        return true;
      }
      if (session.startupPrimeInFlight == null &&
          session.refreshInFlight == null) {
        break;
      }
    }
    return timeline.hasSegments;
  }

  void _startSessionPrimeIfNeeded(_ChaturbateLlHlsSession session) {
    if (session.startupPrimeInFlight != null) {
      return;
    }
    final prime = _primeSession(session);
    session.startupPrimeInFlight = prime;
    unawaited(_finalizeSessionPrime(session, prime));
  }

  Future<void> _finalizeSessionPrime(
    _ChaturbateLlHlsSession session,
    Future<void> prime,
  ) async {
    try {
      await prime;
    } catch (_) {
      // Request-time refresh remains as the fallback path.
    } finally {
      if (identical(session.startupPrimeInFlight, prime)) {
        session.startupPrimeInFlight = null;
      }
    }
  }

  Future<void> _primeSession(_ChaturbateLlHlsSession session) async {
    final deadline = DateTime.now().add(_initialSessionPrimeTimeout);
    var lastProgressSignature = _sessionStartupProgressSignature(session);
    var lastProgressAt = DateTime.now();
    while (true) {
      _startSessionRefreshIfNeeded(session, force: true);
      final refresh = session.refreshInFlight;
      if (refresh != null) {
        await refresh;
      }
      if (!session.hasTimelineData) {
        return;
      }
      await _warmStartupAssetsIfNeeded(session);
      _startStableAssetPrefetchIfNeeded(session);
      final progressSignature = _sessionStartupProgressSignature(session);
      if (_startupProgressAdvanced(
        previous: lastProgressSignature,
        next: progressSignature,
      )) {
        lastProgressSignature = progressSignature;
        lastProgressAt = DateTime.now();
      }
      if (_sessionHasDesiredStartupCoverage(session)) {
        return;
      }
      if (DateTime.now().difference(lastProgressAt) >=
          _startupProgressPatience(session)) {
        return;
      }
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) {
        return;
      }
      await _waitForSessionProgress(
        session,
        remaining < _playlistAdvancePollInterval
            ? remaining
            : _playlistAdvancePollInterval,
      );
    }
  }

  void _startSessionRefreshIfNeeded(
    _ChaturbateLlHlsSession session, {
    bool force = false,
  }) {
    if (session.refreshInFlight != null) {
      return;
    }
    final now = DateTime.now();
    final needsRefresh = force ||
        !session.hasTimelineData ||
        now.difference(session.lastRefreshAt) >= _minimumRefreshInterval;
    if (!needsRefresh) {
      return;
    }
    final refresh = _performSessionRefresh(session);
    session.refreshInFlight = refresh;
    unawaited(_finalizeSessionRefresh(session, refresh));
  }

  Future<void> _finalizeSessionRefresh(
    _ChaturbateLlHlsSession session,
    Future<void> refresh,
  ) async {
    try {
      await refresh;
    } catch (error) {
      if (kDebugMode) {
        debugPrint('ChaturbateLlHlsProxy refresh failed: $error');
      }
    } finally {
      if (identical(session.refreshInFlight, refresh)) {
        session.refreshInFlight = null;
      }
    }
  }

  Future<void> _performSessionRefresh(_ChaturbateLlHlsSession session) async {
    final errors = await Future.wait<Object?>([
      _refreshTimelineForRequest(
        session: session,
        mediaKind: _ChaturbateLlHlsMediaKind.video,
        swallowError: true,
      ),
      _refreshTimelineForRequest(
        session: session,
        mediaKind: _ChaturbateLlHlsMediaKind.audio,
        swallowError: true,
      ),
    ]);
    if (!session.videoTimeline.hasSegments && errors[0] != null) {
      throw errors[0]!;
    }
    if (!session.audioTimeline.hasSegments && errors[1] != null) {
      throw errors[1]!;
    }
    _synchronizeSessionAssets(session);
    session.lastRefreshAt = DateTime.now();
    _startStableAssetPrefetchIfNeeded(session);
  }

  Future<Object?> _refreshTimelineForRequest({
    required _ChaturbateLlHlsSession session,
    required _ChaturbateLlHlsMediaKind mediaKind,
    bool swallowError = false,
  }) async {
    try {
      await _refreshTimeline(
        session: session,
        mediaKind: mediaKind,
        playlistUrl: session.playlistUrlFor(mediaKind),
        headers: session.headersFor(mediaKind),
      );
      return null;
    } catch (error) {
      if (!swallowError) {
        rethrow;
      }
      return error;
    }
  }

  Future<void> _refreshTimeline({
    required _ChaturbateLlHlsSession session,
    required _ChaturbateLlHlsMediaKind mediaKind,
    required String playlistUrl,
    required Map<String, String> headers,
  }) async {
    final timeline = session.timelineFor(mediaKind);
    try {
      final text = await _fetchText(
        playlistUrl,
        headers: headers,
      );
      final parsed = _parseMediaPlaylist(text);
      timeline.merge(
        playlist: parsed,
        session: session,
        sourceUrl: playlistUrl,
        headers: headers,
      );
    } catch (_) {
      if (!timeline.hasSegments) {
        rethrow;
      }
    }
  }

  Future<String> _fetchText(
    String url, {
    required Map<String, String> headers,
  }) async {
    final request = await _client.getUrl(Uri.parse(url));
    headers.forEach(request.headers.set);
    final response = await request.close();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Chaturbate proxy upstream request failed with ${response.statusCode}.',
        uri: Uri.parse(url),
      );
    }
    return utf8.decode(await consolidateHttpClientResponseBytes(response));
  }

  _ParsedMediaPlaylist _parseMediaPlaylist(String text) {
    final lines = text.split(RegExp(r'\r?\n'));
    final segments = <_ParsedMediaSegment>[];
    String? versionLine;
    int? targetDurationSeconds;
    String? mapUri;
    var nextSequenceNumber = 0;
    String? pendingExtinfLine;
    DateTime? pendingProgramDateTime;

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      if (_blockedLlHlsTags.any(trimmed.startsWith)) {
        continue;
      }
      if (trimmed.startsWith('#EXT-X-VERSION:')) {
        versionLine = trimmed;
        continue;
      }
      if (trimmed.startsWith('#EXT-X-TARGETDURATION:')) {
        targetDurationSeconds = int.tryParse(
          trimmed.substring('#EXT-X-TARGETDURATION:'.length).trim(),
        );
        continue;
      }
      if (trimmed.startsWith('#EXT-X-MEDIA-SEQUENCE:')) {
        nextSequenceNumber = int.tryParse(
              trimmed.substring('#EXT-X-MEDIA-SEQUENCE:'.length).trim(),
            ) ??
            nextSequenceNumber;
        continue;
      }
      if (trimmed.startsWith('#EXT-X-MAP:')) {
        mapUri = _extractQuotedUri(trimmed);
        continue;
      }
      if (trimmed.startsWith('#EXT-X-PROGRAM-DATE-TIME:')) {
        pendingProgramDateTime = DateTime.tryParse(
          trimmed.substring('#EXT-X-PROGRAM-DATE-TIME:'.length).trim(),
        );
        continue;
      }
      if (trimmed.startsWith('#EXTINF:')) {
        pendingExtinfLine = trimmed;
        continue;
      }
      if (trimmed.startsWith('#')) {
        continue;
      }
      if (pendingExtinfLine == null) {
        continue;
      }
      segments.add(
        _ParsedMediaSegment(
          sequenceNumber: nextSequenceNumber,
          extinfLine: pendingExtinfLine,
          uri: trimmed,
          programDateTime: pendingProgramDateTime,
        ),
      );
      nextSequenceNumber += 1;
      pendingExtinfLine = null;
      pendingProgramDateTime = null;
    }

    return _ParsedMediaPlaylist(
      versionLine: versionLine,
      targetDurationSeconds: targetDurationSeconds,
      mapUri: mapUri,
      segments: segments,
    );
  }

  String? _extractQuotedUri(String line) {
    final match = RegExp(r'URI="([^"]+)"').firstMatch(line);
    return match?.group(1)?.trim();
  }

  Future<List<_StoredMediaSegment>> _resolvePlayableSegmentsForRequest({
    required _ChaturbateLlHlsSession session,
    required _ChaturbateLlHlsMediaKind mediaKind,
    required _ChaturbateLlHlsMediaTimeline timeline,
  }) async {
    _startSessionRefreshIfNeeded(session);
    if (session.playlistSnapshotFor(mediaKind) == null) {
      final startupSegments = await _resolveStartupSegmentsForInitialPlaylist(
        session: session,
        timeline: timeline,
      );
      if (startupSegments.isNotEmpty) {
        return startupSegments;
      }
    }
    var segments = _selectPlayableSegments(
      session: session,
      mediaKind: mediaKind,
      timeline: timeline,
    );
    if (!_shouldWaitForPlayableAdvance(
      session: session,
      mediaKind: mediaKind,
      timeline: timeline,
      segments: segments,
    )) {
      return segments;
    }

    final deadline = DateTime.now().add(_playlistAdvanceWaitTimeout);
    while (DateTime.now().isBefore(deadline)) {
      _startSessionRefreshIfNeeded(session);
      _startStableAssetPrefetchIfNeeded(session);
      await _waitForSessionProgress(
        session,
        _remainingPlaylistAdvanceWait(deadline),
      );
      final refreshedSegments = _selectPlayableSegments(
        session: session,
        mediaKind: mediaKind,
        timeline: timeline,
      );
      if (_playlistResponseAdvanced(
        previous: segments,
        next: refreshedSegments,
      )) {
        return refreshedSegments;
      }
      segments = refreshedSegments;
      if (!_shouldKeepWaitingForPlayableAdvance(
        session: session,
        timeline: timeline,
        segments: segments,
      )) {
        break;
      }
    }
    return segments;
  }

  Future<List<_StoredMediaSegment>> _resolveStartupSegmentsForInitialPlaylist({
    required _ChaturbateLlHlsSession session,
    required _ChaturbateLlHlsMediaTimeline timeline,
  }) async {
    final startupPolicy = _startupPolicyForSession(session);
    final deadline =
        DateTime.now().add(startupPolicy.initialPlaylistStartupWaitTimeout);
    var lastProgressSignature = _sessionStartupProgressSignature(session);
    var lastProgressAt = DateTime.now();
    while (true) {
      final startupSegments = _selectStartupSegments(
        session: session,
        timeline: timeline,
      );
      if (startupSegments.isEmpty) {
        return const <_StoredMediaSegment>[];
      }
      final cachedStartupPrefix = _selectCachedPrefix(
        session: session,
        segments: startupSegments,
      );
      if (_meetsStartupServingThreshold(
        startupSegments: startupSegments,
        cachedStartupPrefixCount: cachedStartupPrefix.length,
        minimumStartupPlayableSegmentCount:
            startupPolicy.minimumStartupPlayableSegmentCount,
      )) {
        return _trimStartupSegmentsForPlayback(
          startupSegments,
          warmSegmentCount: startupPolicy.warmSegmentCount,
        );
      }
      if (_meetsImmediateStartupServingThreshold(
        startupSegments: startupSegments,
        cachedStartupPrefix: cachedStartupPrefix,
        minimumStartupPlayableSegmentCount:
            startupPolicy.minimumStartupPlayableSegmentCount,
        minimumStartupImmediateServeSegmentCount:
            startupPolicy.minimumStartupImmediateServeSegmentCount,
      )) {
        return _trimStartupSegmentsForPlayback(
          startupSegments,
          warmSegmentCount: startupPolicy.warmSegmentCount,
        );
      }
      final progressSignature = _sessionStartupProgressSignature(session);
      if (_startupProgressAdvanced(
        previous: lastProgressSignature,
        next: progressSignature,
      )) {
        lastProgressSignature = progressSignature;
        lastProgressAt = DateTime.now();
      }
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero ||
          DateTime.now().difference(lastProgressAt) >=
              _startupProgressPatience(session)) {
        if (cachedStartupPrefix.isNotEmpty &&
            startupSegments.length >=
                startupPolicy.minimumStartupPlayableSegmentCount) {
          return _trimStartupSegmentsForPlayback(
            startupSegments,
            warmSegmentCount: startupPolicy.warmSegmentCount,
          );
        }
        return startupSegments
            .take(min(startupPolicy.warmSegmentCount, startupSegments.length))
            .toList(growable: false);
      }
      _startSessionRefreshIfNeeded(session, force: true);
      _startStableAssetPrefetchIfNeeded(session);
      await _waitForSessionProgress(
        session,
        remaining < _playlistAdvancePollInterval
            ? remaining
            : _playlistAdvancePollInterval,
      );
    }
  }

  Duration _remainingPlaylistAdvanceWait(DateTime deadline) {
    final remaining = deadline.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      return Duration.zero;
    }
    if (remaining < _playlistAdvancePollInterval) {
      return remaining;
    }
    return _playlistAdvancePollInterval;
  }

  Future<void> _waitForSessionProgress(
    _ChaturbateLlHlsSession session,
    Duration timeout,
  ) async {
    if (timeout <= Duration.zero) {
      return;
    }
    try {
      final refresh = session.refreshInFlight;
      if (refresh != null) {
        await refresh.timeout(timeout);
        return;
      }
      final prefetch = session.assetPrefetchInFlight;
      if (prefetch != null) {
        await prefetch.timeout(timeout);
        return;
      }
      await Future<void>.delayed(timeout);
    } on TimeoutException {
      // Poll again until the bounded playlist wait budget is exhausted.
    }
  }

  bool _shouldWaitForPlayableAdvance({
    required _ChaturbateLlHlsSession session,
    required _ChaturbateLlHlsMediaKind mediaKind,
    required _ChaturbateLlHlsMediaTimeline timeline,
    required List<_StoredMediaSegment> segments,
  }) {
    if (segments.isEmpty || !_allSegmentsCached(session, segments)) {
      return false;
    }
    final snapshot = session.playlistSnapshotFor(mediaKind);
    if (snapshot == null) {
      return false;
    }
    if (DateTime.now().difference(snapshot.servedAt) >
        _playlistSnapshotFreshWindow) {
      return false;
    }
    final servingSameEdge =
        segments.last.sequenceNumber <= snapshot.lastSequenceNumber &&
            segments.length <= snapshot.segmentCount &&
            segments.first.sequenceNumber == snapshot.firstSequenceNumber;
    if (!servingSameEdge) {
      return false;
    }
    return _shouldKeepWaitingForPlayableAdvance(
      session: session,
      timeline: timeline,
      segments: segments,
    );
  }

  bool _shouldKeepWaitingForPlayableAdvance({
    required _ChaturbateLlHlsSession session,
    required _ChaturbateLlHlsMediaTimeline timeline,
    required List<_StoredMediaSegment> segments,
  }) {
    final stableSegments = _selectStableSegments(
      session: session,
      timeline: timeline,
    );
    final hasUncachedStableTail = segments.length < stableSegments.length;
    final refreshDue = DateTime.now().difference(session.lastRefreshAt) >=
        _minimumRefreshInterval;
    return hasUncachedStableTail ||
        refreshDue ||
        session.refreshInFlight != null ||
        session.hasPendingAssetPrefetches ||
        session.assetPrefetchInFlight != null;
  }

  bool _playlistResponseAdvanced({
    required List<_StoredMediaSegment> previous,
    required List<_StoredMediaSegment> next,
  }) {
    if (next.isEmpty) {
      return false;
    }
    if (previous.isEmpty) {
      return true;
    }
    return next.last.sequenceNumber > previous.last.sequenceNumber ||
        next.length > previous.length ||
        next.first.sequenceNumber != previous.first.sequenceNumber;
  }

  bool _allSegmentsCached(
    _ChaturbateLlHlsSession session,
    List<_StoredMediaSegment> segments,
  ) {
    for (final segment in segments) {
      final asset = session.assets[segment.assetId];
      if (asset == null || !asset.hasCachedBody) {
        return false;
      }
    }
    return true;
  }

  String _buildSyntheticMediaPlaylist({
    required _ChaturbateLlHlsSession session,
    required _ChaturbateLlHlsMediaTimeline timeline,
    required List<_StoredMediaSegment> segments,
  }) {
    if (segments.isEmpty) {
      throw StateError('Chaturbate proxy timeline is empty.');
    }
    return <String>[
      '#EXTM3U',
      timeline.versionLine,
      '#EXT-X-TARGETDURATION:${timeline.targetDurationSeconds}',
      '#EXT-X-MEDIA-SEQUENCE:${segments.first.sequenceNumber}',
      if (_shouldEmitMapForSyntheticPlaylist(
        session: session,
        timeline: timeline,
        segments: segments,
      ))
        '#EXT-X-MAP:URI="${_localAssetUri(session.id, timeline.initAssetId!).toString()}"',
      for (final segment in segments) ...[
        segment.extinfLine,
        _localAssetUri(session.id, segment.assetId).toString(),
      ],
    ].join('\n');
  }

  List<_StoredMediaSegment> _trimSegmentsForMapDecision({
    required _ChaturbateLlHlsSession session,
    required _ChaturbateLlHlsMediaTimeline timeline,
    required List<_StoredMediaSegment> segments,
  }) {
    final firstSelfInitializedIndex = _firstSelfInitializedSegmentIndex(
      session: session,
      timeline: timeline,
      segments: segments,
    );
    if (firstSelfInitializedIndex != null) {
      if (firstSelfInitializedIndex == 0) {
        return segments;
      }
      return segments
          .sublist(firstSelfInitializedIndex)
          .toList(growable: false);
    }
    if (timeline.initAssetId == null || segments.isEmpty) {
      return segments;
    }
    final initRequiredPrefix = <_StoredMediaSegment>[];
    for (final segment in segments) {
      final asset = session.assets[segment.assetId];
      final bytes = asset?.cachedBytes;
      if (bytes == null) {
        break;
      }
      if (chaturbateMp4BytesContainInitialization(bytes)) {
        timeline.recordSelfInitializedSequence(segment.sequenceNumber);
        break;
      }
      initRequiredPrefix.add(segment);
    }
    if (initRequiredPrefix.isNotEmpty) {
      return initRequiredPrefix;
    }
    return segments.take(1).toList(growable: false);
  }

  bool _shouldEmitMapForSyntheticPlaylist({
    required _ChaturbateLlHlsSession session,
    required _ChaturbateLlHlsMediaTimeline timeline,
    required List<_StoredMediaSegment> segments,
  }) {
    if (timeline.initAssetId == null || segments.isEmpty) {
      return false;
    }
    final firstSelfInitializedIndex = _firstSelfInitializedSegmentIndex(
      session: session,
      timeline: timeline,
      segments: segments,
    );
    return firstSelfInitializedIndex == null;
  }

  void _logSyntheticPlaylistDecision({
    required _ChaturbateLlHlsSession session,
    required _ChaturbateLlHlsMediaKind mediaKind,
    required _ChaturbateLlHlsMediaTimeline timeline,
    required List<_StoredMediaSegment> originalSegments,
    required List<_StoredMediaSegment> playlistSegments,
  }) {
    if (!kDebugMode || playlistSegments.isEmpty) {
      return;
    }
    final emitsMap = _shouldEmitMapForSyntheticPlaylist(
      session: session,
      timeline: timeline,
      segments: playlistSegments,
    );
    final message = 'playlist decision '
        'session=${session.id} kind=${mediaKind.name} '
        'original=${_segmentRangeLabel(originalSegments)} '
        'served=${_segmentRangeLabel(playlistSegments)} '
        'emitMap=$emitsMap '
        'selfInitializedFrom=${timeline.selfInitializedFromSequence ?? '-'}';
    debugPrint('ChaturbateLlHlsProxy $message');
    AppLog.instance.info('chaturbate/proxy', message);
  }

  String _segmentRangeLabel(List<_StoredMediaSegment> segments) {
    if (segments.isEmpty) {
      return 'empty';
    }
    return '${segments.first.sequenceNumber}-${segments.last.sequenceNumber}/${segments.length}';
  }

  int? _firstSelfInitializedSegmentIndex({
    required _ChaturbateLlHlsSession session,
    required _ChaturbateLlHlsMediaTimeline timeline,
    required List<_StoredMediaSegment> segments,
  }) {
    final knownSelfInitializedFromSequence =
        timeline.selfInitializedFromSequence;
    if (knownSelfInitializedFromSequence != null) {
      for (var index = 0; index < segments.length; index += 1) {
        if (segments[index].sequenceNumber >=
            knownSelfInitializedFromSequence) {
          return index;
        }
      }
    }
    for (var index = 0; index < segments.length; index += 1) {
      final segment = segments[index];
      final asset = session.assets[segment.assetId];
      final bytes = asset?.cachedBytes;
      if (bytes != null && chaturbateMp4BytesContainInitialization(bytes)) {
        timeline.recordSelfInitializedSequence(segment.sequenceNumber);
        return index;
      }
    }
    return null;
  }

  Future<void> _sniffPlaylistWindowForMapDecision({
    required _ChaturbateLlHlsSession session,
    required List<_StoredMediaSegment> segments,
  }) async {
    final assetIds = <String>{};
    for (final segment in segments) {
      final asset = session.assets[segment.assetId];
      if (asset != null && !asset.hasCachedBody) {
        assetIds.add(segment.assetId);
      }
    }
    if (assetIds.isEmpty) {
      return;
    }
    await Future.wait<void>(assetIds.map((assetId) async {
      try {
        await _cacheAssetIfNeeded(
          session: session,
          assetId: assetId,
        ).timeout(_playlistMapDecisionSniffTimeout);
      } catch (_) {
        // Best-effort sniff only; unresolved assets keep lazy fetch behavior.
      }
    }));
  }

  List<_StoredMediaSegment> _selectStableSegments({
    required _ChaturbateLlHlsSession session,
    required _ChaturbateLlHlsMediaTimeline timeline,
  }) {
    final ordered = timeline.orderedSegments;
    if (ordered.isEmpty) {
      return const <_StoredMediaSegment>[];
    }
    final cutoff = _stableProgramDateTimeCutoff(session);
    if (cutoff != null) {
      final stableByTime = ordered.where((segment) {
        final programDateTime = segment.programDateTime;
        return programDateTime == null || !programDateTime.isAfter(cutoff);
      }).toList(growable: false);
      if (stableByTime.length >= _stableWindowMinimumSegments) {
        final start = max(0, stableByTime.length - _stableWindowSegmentLimit);
        return stableByTime.sublist(start);
      }
    }
    final trimCount = _edgeTrimCount(ordered.length);
    final end = max(1, ordered.length - trimCount);
    final start = max(0, end - _stableWindowSegmentLimit);
    return ordered.sublist(start, end);
  }

  List<_StoredMediaSegment> _selectPlayableSegments({
    required _ChaturbateLlHlsSession session,
    required _ChaturbateLlHlsMediaKind mediaKind,
    required _ChaturbateLlHlsMediaTimeline timeline,
  }) {
    final startupPolicy = _startupPolicyForSession(session);
    final startupSegments = _selectStartupSegments(
      session: session,
      timeline: timeline,
    );
    final servesInitialPlaylist =
        session.playlistSnapshotFor(mediaKind) == null;
    if (servesInitialPlaylist && startupSegments.isNotEmpty) {
      final cachedStartupPrefix = _selectCachedPrefix(
        session: session,
        segments: startupSegments,
      );
      if (_meetsStartupServingThreshold(
        startupSegments: startupSegments,
        cachedStartupPrefixCount: cachedStartupPrefix.length,
        minimumStartupPlayableSegmentCount:
            startupPolicy.minimumStartupPlayableSegmentCount,
      )) {
        return _trimStartupSegmentsForPlayback(
          startupSegments,
          warmSegmentCount: startupPolicy.warmSegmentCount,
        );
      }
      if (_meetsImmediateStartupServingThreshold(
        startupSegments: startupSegments,
        cachedStartupPrefix: cachedStartupPrefix,
        minimumStartupPlayableSegmentCount:
            startupPolicy.minimumStartupPlayableSegmentCount,
        minimumStartupImmediateServeSegmentCount:
            startupPolicy.minimumStartupImmediateServeSegmentCount,
      )) {
        return _trimStartupSegmentsForPlayback(
          startupSegments,
          warmSegmentCount: startupPolicy.warmSegmentCount,
        );
      }
      if (cachedStartupPrefix.isNotEmpty &&
          startupSegments.length >=
              startupPolicy.minimumStartupPlayableSegmentCount) {
        return _trimStartupSegmentsForPlayback(
          startupSegments,
          warmSegmentCount: startupPolicy.warmSegmentCount,
        );
      }
      return startupSegments
          .take(min(startupPolicy.warmSegmentCount, startupSegments.length))
          .toList(growable: false);
    }
    final stableSegments = _selectStableSegments(
      session: session,
      timeline: timeline,
    );
    if (stableSegments.isEmpty) {
      return const <_StoredMediaSegment>[];
    }
    final cachedPrefix = _selectCachedPrefix(
      session: session,
      segments: stableSegments,
    );
    if (cachedPrefix.isNotEmpty) {
      return stableSegments;
    }
    if (kDebugMode) {
      debugPrint(
        'ChaturbateLlHlsProxy exposing uncached ${mediaKind.name} stable '
        'segments as fallback.',
      );
    }
    return stableSegments
        .take(startupPolicy.warmSegmentCount)
        .toList(growable: false);
  }

  bool _meetsStartupServingThreshold({
    required List<_StoredMediaSegment> startupSegments,
    required int cachedStartupPrefixCount,
    required int minimumStartupPlayableSegmentCount,
  }) {
    if (startupSegments.length < minimumStartupPlayableSegmentCount) {
      return false;
    }
    return cachedStartupPrefixCount >= minimumStartupPlayableSegmentCount;
  }

  bool _meetsImmediateStartupServingThreshold({
    required List<_StoredMediaSegment> startupSegments,
    required List<_StoredMediaSegment> cachedStartupPrefix,
    required int minimumStartupPlayableSegmentCount,
    required int minimumStartupImmediateServeSegmentCount,
  }) {
    return shouldServeChaturbateStartupPlaylistEarly(
      startupSegmentCount: startupSegments.length,
      cachedStartupPrefixCount: cachedStartupPrefix.length,
      minimumStartupPlayableSegmentCount: minimumStartupPlayableSegmentCount,
      minimumStartupImmediateServeSegmentCount:
          minimumStartupImmediateServeSegmentCount,
    );
  }

  List<_StoredMediaSegment> _selectStartupSegments({
    required _ChaturbateLlHlsSession session,
    required _ChaturbateLlHlsMediaTimeline timeline,
  }) {
    final startupPolicy = _startupPolicyForSession(session);
    final ordered = timeline.orderedSegments;
    if (ordered.isEmpty) {
      return const <_StoredMediaSegment>[];
    }
    final trimCount = min(
      _startupEdgeTrimSegments,
      max(0, ordered.length - _stableWindowMinimumSegments),
    );
    final end = max(1, ordered.length - trimCount);
    final start = max(0, end - _startupWindowSegmentLimit);
    final startupSegments = ordered.sublist(start, end);
    if (startupSegments.length >= startupPolicy.warmSegmentCount) {
      return startupSegments;
    }
    final stableSegments = _selectStableSegments(
      session: session,
      timeline: timeline,
    );
    if (stableSegments.length > startupSegments.length) {
      return stableSegments;
    }
    return startupSegments;
  }

  List<_StoredMediaSegment> _selectCachedPrefix({
    required _ChaturbateLlHlsSession session,
    required List<_StoredMediaSegment> segments,
  }) {
    var cachedCount = 0;
    for (final segment in segments) {
      final asset = session.assets[segment.assetId];
      if (asset == null || !asset.hasCachedBody) {
        break;
      }
      cachedCount += 1;
    }
    if (cachedCount <= 0) {
      return const <_StoredMediaSegment>[];
    }
    return segments.take(cachedCount).toList(growable: false);
  }

  bool _sessionHasDesiredStartupCoverage(_ChaturbateLlHlsSession session) {
    final startupPolicy = _startupPolicyForSession(session);
    final videoStartupSegments = _selectStartupSegments(
      session: session,
      timeline: session.videoTimeline,
    );
    final audioStartupSegments = _selectStartupSegments(
      session: session,
      timeline: session.audioTimeline,
    );
    return _meetsStartupServingThreshold(
          startupSegments: videoStartupSegments,
          cachedStartupPrefixCount: _selectCachedPrefix(
            session: session,
            segments: videoStartupSegments,
          ).length,
          minimumStartupPlayableSegmentCount:
              startupPolicy.minimumStartupPlayableSegmentCount,
        ) &&
        _meetsStartupServingThreshold(
          startupSegments: audioStartupSegments,
          cachedStartupPrefixCount: _selectCachedPrefix(
            session: session,
            segments: audioStartupSegments,
          ).length,
          minimumStartupPlayableSegmentCount:
              startupPolicy.minimumStartupPlayableSegmentCount,
        );
  }

  List<_StoredMediaSegment> _trimStartupSegmentsForPlayback(
    List<_StoredMediaSegment> segments, {
    required int warmSegmentCount,
  }) {
    if (segments.isEmpty) {
      return const <_StoredMediaSegment>[];
    }
    final start = max(0, segments.length - warmSegmentCount);
    return segments.sublist(start).toList(growable: false);
  }

  ({int videoLastSequence, int audioLastSequence})
      _sessionStartupProgressSignature(_ChaturbateLlHlsSession session) {
    final videoSegments = session.videoTimeline.orderedSegments;
    final audioSegments = session.audioTimeline.orderedSegments;
    return (
      videoLastSequence:
          videoSegments.isEmpty ? -1 : videoSegments.last.sequenceNumber,
      audioLastSequence:
          audioSegments.isEmpty ? -1 : audioSegments.last.sequenceNumber,
    );
  }

  bool _startupProgressAdvanced({
    required ({int videoLastSequence, int audioLastSequence}) previous,
    required ({int videoLastSequence, int audioLastSequence}) next,
  }) {
    return next.videoLastSequence > previous.videoLastSequence ||
        next.audioLastSequence > previous.audioLastSequence;
  }

  Duration _startupProgressPatience(_ChaturbateLlHlsSession session) {
    final patienceSeconds = max(
      2,
      max(
        session.videoTimeline.targetDurationSeconds,
        session.audioTimeline.targetDurationSeconds,
      ),
    );
    return Duration(seconds: patienceSeconds);
  }

  int _edgeTrimCount(int length) {
    if (length <= _stableWindowMinimumSegments) {
      return 0;
    }
    return min(_stableEdgeTrimSegments, length - _stableWindowMinimumSegments);
  }

  DateTime? _stableProgramDateTimeCutoff(_ChaturbateLlHlsSession session) {
    final videoLatest = session.videoTimeline.latestProgramDateTime;
    final audioLatest = session.audioTimeline.latestProgramDateTime;
    if (videoLatest == null || audioLatest == null) {
      return null;
    }
    final base = videoLatest.isBefore(audioLatest) ? videoLatest : audioLatest;
    final holdBackSeconds = max(
          session.videoTimeline.targetDurationSeconds,
          session.audioTimeline.targetDurationSeconds,
        ) *
        _stableEdgeTrimSegments;
    return base.subtract(Duration(seconds: max(2, holdBackSeconds)));
  }

  Uri _localAssetUri(String sessionId, String assetId) {
    final endpoint = _endpoint;
    if (endpoint == null) {
      throw StateError('ChaturbateLlHlsProxy has not been started.');
    }
    return endpoint.replace(
      path: '${endpoint.path}/$sessionId/asset/$assetId',
    );
  }

  Future<void> _pipeAsset(
    HttpResponse response, {
    required _ChaturbateLlHlsSession session,
    required String assetId,
  }) async {
    final assetReady = await _awaitAssetPayloadForServe(
      session: session,
      assetId: assetId,
    );
    if (!assetReady) {
      response.statusCode = HttpStatus.badGateway;
      await response.close();
      return;
    }
    final asset = session.assets[assetId];
    final bytes = asset?.cachedBytes;
    if (asset == null || bytes == null) {
      response.statusCode = HttpStatus.badGateway;
      await response.close();
      return;
    }
    response.statusCode = HttpStatus.ok;
    response.contentLength = bytes.lengthInBytes;
    final contentType = asset.contentType;
    if (contentType != null) {
      response.headers.contentType = contentType;
    }
    final cacheControl = asset.cacheControl;
    if (cacheControl != null && cacheControl.isNotEmpty) {
      response.headers.set(HttpHeaders.cacheControlHeader, cacheControl);
    }
    response.add(bytes);
    await response.close();
  }

  Future<bool> _awaitAssetPayloadForServe({
    required _ChaturbateLlHlsSession session,
    required String assetId,
  }) async {
    final availabilityTimeout = session.isInitAsset(assetId)
        ? _initAssetAvailabilityWaitTimeout
        : _lateAssetAvailabilityWaitTimeout;
    final deadline = DateTime.now().add(availabilityTimeout);
    while (true) {
      final asset = session.assets[assetId];
      if (asset == null) {
        return false;
      }
      if (asset.hasCachedBody) {
        return true;
      }
      try {
        await _cacheAssetIfNeeded(
          session: session,
          assetId: assetId,
        );
      } catch (error) {
        if (kDebugMode) {
          debugPrint('ChaturbateLlHlsProxy asset fetch failed: $error');
        }
      }
      final refreshedAsset = session.assets[assetId];
      if (refreshedAsset != null && refreshedAsset.hasCachedBody) {
        return true;
      }
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) {
        return refreshedAsset?.hasCachedBody ?? false;
      }
      session.prioritizePendingAssetPrefetches(<String>[assetId]);
      _startSessionRefreshIfNeeded(session, force: true);
      _startStableAssetPrefetchIfNeeded(session);
      await _waitForSessionProgress(
        session,
        remaining < _assetAvailabilityPollInterval
            ? remaining
            : _assetAvailabilityPollInterval,
      );
    }
  }

  void _synchronizeSessionAssets(_ChaturbateLlHlsSession session) {
    final retainedAssetIds = <String>{};
    session.videoTimeline.appendRetainedAssetIds(retainedAssetIds);
    session.audioTimeline.appendRetainedAssetIds(retainedAssetIds);
    session.pruneAssets(retainedAssetIds);
  }

  void _startStableAssetPrefetchIfNeeded(_ChaturbateLlHlsSession session) {
    if (!session.hasTimelineData) {
      return;
    }
    session.prioritizePendingAssetPrefetches(_collectStableAssetIds(session));
    if (!session.hasPendingAssetPrefetches) {
      return;
    }
    if (session.assetPrefetchInFlight != null) {
      _kickUrgentStableAssetPrefetch(session);
      return;
    }
    final prefetch = _drainStableAssetPrefetchQueue(session: session);
    session.assetPrefetchInFlight = prefetch;
    unawaited(_finalizeStableAssetPrefetch(session, prefetch));
  }

  Future<void> _finalizeStableAssetPrefetch(
    _ChaturbateLlHlsSession session,
    Future<void> prefetch,
  ) async {
    try {
      await prefetch;
    } finally {
      if (identical(session.assetPrefetchInFlight, prefetch)) {
        session.assetPrefetchInFlight = null;
      }
    }
  }

  Future<void> _drainStableAssetPrefetchQueue({
    required _ChaturbateLlHlsSession session,
  }) async {
    final inFlight = <Future<void>>[];

    void startNext(String assetId) {
      late final Future<void> tracked;
      tracked = (() async {
        try {
          await _cacheAssetIfNeeded(
            session: session,
            assetId: assetId,
          );
        } catch (_) {
          // Keep playback moving even if one upstream segment vanished.
        } finally {
          inFlight.remove(tracked);
        }
      })();
      inFlight.add(tracked);
    }

    while (true) {
      while (inFlight.length < _assetPrefetchBatchSize) {
        final assetId = session.takeNextPendingAssetPrefetchId();
        if (assetId == null) {
          break;
        }
        startNext(assetId);
      }
      if (inFlight.isEmpty) {
        return;
      }
      try {
        await Future.any(inFlight).timeout(_assetPrefetchPollInterval);
      } on TimeoutException {
        // Keep polling so newer stable-window assets can enter free slots
        // even if an older upstream segment fetch is still stalled.
      }
      await Future<void>.delayed(Duration.zero);
    }
  }

  List<String> _collectStableAssetIds(_ChaturbateLlHlsSession session) {
    final assetIds = <String>{};
    void addTimeline(
      _ChaturbateLlHlsMediaTimeline timeline,
      List<_StoredMediaSegment> segments,
    ) {
      final initAssetId = timeline.initAssetId;
      if (initAssetId != null) {
        assetIds.add(initAssetId);
      }
      for (final segment in segments) {
        assetIds.add(segment.assetId);
      }
    }

    addTimeline(
      session.videoTimeline,
      _selectStableSegments(
        session: session,
        timeline: session.videoTimeline,
      ),
    );
    addTimeline(
      session.audioTimeline,
      _selectStableSegments(
        session: session,
        timeline: session.audioTimeline,
      ),
    );
    return assetIds.toList(growable: false);
  }

  Future<void> _warmStartupAssetsIfNeeded(
    _ChaturbateLlHlsSession session,
  ) async {
    final startupPolicy = _startupPolicyForSession(session);
    final assetIds = <String>{};

    void addCriticalAssets(_ChaturbateLlHlsMediaTimeline timeline) {
      final initAssetId = timeline.initAssetId;
      if (initAssetId != null) {
        assetIds.add(initAssetId);
      }
      for (final segment in _trimStartupSegmentsForPlayback(
        _selectStartupSegments(
          session: session,
          timeline: timeline,
        ),
        warmSegmentCount: startupPolicy.warmSegmentCount,
      )) {
        assetIds.add(segment.assetId);
      }
    }

    addCriticalAssets(session.videoTimeline);
    addCriticalAssets(session.audioTimeline);
    if (assetIds.isEmpty) {
      return;
    }
    await Future.wait<void>(assetIds.map((assetId) async {
      try {
        await _cacheAssetIfNeeded(
          session: session,
          assetId: assetId,
        );
      } catch (_) {
        // Fall back to lazy per-request fetch if a warm asset disappears.
      }
    }));
  }

  void _kickUrgentStableAssetPrefetch(_ChaturbateLlHlsSession session) {
    final urgentAssetIds = <String>{};

    void addFrontierAndLatestCriticalAssets(
        _ChaturbateLlHlsMediaTimeline timeline) {
      final segments = _selectStableSegments(
        session: session,
        timeline: timeline,
      );
      for (final segment in segments) {
        final asset = session.assets[segment.assetId];
        if (asset != null && !asset.hasCachedBody) {
          urgentAssetIds.add(segment.assetId);
          break;
        }
      }
      for (final segment
          in segments.reversed.take(_urgentEdgePrefetchSegmentCount)) {
        final asset = session.assets[segment.assetId];
        if (asset != null && !asset.hasCachedBody) {
          urgentAssetIds.add(segment.assetId);
        }
      }
    }

    addFrontierAndLatestCriticalAssets(session.videoTimeline);
    addFrontierAndLatestCriticalAssets(session.audioTimeline);
    for (final assetId in urgentAssetIds) {
      unawaited(() async {
        try {
          await _cacheAssetIfNeeded(
            session: session,
            assetId: assetId,
          );
        } catch (_) {
          // Best-effort fast lane for the newest stable edge assets.
        }
      }());
    }
  }

  Future<void> _cacheAssetIfNeeded({
    required _ChaturbateLlHlsSession session,
    required String assetId,
  }) async {
    final asset = session.assets[assetId];
    if (asset == null || asset.hasCachedBody) {
      return;
    }
    final inFlight = asset.cacheInFlight;
    if (inFlight != null) {
      await inFlight;
      return;
    }
    final fetch = _fetchAndStoreAsset(
      session: session,
      assetId: assetId,
    );
    asset.cacheInFlight = fetch;
    try {
      await fetch;
    } finally {
      if (identical(asset.cacheInFlight, fetch)) {
        asset.cacheInFlight = null;
      }
    }
  }

  Future<void> _fetchAndStoreAsset({
    required _ChaturbateLlHlsSession session,
    required String assetId,
  }) async {
    final asset = session.assets[assetId];
    if (asset == null) {
      return;
    }
    final request = await _client.getUrl(Uri.parse(asset.url));
    asset.headers.forEach(request.headers.set);
    final upstream = await request.close();
    if (upstream.statusCode < 200 || upstream.statusCode >= 300) {
      await upstream.drain<void>();
      throw HttpException(
        'Chaturbate proxy asset upstream request failed with '
        '${upstream.statusCode}.',
        uri: Uri.parse(asset.url),
      );
    }
    final bytes = Uint8List.fromList(
      await consolidateHttpClientResponseBytes(upstream),
    );
    session.storeAssetPayload(
      assetId: assetId,
      bytes: bytes,
      contentType: upstream.headers.contentType,
      cacheControl: upstream.headers.value(HttpHeaders.cacheControlHeader),
    );
  }

  void _purgeExpiredSessions() {
    final now = DateTime.now();
    _sessions.removeWhere((_, session) {
      return now.difference(session.lastTouchedAt) > _sessionTtl;
    });
  }

  String _firstNonEmpty(Iterable<String?> candidates) {
    for (final candidate in candidates) {
      final trimmed = candidate?.trim() ?? '';
      if (trimmed.isNotEmpty) {
        return trimmed;
      }
    }
    return '';
  }

  int? _readFirstPositiveInt(List<Object?> values) {
    for (final value in values) {
      final parsed = int.tryParse(value?.toString() ?? '');
      if (parsed != null && parsed > 0) {
        return parsed;
      }
    }
    return null;
  }

  Map<String, String> _readHeadersMap(Object? raw) {
    if (raw is! Map) {
      return const <String, String>{};
    }
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

  bool _looksLikeMmcdnLlHlsPlaylist(String rawUrl) {
    final uri = Uri.tryParse(rawUrl);
    if (uri == null) {
      return false;
    }
    final host = uri.host.toLowerCase();
    final path = uri.path.toLowerCase();
    return (host.endsWith('live.mmcdn.com') ||
            host == InternetAddress.loopbackIPv4.address ||
            host == 'localhost') &&
        path.contains('/v1/edge/streams/') &&
        path.contains('llhls') &&
        path.endsWith('.m3u8');
  }

  bool _looksLikeLocalProxyUrl(String rawUrl) {
    final uri = Uri.tryParse(rawUrl);
    if (uri == null) {
      return false;
    }
    return uri.host == InternetAddress.loopbackIPv4.address &&
        uri.path.contains(_routePrefix);
  }

  String _randomToken(int length) {
    const alphabet =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random.secure();
    return List.generate(
      length,
      (_) => alphabet[random.nextInt(alphabet.length)],
    ).join();
  }

  bool get _supportsPlatform {
    final override = _enabledOverride;
    if (override != null) {
      return override;
    }
    if (kIsWeb) {
      return false;
    }
    return Platform.isAndroid || Platform.isIOS;
  }

  ChaturbateHlsVariant? _selectVariantForQuality({
    required LivePlayQuality quality,
    required List<ChaturbateHlsVariant> variants,
  }) {
    if (variants.isEmpty) {
      return null;
    }
    if (quality.id.trim().toLowerCase() == 'auto') {
      return _selectStartupSafeVariant(variants);
    }
    final requestedBandwidth = int.tryParse(quality.id.trim());
    if (requestedBandwidth != null) {
      for (final variant in variants) {
        if (variant.bandwidth == requestedBandwidth) {
          return variant;
        }
      }
      final sorted = [...variants]..sort((left, right) {
          final leftDelta = (left.bandwidth - requestedBandwidth).abs();
          final rightDelta = (right.bandwidth - requestedBandwidth).abs();
          final compare = leftDelta.compareTo(rightDelta);
          if (compare != 0) {
            return compare;
          }
          return left.bandwidth.compareTo(right.bandwidth);
        });
      return sorted.first;
    }
    final requestedLabel = quality.label.trim().toLowerCase();
    if (requestedLabel.isNotEmpty) {
      for (final variant in variants) {
        if (variant.label.trim().toLowerCase() == requestedLabel) {
          return variant;
        }
      }
    }
    return variants.first;
  }

  ChaturbateHlsVariant _selectStartupSafeVariant(
    List<ChaturbateHlsVariant> variants,
  ) {
    for (final variant in variants) {
      final height = variant.height ?? 0;
      if (height > 0 && height <= 720) {
        return variant;
      }
      final bandwidth = variant.bandwidth;
      if (bandwidth > 0 && bandwidth <= 3500000) {
        return variant;
      }
    }
    return variants.last;
  }

  String _resolveHlsBitrateForVariant({
    required LivePlayQuality quality,
    required ChaturbateHlsVariant variant,
  }) {
    final existing = quality.metadata?['hlsBitrate']?.toString().trim() ?? '';
    if (existing.isNotEmpty) {
      return existing;
    }
    if (quality.id.trim().toLowerCase() == 'auto') {
      return variant.bandwidth > 0 ? variant.bandwidth.toString() : 'max';
    }
    return variant.bandwidth > 0 ? variant.bandwidth.toString() : quality.id;
  }

  ({
    int warmSegmentCount,
    int minimumStartupPlayableSegmentCount,
    int minimumStartupImmediateServeSegmentCount,
    Duration initialPlaylistStartupWaitTimeout,
  }) _startupPolicyForSession(_ChaturbateLlHlsSession session) {
    return resolveChaturbateLlHlsStartupPolicy(
      bandwidth: session.bandwidth,
      height: session.height,
    );
  }
}

class _ChaturbateLlHlsSession {
  _ChaturbateLlHlsSession({
    required this.id,
    required this.videoPlaylistUrl,
    required this.videoHeaders,
    required this.audioPlaylistUrl,
    required this.audioHeaders,
    required this.bandwidth,
    required this.width,
    required this.height,
    required this.codecs,
  });

  final String id;
  final String videoPlaylistUrl;
  final Map<String, String> videoHeaders;
  final String audioPlaylistUrl;
  final Map<String, String> audioHeaders;
  final int bandwidth;
  final int? width;
  final int? height;
  final String? codecs;
  final Map<String, _ChaturbateLlHlsAsset> assets =
      <String, _ChaturbateLlHlsAsset>{};
  final _ChaturbateLlHlsMediaTimeline videoTimeline =
      _ChaturbateLlHlsMediaTimeline();
  final _ChaturbateLlHlsMediaTimeline audioTimeline =
      _ChaturbateLlHlsMediaTimeline();

  DateTime lastTouchedAt = DateTime.now();
  DateTime lastRefreshAt = DateTime.fromMillisecondsSinceEpoch(0);
  Future<void>? startupPrimeInFlight;
  Future<void>? refreshInFlight;
  Future<void>? assetPrefetchInFlight;
  final Set<String> _pendingAssetPrefetchIds = <String>{};
  final Map<_ChaturbateLlHlsMediaKind, _ServedPlaylistSnapshot>
      _servedPlaylistSnapshots =
      <_ChaturbateLlHlsMediaKind, _ServedPlaylistSnapshot>{};

  void touch() {
    lastTouchedAt = DateTime.now();
  }

  bool get hasTimelineData =>
      videoTimeline.hasSegments && audioTimeline.hasSegments;

  _ChaturbateLlHlsMediaTimeline timelineFor(_ChaturbateLlHlsMediaKind kind) {
    switch (kind) {
      case _ChaturbateLlHlsMediaKind.video:
        return videoTimeline;
      case _ChaturbateLlHlsMediaKind.audio:
        return audioTimeline;
    }
  }

  _ServedPlaylistSnapshot? playlistSnapshotFor(
    _ChaturbateLlHlsMediaKind kind,
  ) {
    return _servedPlaylistSnapshots[kind];
  }

  String playlistUrlFor(_ChaturbateLlHlsMediaKind kind) {
    switch (kind) {
      case _ChaturbateLlHlsMediaKind.video:
        return videoPlaylistUrl;
      case _ChaturbateLlHlsMediaKind.audio:
        return audioPlaylistUrl;
    }
  }

  Map<String, String> headersFor(_ChaturbateLlHlsMediaKind kind) {
    switch (kind) {
      case _ChaturbateLlHlsMediaKind.video:
        return videoHeaders;
      case _ChaturbateLlHlsMediaKind.audio:
        return audioHeaders;
    }
  }

  void recordServedPlaylist({
    required _ChaturbateLlHlsMediaKind mediaKind,
    required List<_StoredMediaSegment> segments,
    required String playlistBody,
  }) {
    if (segments.isEmpty) {
      return;
    }
    _servedPlaylistSnapshots[mediaKind] = _ServedPlaylistSnapshot(
      firstSequenceNumber: segments.first.sequenceNumber,
      lastSequenceNumber: segments.last.sequenceNumber,
      segmentCount: segments.length,
      servedAt: DateTime.now(),
      playlistBody: playlistBody,
    );
  }

  String registerAsset({
    required String url,
    required Map<String, String> headers,
  }) {
    for (final entry in assets.entries) {
      if (entry.value.url == url && mapEquals(entry.value.headers, headers)) {
        return entry.key;
      }
    }
    final assetId = _assetIdFor(url);
    assets[assetId] = _ChaturbateLlHlsAsset(
      url: url,
      headers: Map<String, String>.from(headers),
    );
    return assetId;
  }

  void storeAssetPayload({
    required String assetId,
    required Uint8List bytes,
    required ContentType? contentType,
    required String? cacheControl,
  }) {
    final asset = assets[assetId];
    if (asset == null) {
      return;
    }
    asset.cachedBytes = bytes;
    asset.contentType = contentType;
    asset.cacheControl = cacheControl;
    if (chaturbateMp4BytesContainInitialization(bytes)) {
      videoTimeline.recordSelfInitializedAsset(assetId);
      audioTimeline.recordSelfInitializedAsset(assetId);
    }
  }

  void pruneAssets(Set<String> retainedAssetIds) {
    assets.removeWhere((assetId, _) => !retainedAssetIds.contains(assetId));
    _pendingAssetPrefetchIds.removeWhere(
      (assetId) => !retainedAssetIds.contains(assetId),
    );
  }

  void prioritizePendingAssetPrefetches(Iterable<String> assetIds) {
    final nextQueue = <String>{};
    for (final assetId in assetIds) {
      final asset = assets[assetId];
      if (asset != null && !asset.hasCachedBody) {
        nextQueue.add(assetId);
      }
    }
    for (final assetId in _pendingAssetPrefetchIds) {
      final asset = assets[assetId];
      if (asset != null && !asset.hasCachedBody) {
        nextQueue.add(assetId);
      }
    }
    _pendingAssetPrefetchIds
      ..clear()
      ..addAll(nextQueue);
  }

  bool get hasPendingAssetPrefetches => _pendingAssetPrefetchIds.isNotEmpty;

  bool isInitAsset(String assetId) {
    return videoTimeline.initAssetId == assetId ||
        audioTimeline.initAssetId == assetId;
  }

  String? takeNextPendingAssetPrefetchId() {
    while (_pendingAssetPrefetchIds.isNotEmpty) {
      final assetId = _pendingAssetPrefetchIds.first;
      _pendingAssetPrefetchIds.remove(assetId);
      final asset = assets[assetId];
      if (asset != null && !asset.hasCachedBody) {
        return assetId;
      }
    }
    return null;
  }

  String _assetIdFor(String url) {
    final buffer = StringBuffer();
    for (final code in utf8.encode(url)) {
      buffer.write(code.toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }
}

class _ChaturbateLlHlsAsset {
  _ChaturbateLlHlsAsset({
    required this.url,
    required this.headers,
  });

  final String url;
  final Map<String, String> headers;
  Uint8List? cachedBytes;
  ContentType? contentType;
  String? cacheControl;
  Future<void>? cacheInFlight;

  bool get hasCachedBody => cachedBytes != null;
}

class _ServedPlaylistSnapshot {
  const _ServedPlaylistSnapshot({
    required this.firstSequenceNumber,
    required this.lastSequenceNumber,
    required this.segmentCount,
    required this.servedAt,
    required this.playlistBody,
  });

  final int firstSequenceNumber;
  final int lastSequenceNumber;
  final int segmentCount;
  final DateTime servedAt;
  final String playlistBody;

  int get firstSequence => firstSequenceNumber;
  int get lastSequence => lastSequenceNumber;
}

enum _ChaturbateLlHlsMediaKind {
  video,
  audio,
}

class _ChaturbateLlHlsMediaTimeline {
  final SplayTreeMap<int, _StoredMediaSegment> _segments =
      SplayTreeMap<int, _StoredMediaSegment>();

  String versionLine = '#EXT-X-VERSION:6';
  int targetDurationSeconds = 2;
  String? initAssetId;
  int? selfInitializedFromSequence;
  DateTime? latestProgramDateTime;

  bool get hasSegments => _segments.isNotEmpty;

  List<_StoredMediaSegment> get orderedSegments =>
      _segments.values.toList(growable: false);

  void appendRetainedAssetIds(Set<String> assetIds) {
    final initAssetId = this.initAssetId;
    if (initAssetId != null) {
      assetIds.add(initAssetId);
    }
    for (final segment in _segments.values) {
      assetIds.add(segment.assetId);
    }
  }

  void recordSelfInitializedAsset(String assetId) {
    for (final segment in _segments.values) {
      if (segment.assetId == assetId) {
        recordSelfInitializedSequence(segment.sequenceNumber);
        return;
      }
    }
  }

  void recordSelfInitializedSequence(int sequenceNumber) {
    final current = selfInitializedFromSequence;
    if (current == null || sequenceNumber < current) {
      selfInitializedFromSequence = sequenceNumber;
    }
  }

  void merge({
    required _ParsedMediaPlaylist playlist,
    required _ChaturbateLlHlsSession session,
    required String sourceUrl,
    required Map<String, String> headers,
  }) {
    if (playlist.versionLine != null) {
      versionLine = playlist.versionLine!;
    }
    if (playlist.targetDurationSeconds != null &&
        playlist.targetDurationSeconds! > 0) {
      targetDurationSeconds = playlist.targetDurationSeconds!;
    }
    final mapUri = playlist.mapUri?.trim();
    if (mapUri != null && mapUri.isNotEmpty) {
      initAssetId = session.registerAsset(
        url: Uri.parse(sourceUrl).resolve(mapUri).toString(),
        headers: headers,
      );
    }
    for (final segment in playlist.segments) {
      final assetId = session.registerAsset(
        url: Uri.parse(sourceUrl).resolve(segment.uri).toString(),
        headers: headers,
      );
      _segments[segment.sequenceNumber] = _StoredMediaSegment(
        sequenceNumber: segment.sequenceNumber,
        extinfLine: segment.extinfLine,
        assetId: assetId,
        programDateTime: segment.programDateTime,
      );
      final programDateTime = segment.programDateTime;
      if (programDateTime != null &&
          (latestProgramDateTime == null ||
              programDateTime.isAfter(latestProgramDateTime!))) {
        latestProgramDateTime = programDateTime;
      }
    }
    while (_segments.length > _historySegmentLimit) {
      _segments.remove(_segments.firstKey());
    }
  }
}

class _ParsedMediaPlaylist {
  const _ParsedMediaPlaylist({
    required this.versionLine,
    required this.targetDurationSeconds,
    required this.mapUri,
    required this.segments,
  });

  final String? versionLine;
  final int? targetDurationSeconds;
  final String? mapUri;
  final List<_ParsedMediaSegment> segments;
}

class _ParsedMediaSegment {
  const _ParsedMediaSegment({
    required this.sequenceNumber,
    required this.extinfLine,
    required this.uri,
    required this.programDateTime,
  });

  final int sequenceNumber;
  final String extinfLine;
  final String uri;
  final DateTime? programDateTime;
}

class _StoredMediaSegment {
  const _StoredMediaSegment({
    required this.sequenceNumber,
    required this.extinfLine,
    required this.assetId,
    required this.programDateTime,
  });

  final int sequenceNumber;
  final String extinfLine;
  final String assetId;
  final DateTime? programDateTime;
}
