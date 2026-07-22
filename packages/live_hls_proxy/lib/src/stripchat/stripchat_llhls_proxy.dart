import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:live_core/live_core.dart';
import 'package:meta/meta.dart';

import '../aes_worker.dart';
import '../hls_proxy_delivery_knobs.dart';
import '../hls_proxy_platform_adapter.dart';
import 'stripchat_mouflon_key_cache.dart';
import 'stripchat_mouflon_runtime_support.dart' as stripchat_runtime;

// Delivery knobs: see [HlsProxyDeliveryKnobs] (mobile=release, desktop=thick Linux).
// Instance field `_d` is bound in the constructor from [DeliveryPlatformProfile].

const _stripchatMouflonDecryptCacheLimit = 512;
final RegExp _stripchatLocalAssetIdRe = RegExp(
  r'/stripchat-llhls/[^/]+/asset/([a-f0-9]{40})',
  caseSensitive: false,
);
const _stripchatUpstreamQueryParam = 'upstream';
const _stripchatBridgeWarmUpfrontWait = Duration(milliseconds: 1500);
const _stripchatBridgeLookupTimeout = Duration(seconds: 4);
const _stripchatBridgeLookupPollInterval = Duration(milliseconds: 150);

// Domains that permanently fail at the TLS handshake level.
// Only applied to API-supplied stripchatCdnDomains; hardcoded
// KnownCdnDomains list already excludes them.
const Set<String> _stripchatTlsDeadCdnDomains = <String>{
  'doppiocdn1.com',
  'doppiocdn.live',
};

typedef StripchatPdkeyResolver = Future<StripchatMouflonKeyCache> Function();
typedef StripchatDecodedUrlResolver =
    String? Function({required String roomUrl, required String segmentKey});
typedef StripchatWarmDecodedUrlBridge = Future<void> Function(String roomUrl);
typedef _StripchatMouflonDecryptor =
    Future<String?> Function(String encryptedSegment, String pdkey);

/// Whether a stripchat/proxy log line should be emitted.
///
/// [verbose] covers per-segment pdkey/mouflon chatter and is suppressed when
/// [kDebugMode] is false (production-style logging).
@visibleForTesting
bool shouldEmitStripchatProxyLog({
  required bool verbose,
  required bool kDebugMode,
}) {
  return !verbose || kDebugMode;
}

class StripchatLlHlsProxy {
  StripchatLlHlsProxy({
    required HlsProxyPlatformAdapter platformAdapter,
    HttpClient? client,
    Duration sessionTtl = const Duration(minutes: 8),
    bool? enabledOverride,
    bool enablePdkeyFallback = true,
    bool enablePriming = true,
    StripchatPdkeyResolver? pdkeyResolver,
    StripchatDecodedUrlResolver? decodedUrlResolver,
    StripchatWarmDecodedUrlBridge? warmDecodedUrlBridge,
    HlsProxyDeliveryKnobs? deliveryKnobs,
  }) : _platformAdapter = platformAdapter,
       _client = client ?? HttpClient(),
       _sessionTtl = sessionTtl,
       _enabledOverride = enabledOverride,
       _enablePdkeyFallback = enablePdkeyFallback,
       _enablePriming = enablePriming,
       _pdkeyResolver = pdkeyResolver,
       _decodedUrlResolver = decodedUrlResolver,
       _warmDecodedUrlBridge = warmDecodedUrlBridge,
       _d = deliveryKnobs ?? HlsProxyDeliveryKnobs.fromActiveProfile() {
    // Mobile: release-era 15s connect. Desktop: short so dead CDN fails over
    // before mpv open budget (~5s → "Failed to open" with no UI detail).
    _client.connectionTimeout = _d.scConnectionTimeout;
    _client.idleTimeout = _d.scIdleTimeout;
    // Prefetch edge + concurrent mpv demand; CB uses 32 for pure CDN.
    // SC also pays mouflon/AES cost so keep headroom for on-demand bursts.
    _client.maxConnectionsPerHost = _d.scMaxConnectionsPerHost;
  }

  static const String routePrefix = 'stripchat-llhls';

  final HlsProxyPlatformAdapter _platformAdapter;
  final HttpClient _client;
  final Duration _sessionTtl;
  final bool? _enabledOverride;
  final bool _enablePdkeyFallback;
  final bool _enablePriming;
  final HlsProxyDeliveryKnobs _d;

  /// A resolver for retrieving Stripchat's cached pdkeys.
  /// Can be null if the platform key store is unavailable or pdkey fallback is disabled.
  final StripchatPdkeyResolver? _pdkeyResolver;

  /// A synchronous resolver provided by the native JS bridge to decode segment URLs.
  /// This callback is null on platforms or environments (like iOS, desktop, or testing)
  /// where the Mouflon WebView/JS bridge is not initialized, in which case we fall back
  /// to static decryption/resolving.

  final StripchatDecodedUrlResolver? _decodedUrlResolver;

  /// A trigger callback to warm up the Mouflon JS bridge for a specific stream.
  /// Can be null when no bridge is active or needed.
  final StripchatWarmDecodedUrlBridge? _warmDecodedUrlBridge;
  final Map<String, _StripchatLlHlsSession> _sessions =
      <String, _StripchatLlHlsSession>{};

  HttpServer? _server;
  Uri? _endpoint;
  Future<void>? _serverLoop;
  Future<void>? _startFuture;
  bool _disposed = false;

  Future<List<LivePlayUrl>> wrapPlayUrls({
    required String roomId,
    required LivePlayQuality quality,
    required List<LivePlayUrl> playUrls,
  }) async {
    if (!_supportsPlatform || playUrls.isEmpty) {
      return playUrls;
    }
    if (!playUrls.any(_looksLikeProxyCandidate)) {
      return playUrls;
    }
    try {
      await ensureStarted();
    } catch (e, stackTrace) {
      _trace('Failed to start Stripchat LL-HLS proxy: $e\n$stackTrace');
      return playUrls;
    }
    _purgeExpiredSessions();
    final keyCache = !_enablePdkeyFallback || _pdkeyResolver == null
        ? const StripchatMouflonKeyCache()
        : await _pdkeyResolver();
    final wrapped = <LivePlayUrl>[];
    final warmedRoomUrls = <String>{};
    for (final playUrl in playUrls) {
      if (!_looksLikeProxyCandidate(playUrl)) {
        wrapped.add(playUrl);
        continue;
      }
      final session = _createSession(
        playUrl,
        roomId: roomId,
        keyCache: keyCache,
        preferredVariantId: quality.id,
      );
      final roomUrl = session.roomUrl.trim();
      if (roomUrl.isNotEmpty && warmedRoomUrls.add(roomUrl)) {
        final warmFuture = _warmDecodedUrlBridge?.call(roomUrl);
        if (warmFuture != null) {
          unawaited(warmFuture);
          try {
            await warmFuture.timeout(_stripchatBridgeWarmUpfrontWait);
          } on TimeoutException {
            _trace(
              'bridge warm continues in background room=$roomUrl '
              'waitMs=${_stripchatBridgeWarmUpfrontWait.inMilliseconds}',
            );
          }
        }
      }
      _sessions[session.id] = session;
      _startSessionPrimeIfNeeded(session);
      wrapped.add(
        LivePlayUrl(
          url: _sessionPlaylistUri(session.id).toString(),
          headers: playUrl.headers,
          lineLabel: playUrl.lineLabel,
          metadata: _buildWrappedMetadata(playUrl, session),
        ),
      );
    }
    return wrapped;
  }

  @visibleForTesting
  Future<void>? getSessionPrimeFuture(String sessionId) {
    return _sessions[sessionId]?.startupPrimeInFlight;
  }

  @visibleForTesting
  bool? getSessionShouldDropMap(String sessionId) {
    return _sessions[sessionId]?.shouldDropMap;
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    final startFuture = _startFuture;
    if (startFuture != null) {
      try {
        await startFuture;
      } catch (_) {}
    }
    final sessions = _sessions.values.toList(growable: false);
    _sessions.clear();
    final server = _server;
    _server = null;
    _endpoint = null;
    final serverLoop = _serverLoop;
    _serverLoop = null;
    _startFuture = null;
    for (final session in sessions) {
      await session.dispose();
    }
    if (server != null) {
      await server.close(force: true);
    }
    try {
      await serverLoop;
    } catch (_) {}
    _client.close(force: true);
  }

  void unregisterSession(String roomId) {
    _sessions.removeWhere((id, session) {
      if (session.roomId == roomId) {
        unawaited(session.dispose());
        return true;
      }
      return false;
    });
  }

  Map<String, Object?> _buildWrappedMetadata(
    LivePlayUrl playUrl,
    _StripchatLlHlsSession session,
  ) {
    return <String, Object?>{
      ...?playUrl.metadata,
      'proxied': true,
      'proxyKind': routePrefix,
      // Actual upstream the proxy fetches (probed media playlist when present).
      'upstreamUrl': session.upstreamUri.toString(),
      'pdkeyHealthAlertChecker': () => session.pdkeyHealthAlert,
    };
  }

  _StripchatLlHlsSession _createSession(
    LivePlayUrl playUrl, {
    required String roomId,
    required StripchatMouflonKeyCache keyCache,
    String? preferredVariantId,
  }) {
    final endpoint = _endpoint;
    if (endpoint == null) {
      throw StateError('Stripchat LL-HLS proxy endpoint unavailable.');
    }
    final sessionId = _randomId();
    final metadataPreferred =
        playUrl.metadata?['preferredVariantId']?.toString().trim() ?? '';
    final qualityPreferred = preferredVariantId?.trim() ?? '';
    final preferred = metadataPreferred.isNotEmpty
        ? metadataPreferred
        : qualityPreferred;
    final normalizedPreferred = preferred.toLowerCase();
    // Business logic (unchanged from platform semantics):
    // - play URL is always the edge *_auto.m3u8 master
    // - quality.id == auto → multi-variant master for platform ABR
    // - fixed quality → preferredVariantId + probed child when available
    // Delivery (sticky/cache-ahead) must not rewrite Auto into a forced tier.
    final isAdaptiveAuto =
        normalizedPreferred.isEmpty || normalizedPreferred == 'auto';
    final probedMedia =
        playUrl.metadata?['resolvedPlaylistUrl']?.toString().trim() ?? '';
    final masterMeta =
        playUrl.metadata?['masterPlaylistUrl']?.toString().trim() ?? '';
    final playUrlRaw = playUrl.url.trim();
    final String upstreamRaw;
    if (isAdaptiveAuto) {
      upstreamRaw = playUrlRaw;
    } else if (probedMedia.isNotEmpty) {
      upstreamRaw = probedMedia;
    } else {
      upstreamRaw = playUrlRaw;
    }
    // Keep a master URI for pin recovery when the probed media child 404s
    // (Nicoleevien 15:53: source child 404 → assets=0 master loop).
    final masterCandidate = masterMeta.isNotEmpty
        ? masterMeta
        : (playUrlRaw.contains('_auto.m3u8') || playUrlRaw.contains('/master/')
              ? playUrlRaw
              : '');
    final masterPlaylistUri = masterCandidate.isEmpty
        ? null
        : Uri.tryParse(masterCandidate);

    return _StripchatLlHlsSession(
      roomId: roomId,
      id: sessionId,
      upstreamUri: Uri.parse(upstreamRaw),
      headers: Map<String, String>.from(playUrl.headers),
      createdAt: DateTime.now(),
      lastAccessedAt: DateTime.now(),
      localBaseUri: endpoint,
      keyCache: keyCache,
      roomUrl: playUrl.metadata?['stripchatRoomUrl']?.toString().trim() ?? '',
      preferredVariantId: isAdaptiveAuto ? '' : preferred,
      pinSingleRendition: !isAdaptiveAuto,
      masterPlaylistUri: masterPlaylistUri,
      aesWorker: HlsAesWorkerSession(debugLabel: 'stripchat:$sessionId'),
      delivery: _d,
      playlistCdnDomains:
          (List<String>.from(
                playUrl.metadata?['stripchatCdnDomains'] as List? ??
                    const <String>[],
              ))
              .where(
                (d) => !_stripchatTlsDeadCdnDomains.contains(
                  d.trim().toLowerCase(),
                ),
              )
              .toList(growable: false),
    );
  }

  bool _looksLikeProxyCandidate(LivePlayUrl playUrl) {
    final proxyKind = playUrl.metadata?['proxyKind']?.toString().trim();
    if (proxyKind == routePrefix) {
      return false;
    }
    final candidates = <String>[
      playUrl.url,
      playUrl.metadata?['masterPlaylistUrl']?.toString() ?? '',
    ];
    for (final candidate in candidates) {
      final uri = Uri.tryParse(candidate);
      if (uri == null) {
        continue;
      }
      final host = uri.host.toLowerCase();
      if (!(host.startsWith('media-hls.') || host.startsWith('edge-hls.'))) {
        continue;
      }
      if (!uri.path.toLowerCase().endsWith('.m3u8')) {
        continue;
      }
      return true;
    }
    return false;
  }

  Future<void> ensureStarted() async {
    if (_disposed) {
      throw StateError('StripchatLlHlsProxy is disposed.');
    }
    if (_server != null && _endpoint != null) {
      return;
    }
    final existing = _startFuture;
    if (existing != null) {
      await existing;
      _ensureRunningAfterStart();
      return;
    }
    final started = _startServer();
    _startFuture = started;
    try {
      await started;
      _ensureRunningAfterStart();
    } finally {
      if (identical(_startFuture, started)) {
        _startFuture = null;
      }
    }
  }

  void _ensureRunningAfterStart() {
    if (_disposed) {
      throw StateError('StripchatLlHlsProxy is disposed.');
    }
    if (_server == null || _endpoint == null) {
      throw StateError('StripchatLlHlsProxy failed to start.');
    }
  }

  Future<void> _startServer() async {
    if (_server != null && _endpoint != null) {
      return;
    }
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    if (_disposed) {
      await server.close(force: true);
      throw StateError('StripchatLlHlsProxy is disposed.');
    }
    _server = server;
    _endpoint = Uri.parse('http://127.0.0.1:${server.port}');
    final serverLoop = Completer<void>();
    server.listen(
      (request) {
        unawaited(() async {
          try {
            await _handleRequest(request);
          } catch (error) {
            _trace(
              'request failed path=${request.requestedUri.path} error=$error',
            );
            try {
              request.response.statusCode = HttpStatus.badGateway;
            } catch (_) {}
            try {
              await request.response.close();
            } catch (_) {}
          }
        }());
      },
      onError: (Object error, StackTrace stackTrace) {
        _trace('server loop failed error=$error');
        if (!serverLoop.isCompleted) {
          serverLoop.completeError(error, stackTrace);
        }
      },
      onDone: () {
        if (!serverLoop.isCompleted) {
          serverLoop.complete();
        }
      },
      cancelOnError: false,
    );
    _serverLoop = serverLoop.future;
  }

  Future<void> _sendServiceUnavailable(HttpRequest request) async {
    try {
      request.response.statusCode = HttpStatus.serviceUnavailable;
      await request.response.close();
    } catch (_) {}
  }

  Future<void> _handleRequest(HttpRequest request) async {
    if (_disposed) {
      await _sendServiceUnavailable(request);
      return;
    }
    final segments = request.uri.pathSegments;
    if (segments.length < 3 || segments[0] != routePrefix) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    final session = _sessions[segments[1]];
    if (session == null || session._disposed) {
      request.response.statusCode = HttpStatus.gone;
      await request.response.close();
      return;
    }
    session.lastAccessedAt = DateTime.now();
    if (segments.length == 4 && segments[2] == 'asset') {
      await _handleAssetRequest(
        request,
        session: session,
        assetId: segments[3],
      );
      return;
    }
    if (segments.length != 3 || segments[2] != 'playlist.m3u8') {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    await _handlePlaylistRequest(request, session: session);
  }

  Future<void> _handlePlaylistRequest(
    HttpRequest request, {
    required _StripchatLlHlsSession session,
  }) async {
    if (_disposed || session._disposed) {
      await _sendServiceUnavailable(request);
      return;
    }
    final playlistStartedAt = DateTime.now();
    // Mobile simple path: full rewritten media playlist (no history thicken),
    // optional short sticky so ABR polls do not re-hit CDN every time.
    // Master stays multi-variant for Auto ABR.
    if (_d.scSimplePublish) {
      final requestUpstream = _resolvePlaylistUpstreamUri(
        session: session,
        requestUri: request.requestedUri,
      );
      final mediaKey = _mediaPlaylistKey(requestUpstream);
      final stickySlot = session.mediaStickyByKey[mediaKey];
      if (stickySlot != null &&
          _d.scPlaylistStickyMaxAge > Duration.zero &&
          stickySlot.mediaSegmentCount >= 1 &&
          stickySlot.manifest.trim().isNotEmpty &&
          !_looksLikeMasterPlaylist(stickySlot.manifest)) {
        final stickyAge = DateTime.now().difference(stickySlot.updatedAt);
        if (stickyAge <= _d.scPlaylistStickyMaxAge) {
          session.activateMediaSticky(mediaKey);
          if (stickySlot.rawAssetIds.isNotEmpty) {
            final warmIds = stickySlot.rawAssetIds
                .take(_d.scWarmAssetPrefetchLimit)
                .toList(growable: false);
            session.enqueueWarmAssets(warmIds, prioritize: true);
            _kickStripchatWarmDrain(session);
          }
          _kickBackgroundPlaylistRefresh(
            session,
            requestUri: request.requestedUri,
            mediaKey: mediaKey,
          );
          _trace(
            'playlist simple-sticky session=${session.id} key=$mediaKey '
            'ageMs=${stickyAge.inMilliseconds} '
            'media=${stickySlot.mediaSegmentCount}',
          );
          await _writePlaylistResponse(request, stickySlot.manifest);
          return;
        }
      }
      final result = await _materializePlaylist(
        session: session,
        requestUri: request.requestedUri,
      );
      if (_disposed || session._disposed) {
        await _sendServiceUnavailable(request);
        return;
      }
      if (result == null || result.manifest.trim().isEmpty) {
        final pathStale = session.mediaStickyByKey[mediaKey];
        final stale = pathStale?.manifest ?? session.lastSuccessfulPlaylist;
        if (stale != null && stale.trim().isNotEmpty) {
          await _writePlaylistResponse(request, stale);
          return;
        }
        await _sendServiceUnavailable(request);
        return;
      }
      _trace(
        'playlist simple-publish session=${session.id} '
        'media=${result.mediaSegmentCount} assets=${result.assetIds.length} '
        'elapsedMs=${DateTime.now().difference(playlistStartedAt).inMilliseconds}',
      );
      await _writePlaylistResponse(request, result.manifest);
      return;
    }
    final requestUpstream = _resolvePlaylistUpstreamUri(
      session: session,
      requestUri: request.requestedUri,
    );
    final mediaKey = _mediaPlaylistKey(requestUpstream);
    final policy = _publishPolicy(
      session: session,
      mediaUri: requestUpstream,
    );
    // Per-path sticky so Auto ABR can hop 1080↔720↔240 without losing cache.
    var slot = session.mediaStickyByKey[mediaKey];
    // Thin sticky (e.g. media=2 on 1080p) looks "playable" over HTTP but demuxer
    // underruns. If a refresh is already flying, wait briefly for a thicker slot.
    if (slot != null &&
        slot.mediaSegmentCount < policy.minMedia &&
        session.refreshInFlightByKey.containsKey(mediaKey)) {
      try {
        await session.refreshInFlightByKey[mediaKey]!.timeout(
          _d.scThinStickyRefreshWait,
        );
      } catch (_) {}
      slot = session.mediaStickyByKey[mediaKey];
    }
    final stickyAge = slot == null
        ? null
        : DateTime.now().difference(slot.updatedAt);
    final refreshing = session.refreshInFlightByKey.containsKey(mediaKey);
    final stickyFresh =
        stickyAge != null && stickyAge <= policy.stickyMaxAge;
    // High tier (1080/source): never sticky-serve under minMedia (logs media=2
    // rebuffer). Low/mid: sticky with ≥1 keeps playlist HTTP non-blocking while
    // a slow segment warm is in flight (unit: refresh-while-asset-inflight).
    final stickyMinMedia =
        policy.tier == _StripchatTierClass.high ? policy.minMedia : 1;
    final stickyThickEnough =
        slot != null && slot.mediaSegmentCount >= stickyMinMedia;
    // High: cold raw edge OR cold tail of the *published* sticky assets means
    // demuxer will starve even if media count looks like 8 (15:43 retest).
    final coldRawEdge = slot == null
        ? const <String>[]
        : _uncachedTailMediaIds(
            session: session,
            assetIds: slot.rawAssetIds,
            tailCount: _d.scHighEdgeWarmCount,
          );
    // sticky.assetIds may be media-only (no MAP head) — use plain last-N.
    final coldStickyTail = slot == null
        ? const <String>[]
        : _uncachedLastIds(
            session: session,
            assetIds: slot.assetIds,
            tailCount: _d.scHighEdgeWarmCount,
          );
    final coldEdgeIds = <String>{...coldRawEdge, ...coldStickyTail}.toList();
    final highEdgeCold =
        policy.tier == _StripchatTierClass.high && coldEdgeIds.isNotEmpty;
    if (highEdgeCold) {
      session.enqueueWarmAssets(coldEdgeIds, prioritize: true);
      for (final id in coldEdgeIds) {
        if (!session.cachedAssets.containsKey(id) &&
            !session.isWarmInFlight(id)) {
          _startStripchatWarmTask(session, id);
        }
      }
    }
    final stickyStaleReentry =
        slot != null &&
        stickyAge != null &&
        stickyAge <= _d.scPlaylistStickyStaleServeMaxAge &&
        stickyThickEnough;
    // Do not sticky-serve when high live-edge / sticky tail is cold — force
    // materialize so we only advertise fully warm segments.
    final canServeSticky =
        slot != null &&
        slot.manifest.trim().isNotEmpty &&
        !_looksLikeMasterPlaylist(slot.manifest) &&
        stickyThickEnough &&
        !highEdgeCold &&
        (stickyFresh || refreshing || stickyStaleReentry);
    if (canServeSticky) {
      session.activateMediaSticky(mediaKey);
      _kickBackgroundPlaylistRefresh(
        session,
        requestUri: request.requestedUri,
        mediaKey: mediaKey,
      );
      _ensurePlaylistPump(session);
      if (slot.rawAssetIds.isNotEmpty) {
        // High: re-warm *entire* raw window on every sticky hit so demuxer
        // catch-up does not meet a cold mid-window segment (154803 Source).
        if (policy.tier == _StripchatTierClass.high) {
          session.enqueueWarmAssets(slot.rawAssetIds, prioritize: true);
          for (final id in slot.rawAssetIds) {
            if (!session.cachedAssets.containsKey(id) &&
                !session.isWarmInFlight(id)) {
              _startStripchatWarmTask(session, id);
            }
          }
        } else {
          _warmStripchatPlaylistAssets(session, slot.rawAssetIds);
        }
      }
      // Prioritize raw edge + sticky tail warm on every sticky hit.
      final edge = <String>{
        ..._tailMediaIds(slot.rawAssetIds, _d.scHighEdgeWarmCount),
        ..._lastIds(slot.assetIds, _d.scHighEdgeWarmCount),
      }.toList(growable: false);
      if (edge.isNotEmpty) {
        session.enqueueWarmAssets(edge, prioritize: true);
        for (final id in edge) {
          if (!session.cachedAssets.containsKey(id) &&
              !session.isWarmInFlight(id)) {
            _startStripchatWarmTask(session, id);
          }
        }
      }
      _trace(
        'playlist sticky session=${session.id} '
        'key=$mediaKey '
        'ageMs=${stickyAge?.inMilliseconds ?? -1} '
        'assets=${slot.assetIds.length} '
        'media=${slot.mediaSegmentCount} '
        'stickyMin=$stickyMinMedia '
        'tier=${policy.tier.name} '
        'refreshing=$refreshing '
        'staleReentry=$stickyStaleReentry '
        'edgeCold=false',
      );
      await _writePlaylistResponse(request, slot.manifest);
      return;
    }
    if (highEdgeCold && slot != null) {
      _trace(
        'playlist sticky skip-edge-cold session=${session.id} '
        'key=$mediaKey cold=${coldEdgeIds.length} '
        'media=${slot.mediaSegmentCount} tier=${policy.tier.name}',
      );
    }
    if (slot != null && !stickyThickEnough) {
      _trace(
        'playlist sticky skip-thin session=${session.id} '
        'key=$mediaKey media=${slot.mediaSegmentCount} '
        'stickyMin=$stickyMinMedia tier=${policy.tier.name}',
      );
      // Ensure warm continues while we materialize.
      if (slot.rawAssetIds.isNotEmpty) {
        _warmStripchatPlaylistAssets(session, slot.rawAssetIds);
      }
      _kickBackgroundPlaylistRefresh(
        session,
        requestUri: request.requestedUri,
        mediaKey: mediaKey,
      );
    }

    final result = await _materializePlaylist(
      session: session,
      requestUri: request.requestedUri,
    );
    if (_disposed || session._disposed) {
      await _sendServiceUnavailable(request);
      return;
    }
    if (result == null) {
      // Prefer same-path sticky, then any playable media sticky.
      final pathStale = session.mediaStickyByKey[mediaKey];
      final anyStale = pathStale ?? session.bestMediaSticky();
      if (anyStale != null && anyStale.manifest.trim().isNotEmpty) {
        session.activateMediaSticky(anyStale.mediaKey);
        _trace(
          'playlist materialize failed session=${session.id} stale=true '
          'key=${anyStale.mediaKey} '
          'elapsedMs=${DateTime.now().difference(playlistStartedAt).inMilliseconds}',
        );
        await _writePlaylistResponse(request, anyStale.manifest);
        return;
      }
      request.response.headers.contentType = ContentType.text;
      request.response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
      request.response.statusCode = HttpStatus.badGateway;
      request.response.write(
        'stripchat playlist upstream unavailable '
        '(room may be private/offline or CDN timed out)',
      );
      await request.response.close();
      return;
    }
    _ensurePlaylistPump(session);
    _trace(
      'playlist served session=${session.id} assets=${result.assetIds.length} '
      'elapsedMs=${DateTime.now().difference(playlistStartedAt).inMilliseconds} '
      'mode=blocking',
    );
    await _writePlaylistResponse(request, result.manifest);
  }

  Future<void> _writePlaylistResponse(
    HttpRequest request,
    String manifest,
  ) async {
    request.response.headers.contentType = ContentType(
      'application',
      'vnd.apple.mpegurl',
      charset: 'utf-8',
    );
    request.response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    request.response.statusCode = HttpStatus.ok;
    request.response.write(manifest);
    await request.response.close();
  }

  void _ensurePlaylistPump(_StripchatLlHlsSession session) {
    if (_disposed || session._disposed) {
      return;
    }
    final interval = _playlistPumpIntervalFor(session);
    // Restart pump when high-tier needs a faster cadence than the default.
    if (session.playlistPumpTimer != null) {
      if (session.playlistPumpInterval == interval) {
        return;
      }
      session.playlistPumpTimer?.cancel();
      session.playlistPumpTimer = null;
    }
    session.playlistPumpInterval = interval;
    session.playlistPumpTimer = Timer.periodic(interval, (_) {
      if (_disposed || session._disposed) {
        session.playlistPumpTimer?.cancel();
        session.playlistPumpTimer = null;
        return;
      }
      _kickBackgroundPlaylistRefresh(session);
    });
  }

  Duration _playlistPumpIntervalFor(_StripchatLlHlsSession session) {
    final mediaUri =
        session.pinnedMediaPlaylistUri ??
        session.playlistUri ??
        session.upstreamUri;
    final policy = _publishPolicy(session: session, mediaUri: mediaUri);
    return policy.pumpInterval;
  }

  void _kickBackgroundPlaylistRefresh(
    _StripchatLlHlsSession session, {
    Uri? requestUri,
    String? mediaKey,
  }) {
    if (_disposed || session._disposed) {
      return;
    }
    // Prefer client request URI so _HLS_* live-reload params merge in.
    final effectiveRequestUri =
        requestUri ??
        (session.pinnedMediaPlaylistUri != null
            ? _sessionPlaylistUri(
                session.id,
                upstreamUri: session.pinnedMediaPlaylistUri,
              )
            : session.upstreamUri);
    final key =
        mediaKey ??
        _mediaPlaylistKey(
          _resolvePlaylistUpstreamUri(
            session: session,
            requestUri: effectiveRequestUri,
          ),
        );
    if (session.refreshInFlightByKey.containsKey(key)) {
      return;
    }
    final lastAt = session.mediaStickyByKey[key]?.updatedAt;
    final hasLiveReloadQuery = () {
      if (requestUri == null) {
        return false;
      }
      final q = requestUri.queryParameters;
      return q.containsKey('_HLS_msn') ||
          q.containsKey('_HLS_part') ||
          q.keys.any((k) => k.startsWith('_HLS_'));
    }();
    final mediaUri = _resolvePlaylistUpstreamUri(
      session: session,
      requestUri: effectiveRequestUri,
    );
    final policy = _publishPolicy(session: session, mediaUri: mediaUri);
    if (!hasLiveReloadQuery &&
        lastAt != null &&
        DateTime.now().difference(lastAt) < policy.backgroundMinInterval) {
      return;
    }
    final refresh = _materializePlaylist(
      session: session,
      requestUri: effectiveRequestUri,
    );
    session.refreshInFlightByKey[key] = refresh;
    unawaited(() async {
      try {
        final result = await refresh;
        if (result != null) {
          _trace(
            'playlist background refresh session=${session.id} '
            'key=$key assets=${result.assetIds.length}',
          );
        }
      } catch (error) {
        _trace(
          'playlist background refresh failed session=${session.id} '
          'key=$key error=$error',
        );
      } finally {
        if (identical(session.refreshInFlightByKey[key], refresh)) {
          session.refreshInFlightByKey.remove(key);
        }
      }
    }());
  }

  /// Fetch upstream (collapse master if needed), rewrite, store + warm assets.
  /// Returns null on hard failure (caller may serve sticky/stale or 502).
  /// Concurrent materialize for the same media/master path is coalesced so
  /// Auto prewarm storms and ABR probes share one CDN round-trip.
  Future<_StripchatRewrittenPlaylist?> _materializePlaylist({
    required _StripchatLlHlsSession session,
    required Uri requestUri,
  }) async {
    if (_disposed || session._disposed) {
      return null;
    }
    final upstreamUri = _resolvePlaylistUpstreamUri(
      session: session,
      requestUri: requestUri,
    );
    final coalesceKey = _mediaPlaylistKey(upstreamUri);
    final existing = session.materializeInFlightByKey[coalesceKey];
    if (existing != null) {
      return existing;
    }
    final future = _materializePlaylistImpl(
      session: session,
      requestUri: requestUri,
      upstreamUri: upstreamUri,
    );
    session.materializeInFlightByKey[coalesceKey] = future;
    try {
      return await future;
    } finally {
      if (identical(
        session.materializeInFlightByKey[coalesceKey],
        future,
      )) {
        session.materializeInFlightByKey.remove(coalesceKey);
      }
    }
  }

  Future<_StripchatRewrittenPlaylist?> _materializePlaylistImpl({
    required _StripchatLlHlsSession session,
    required Uri requestUri,
    required Uri upstreamUri,
  }) async {
    if (_disposed || session._disposed) {
      return null;
    }
    _trace(
      'playlist materialize session=${session.id} uri=$upstreamUri '
      'pinned=${session.pinnedMediaPlaylistUri != null}',
    );
    _FetchedPlaylist upstream;
    try {
      upstream = await _fetchPlaylistWithFallbacks(
        session: session,
        uri: upstreamUri,
        headers: session.headers,
      );
    } on Object catch (error) {
      _trace(
        'playlist materialize fetch error session=${session.id} '
        'uri=$upstreamUri error=$error',
      );
      return null;
    }
    if (_disposed || session._disposed) {
      return null;
    }
    if (upstream.statusCode == HttpStatus.forbidden ||
        upstream.statusCode == 418) {
      final pkeyUris = _buildPkeyFallbackUris(upstreamUri, session.keyCache);
      for (final pkeyUri in pkeyUris) {
        if (_disposed || session._disposed) {
          return null;
        }
        try {
          final alt = await _fetchPlaylistWithFallbacks(
            session: session,
            uri: pkeyUri,
            headers: session.headers,
          );
          if (alt.statusCode == HttpStatus.ok) {
            _trace(
              'playlist pkey fallback session=${session.id} '
              'from=${upstreamUri.queryParameters['pkey']} '
              'to=${pkeyUri.queryParameters['pkey']}',
            );
            upstream = alt;
            break;
          }
        } on Object {
          continue;
        }
      }
    }
    // Fixed quality: probed media child may 404 while edge master still lists
    // working absolute media URLs (Nicoleevien Source 15:53).
    if (upstream.statusCode != HttpStatus.ok && session.pinSingleRendition) {
      final recovered = await _recoverPinnedMediaFromMaster(session);
      if (recovered != null) {
        _trace(
          'playlist pin recover-from-master session=${session.id} '
          'fromStatus=${upstream.statusCode} to=${recovered.finalUri.path}',
        );
        upstream = recovered;
      }
    }
    if (upstream.statusCode != HttpStatus.ok) {
      _trace(
        'playlist materialize bad status session=${session.id} '
        'status=${upstream.statusCode} uri=$upstreamUri',
      );
      return null;
    }
    if (session.pinSingleRendition) {
      final collapsed = await _collapseMasterToPreferredMediaPlaylist(
        session: session,
        upstream: upstream,
      );
      if (collapsed != null) {
        upstream = collapsed;
      }
    }
    // Fixed quality must never serve multi-variant master (assets=0 loop).
    if (session.pinSingleRendition &&
        _looksLikeMasterPlaylist(upstream.body)) {
      final recovered = await _recoverPinnedMediaFromMaster(session);
      if (recovered != null && !_looksLikeMasterPlaylist(recovered.body)) {
        upstream = recovered;
      } else {
        _trace(
          'playlist materialize pin refuse empty-master session=${session.id} '
          'uri=${upstream.finalUri}',
        );
        return null;
      }
    }
    // Media playlists (child of Auto master, or fixed-quality pin): record key
    // for sticky matching. Masters stay multi-variant for Auto ABR.
    if (!_looksLikeMasterPlaylist(upstream.body)) {
      session.pinnedMediaPlaylistUri = upstream.finalUri;
      session.lastStickyMediaKey = _mediaPlaylistKey(upstream.finalUri);
    }
    if (_disposed || session._disposed) {
      return null;
    }
    final rewritten = await _rewritePlaylist(
      session: session,
      playlistUri: upstream.finalUri,
      manifest: upstream.body,
    );
    if (_disposed || session._disposed) {
      return null;
    }
    // Refuse to publish empty media playlists (winter11: assets=0 after 10s).
    if (rewritten.assetIds.isEmpty &&
        !_looksLikeMasterPlaylist(rewritten.manifest)) {
      _trace(
        'playlist materialize empty assets session=${session.id} '
        'uri=${upstream.finalUri}',
      );
      return null;
    }
    if (session.pdkeyHealthAlert) {
      _trace(
        'pdkey health alert session=${session.id} '
        'allFailed=${session._pdkeyAllFailedCount} '
        'totalSegments=${session._assetTargets.length} '
        '- all known pdkeys may be invalid',
      );
    }
    session.playlistUri = upstream.finalUri;
    if (session.roomUrl.isNotEmpty) {
      unawaited(_warmDecodedUrlBridge?.call(session.roomUrl));
    }
    // Auto multi-variant master: return rewritten STREAM-INF immediately.
    // Segment cache gates apply only to media playlists the player selects.
    if (_looksLikeMasterPlaylist(rewritten.manifest)) {
      session.initialEdgeWarmCompleted = true;
      // Desktop only: Kick top-N media cache-ahead without collapsing master ABR.
      // Mobile release had no Auto prewarm storm (prewarmTop=0).
      if (!session.pinSingleRendition && _d.scAutoPrewarmTopVariants > 0) {
        unawaited(_prewarmAutoMediaVariants(session));
      }
      _trace(
        'playlist materialize master session=${session.id} '
        'entries=${rewritten.assetIds.length} '
        'simple=${_d.scSimplePublish}',
      );
      return rewritten;
    }

    final mediaKey = _mediaPlaylistKey(upstream.finalUri);
    final pathSlot = session.mediaStickyByKey[mediaKey];
    final pathRawAssetIds = List<String>.unmodifiable(rewritten.assetIds);
    final policy = _publishPolicy(
      session: session,
      mediaUri: upstream.finalUri,
    );
    // Always remember the full rewritten window for neighbor warm, even when
    // we only publish a cached subset.
    session.lastRawAssetIds = pathRawAssetIds;

    // Mobile release-like: publish full rewritten media playlist immediately
    // and warm only a small head/edge window (no sticky/history thicken).
    if (_d.scSimplePublish) {
      final warmIds = rewritten.assetIds
          .take(_d.scWarmAssetPrefetchLimit)
          .toList(growable: false);
      if (warmIds.isNotEmpty) {
        session.enqueueWarmAssets(warmIds, prioritize: true);
        _kickStripchatWarmDrain(session);
      }
      final publishedMedia = rewritten.mediaSegmentCount > 0
          ? rewritten.mediaSegmentCount
          : _countMediaSegmentsInManifest(rewritten.manifest);
      session.putMediaSticky(
        mediaKey: mediaKey,
        manifest: rewritten.manifest,
        assetIds: rewritten.assetIds,
        rawAssetIds: pathRawAssetIds,
        mediaSegmentCount: publishedMedia,
        playlistUri: session.playlistUri ?? upstream.finalUri,
        contentChanged: true,
      );
      session.initialEdgeWarmCompleted = true;
      _trace(
        'playlist materialize simple session=${session.id} '
        'key=$mediaKey media=$publishedMedia '
        'warm=${warmIds.length}',
      );
      return rewritten;
    }

    // Warm first, then prefer a cached-only stable window. Never publish a
    // MAP-only playlist. Prefer never publishing uncached media (fallback-full
    // with cold edge caused post-start rebuffer in 13:29 logs).
    // First publish is *per media path* so ABR into a new tier still warms hard.
    final isFirstPublish =
        pathSlot == null || pathSlot.mediaSegmentCount <= 0;
    _warmStripchatPlaylistAssets(session, rewritten.assetIds);
    // Fixed high quality / any media path: force-start every uncached id now
    // (do not wait for drain slots only) — 1080 segs need full-window concurrency.
    final newMediaIds = _newMediaAssetIds(
      previousAssetIds: pathSlot?.assetIds ?? const <String>[],
      assetIds: rewritten.assetIds,
    );
    final warmPriorityIds = <String>{
      ...newMediaIds,
      ..._mediaAssetIds(rewritten.assetIds),
    }.toList(growable: false);
    if (warmPriorityIds.isNotEmpty) {
      session.enqueueWarmAssets(warmPriorityIds, prioritize: true);
      for (final id in warmPriorityIds) {
        if (!session.cachedAssets.containsKey(id) &&
            !session.isWarmInFlight(id)) {
          _startStripchatWarmTask(session, id);
        }
      }
    }
    await _awaitPublishWarm(
      session,
      rewritten.assetIds,
      isFirstPublish: isFirstPublish,
      preferThicker: !isFirstPublish,
      policy: policy,
    );
    if (_disposed || session._disposed) {
      return null;
    }
    var filtered = _buildCachedOnlyPlaylist(
      session: session,
      rewritten: rewritten,
    );
    // If still thin vs tier min, wait again then re-filter.
    if (filtered.mediaSegmentCount < policy.minMedia) {
      await _awaitPublishWarm(
        session,
        rewritten.assetIds,
        isFirstPublish: isFirstPublish,
        budgetOverride: policy.retryWait,
        policy: policy,
      );
      if (_disposed || session._disposed) {
        return null;
      }
      filtered = _buildCachedOnlyPlaylist(
        session: session,
        rewritten: rewritten,
      );
    }
    // High mid-play: wait for *all new media* + full raw tail warm before we
    // advertise the window (15:43: playlist media=8 but demuxer still underran).
    if (policy.tier == _StripchatTierClass.high && !isFirstPublish) {
      if (newMediaIds.isNotEmpty) {
        await _awaitSpecificAssetsWarm(
          session,
          newMediaIds,
          budget: _d.scHighNewMediaWarmWait,
        );
      }
      await _awaitTailMediaWarm(
        session,
        rewritten.assetIds,
        tailCount: _d.scHighEdgeWarmCount,
        budget: _d.scHighEdgeWarmWait,
      );
      if (_disposed || session._disposed) {
        return null;
      }
      filtered = _buildCachedOnlyPlaylist(
        session: session,
        rewritten: rewritten,
      );
    }
    final isMaster = _looksLikeMasterPlaylist(rewritten.manifest);
    // Thicken demuxer buffer by retaining still-cached media from previous
    // sticky *for this path* until we hit history target (high → 6 segs).
    // Critical: preferMedia must be > raw window (~3) or thicken never runs
    // once minMedia=3 is met (Hall 14:55 stuck at publishedMedia=3).
    final thickened = _thickenWithStickyHistory(
      previousManifest: pathSlot?.manifest,
      session: session,
      filtered: filtered,
      structureManifest: rewritten.manifest,
      preferMedia: policy.preferMedia,
      maxExtras: policy.maxHistoryExtras,
    );
    final publishFiltered = thickened ?? filtered;
    final cachedMedia = publishFiltered.mediaSegmentCount;
    final prevMedia = pathSlot?.mediaSegmentCount ?? 0;
    final hasPlayableSticky =
        pathSlot != null &&
        pathSlot.manifest.trim().isNotEmpty &&
        prevMedia >= policy.minMedia;

    _StripchatRewrittenPlaylist choose() {
      if (isMaster) {
        return rewritten;
      }
      // Prefer cached-only whenever we meet the tier minimum.
      if (cachedMedia >= policy.minMedia) {
        return _StripchatRewrittenPlaylist(
          manifest: publishFiltered.manifest,
          assetIds: publishFiltered.assetIds,
          mediaSegmentCount: publishFiltered.mediaSegmentCount,
        );
      }
      // High tier: refuse to publish-thin on first open if sticky has better.
      final keepSlot = pathSlot;
      if (hasPlayableSticky &&
          keepSlot != null &&
          prevMedia > cachedMedia) {
        _trace(
          'playlist materialize keep-sticky session=${session.id} '
          'key=$mediaKey reason=thin-vs-sticky cachedMedia=$cachedMedia '
          'prevMedia=$prevMedia minMedia=${policy.minMedia} '
          'tier=${policy.tier.name}',
        );
        return _StripchatRewrittenPlaylist(
          manifest: keepSlot.manifest,
          assetIds: keepSlot.assetIds,
          mediaSegmentCount: prevMedia,
        );
      }
      // Single/thin cached media: only for low tier or as last mid-play option.
      if (cachedMedia >= 1 &&
          (policy.tier == _StripchatTierClass.low || !isFirstPublish)) {
        _trace(
          'playlist materialize publish-thin session=${session.id} '
          'key=$mediaKey cachedMedia=$cachedMedia '
          'minMedia=${policy.minMedia} tier=${policy.tier.name} '
          'raw=${rewritten.assetIds.length}',
        );
        return _StripchatRewrittenPlaylist(
          manifest: publishFiltered.manifest,
          assetIds: publishFiltered.assetIds,
          mediaSegmentCount: publishFiltered.mediaSegmentCount,
        );
      }
      if (hasPlayableSticky && keepSlot != null) {
        _trace(
          'playlist materialize keep-sticky session=${session.id} '
          'key=$mediaKey reason=thin-cached cachedMedia=$cachedMedia '
          'prevMedia=$prevMedia raw=${rewritten.assetIds.length} '
          'newMedia=${newMediaIds.length}',
        );
        return _StripchatRewrittenPlaylist(
          manifest: keepSlot.manifest,
          assetIds: keepSlot.assetIds,
          mediaSegmentCount: prevMedia,
        );
      }
      // Last resort first open with zero/under-min cached media after waits.
      _trace(
        'playlist materialize fallback-full session=${session.id} '
        'key=$mediaKey reason=open-needs-media cachedMedia=$cachedMedia '
        'minMedia=${policy.minMedia} tier=${policy.tier.name} '
        'raw=${rewritten.assetIds.length}',
      );
      return rewritten;
    }

    var publishable = choose();
    // High: never put a media URI in the sticky that is not fully cached.
    if (!isMaster && policy.tier == _StripchatTierClass.high) {
      final verified = _restrictPlaylistToCachedAssets(
        session: session,
        playlist: publishable,
        structureManifest: rewritten.manifest,
      );
      if (verified != null) {
        publishable = verified;
      }
    }
    final contentChanged =
        pathSlot == null || publishable.manifest != pathSlot.manifest;
    final publishedMedia = isMaster
        ? 0
        : (publishable.mediaSegmentCount > 0
              ? publishable.mediaSegmentCount
              : _countMediaSegmentsInManifest(publishable.manifest));
    // Do not sticky multi-variant masters (Auto ABR).
    if (!isMaster) {
      session.putMediaSticky(
        mediaKey: mediaKey,
        manifest: publishable.manifest,
        assetIds: publishable.assetIds,
        rawAssetIds: pathRawAssetIds,
        mediaSegmentCount: publishedMedia,
        playlistUri: session.playlistUri ?? upstream.finalUri,
        contentChanged: contentChanged,
      );
    }
    session.initialEdgeWarmCompleted = true;
    // Keep warming the full raw window (including unpublished edge).
    _warmStripchatPlaylistAssets(session, pathRawAssetIds);
    // Re-warm everything we just advertised + neighbors so demuxer does not
    // underrun after advanced=true (Glamorous 15:43 mid-play).
    if (!isMaster && publishable.assetIds.isNotEmpty) {
      session.enqueueWarmAssets(publishable.assetIds, prioritize: true);
      for (final id in publishable.assetIds) {
        if (!session.cachedAssets.containsKey(id) &&
            !session.isWarmInFlight(id)) {
          _startStripchatWarmTask(session, id);
        }
      }
      final tail = _tailMediaIds(
        publishable.assetIds,
        _d.scHighEdgeWarmCount,
      );
      for (final id in tail) {
        _warmNeighborAssets(session, id);
      }
      // Also warm full raw tail aggressively.
      final rawTail = _tailMediaIds(
        pathRawAssetIds,
        _d.scHighEdgeWarmCount,
      );
      session.enqueueWarmAssets(rawTail, prioritize: true);
      for (final id in rawTail) {
        if (!session.cachedAssets.containsKey(id) &&
            !session.isWarmInFlight(id)) {
          _startStripchatWarmTask(session, id);
        }
      }
    }
    // Upgrade pump cadence once we know this is a high-tier media session.
    _ensurePlaylistPump(session);
    _trace(
      'playlist materialize publish session=${session.id} '
      'key=$mediaKey cachedMedia=$cachedMedia publishedMedia=$publishedMedia '
      'minMedia=${policy.minMedia} preferMedia=${policy.preferMedia} '
      'tier=${policy.tier.name} '
      'rawAssets=${rewritten.assetIds.length} '
      'advanced=$contentChanged',
    );
    return publishable;
  }

  /// Delivery policy by media tier (path / fixed quality id). Not ABR policy.
  _StripchatPublishPolicy _publishPolicy({
    required _StripchatLlHlsSession session,
    required Uri mediaUri,
  }) {
    final tier = _tierClassFor(
      preferredVariantId: session.preferredVariantId,
      mediaUri: mediaUri,
      pinSingleRendition: session.pinSingleRendition,
    );
    switch (tier) {
      case _StripchatTierClass.high:
        return _StripchatPublishPolicy(
          tier: _StripchatTierClass.high,
          minMedia: _d.scHighMinPublishMediaSegments,
          preferMedia: _d.scHighPreferPublishMediaSegments,
          maxHistoryExtras: _d.scHighMaxHistoryExtras,
          firstWait: _d.scHighPublishWarmWaitFirst,
          backgroundWait: _d.scHighPublishWarmWaitBackground,
          retryWait: _d.scHighPublishWarmRetry,
          stickyMaxAge: _d.scHighPlaylistStickyMaxAge,
          backgroundMinInterval: _d.scHighPlaylistBackgroundMinInterval,
          pumpInterval: _d.scHighPlaylistPumpInterval,
        );
      case _StripchatTierClass.mid:
        return _StripchatPublishPolicy(
          tier: _StripchatTierClass.mid,
          minMedia: _d.scMidMinPublishMediaSegments,
          preferMedia: _d.scMidPreferPublishMediaSegments,
          maxHistoryExtras: _d.scMidMaxHistoryExtras,
          firstWait: _d.scPublishWarmWaitFirst,
          backgroundWait: _d.scPublishWarmWaitBackground,
          retryWait: _d.scPublishWarmRetry,
          stickyMaxAge: _d.scPlaylistStickyMaxAge,
          backgroundMinInterval: _d.scPlaylistBackgroundMinInterval,
          pumpInterval: _d.scPlaylistPumpInterval,
        );
      case _StripchatTierClass.low:
        return _StripchatPublishPolicy(
          tier: _StripchatTierClass.low,
          minMedia: _d.scMinPublishCachedMediaSegments,
          preferMedia: _d.scPreferPublishCachedMediaSegments,
          maxHistoryExtras: _d.scLowMaxHistoryExtras,
          firstWait: _d.scPublishWarmWaitFirst,
          backgroundWait: _d.scPublishWarmWaitBackground,
          retryWait: _d.scPublishWarmRetry,
          stickyMaxAge: _d.scPlaylistStickyMaxAge,
          backgroundMinInterval: _d.scPlaylistBackgroundMinInterval,
          pumpInterval: _d.scPlaylistPumpInterval,
        );
    }
  }

  _StripchatTierClass _tierClassFor({
    required String preferredVariantId,
    required Uri mediaUri,
    required bool pinSingleRendition,
  }) {
    final preferred = preferredVariantId.trim().toLowerCase();
    final path = mediaUri.path.toLowerCase();
    final file = mediaUri.pathSegments.isEmpty
        ? ''
        : mediaUri.pathSegments.last.toLowerCase();
    bool looksHigh(String s) =>
        s.contains('1080') ||
        s.contains('source') ||
        s == 'auto-max' ||
        // Bare `{id}.m3u8` is Stripchat "source"/max progressive.
        RegExp(r'^\d+\.m3u8$').hasMatch(s);
    bool looksMid(String s) => s.contains('720');
    if (looksHigh(preferred) || looksHigh(file) || looksHigh(path)) {
      return _StripchatTierClass.high;
    }
    if (looksMid(preferred) || looksMid(file) || looksMid(path)) {
      return _StripchatTierClass.mid;
    }
    // Fixed pin without quality token still treat as mid (safer than low).
    if (pinSingleRendition && preferred.isNotEmpty) {
      return _StripchatTierClass.mid;
    }
    return _StripchatTierClass.low;
  }

  /// Media asset ids (heuristic: drop first id as MAP when list is multi).
  List<String> _mediaAssetIds(List<String> assetIds) {
    if (assetIds.isEmpty) {
      return const <String>[];
    }
    if (assetIds.length == 1) {
      return List<String>.from(assetIds);
    }
    return assetIds.sublist(1);
  }

  /// Merge still-cached media pairs from previous sticky in front of [filtered]
  /// so demuxer keeps a multi-window runway (high target ~6 media segs).
  _StripchatFilteredPlaylist? _thickenWithStickyHistory({
    required String? previousManifest,
    required _StripchatLlHlsSession session,
    required _StripchatFilteredPlaylist filtered,
    required String structureManifest,
    int? preferMedia,
    int? maxExtras,
  }) {
    final prefer = preferMedia ?? _d.scPreferPublishCachedMediaSegments;
    final maxHistory = maxExtras ?? _d.scLowMaxHistoryExtras;
    final prev = previousManifest;
    if (prev == null || prev.trim().isEmpty) {
      return null;
    }
    if (filtered.mediaSegmentCount >= prefer) {
      return null;
    }
    final prevPairs = _extractMediaPairs(prev);
    final newPairs = _extractMediaPairs(filtered.manifest);
    if (prevPairs.isEmpty || newPairs.isEmpty) {
      return null;
    }
    final newIds = newPairs.map((p) => p.assetId).toSet();
    final historyPairs = <_StripchatMediaPair>[];
    for (final pair in prevPairs) {
      if (newIds.contains(pair.assetId)) {
        continue;
      }
      if (!session.cachedAssets.containsKey(pair.assetId)) {
        continue;
      }
      historyPairs.add(pair);
    }
    // Need enough extras to approach preferMedia (e.g. 3 new + 3 old = 6).
    final wantExtras = max(0, prefer - newPairs.length);
    final cap = max(maxHistory, wantExtras);
    final retained = historyPairs.length <= cap
        ? historyPairs
        : historyPairs.sublist(historyPairs.length - cap);
    if (retained.isEmpty) {
      return null;
    }
    final mergedPairs = <_StripchatMediaPair>[...retained, ...newPairs];
    // Cap total media to preferMedia (keep newest tail).
    final cappedPairs = mergedPairs.length <= prefer
        ? mergedPairs
        : mergedPairs.sublist(mergedPairs.length - prefer);
    final built = _rebuildManifestWithMediaPairs(
      structureManifest: structureManifest,
      pairs: cappedPairs,
    );
    final assetIds = <String>[
      for (final pair in cappedPairs) pair.assetId,
    ];
    _trace(
      'playlist thicken history session=${session.id} '
      'extras=${retained.length} new=${newPairs.length} '
      'total=${cappedPairs.length} target=$prefer',
    );
    return _StripchatFilteredPlaylist(
      manifest: built,
      assetIds: List<String>.unmodifiable(assetIds),
      // Must match capped list (was wrongly using uncapped merged length).
      mediaSegmentCount: cappedPairs.length,
    );
  }

  List<_StripchatMediaPair> _extractMediaPairs(String manifest) {
    final pairs = <_StripchatMediaPair>[];
    String? pendingExtinf;
    for (final raw in const LineSplitter().convert(manifest)) {
      final line = raw.trim();
      if (line.toUpperCase().startsWith('#EXTINF:')) {
        pendingExtinf = raw;
        continue;
      }
      if (line.isEmpty || line.startsWith('#')) {
        continue;
      }
      final match = _stripchatLocalAssetIdRe.firstMatch(line);
      if (pendingExtinf != null && match != null) {
        pairs.add(
          _StripchatMediaPair(
            extinfLine: pendingExtinf,
            uriLine: raw,
            assetId: match.group(1)!,
          ),
        );
      }
      pendingExtinf = null;
    }
    return pairs;
  }

  String _rebuildManifestWithMediaPairs({
    required String structureManifest,
    required List<_StripchatMediaPair> pairs,
  }) {
    final header = <String>[];
    for (final raw in const LineSplitter().convert(structureManifest)) {
      final line = raw.trim();
      if (line.toUpperCase().startsWith('#EXTINF:')) {
        break;
      }
      if (!line.startsWith('#') &&
          _stripchatLocalAssetIdRe.hasMatch(line) &&
          !line.toUpperCase().contains('MAP')) {
        // Bare media URI without walking into body.
        break;
      }
      header.add(raw);
    }
    final out = <String>[...header];
    for (final pair in pairs) {
      out.add(pair.extinfLine);
      out.add(pair.uriLine);
    }
    return '${out.join('\n')}\n';
  }

  /// Media ids in [assetIds] that are not in the last published sticky set.
  List<String> _newMediaAssetIds({
    required List<String> previousAssetIds,
    required List<String> assetIds,
  }) {
    final media = _mediaAssetIds(assetIds);
    if (media.isEmpty) {
      return const <String>[];
    }
    final previous = previousAssetIds.toSet();
    if (previous.isEmpty) {
      return media;
    }
    return media.where((id) => !previous.contains(id)).toList(growable: false);
  }

  int _countMediaSegmentsInManifest(String manifest) {
    var count = 0;
    var pendingExtinf = false;
    for (final raw in const LineSplitter().convert(manifest)) {
      final line = raw.trim();
      if (line.toUpperCase().startsWith('#EXTINF:')) {
        pendingExtinf = true;
        continue;
      }
      if (line.isEmpty || line.startsWith('#')) {
        continue;
      }
      if (pendingExtinf && _stripchatLocalAssetIdRe.hasMatch(line)) {
        count += 1;
      }
      pendingExtinf = false;
    }
    return count;
  }

  /// Wait until enough *media* segments of this window are cached.
  /// Runs for first open and background materialize (sticky HTTP still free).
  Future<void> _awaitPublishWarm(
    _StripchatLlHlsSession session,
    List<String> assetIds, {
    required bool isFirstPublish,
    Duration? budgetOverride,
    bool preferThicker = false,
    _StripchatPublishPolicy? policy,
  }) async {
    if (assetIds.isEmpty || _disposed || session._disposed) {
      return;
    }
    final effective =
        policy ??
        _StripchatPublishPolicy(
          tier: _StripchatTierClass.low,
          minMedia: _d.scMinPublishCachedMediaSegments,
          preferMedia: _d.scPreferPublishCachedMediaSegments,
          maxHistoryExtras: _d.scLowMaxHistoryExtras,
          firstWait: _d.scPublishWarmWaitFirst,
          backgroundWait: _d.scPublishWarmWaitBackground,
          retryWait: _d.scPublishWarmRetry,
          stickyMaxAge: _d.scPlaylistStickyMaxAge,
          backgroundMinInterval: _d.scPlaylistBackgroundMinInterval,
          pumpInterval: _d.scPlaylistPumpInterval,
        );
    // Wait on ALL media segs (including live edge). Using only "stable" (drop
    // newest) capped want at 2 forever — logs publishedMedia=2 on 49/55 pubs.
    final media = _mediaAssetIds(assetIds);
    final targets = media;
    if (targets.isEmpty) {
      return;
    }
    for (final id in assetIds) {
      if (!session.cachedAssets.containsKey(id) &&
          !session.isWarmInFlight(id)) {
        _startStripchatWarmTask(session, id);
      }
    }
    // High mid-play: try to cache the *entire* raw media window (usually 3),
    // not just minMedia — otherwise edge lags while history looks thick.
    final prefer = effective.tier == _StripchatTierClass.high
        ? (preferThicker || isFirstPublish
              ? max(effective.minMedia, targets.length)
              : targets.length)
        : (preferThicker || isFirstPublish
              ? effective.preferMedia
              : effective.minMedia);
    final want = min(targets.length, prefer);
    final minAcceptable = min(targets.length, effective.minMedia);
    final budget =
        budgetOverride ??
        (isFirstPublish ? effective.firstWait : effective.backgroundWait);
    final deadline = DateTime.now().add(budget);
    // High tier first open must not early-exit at media=2 (14:19 rebuffer).
    final strictMin =
        isFirstPublish && effective.tier == _StripchatTierClass.high;
    // High mid-play: also require tail edge warm before accepting min.
    final requireEdge =
        effective.tier == _StripchatTierClass.high && !isFirstPublish;
    while (DateTime.now().isBefore(deadline)) {
      if (_disposed || session._disposed) {
        return;
      }
      final cached = targets
          .where((id) => session.cachedAssets.containsKey(id))
          .length;
      final edgeOk = !requireEdge ||
          _uncachedTailMediaIds(
            session: session,
            assetIds: assetIds,
            tailCount: _d.scHighEdgeWarmCount,
          ).isEmpty;
      final elapsed = budget - deadline.difference(DateTime.now());
      final pastHalf = elapsed >= budget * 0.55;
      if (cached >= want && edgeOk) {
        return;
      }
      if (!strictMin && pastHalf && cached >= minAcceptable && edgeOk) {
        return;
      }
      // Strict HQ first: accept min only in the last 20% of budget.
      if (strictMin &&
          elapsed >= budget * 0.80 &&
          cached >= minAcceptable) {
        return;
      }
      // Keep re-kicking uncached edge.
      if (requireEdge) {
        final cold = _uncachedTailMediaIds(
          session: session,
          assetIds: assetIds,
          tailCount: _d.scHighEdgeWarmCount,
        );
        if (cold.isNotEmpty) {
          session.enqueueWarmAssets(cold, prioritize: true);
          for (final id in cold) {
            if (!session.isWarmInFlight(id)) {
              _startStripchatWarmTask(session, id);
            }
          }
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
  }

  List<String> _tailMediaIds(List<String> assetIds, int tailCount) {
    final media = _mediaAssetIds(assetIds);
    return _lastIds(media, tailCount);
  }

  List<String> _lastIds(List<String> ids, int tailCount) {
    if (ids.isEmpty || tailCount <= 0) {
      return const <String>[];
    }
    if (ids.length <= tailCount) {
      return List<String>.from(ids);
    }
    return ids.sublist(ids.length - tailCount);
  }

  List<String> _uncachedTailMediaIds({
    required _StripchatLlHlsSession session,
    required List<String> assetIds,
    required int tailCount,
  }) {
    return _tailMediaIds(assetIds, tailCount)
        .where((id) => !session.cachedAssets.containsKey(id))
        .toList(growable: false);
  }

  List<String> _uncachedLastIds({
    required _StripchatLlHlsSession session,
    required List<String> assetIds,
    required int tailCount,
  }) {
    return _lastIds(assetIds, tailCount)
        .where((id) => !session.cachedAssets.containsKey(id))
        .toList(growable: false);
  }

  Future<void> _awaitTailMediaWarm(
    _StripchatLlHlsSession session,
    List<String> assetIds, {
    required int tailCount,
    required Duration budget,
  }) async {
    final targets = _tailMediaIds(assetIds, tailCount);
    await _awaitSpecificAssetsWarm(session, targets, budget: budget);
  }

  Future<void> _awaitSpecificAssetsWarm(
    _StripchatLlHlsSession session,
    List<String> targets, {
    required Duration budget,
  }) async {
    if (targets.isEmpty || _disposed || session._disposed) {
      return;
    }
    session.enqueueWarmAssets(targets, prioritize: true);
    for (final id in targets) {
      if (!session.cachedAssets.containsKey(id) &&
          !session.isWarmInFlight(id)) {
        _startStripchatWarmTask(session, id);
      }
    }
    final deadline = DateTime.now().add(budget);
    while (DateTime.now().isBefore(deadline)) {
      if (_disposed || session._disposed) {
        return;
      }
      if (targets.every(session.cachedAssets.containsKey)) {
        return;
      }
      for (final id in targets) {
        if (!session.cachedAssets.containsKey(id) &&
            !session.isWarmInFlight(id)) {
          _startStripchatWarmTask(session, id);
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }
  }

  /// Drop any uncached media URIs from a rewritten playlist (high-tier safety).
  _StripchatRewrittenPlaylist? _restrictPlaylistToCachedAssets({
    required _StripchatLlHlsSession session,
    required _StripchatRewrittenPlaylist playlist,
    required String structureManifest,
  }) {
    if (playlist.assetIds.isEmpty) {
      return playlist;
    }
    final cold = playlist.assetIds
        .where((id) => !session.cachedAssets.containsKey(id))
        .toList(growable: false);
    if (cold.isEmpty) {
      return playlist;
    }
    // Re-filter via cached-only builder on the rewritten body.
    final filtered = _buildCachedOnlyPlaylist(
      session: session,
      rewritten: playlist,
    );
    if (filtered.mediaSegmentCount <= 0) {
      return null;
    }
    _trace(
      'playlist restrict-cached session=${session.id} '
      'dropped=${cold.length} kept=${filtered.mediaSegmentCount}',
    );
    return _StripchatRewrittenPlaylist(
      manifest: filtered.manifest,
      assetIds: filtered.assetIds,
      mediaSegmentCount: filtered.mediaSegmentCount,
    );
  }

  /// After an asset is delivered, warm following media in the raw window.
  void _warmNeighborAssets(
    _StripchatLlHlsSession session,
    String assetId,
  ) {
    final raw = session.lastRawAssetIds;
    if (raw.isEmpty) {
      return;
    }
    final index = raw.indexOf(assetId);
    if (index < 0) {
      return;
    }
    final neighbors = <String>[];
    for (
      var i = index + 1;
      i < raw.length && neighbors.length < _d.scNeighborWarmAhead;
      i += 1
    ) {
      neighbors.add(raw[i]);
    }
    // Also keep previous stable segs warm (re-seek / playlist overlap).
    for (var i = max(0, index - 1); i < index; i += 1) {
      neighbors.add(raw[i]);
    }
    if (neighbors.isEmpty) {
      return;
    }
    session.enqueueWarmAssets(neighbors, prioritize: true);
    for (final id in neighbors) {
      if (!session.cachedAssets.containsKey(id) &&
          !session.isWarmInFlight(id)) {
        _startStripchatWarmTask(session, id);
      }
    }
  }

  /// Rewrite media playlist so only locally cached *media* segment URIs remain.
  /// Uncached live-edge EXTINF+URI pairs are stripped. MAP is kept (init).
  /// [mediaSegmentCount] counts only EXTINF+URI pairs (not MAP).
  _StripchatFilteredPlaylist _buildCachedOnlyPlaylist({
    required _StripchatLlHlsSession session,
    required _StripchatRewrittenPlaylist rewritten,
  }) {
    if (_looksLikeMasterPlaylist(rewritten.manifest)) {
      return _StripchatFilteredPlaylist(
        manifest: rewritten.manifest,
        assetIds: rewritten.assetIds,
        mediaSegmentCount: 0,
      );
    }
    final output = <String>[];
    final keptAssets = <String>[];
    var mediaSegmentCount = 0;
    String? pendingExtinf;
    for (final rawLine in const LineSplitter().convert(rewritten.manifest)) {
      final line = rawLine.trim();
      if (line.isEmpty) {
        output.add(rawLine);
        continue;
      }
      if (line.toUpperCase().startsWith('#EXTINF:')) {
        pendingExtinf = rawLine;
        continue;
      }
      if (line.startsWith('#')) {
        pendingExtinf = null;
        output.add(rawLine);
        continue;
      }
      final assetMatch = _stripchatLocalAssetIdRe.firstMatch(line);
      if (assetMatch == null) {
        if (pendingExtinf != null) {
          output.add(pendingExtinf);
          pendingExtinf = null;
        }
        output.add(rawLine);
        continue;
      }
      final assetId = assetMatch.group(1)!;
      final isMediaSeg = pendingExtinf != null;
      if (session.cachedAssets.containsKey(assetId)) {
        if (pendingExtinf != null) {
          output.add(pendingExtinf);
          pendingExtinf = null;
        }
        output.add(rawLine);
        if (!keptAssets.contains(assetId)) {
          keptAssets.add(assetId);
        }
        if (isMediaSeg) {
          mediaSegmentCount += 1;
        }
      } else {
        // Drop cold segment and its duration tag — mpv must not request it yet.
        pendingExtinf = null;
      }
    }
    return _StripchatFilteredPlaylist(
      manifest: '${output.join('\n')}\n',
      assetIds: List<String>.unmodifiable(keptAssets),
      mediaSegmentCount: mediaSegmentCount,
    );
  }

  /// Warm every asset in the (short) media playlist — SC usually has ~4 segs.
  /// Newest first after MAP/init head so live edge is ready before demuxer.
  void _warmStripchatPlaylistAssets(
    _StripchatLlHlsSession session,
    List<String> assetIds,
  ) {
    if (assetIds.isEmpty) {
      return;
    }
    final unique = <String>[];
    final seen = <String>{};
    // Keep playlist head (MAP/init) first.
    final initCount = min(_d.scWarmInitAssetCount, assetIds.length);
    for (final id in assetIds.take(initCount)) {
      if (seen.add(id)) {
        unique.add(id);
      }
    }
    // Then remaining segments newest-first (live edge).
    if (assetIds.length > initCount) {
      final rest = assetIds.sublist(initCount);
      for (final id in rest.reversed) {
        if (seen.add(id)) {
          unique.add(id);
        }
      }
    }
    session.enqueueWarmAssets(unique, prioritize: false);
    _kickStripchatWarmDrain(session);
  }

  /// Best-effort wait used only by session prime (not the live HTTP path).
  Future<void> _awaitStripchatEdgeWarm(
    _StripchatLlHlsSession session,
    List<String> assetIds, {
    Duration? timeout,
  }) async {
    if (assetIds.isEmpty || _disposed || session._disposed) {
      return;
    }
    final edgeCount = min(_d.scWarmAssetPrefetchLimit, assetIds.length);
    final edge = assetIds.sublist(assetIds.length - edgeCount);
    final want = min(_d.scPlaylistEdgeWarmMinCached, edge.length);
    // Newest first targets.
    final targets = edge.reversed.take(want).toList(growable: false);
    if (targets.isEmpty) {
      return;
    }
    session.enqueueWarmAssets(targets, prioritize: true);
    _kickStripchatWarmDrain(session);
    final deadline = DateTime.now().add(
      timeout ?? _d.scPrimeEdgeWarmWait,
    );
    while (DateTime.now().isBefore(deadline)) {
      if (_disposed || session._disposed) {
        return;
      }
      final cached = targets
          .where((id) => session.cachedAssets.containsKey(id))
          .length;
      if (cached >= want) {
        return;
      }
      for (final id in targets) {
        if (!session.cachedAssets.containsKey(id) &&
            !session.isWarmInFlight(id)) {
          _startStripchatWarmTask(session, id);
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
  }

  void _kickStripchatWarmDrain(_StripchatLlHlsSession session) {
    if (_disposed || session._disposed) {
      return;
    }
    while (session.warmInFlightCount < _d.scWarmConcurrency) {
      final assetId = session.takeNextWarmAssetId();
      if (assetId == null) {
        return;
      }
      if (session.cachedAssets.containsKey(assetId)) {
        session.touchCachedAsset(assetId);
        continue;
      }
      _startStripchatWarmTask(session, assetId);
    }
  }

  /// Start a warm fetch. Player-requested assets may call this even when the
  /// concurrency budget is full so mpv is not blocked behind background warms.
  void _startStripchatWarmTask(
    _StripchatLlHlsSession session,
    String assetId,
  ) {
    if (session.cachedAssets.containsKey(assetId) ||
        session.isWarmInFlight(assetId)) {
      return;
    }
    session.removeFromWarmQueue(assetId);
    final future = _prefetchAsset(session, assetId).whenComplete(() {
      session.noteWarmFinished(assetId);
      // Drain next queued items as slots free.
      _kickStripchatWarmDrain(session);
    });
    session.noteWarmStarted(assetId, future);
    unawaited(future);
  }

  Future<void> _handleAssetRequest(
    HttpRequest request, {
    required _StripchatLlHlsSession session,
    required String assetId,
  }) async {
    if (_disposed || session._disposed) {
      await _sendServiceUnavailable(request);
      return;
    }
    final assetTarget = session.resolveAssetTarget(assetId);
    if (assetTarget == null) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    final assetUris = assetTarget.uris;
    final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
    final shouldBypassCache =
        rangeHeader != null && rangeHeader.trim().isNotEmpty;
    // assetId is content-addressed by the URI set. Serve whatever we cached
    // for this id — including bridge-decoded source URLs that are not in
    // assetUris (the previous sourceUrl∈uris check discarded warm hits).
    final cached = shouldBypassCache ? null : session.cachedAssets[assetId];
    if (cached != null) {
      session.touchCachedAsset(assetId);
      _warmNeighborAssets(session, assetId);
      request.response.statusCode = HttpStatus.ok;
      request.response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
      if (cached.contentType != null) {
        request.response.headers.contentType = cached.contentType;
      }
      request.response.add(cached.bytes);
      await request.response.close();
      return;
    }
    if (!shouldBypassCache) {
      // Player demand always starts immediately (may exceed concurrency cap)
      // so we wait on a real in-flight future instead of a queued slot.
      if (!session.cachedAssets.containsKey(assetId) &&
          !session.isWarmInFlight(assetId)) {
        _startStripchatWarmTask(session, assetId);
      }
      // High-bitrate SC segments often need >1.2s; wait longer on demand path.
      final warmBudget = session.pinSingleRendition ||
              _tierClassFor(
                    preferredVariantId: session.preferredVariantId,
                    mediaUri: session.playlistUri ?? session.upstreamUri,
                    pinSingleRendition: session.pinSingleRendition,
                  ) ==
                  _StripchatTierClass.high
          ? _d.scHighWarmWaitTimeout
          : _d.scWarmWaitTimeout;
      final warmed = await session.waitForWarmAsset(
        assetId,
        timeout: warmBudget,
      );
      if (_disposed || session._disposed) {
        await _sendServiceUnavailable(request);
        return;
      }
      if (warmed != null) {
        session.touchCachedAsset(assetId);
        _warmNeighborAssets(session, assetId);
        request.response.statusCode = HttpStatus.ok;
        request.response.headers.set(
          HttpHeaders.cacheControlHeader,
          'no-store',
        );
        if (warmed.contentType != null) {
          request.response.headers.contentType = warmed.contentType;
        }
        request.response.add(warmed.bytes);
        await request.response.close();
        return;
      }
    }
    final resolvedDecodedUri = await _resolveDecodedBridgeUri(
      session: session,
      assetTarget: assetTarget,
      allowWait: true,
    );
    if (_disposed || session._disposed) {
      await _sendServiceUnavailable(request);
      return;
    }
    if (resolvedDecodedUri != null) {
      session.noteBridgeResolved();
      final directResponse = await _openAssetResponse(
        uri: resolvedDecodedUri,
        sessionHeaders: session.headers,
        passthroughHeaders: _buildPassthroughRequestHeaders(request),
      );
      if (_disposed || session._disposed) {
        await _sendServiceUnavailable(request);
        return;
      }
      request.response.statusCode = directResponse.statusCode;
      request.response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
      final directContentType = directResponse.headers.contentType;
      if (directContentType != null) {
        request.response.headers.contentType = directContentType;
      }
      if (!shouldBypassCache && directResponse.statusCode == HttpStatus.ok) {
        final bytes = Uint8List.fromList(
          await directResponse.fold<List<int>>(
            <int>[],
            (buffer, data) => buffer..addAll(data),
          ),
        );
        if (_disposed || session._disposed) {
          await _sendServiceUnavailable(request);
          return;
        }
        session.cachedAssets[assetId] = _StripchatCachedAsset(
          bytes: bytes,
          contentType: directContentType,
          sourceUrl: resolvedDecodedUri.toString(),
        );
        session.touchCachedAsset(assetId);
        _warmNeighborAssets(session, assetId);
        request.response.add(bytes);
        await request.response.close();
        return;
      }
      if (_disposed || session._disposed) {
        await _sendServiceUnavailable(request);
        return;
      }
      await directResponse.pipe(request.response);
      return;
    }
    session.noteBridgeMiss();
    if (!_enablePdkeyFallback || assetUris.isEmpty) {
      request.response.statusCode = HttpStatus.badGateway;
      request.response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
      request.response.write(
        'stripchat decoded url unavailable and pdkey fallback disabled',
      );
      await request.response.close();
      return;
    }
    final opened = await _openAssetResponseWithFallbacks(
      session: session,
      sessionId: session.id,
      assetId: assetId,
      uris: assetUris,
      sessionHeaders: session.headers,
      passthroughHeaders: _buildPassthroughRequestHeaders(request),
    );
    if (_disposed || session._disposed) {
      await _sendServiceUnavailable(request);
      return;
    }
    final upstreamResponse = opened.response;
    request.response.statusCode = upstreamResponse.statusCode;
    request.response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    final contentType = upstreamResponse.headers.contentType;
    if (contentType != null) {
      request.response.headers.contentType = contentType;
    }
    if (!shouldBypassCache && upstreamResponse.statusCode == HttpStatus.ok) {
      final bytes = Uint8List.fromList(
        await upstreamResponse.fold<List<int>>(
          <int>[],
          (buffer, data) => buffer..addAll(data),
        ),
      );
      if (_disposed || session._disposed) {
        await _sendServiceUnavailable(request);
        return;
      }
      session.cachedAssets[assetId] = _StripchatCachedAsset(
        bytes: bytes,
        contentType: contentType,
        sourceUrl: opened.uri.toString(),
      );
      session.touchCachedAsset(assetId);
      _warmNeighborAssets(session, assetId);
      request.response.add(bytes);
      await request.response.close();
      return;
    }
    if (_disposed || session._disposed) {
      await _sendServiceUnavailable(request);
      return;
    }
    await upstreamResponse.pipe(request.response);
  }

  Future<void> _prefetchAsset(
    _StripchatLlHlsSession session,
    String assetId,
  ) async {
    if (_disposed || session._disposed) return;
    Object? lastError;
    for (
      var attempt = 0;
      attempt <= _d.scPrefetchTransientRetries;
      attempt += 1
    ) {
      if (_disposed || session._disposed) return;
      if (session.cachedAssets.containsKey(assetId)) {
        session.touchCachedAsset(assetId);
        return;
      }
      try {
        await _prefetchAssetOnce(session, assetId);
        if (session.cachedAssets.containsKey(assetId)) {
          return;
        }
        // Non-throwing miss (404 / no bridge): do not retry forever.
        return;
      } catch (error) {
        lastError = error;
        if (!_isTransientUpstreamError(error) ||
            attempt >= _d.scPrefetchTransientRetries) {
          _trace(
            'asset prefetch failed session=${session.id} asset=$assetId '
            'attempt=${attempt + 1} error=$error',
          );
          return;
        }
        _trace(
          'asset prefetch retry session=${session.id} asset=$assetId '
          'attempt=${attempt + 1} error=$error',
        );
        await Future<void>.delayed(_d.scPrefetchRetryDelay);
      }
    }
    if (lastError != null) {
      _trace(
        'asset prefetch failed session=${session.id} asset=$assetId '
        'error=$lastError',
      );
    }
  }

  /// Single prefetch attempt. Throws on mid-body disconnect so caller can retry.
  Future<void> _prefetchAssetOnce(
    _StripchatLlHlsSession session,
    String assetId,
  ) async {
    final assetTarget = session.resolveAssetTarget(assetId);
    if (assetTarget == null) {
      return;
    }
    final assetUris = assetTarget.uris;
    final existing = session.cachedAssets[assetId];
    if (existing != null) {
      session.touchCachedAsset(assetId);
      return;
    }
    final resolvedDecodedUri = await _resolveDecodedBridgeUri(
      session: session,
      assetTarget: assetTarget,
    );
    if (_disposed || session._disposed) return;
    if (resolvedDecodedUri != null) {
      session.noteBridgeResolved();
      final response = await _openAssetResponse(
        uri: resolvedDecodedUri,
        sessionHeaders: session.headers,
      );
      if (_disposed || session._disposed) return;
      if (response.statusCode == HttpStatus.ok) {
        final contentType = response.headers.contentType;
        final bytes = Uint8List.fromList(
          await response.fold<List<int>>(
            <int>[],
            (buffer, data) => buffer..addAll(data),
          ),
        );
        if (_disposed || session._disposed) return;
        session.cachedAssets[assetId] = _StripchatCachedAsset(
          bytes: bytes,
          contentType: contentType,
          sourceUrl: resolvedDecodedUri.toString(),
        );
        session.touchCachedAsset(assetId);
        return;
      }
      await response.drain<void>();
    }
    if (_disposed || session._disposed) return;
    session.noteBridgeMiss();
    if (!_enablePdkeyFallback || assetUris.isEmpty) {
      _trace(
        'asset prefetch skipped session=${session.id} asset=$assetId '
        'reason=no-bridge-and-pdkey-fallback-disabled',
      );
      return;
    }
    final opened = await _openAssetResponseWithFallbacks(
      session: session,
      sessionId: session.id,
      assetId: assetId,
      uris: assetUris,
      sessionHeaders: session.headers,
    );
    if (_disposed || session._disposed) return;
    final response = opened.response;
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      _trace(
        'asset prefetch skipped session=${session.id} asset=$assetId '
        'status=${response.statusCode} uri=${opened.uri}',
      );
      return;
    }
    final contentType = response.headers.contentType;
    final bytes = Uint8List.fromList(
      await response.fold<List<int>>(
        <int>[],
        (buffer, data) => buffer..addAll(data),
      ),
    );
    if (_disposed || session._disposed) return;
    session.cachedAssets[assetId] = _StripchatCachedAsset(
      bytes: bytes,
      contentType: contentType,
      sourceUrl: opened.uri.toString(),
    );
    session.touchCachedAsset(assetId);
  }

  bool _isTransientUpstreamError(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('connection closed') ||
        text.contains('connection reset') ||
        text.contains('broken pipe') ||
        text.contains('connection abort') ||
        text.contains('timed out') ||
        text.contains('timeout') ||
        text.contains('http exception');
  }

  void _startSessionPrimeIfNeeded(_StripchatLlHlsSession session) {
    if (!_enablePriming) {
      return;
    }
    if (session._disposed) {
      return;
    }
    if (session.startupPrimeInFlight != null) {
      return;
    }
    final prime = _primeSession(session);
    session.startupPrimeInFlight = prime;
    unawaited(_finalizeSessionPrime(session, prime));
  }

  Future<void> _finalizeSessionPrime(
    _StripchatLlHlsSession session,
    Future<void> prime,
  ) async {
    try {
      await prime;
    } catch (_) {
    } finally {
      if (identical(session.startupPrimeInFlight, prime)) {
        session.startupPrimeInFlight = null;
      }
    }
  }

  Future<void> _primeSession(_StripchatLlHlsSession session) async {
    try {
      final rewritten = await _materializePlaylist(
        session: session,
        requestUri: session.upstreamUri,
      );
      if (session._disposed || rewritten == null) {
        return;
      }
      // Auto master has no media assets (only STREAM-INF). Warm top-N media
      // children in the background so ABR hops are cache-ahead ready.
      // Never collapse the served master — platform ABR still owns the ladder.
      // Mobile (simple): no Auto prewarm; light edge warm only.
      if (_looksLikeMasterPlaylist(rewritten.manifest) &&
          !session.pinSingleRendition) {
        if (_d.scAutoPrewarmTopVariants > 0) {
          unawaited(_prewarmAutoMediaVariants(session));
        }
      } else if (!_d.scSimplePublish) {
        await _awaitStripchatEdgeWarm(session, rewritten.assetIds);
      } else if (rewritten.assetIds.isNotEmpty) {
        final warmIds = rewritten.assetIds
            .take(_d.scWarmAssetPrefetchLimit)
            .toList(growable: false);
        session.enqueueWarmAssets(warmIds, prioritize: true);
        _kickStripchatWarmDrain(session);
      }
      if (!_d.scSimplePublish) {
        _ensurePlaylistPump(session);
      }
    } catch (error) {
      _trace('session prime failed session=${session.id} error=$error');
    }
  }

  /// Delivery-only: cache-ahead top-N bandwidth media playlists for Auto ABR.
  /// Player still receives multi-variant master. Coalesced so concurrent master
  /// materialize / prime only start one prewarm wave.
  Future<void> _prewarmAutoMediaVariants(
    _StripchatLlHlsSession session,
  ) async {
    if (_disposed ||
        session._disposed ||
        session.pinSingleRendition ||
        _d.scAutoPrewarmTopVariants <= 0) {
      return;
    }
    final existing = session.autoPrewarmInFlight;
    if (existing != null) {
      return existing;
    }
    final run = () async {
      try {
        final upstream = await _fetchPlaylistWithFallbacks(
          session: session,
          uri: session.upstreamUri,
          headers: session.headers,
        );
        if (_disposed ||
            session._disposed ||
            upstream.statusCode != HttpStatus.ok ||
            !_looksLikeMasterPlaylist(upstream.body)) {
          return;
        }
        final variants = _listMasterVariantsByBandwidthDesc(
          playlistUri: upstream.finalUri,
          manifest: upstream.body,
        );
        if (variants.isEmpty) {
          return;
        }
        final top = variants
            .take(_d.scAutoPrewarmTopVariants)
            .toList(growable: false);
        _trace(
          'auto media prewarm start session=${session.id} '
          'count=${top.length} '
          'children=${top.map((v) => v.pathSegments.isEmpty ? v.path : v.pathSegments.last).join(',')}',
        );
        // Parallel tier materialize (coalesced per path) so top-3 land together
        // instead of serial ~10s (14:14 logs). Highest BW first in list for
        // enqueue priority when tasks race.
        await Future.wait(
          top.map((childUri) async {
            if (_disposed || session._disposed) {
              return;
            }
            final localRequest = _sessionPlaylistUri(
              session.id,
              upstreamUri: childUri,
            );
            final warmed = await _materializePlaylist(
              session: session,
              requestUri: localRequest,
            );
            _trace(
              'auto media prewarm tier session=${session.id} '
              'child=${childUri.path} '
              'media=${warmed?.mediaSegmentCount ?? 0} '
              'assets=${warmed?.assetIds.length ?? 0}',
            );
          }),
        );
        _trace('auto media prewarm done session=${session.id}');
      } catch (error) {
        _trace(
          'auto media prewarm failed session=${session.id} error=$error',
        );
      }
    }();
    session.autoPrewarmInFlight = run;
    try {
      await run;
    } finally {
      if (identical(session.autoPrewarmInFlight, run)) {
        session.autoPrewarmInFlight = null;
      }
    }
  }

  /// Master variants sorted highest-bandwidth first (for Auto prewarm ladder).
  List<Uri> _listMasterVariantsByBandwidthDesc({
    required Uri playlistUri,
    required String manifest,
  }) {
    final auth = _parseMouflonAuthFromManifest(manifest);
    final variants = <({Uri url, int bandwidth})>[];
    String? currentInfoLine;
    for (final rawLine in const LineSplitter().convert(manifest)) {
      final line = rawLine.trim();
      if (line.toUpperCase().startsWith('#EXT-X-STREAM-INF:')) {
        currentInfoLine = line;
        continue;
      }
      if (line.startsWith('#')) {
        continue;
      }
      if (!line.toLowerCase().contains('.m3u8') || currentInfoLine == null) {
        currentInfoLine = null;
        continue;
      }
      final bandwidth = _parseStreamInfBandwidth(currentInfoLine);
      currentInfoLine = null;
      if (bandwidth <= 0) {
        continue;
      }
      final resolved = _appendPlaylistAuth(playlistUri.resolve(line), auth);
      variants.add((url: resolved, bandwidth: bandwidth));
    }
    variants.sort((a, b) => b.bandwidth.compareTo(a.bandwidth));
    return variants.map((v) => v.url).toList(growable: false);
  }

  Future<Uri?> _resolveDecodedBridgeUri({
    required _StripchatLlHlsSession session,
    required _StripchatAssetTargets assetTarget,
    bool allowWait = false,
  }) async {
    final resolver = _decodedUrlResolver;
    final roomUrl = session.roomUrl.trim();
    final segmentKey = assetTarget.segmentKey.trim();
    if (resolver == null || roomUrl.isEmpty || segmentKey.isEmpty) {
      return null;
    }

    Uri? parseResolved() {
      final resolvedDecodedUrl = resolver(
        roomUrl: roomUrl,
        segmentKey: segmentKey,
      );
      if (resolvedDecodedUrl == null || resolvedDecodedUrl.trim().isEmpty) {
        return null;
      }
      return Uri.tryParse(resolvedDecodedUrl.trim());
    }

    final immediate = parseResolved();
    if (immediate != null || !allowWait) {
      return immediate;
    }

    final deadline = DateTime.now().add(_stripchatBridgeLookupTimeout);
    while (DateTime.now().isBefore(deadline)) {
      if (_disposed || session._disposed) {
        return null;
      }
      await Future<void>.delayed(_stripchatBridgeLookupPollInterval);
      if (_disposed || session._disposed) {
        return null;
      }
      final resolved = parseResolved();
      if (resolved != null) {
        return resolved;
      }
    }
    return null;
  }

  Map<String, String> _buildPassthroughRequestHeaders(HttpRequest request) {
    final passthrough = <String, String>{};
    final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
    if (rangeHeader != null && rangeHeader.trim().isNotEmpty) {
      passthrough[HttpHeaders.rangeHeader] = rangeHeader;
    }
    final ifRangeHeader = request.headers.value(HttpHeaders.ifRangeHeader);
    if (ifRangeHeader != null && ifRangeHeader.trim().isNotEmpty) {
      passthrough[HttpHeaders.ifRangeHeader] = ifRangeHeader;
    }
    return passthrough;
  }

  Future<HttpClientResponse> _openAssetResponse({
    required Uri uri,
    required Map<String, String> sessionHeaders,
    Map<String, String> passthroughHeaders = const <String, String>{},
  }) async {
    final request = await _client
        .getUrl(uri)
        .timeout(const Duration(seconds: 8));
    _buildUpstreamHeaders(sessionHeaders).forEach(request.headers.set);
    passthroughHeaders.forEach(request.headers.set);
    return request.close().timeout(const Duration(seconds: 8));
  }

  Future<_OpenedAssetResponse> _openAssetResponseWithFallbacks({
    required _StripchatLlHlsSession session,
    required String sessionId,
    required String assetId,
    required List<Uri> uris,
    required Map<String, String> sessionHeaders,
    Map<String, String> passthroughHeaders = const <String, String>{},
  }) async {
    if (uris.isEmpty) {
      throw StateError(
        'Stripchat asset fallback invoked with no candidate uris: '
        'session=$sessionId asset=$assetId',
      );
    }
    late _OpenedAssetResponse lastOpened;
    for (var index = 0; index < uris.length; index += 1) {
      final uri = uris[index];
      try {
        final response = await _openAssetResponse(
          uri: uri,
          sessionHeaders: sessionHeaders,
          passthroughHeaders: passthroughHeaders,
        );
        lastOpened = _OpenedAssetResponse(uri: uri, response: response);
        final isLast = index == uris.length - 1;
        if (response.statusCode < HttpStatus.badRequest || isLast) {
          if (index > 0) {
            _trace(
              'asset fallback resolved session=$sessionId asset=$assetId '
              'status=${response.statusCode} uri=$uri',
            );
          }
          return lastOpened;
        }
        _trace(
          'asset primary failed session=$sessionId asset=$assetId '
          'status=${response.statusCode} uri=$uri',
        );
        await response.drain<void>().timeout(const Duration(seconds: 3));
      } catch (error) {
        if (index == uris.length - 1) {
          rethrow;
        }
        _trace(
          'asset primary failed with error session=$sessionId asset=$assetId '
          'error=$error uri=$uri',
        );
      }
    }
    return lastOpened;
  }

  Future<_FetchedPlaylist> _fetchPlaylist({
    required Uri uri,
    required Map<String, String> headers,
  }) async {
    final request = await _client
        .getUrl(uri)
        .timeout(_d.scPlaylistFetchTimeout);
    _buildUpstreamHeaders(headers).forEach(request.headers.set);
    final response = await request
        .close()
        .timeout(_d.scPlaylistFetchTimeout);
    final body = await response
        .transform(utf8.decoder)
        .join()
        .timeout(_d.scPlaylistFetchTimeout);
    final redirect = response.redirects.isNotEmpty
        ? response.redirects.last.location
        : null;
    final finalUri = redirect == null ? uri : uri.resolveUri(redirect);
    return _FetchedPlaylist(
      statusCode: response.statusCode,
      body: body,
      finalUri: finalUri,
    );
  }

  Future<_FetchedPlaylist> _fetchPlaylistWithFallbacks({
    required _StripchatLlHlsSession session,
    required Uri uri,
    required Map<String, String> headers,
    List<Uri>? fallbackUrisOverride,
  }) async {
    final attemptedHosts = <String>{uri.host.toLowerCase()};
    Object? lastError;
    StackTrace? lastStackTrace;
    _FetchedPlaylist? primary;

    Future<_FetchedPlaylist?> tryFetch(
      Uri targetUri, {
      required bool isPrimary,
    }) async {
      try {
        final fetched = await _fetchPlaylist(uri: targetUri, headers: headers);
        attemptedHosts.add(fetched.finalUri.host.toLowerCase());
        if (isPrimary) {
          primary = fetched;
        }
        return fetched;
      } on Object catch (error, stackTrace) {
        lastError = error;
        lastStackTrace = stackTrace;
        _trace(
          'playlist upstream fetch error session=${session.id} '
          'uri=$targetUri error=$error',
        );
        return null;
      }
    }

    bool isOk(_FetchedPlaylist fetched) =>
        fetched.statusCode >= 200 && fetched.statusCode < 300;

    _FetchedPlaylist? primaryFetched;
    primaryFetched = await tryFetch(uri, isPrimary: true);
    // Only 2xx short-circuits. 403/404/5xx must try host + sibling fallbacks
    // (Nicoleevien 15:53: source media 404 returned immediately → empty loop).
    if (primaryFetched != null && isOk(primaryFetched)) {
      return primaryFetched;
    }

    final fallbackBaseUri = primaryFetched?.finalUri ?? uri;
    final fallbackUris =
        fallbackUrisOverride ??
        buildStripchatPlaylistFallbackUris(
          uri: fallbackBaseUri,
          preferredCdnDomains: session.playlistCdnDomains,
          attemptedHosts: attemptedHosts,
        );
    for (final fallbackUri in fallbackUris) {
      final fallback = await tryFetch(fallbackUri, isPrimary: false);
      if (fallback == null) {
        continue;
      }
      if (isOk(fallback)) {
        _trace(
          'playlist upstream host fallback session=${session.id} '
          'from=${(primaryFetched?.finalUri ?? uri).host} to=${fallback.finalUri.host} '
          'primaryStatus=${primaryFetched?.statusCode ?? -1}',
        );
        return fallback;
      }
    }

    final siblingFallbackUris = buildStripchatSiblingPlaylistFallbackUris(
      uri: fallbackBaseUri,
      attemptedUris: <Uri>[
        uri,
        if (primaryFetched != null) primaryFetched.finalUri,
        ...fallbackUris,
      ],
    );
    for (final siblingUri in siblingFallbackUris) {
      final sibling = await tryFetch(siblingUri, isPrimary: false);
      if (sibling == null) {
        continue;
      }
      if (isOk(sibling)) {
        _trace(
          'playlist upstream sibling fallback session=${session.id} '
          'from=${fallbackBaseUri.pathSegments.isNotEmpty ? fallbackBaseUri.pathSegments.last : fallbackBaseUri.path} '
          'to=${sibling.finalUri.pathSegments.isNotEmpty ? sibling.finalUri.pathSegments.last : sibling.finalUri.path} '
          'primaryStatus=${primaryFetched?.statusCode ?? -1}',
        );
        return sibling;
      }
    }

    final failedPrimary = primary;
    if (failedPrimary != null) {
      return failedPrimary;
    }
    final error = lastError ?? StateError('playlist upstream unavailable');
    final stackTrace = lastStackTrace ?? StackTrace.current;
    Error.throwWithStackTrace(error, stackTrace);
  }

  /// Same selection policy as Android `probePlaybackPlaylist` /
  /// `_selectPreferredVariantUrl`: preferred quality id first, then remaining
  /// variants by bandwidth so a dead source child still lands on highest
  /// working media (delivery recovery — does not change Auto multi-variant).
  Future<_FetchedPlaylist?> _collapseMasterToPreferredMediaPlaylist({
    required _StripchatLlHlsSession session,
    required _FetchedPlaylist upstream,
  }) async {
    if (!_looksLikeMasterPlaylist(upstream.body)) {
      return null;
    }
    final candidates = _orderedCollapseVariantUris(
      playlistUri: upstream.finalUri,
      manifest: upstream.body,
      preferredVariantId: session.preferredVariantId,
    );
    if (candidates.isEmpty) {
      return null;
    }
    for (final childUri in candidates) {
      if (_disposed || session._disposed) {
        return null;
      }
      try {
        final child = await _fetchPlaylistWithFallbacks(
          session: session,
          uri: childUri,
          headers: session.headers,
        );
        if (child.statusCode != HttpStatus.ok ||
            _looksLikeMasterPlaylist(child.body) ||
            !child.body.contains('#EXTINF:')) {
          _trace(
            'master collapse skip session=${session.id} '
            'child=${childUri.path} status=${child.statusCode}',
          );
          continue;
        }
        _trace(
          'master collapsed session=${session.id} '
          'from=${upstream.finalUri.path} to=${child.finalUri.path} '
          'preferred=${session.preferredVariantId.isEmpty ? 'auto-max' : session.preferredVariantId}',
        );
        session.pinnedMediaPlaylistUri = child.finalUri;
        session.lastStickyMediaKey = _mediaPlaylistKey(child.finalUri);
        return child;
      } on Object catch (error) {
        _trace(
          'master collapse error session=${session.id} uri=$childUri error=$error',
        );
      }
    }
    return null;
  }

  /// Re-fetch edge master and collapse when fixed-quality media child is dead.
  Future<_FetchedPlaylist?> _recoverPinnedMediaFromMaster(
    _StripchatLlHlsSession session,
  ) async {
    if (!session.pinSingleRendition || session.masterPlaylistUri == null) {
      return null;
    }
    final masterUri = session.masterPlaylistUri!;
    try {
      final master = await _fetchPlaylistWithFallbacks(
        session: session,
        uri: masterUri,
        headers: session.headers,
      );
      if (master.statusCode != HttpStatus.ok ||
          !_looksLikeMasterPlaylist(master.body)) {
        return null;
      }
      return _collapseMasterToPreferredMediaPlaylist(
        session: session,
        upstream: master,
      );
    } on Object catch (error) {
      _trace(
        'playlist pin master-recover error session=${session.id} '
        'uri=$masterUri error=$error',
      );
      return null;
    }
  }

  /// Preferred match first (if any), then all remaining by bandwidth desc.
  /// HAR 0716: STREAM-INF includes NAME="source"|"720p60"|... — honor NAME too.
  List<Uri> _orderedCollapseVariantUris({
    required Uri playlistUri,
    required String manifest,
    required String preferredVariantId,
  }) {
    final auth = _parseMouflonAuthFromManifest(manifest);
    final variants = <({Uri url, int bandwidth, String qualityId})>[];
    String? currentInfoLine;
    for (final rawLine in const LineSplitter().convert(manifest)) {
      final line = rawLine.trim();
      if (line.isEmpty) {
        continue;
      }
      if (line.toUpperCase().startsWith('#EXT-X-STREAM-INF:')) {
        currentInfoLine = line;
        continue;
      }
      if (line.startsWith('#')) {
        continue;
      }
      if (!line.toLowerCase().contains('.m3u8') || currentInfoLine == null) {
        currentInfoLine = null;
        continue;
      }
      final infoLine = currentInfoLine;
      final bandwidth = _parseStreamInfBandwidth(infoLine);
      currentInfoLine = null;
      if (bandwidth <= 0) {
        continue;
      }
      final resolved = _appendPlaylistAuth(playlistUri.resolve(line), auth);
      final filename = resolved.pathSegments.isEmpty
          ? ''
          : resolved.pathSegments.last.toLowerCase();
      final qualityMatch = RegExp(
        r'_(\d+p(?:60)?)\.m3u8$',
      ).firstMatch(filename);
      final nameMatch = RegExp(
        r'NAME="([^"]+)"',
        caseSensitive: false,
      ).firstMatch(infoLine);
      final nameId = nameMatch?.group(1)?.trim().toLowerCase() ?? '';
      final sourceLike =
          nameId == 'source' ||
          (qualityMatch == null &&
              RegExp(r'(^|/)\d+\.m3u8$').hasMatch(resolved.path.toLowerCase()));
      final qualityId = nameId.isNotEmpty
          ? nameId
          : (qualityMatch?.group(1) ?? (sourceLike ? 'source' : ''));
      variants.add((
        url: resolved,
        bandwidth: bandwidth,
        qualityId: qualityId,
      ));
    }
    if (variants.isEmpty) {
      return const <Uri>[];
    }
    final preferred = preferredVariantId.trim().toLowerCase();
    final ordered = <Uri>[];
    final seen = <String>{};
    void addUri(Uri url) {
      final key = '${url.host.toLowerCase()}${url.path}';
      if (seen.add(key)) {
        ordered.add(url);
      }
    }

    if (preferred.isNotEmpty && preferred != 'auto') {
      final matched = variants
          .where((variant) {
            if (preferred == 'source') {
              return variant.qualityId == 'source';
            }
            final path = variant.url.path.toLowerCase();
            return variant.qualityId == preferred ||
                variant.qualityId == '${preferred}60' ||
                path.contains('_$preferred.m3u8') ||
                path.contains('_${preferred}60.m3u8');
          })
          .toList(growable: false);
      matched.sort((a, b) => b.bandwidth.compareTo(a.bandwidth));
      for (final variant in matched) {
        addUri(variant.url);
      }
    }
    final rest = List.of(variants)
      ..sort((a, b) => b.bandwidth.compareTo(a.bandwidth));
    for (final variant in rest) {
      addUri(variant.url);
    }
    return ordered;
  }

  bool _looksLikeMasterPlaylist(String body) {
    return body.contains('#EXT-X-STREAM-INF');
  }

  /// Sticky key for a media playlist (host+path); ignore volatile HLS query.
  String _mediaPlaylistKey(Uri uri) {
    return '${uri.host.toLowerCase()}${uri.path}';
  }

  int _parseStreamInfBandwidth(String streamInfLine) {
    final match = RegExp(
      r'BANDWIDTH=(\d+)',
      caseSensitive: false,
    ).firstMatch(streamInfLine);
    return int.tryParse(match?.group(1) ?? '') ?? 0;
  }

  _StripchatPlaylistAuth? _parseMouflonAuthFromManifest(String manifest) {
    for (final rawLine in const LineSplitter().convert(manifest)) {
      final parsed = _parseMouflonAuth(rawLine.trim());
      if (parsed != null) {
        return parsed;
      }
    }
    return null;
  }

  Future<_StripchatRewrittenPlaylist> _rewritePlaylist({
    required _StripchatLlHlsSession session,
    required Uri playlistUri,
    required String manifest,
  }) async {
    final output = <String>[];
    final assetIds = <String>[];
    _StripchatResolvedAssetTargets? pendingMouflonTargets;
    _StripchatPlaylistAuth? auth;
    final seenPkeys = <String>[];
    String? pendingMapLine;
    Uri? pendingMapTarget;
    String? pendingVariantTag;
    final rawLines = const LineSplitter().convert(manifest).toList();

    // Phase 1: schedule all mouflon URI decrypts in parallel (auth is known
    // by the time each URI appears). Sequential await was the playlist
    // critical-path bottleneck on every 1–2s refresh.
    final mouflonFutures = <int, Future<_StripchatResolvedAssetTargets>>{};
    _StripchatPlaylistAuth? scanAuth;
    final scanSeenPkeys = <String>[];
    for (var index = 0; index < rawLines.length; index += 1) {
      final line = rawLines[index].trim();
      if (line.startsWith('#EXT-X-MOUFLON:PSCH:')) {
        final parsed = _parseMouflonAuth(line);
        final pkey = parsed?.pkey.trim() ?? '';
        if (pkey.isNotEmpty && !scanSeenPkeys.contains(pkey)) {
          scanSeenPkeys.add(pkey);
        }
        if (scanAuth == null) {
          scanAuth = parsed;
        } else if (parsed != null) {
          final effectiveCache = session.keyCache.withTrustedFallbacks();
          final currentRecord = effectiveCache.lookup(scanAuth.pkey);
          final currentKnown =
              currentRecord != null && !_shouldIgnorePdkeyRecord(currentRecord);
          if (!currentKnown) {
            final newRecord = effectiveCache.lookup(pkey);
            final newKnown =
                newRecord != null && !_shouldIgnorePdkeyRecord(newRecord);
            if (newKnown) {
              scanAuth = parsed;
            }
          }
        }
        continue;
      }
      if (line.startsWith('#EXT-X-MOUFLON:URI:')) {
        final authSnapshot = scanAuth;
        final seenSnapshot = List<String>.from(scanSeenPkeys);
        mouflonFutures[index] = _resolveMouflonAssetTargets(
          rawUri: line.substring('#EXT-X-MOUFLON:URI:'.length),
          playlistUri: playlistUri,
          auth: authSnapshot,
          enablePdkeyFallback: _enablePdkeyFallback,
          candidatePkeys: _orderedMouflonPkeys(
            currentPkey: authSnapshot?.pkey,
            upstreamPkey: playlistUri.queryParameters['pkey'],
            seenPkeys: seenSnapshot,
            keyCache: session.keyCache,
          ),
          keyCache: session.keyCache,
          tracePdkey: (phase, {required pkey, required source}) {
            _trace(
              'pdkey $phase pkey=$pkey source=$source',
              verbose: true,
            );
          },
          traceDecision: (message) => _trace(message, verbose: true),
          onPdkeyAllFailed: session.notePdkeyAllFailed,
          decryptMouflonSegment: session.decryptMouflonSegment,
          kDebugMode: _platformAdapter.kDebugMode,
          debugPrint: _platformAdapter.debugPrint,
        );
      }
    }
    final mouflonResolved = <int, _StripchatResolvedAssetTargets>{};
    if (mouflonFutures.isNotEmpty) {
      final entries = mouflonFutures.entries.toList(growable: false);
      final results = await Future.wait(entries.map((e) => e.value));
      for (var i = 0; i < entries.length; i += 1) {
        mouflonResolved[entries[i].key] = results[i];
      }
    }

    for (var lineIndex = 0; lineIndex < rawLines.length; lineIndex += 1) {
      final rawLine = rawLines[lineIndex];
      final line = rawLine.trim();
      if (line.isEmpty) {
        output.add(rawLine);
        continue;
      }
      if (_shouldDropLlHlsTag(line)) {
        if (line.startsWith('#EXT-X-PART:') ||
            line.startsWith('#EXT-X-PRELOAD-HINT:')) {
          pendingMouflonTargets = null;
        }
        continue;
      }
      if (line.startsWith('#EXT-X-MOUFLON:PSCH:')) {
        final parsed = _parseMouflonAuth(line);
        final pkey = parsed?.pkey.trim() ?? '';
        if (pkey.isNotEmpty && !seenPkeys.contains(pkey)) {
          seenPkeys.add(pkey);
        }
        // Prefer the first pkey that has a known pdkey in the key cache.
        // The pkey appended to sub-playlist URLs determines which pdkey the
        // CDN uses to encrypt segment IDs — choosing the wrong pkey means
        // CDN returns segments we cannot decrypt.
        String redact(String? k) {
          if (k == null || k.isEmpty) return '';
          return k.length <= 4 ? '***' : '${k.substring(0, 4)}***';
        }

        if (auth == null) {
          auth = parsed;
          if (_platformAdapter.kDebugMode) {
            _platformAdapter.debugPrint(
              '[psch] auth init pkey=${redact(parsed?.pkey)}',
            );
          }
        } else if (parsed != null) {
          final effectiveCache = session.keyCache.withTrustedFallbacks();
          final currentRecord = effectiveCache.lookup(auth.pkey);
          final currentKnown =
              currentRecord != null && !_shouldIgnorePdkeyRecord(currentRecord);
          if (!currentKnown) {
            final newRecord = effectiveCache.lookup(pkey);
            final newKnown =
                newRecord != null && !_shouldIgnorePdkeyRecord(newRecord);
            if (newKnown) {
              if (_platformAdapter.kDebugMode) {
                _platformAdapter.debugPrint(
                  '[psch] auth upgraded unknown=${redact(auth.pkey)} → known=${redact(pkey)}',
                );
              }
              auth = parsed;
            }
          } else if (_platformAdapter.kDebugMode) {
            _platformAdapter.debugPrint(
              '[psch] auth kept known=${redact(auth.pkey)}, skip ${redact(pkey)}',
            );
          }
        }
        continue;
      }
      if (line.startsWith('#EXT-X-MOUFLON:URI:')) {
        pendingMouflonTargets = mouflonResolved[lineIndex];
        continue;
      }
      if (_hasUriAttributeTag(line)) {
        if (line.toUpperCase().startsWith('#EXT-X-MAP:')) {
          pendingMapLine = rawLine;
          pendingMapTarget = _extractUriAttributeTarget(
            line: rawLine,
            playlistUri: playlistUri,
            auth: auth,
          );
          continue;
        }
        final rewrittenLine = _rewriteUriAttributes(
          line: rawLine,
          session: session,
          playlistUri: playlistUri,
          auth: auth,
          pendingMouflonTargets: pendingMouflonTargets,
          assetIds: assetIds,
        );
        output.add(rewrittenLine);
        if (line.startsWith('#EXT-X-PART:') ||
            line.startsWith('#EXT-X-PRELOAD-HINT:')) {
          pendingMouflonTargets = null;
        }
        continue;
      }
      if (line.startsWith('#')) {
        if (line.toUpperCase().startsWith('#EXT-X-STREAM-INF:')) {
          // Buffer STREAM-INF so we can drop it if the variant pkey is unknown.
          pendingVariantTag = rawLine;
        } else {
          output.add(rawLine);
        }
        continue;
      }
      final target =
          pendingMouflonTargets?.primary ??
          _resolvePlaylistTarget(
            playlistUri: playlistUri,
            rawValue: line,
            auth: auth,
          );
      // Variant stream pkey filter (master playlist context).
      // Drop variants whose pkey is not in the known key cache so we never
      // hit a 418; log the unknown pkey to aid pdkey-recovery.
      // Use the raw line URL (before auth appending) to extract pkey so we
      // don't confuse the master's auth.pkey with the variant's own pkey.
      if (target.path.toLowerCase().endsWith('.m3u8')) {
        final rawVariantUri = Uri.tryParse(
          playlistUri.resolve(line.trim()).toString(),
        );
        final variantPkey =
            rawVariantUri?.queryParameters['pkey']?.trim() ?? '';
        if (variantPkey.isNotEmpty) {
          final effectiveCache = session.keyCache.withTrustedFallbacks();
          final record = effectiveCache.lookup(variantPkey);
          final hasKnownPkey =
              record != null && !_shouldIgnorePdkeyRecord(record);
          if (!hasKnownPkey) {
            _trace(
              'master unknown pkey=$variantPkey — variant skipped; '
              'run pdkey-recovery to capture this key',
            );
            pendingVariantTag = null;
            pendingMouflonTargets = null;
            continue;
          }
        }
        if (pendingVariantTag != null) {
          output.add(pendingVariantTag);
          pendingVariantTag = null;
        }
      } else if (pendingVariantTag != null) {
        output.add(pendingVariantTag);
        pendingVariantTag = null;
      }
      final pendingMediaTag =
          output.isNotEmpty &&
              output.last.trim().toUpperCase().startsWith('#EXTINF:')
          ? output.removeLast()
          : null;
      if (pendingMapLine != null) {
        final shouldDropMap = await _shouldDropMapForPlaylist(
          session: session,
          firstSegmentTarget: target,
          firstSegmentFallbacks: pendingMouflonTargets?.fallback,
          mapTarget: pendingMapTarget,
        );
        if (!shouldDropMap) {
          output.add(
            _rewriteUriAttributes(
              line: pendingMapLine,
              session: session,
              playlistUri: playlistUri,
              auth: auth,
              pendingMouflonTargets: null,
              assetIds: assetIds,
            ),
          );
        }
        pendingMapLine = null;
        pendingMapTarget = null;
      }
      if (pendingMediaTag != null) {
        output.add(pendingMediaTag);
      }
      output.add(
        _localProxyUri(
          session,
          target,
          segmentKey: pendingMouflonTargets?.segmentKey,
          assetIds: assetIds,
          fallbackTargets: pendingMouflonTargets?.fallback,
        ).toString(),
      );
      pendingMouflonTargets = null;
    }
    return _StripchatRewrittenPlaylist(
      manifest: '${output.join('\n')}\n',
      assetIds: List<String>.unmodifiable(assetIds),
    );
  }

  Uri? _extractUriAttributeTarget({
    required String line,
    required Uri playlistUri,
    required _StripchatPlaylistAuth? auth,
  }) {
    final match = RegExp(_hlsUriAttributePattern).firstMatch(line);
    if (match == null) {
      return null;
    }
    final raw = match.group(2) ?? match.group(3) ?? '';
    if (raw.isEmpty) {
      return null;
    }
    return _resolvePlaylistTarget(
      playlistUri: playlistUri,
      rawValue: raw,
      auth: auth,
    );
  }

  Future<bool> _shouldDropMapForPlaylist({
    required _StripchatLlHlsSession session,
    required Uri? firstSegmentTarget,
    required List<Uri>? firstSegmentFallbacks,
    required Uri? mapTarget,
  }) async {
    if (mapTarget == null || firstSegmentTarget == null) {
      return false;
    }
    if (session.shouldDropMap != null) {
      return session.shouldDropMap!;
    }

    final rawCandidates =
        (firstSegmentFallbacks != null && firstSegmentFallbacks.isNotEmpty)
        ? firstSegmentFallbacks
        : <Uri>[firstSegmentTarget];

    final candidates = rawCandidates.fold<List<Uri>>(<Uri>[], (
      list,
      candidate,
    ) {
      if (!list.any((item) => item.toString() == candidate.toString())) {
        list.add(candidate);
      }
      return list;
    });

    Future<bool> checkCandidate(Uri candidate) async {
      try {
        final response = await _openAssetResponse(
          uri: candidate,
          sessionHeaders: session.headers,
          passthroughHeaders: const {'Range': 'bytes=0-32767'},
        ).timeout(const Duration(seconds: 3));
        try {
          if (response.statusCode != HttpStatus.ok &&
              response.statusCode != HttpStatus.partialContent) {
            return false;
          }
          final bytesBuilder = BytesBuilder();
          await for (final chunk in response.timeout(
            const Duration(seconds: 3),
          )) {
            bytesBuilder.add(chunk);
            if (bytesBuilder.length >= 32768) {
              break;
            }
          }
          final bytes = bytesBuilder.takeBytes();
          return stripchat_runtime.stripchatMp4BytesContainInitialization(
            bytes,
          );
        } finally {
          if (response.statusCode != HttpStatus.ok &&
              response.statusCode != HttpStatus.partialContent) {
            await response
                .drain<void>()
                .timeout(const Duration(seconds: 1))
                .catchError((_) {});
          }
        }
      } catch (_) {
        return false;
      }
    }

    final results = await Future.wait(candidates.map(checkCandidate));
    final shouldDrop = results.any((result) => result);
    session.shouldDropMap = shouldDrop;
    return shouldDrop;
  }

  @visibleForTesting
  static UnmodifiableListView<Uri> buildStripchatPlaylistFallbackUris({
    required Uri uri,
    List<String> preferredCdnDomains = const <String>[],
    Set<String> attemptedHosts = const <String>{},
  }) {
    final host = uri.host.trim().toLowerCase();
    final prefix = host.startsWith('media-hls.')
        ? 'media-hls.'
        : host.startsWith('edge-hls.')
        ? 'edge-hls.'
        : '';
    final seenHosts = <String>{
      host,
      ...attemptedHosts.map((item) => item.toLowerCase()),
    };
    // Prefer profile CDN order (desktop .net-first; mobile release order).
    final domains = _orderStripchatCdnDomains(<String>[
      ...preferredCdnDomains,
      ...HlsProxyDeliveryKnobs.fromActiveProfile().scKnownCdnDomains,
    ]);
    final fallbacks = <Uri>[];
    for (final domain in domains) {
      final normalizedDomain = domain.trim().toLowerCase();
      if (normalizedDomain.isEmpty) {
        continue;
      }
      final candidateHost = '$prefix$normalizedDomain';
      if (!seenHosts.add(candidateHost)) {
        continue;
      }
      fallbacks.add(
        uri.replace(
          host: candidateHost,
          path: uri.path,
          query: uri.hasQuery ? uri.query : null,
        ),
      );
    }
    return UnmodifiableListView<Uri>(fallbacks);
  }

  /// Stable CDN TLD preference for host failover (official player = .net).
  static List<String> _orderStripchatCdnDomains(Iterable<String> domains) {
    const rank = <String, int>{
      'doppiocdn.net': 0,
      'doppiocdn.org': 1,
      'doppiocdn.com': 2,
      'doppiocdn.media': 3,
    };
    final seen = <String>{};
    final ordered = <String>[];
    for (final domain in domains) {
      final d = domain.trim().toLowerCase();
      if (d.isEmpty || !seen.add(d)) {
        continue;
      }
      ordered.add(d);
    }
    ordered.sort((a, b) {
      final ra = rank[a] ?? 50;
      final rb = rank[b] ?? 50;
      if (ra != rb) {
        return ra.compareTo(rb);
      }
      return a.compareTo(b);
    });
    return ordered;
  }

  List<Uri> _buildPkeyFallbackUris(Uri uri, StripchatMouflonKeyCache cache) {
    final currentPkey = uri.queryParameters['pkey']?.trim() ?? '';
    final effectiveCache = cache.withTrustedFallbacks();
    final result = <Uri>[];
    final seen = <String>{currentPkey};
    for (final record in effectiveCache.records) {
      if (seen.contains(record.pkey)) continue;
      if (_shouldIgnorePdkeyRecord(record)) continue;
      seen.add(record.pkey);
      final queryParams = Map<String, String>.from(uri.queryParameters);
      queryParams['pkey'] = record.pkey;
      queryParams.remove('psch');
      queryParams['psch'] = 'v2';
      result.add(uri.replace(queryParameters: queryParams));
    }
    return result;
  }

  @visibleForTesting
  static UnmodifiableListView<Uri> buildStripchatSiblingPlaylistFallbackUris({
    required Uri uri,
    Iterable<Uri> attemptedUris = const <Uri>[],
  }) {
    final filename = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
    final streamNameMatch = RegExp(
      r'^(\d+)(?:_([A-Za-z0-9]+))?\.m3u8$',
      caseSensitive: false,
    ).firstMatch(filename);
    if (streamNameMatch == null) {
      return UnmodifiableListView<Uri>(const <Uri>[]);
    }
    final streamName = streamNameMatch.group(1) ?? '';
    if (streamName.isEmpty) {
      return UnmodifiableListView<Uri>(const <Uri>[]);
    }
    final currentQuality = streamNameMatch.group(2)?.toLowerCase() ?? '';
    final candidates = <String>[
      '',
      'source',
      '1080p60',
      '1080p',
      '720p60',
      '720p',
      '480p',
      '240p',
      '160p',
    ];
    final attempted = <String>{
      uri.toString(),
      ...attemptedUris.map((item) => item.toString()),
    };
    final fallbacks = <Uri>[];
    for (final quality in candidates) {
      if (quality == currentQuality ||
          (quality == 'source' && currentQuality.isEmpty) ||
          (quality.isEmpty && currentQuality.isEmpty)) {
        continue;
      }
      final siblingFilename = quality.isEmpty || quality == 'source'
          ? '$streamName.m3u8'
          : '${streamName}_$quality.m3u8';
      final sibling = uri.replace(
        pathSegments: <String>[
          ...uri.pathSegments.take(uri.pathSegments.length - 1),
          siblingFilename,
        ],
      );
      if (!attempted.add(sibling.toString())) {
        continue;
      }
      fallbacks.add(sibling);
    }
    return UnmodifiableListView<Uri>(fallbacks);
  }

  bool _hasUriAttributeTag(String line) {
    final upper = line.toUpperCase();
    return upper.startsWith('#EXT-X-MEDIA:') ||
        upper.startsWith('#EXT-X-I-FRAME-STREAM-INF:') ||
        upper.startsWith('#EXT-X-MAP:') ||
        upper.startsWith('#EXT-X-KEY:');
  }

  bool _shouldDropLlHlsTag(String line) {
    final upper = line.toUpperCase();
    return upper.startsWith('#EXT-X-PART-INF:') ||
        upper.startsWith('#EXT-X-PART:') ||
        upper.startsWith('#EXT-X-PRELOAD-HINT:') ||
        upper.startsWith('#EXT-X-RENDITION-REPORT:');
  }

  String _rewriteUriAttributes({
    required String line,
    required _StripchatLlHlsSession session,
    required Uri playlistUri,
    required _StripchatPlaylistAuth? auth,
    required _StripchatResolvedAssetTargets? pendingMouflonTargets,
    required List<String> assetIds,
  }) {
    return line.replaceAllMapped(RegExp(_hlsUriAttributePattern), (match) {
      final raw = match.group(2) ?? match.group(3) ?? '';
      if (raw.isEmpty && pendingMouflonTargets == null) {
        return match.group(0) ?? '';
      }
      final target =
          pendingMouflonTargets?.primary ??
          _resolvePlaylistTarget(
            playlistUri: playlistUri,
            rawValue: raw,
            auth: auth,
          );
      final local = _localProxyUri(
        session,
        target,
        segmentKey: pendingMouflonTargets?.segmentKey,
        assetIds: assetIds,
        fallbackTargets: pendingMouflonTargets?.fallback,
      ).toString();
      if (match.group(2) != null) {
        return 'URI="${_escapeHlsQuotedString(local)}"';
      }
      return 'URI=$local';
    });
  }

  Uri _resolvePlaylistTarget({
    required Uri playlistUri,
    required String? rawValue,
    required _StripchatPlaylistAuth? auth,
  }) {
    return _resolveStripchatTarget(
      playlistUri: playlistUri,
      rawValue: rawValue,
      auth: auth,
    );
  }

  Uri _localProxyUri(
    _StripchatLlHlsSession session,
    Uri target, {
    String? segmentKey,
    List<String>? assetIds,
    List<Uri>? fallbackTargets,
  }) {
    if (target.path.toLowerCase().endsWith('.m3u8')) {
      return _sessionPlaylistUri(session.id, upstreamUri: target);
    }
    final assetUris = fallbackTargets == null || fallbackTargets.isEmpty
        ? <Uri>[target]
        : <Uri>[...fallbackTargets];
    final assetId = session.rememberAssetUris(
      assetUris,
      segmentKey: segmentKey,
    );
    assetIds?.add(assetId);
    return _localAssetUri(session, assetId);
  }

  Map<String, String> _buildUpstreamHeaders(Map<String, String> headers) {
    const allowedHeaders = <String>{
      HttpHeaders.userAgentHeader,
      HttpHeaders.refererHeader,
      HttpHeaders.acceptHeader,
      HttpHeaders.acceptLanguageHeader,
      HttpHeaders.acceptEncodingHeader,
      'origin',
      'sec-ch-ua',
      'sec-ch-ua-mobile',
      'sec-ch-ua-platform',
    };
    final sanitized = <String, String>{};
    headers.forEach((key, value) {
      final normalizedKey = key.trim().toLowerCase();
      if (!allowedHeaders.contains(normalizedKey)) {
        return;
      }
      final trimmedValue = value.trim();
      if (trimmedValue.isEmpty) {
        return;
      }
      sanitized[normalizedKey] = trimmedValue;
    });
    return sanitized;
  }

  Uri _resolvePlaylistUpstreamUri({
    required _StripchatLlHlsSession session,
    required Uri requestUri,
  }) {
    final rawUpstream =
        requestUri.queryParameters[_stripchatUpstreamQueryParam];
    final parsedUpstream = rawUpstream == null || rawUpstream.trim().isEmpty
        ? null
        : Uri.tryParse(rawUpstream);
    // Fixed quality: after collapse, refresh the pinned media child.
    // Auto: never force pinned child — master refreshes and ABR use upstream=
    // on rewritten STREAM-INF URLs (parsedUpstream).
    final base =
        parsedUpstream ??
        (session.pinSingleRendition ? session.pinnedMediaPlaylistUri : null) ??
        session.playlistUri ??
        session.upstreamUri;
    final merged = <String, String>{...base.queryParameters};
    requestUri.queryParameters.forEach((key, value) {
      if (key == _stripchatUpstreamQueryParam || value.trim().isEmpty) {
        return;
      }
      merged[key] = value;
    });
    return base.replace(queryParameters: merged.isEmpty ? null : merged);
  }

  void _purgeExpiredSessions() {
    if (_sessions.isEmpty) {
      return;
    }
    final now = DateTime.now();
    final expired = _sessions.entries
        .where(
          (entry) => now.difference(entry.value.lastAccessedAt) > _sessionTtl,
        )
        .map((entry) => entry.key)
        .toList(growable: false);
    for (final key in expired) {
      final session = _sessions.remove(key);
      if (session == null) {
        continue;
      }
      unawaited(session.dispose());
    }
  }

  Uri _sessionPlaylistUri(String sessionId, {Uri? upstreamUri}) {
    final endpoint = _endpoint;
    if (endpoint == null) {
      throw StateError('Stripchat LL-HLS proxy endpoint unavailable.');
    }
    return endpoint.replace(
      pathSegments: <String>[routePrefix, sessionId, 'playlist.m3u8'],
      queryParameters: upstreamUri == null
          ? null
          : <String, String>{
              _stripchatUpstreamQueryParam: upstreamUri.toString(),
            },
    );
  }

  String _randomId([int length = 20]) {
    const alphabet =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random.secure();
    return List<String>.generate(
      length,
      (_) => alphabet[random.nextInt(alphabet.length)],
    ).join();
  }

  bool get _supportsPlatform {
    final override = _enabledOverride;
    if (override != null) {
      return override;
    }
    // Same gate as Chaturbate/Twitch: enable wherever headless WebView is
    // available. Android isMobile==true implies this; Linux desktop must not
    // fall back to raw edge-hls (mouflon-encrypted / CPA ad path).
    return _platformAdapter.supportsHeadlessWebView;
  }

  /// Logs proxy diagnostics. Segment-level pdkey/mouflon chatter is [verbose]
  /// and only emitted when [HlsProxyPlatformAdapter.kDebugMode] is true so
  /// release captures are not flooded (session-2026-07-21: 4.5k INFO lines).
  void _trace(String message, {bool verbose = false}) {
    if (!shouldEmitStripchatProxyLog(
      verbose: verbose,
      kDebugMode: _platformAdapter.kDebugMode,
    )) {
      return;
    }
    final redacted = message.replaceAllMapped(
      RegExp(r'(pkeys?|psch)=([a-zA-Z0-9_-]+)'),
      (match) {
        final key = match.group(1);
        final val = match.group(2) ?? '';
        if (val.length <= 4) {
          return '$key=***';
        }
        return '$key=${val.substring(0, 4)}***';
      },
    );
    _platformAdapter.log('stripchat/proxy', redacted);
  }

  @visibleForTesting
  StripchatLlHlsProxyTestSession createSessionForTest(
    LivePlayUrl playUrl, {
    required StripchatMouflonKeyCache keyCache,
  }) {
    _endpoint ??= Uri.parse('http://127.0.0.1:0');
    return StripchatLlHlsProxyTestSession(
      _createSession(playUrl, roomId: 'test_room', keyCache: keyCache),
    );
  }

  @visibleForTesting
  Future<StripchatLlHlsProxyFetchedPlaylist> fetchPlaylistWithFallbacksForTest({
    required StripchatLlHlsProxyTestSession session,
    required Uri uri,
    required Map<String, String> headers,
    List<Uri>? fallbackUrisOverride,
  }) async {
    final fetched = await _fetchPlaylistWithFallbacks(
      session: session._session,
      uri: uri,
      headers: headers,
      fallbackUrisOverride: fallbackUrisOverride,
    );
    return StripchatLlHlsProxyFetchedPlaylist(
      statusCode: fetched.statusCode,
      body: fetched.body,
      finalUri: fetched.finalUri,
    );
  }
}

@visibleForTesting
class StripchatLlHlsProxyTestSession {
  // ignore: library_private_types_in_public_api
  const StripchatLlHlsProxyTestSession(this._session);

  // ignore: library_private_types_in_public_api
  final _StripchatLlHlsSession _session;
}

@visibleForTesting
class StripchatLlHlsProxyFetchedPlaylist {
  const StripchatLlHlsProxyFetchedPlaylist({
    required this.statusCode,
    required this.body,
    required this.finalUri,
  });

  final int statusCode;
  final String body;
  final Uri finalUri;
}

class _StripchatLlHlsSession {
  _StripchatLlHlsSession({
    required this.roomId,
    required this.id,
    required this.upstreamUri,
    required this.headers,
    required this.createdAt,
    required this.lastAccessedAt,
    required this.localBaseUri,
    required this.keyCache,
    required this.roomUrl,
    required this.aesWorker,
    required this.delivery,
    this.preferredVariantId = '',
    this.pinSingleRendition = false,
    this.masterPlaylistUri,
    this.playlistCdnDomains = const <String>[],
  });

  final String roomId;
  final String id;
  final Uri upstreamUri;
  final Map<String, String> headers;
  final DateTime createdAt;
  DateTime lastAccessedAt;
  final Uri localBaseUri;
  final StripchatMouflonKeyCache keyCache;
  final String roomUrl;
  final String preferredVariantId;
  /// Fixed quality only: collapse master → preferred media playlist.
  /// Auto keeps multi-variant master for platform ABR.
  final bool pinSingleRendition;
  /// Edge master for pin recovery when probed media child is 404.
  final Uri? masterPlaylistUri;
  final HlsAesWorkerSession aesWorker;
  final List<String> playlistCdnDomains;
  /// Platform delivery knobs (mobile thin vs desktop thick); not quality policy.
  final HlsProxyDeliveryKnobs delivery;
  Uri? playlistUri;
  Uri? pinnedMediaPlaylistUri;
  String? lastSuccessfulPlaylist;
  DateTime? lastSuccessfulPlaylistAt;
  /// host+path of the media playlist lastSuccessful applies to (ABR-safe).
  String? lastStickyMediaKey;
  List<String> lastAssetIds = const <String>[];
  /// Full rewritten window (including unpublished live edge) for neighbor warm.
  List<String> lastRawAssetIds = const <String>[];
  /// EXTINF media segments in [lastSuccessfulPlaylist] (not MAP).
  int lastMediaSegmentCount = 0;
  /// Per media-path sticky slots for Auto ABR (1080/720/480/source independently).
  final Map<String, _StripchatMediaStickySlot> mediaStickyByKey =
      <String, _StripchatMediaStickySlot>{};
  /// Coalesce concurrent materialize for the same master/media path.
  final Map<String, Future<_StripchatRewrittenPlaylist?>>
  materializeInFlightByKey =
      <String, Future<_StripchatRewrittenPlaylist?>>{};
  /// Per-path background refresh (ABR can refresh 1080 while serving 240 sticky).
  final Map<String, Future<_StripchatRewrittenPlaylist?>> refreshInFlightByKey =
      <String, Future<_StripchatRewrittenPlaylist?>>{};
  /// Single Auto top-N prewarm wave per session.
  Future<void>? autoPrewarmInFlight;
  bool? shouldDropMap;
  /// After the first edge-warm gate, playlist refreshes must stay non-blocking.
  bool initialEdgeWarmCompleted = false;
  Future<void>? startupPrimeInFlight;
  Timer? playlistPumpTimer;
  /// Last pump period so high-tier can restart at a faster cadence.
  Duration? playlistPumpInterval;

  void putMediaSticky({
    required String mediaKey,
    required String manifest,
    required List<String> assetIds,
    required List<String> rawAssetIds,
    required int mediaSegmentCount,
    required Uri playlistUri,
    required bool contentChanged,
  }) {
    final previous = mediaStickyByKey[mediaKey];
    final now = DateTime.now();
    mediaStickyByKey[mediaKey] = _StripchatMediaStickySlot(
      mediaKey: mediaKey,
      manifest: manifest,
      assetIds: List<String>.unmodifiable(assetIds),
      rawAssetIds: List<String>.unmodifiable(rawAssetIds),
      mediaSegmentCount: mediaSegmentCount,
      playlistUri: playlistUri,
      updatedAt: contentChanged || previous == null ? now : previous.updatedAt,
    );
    // Touch order for LRU: re-insert by remove+add via LinkedHashMap semantics.
    // Map in Dart preserves insertion order; re-put moves to end if we remove first.
    final slot = mediaStickyByKey.remove(mediaKey)!;
    mediaStickyByKey[mediaKey] = slot;
    while (mediaStickyByKey.length > delivery.scMediaStickySlotLimit) {
      mediaStickyByKey.remove(mediaStickyByKey.keys.first);
    }
    activateMediaSticky(mediaKey);
  }

  void activateMediaSticky(String mediaKey) {
    final slot = mediaStickyByKey[mediaKey];
    if (slot == null) {
      return;
    }
    lastStickyMediaKey = mediaKey;
    lastSuccessfulPlaylist = slot.manifest;
    lastSuccessfulPlaylistAt = slot.updatedAt;
    lastAssetIds = slot.assetIds;
    lastRawAssetIds = slot.rawAssetIds;
    lastMediaSegmentCount = slot.mediaSegmentCount;
    pinnedMediaPlaylistUri = slot.playlistUri;
    playlistUri = slot.playlistUri;
  }

  _StripchatMediaStickySlot? bestMediaSticky() {
    _StripchatMediaStickySlot? best;
    for (final slot in mediaStickyByKey.values) {
      if (slot.manifest.trim().isEmpty) {
        continue;
      }
      if (slot.mediaSegmentCount < delivery.scMinPublishCachedMediaSegments) {
        continue;
      }
      if (best == null || slot.updatedAt.isAfter(best.updatedAt)) {
        best = slot;
      }
    }
    return best;
  }
  final Map<String, _StripchatAssetTargets> _assetTargets =
      <String, _StripchatAssetTargets>{};
  final Map<String, String> _assetIdsByKey = <String, String>{};
  final Map<String, _StripchatCachedAsset> cachedAssets =
      <String, _StripchatCachedAsset>{};
  final Map<String, Future<void>> _pendingWarmAssets = <String, Future<void>>{};
  /// Background warm queue (FIFO). [enqueueWarmAssets] with prioritize:true
  /// inserts at the front so player-requested segments jump the line.
  final Queue<String> _warmQueue = Queue<String>();
  final Set<String> _warmQueued = <String>{};
  int _warmInFlightCount = 0;
  /// Cache successful mouflon path decrypts so playlist rewrites (every 1–2s)
  /// do not re-hit the AES isolate for the same window.
  final Map<String, String> _mouflonDecryptCache = <String, String>{};
  int _pdkeyAllFailedCount = 0;
  bool _disposed = false;

  int get warmInFlightCount => _warmInFlightCount;

  bool isWarmInFlight(String assetId) => _pendingWarmAssets.containsKey(assetId);

  void removeFromWarmQueue(String assetId) {
    if (_warmQueued.remove(assetId)) {
      _warmQueue.remove(assetId);
    }
  }

  String rememberAssetUris(List<Uri> uris, {String? segmentKey}) {
    final normalizedUris = uris
        .map((uri) => uri.toString().trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    final key = normalizedUris.join('\n');
    final existing = _assetIdsByKey[key];
    if (existing != null) {
      return existing;
    }
    final assetId = sha1.convert(utf8.encode(key)).toString();
    _assetIdsByKey[key] = assetId;
    _assetTargets[assetId] = _StripchatAssetTargets(
      uris: List<Uri>.unmodifiable(normalizedUris.map(Uri.parse)),
      segmentKey: segmentKey ?? '',
    );
    return assetId;
  }

  _StripchatAssetTargets? resolveAssetTarget(String assetId) {
    return _assetTargets[assetId];
  }

  void noteBridgeMiss() {
    // sticky downgrade is represented by asset requests falling back to pdkey
    // after bridge lookup miss; no additional session state is currently needed.
  }

  void noteBridgeResolved() {
    // bridge lookups are stateless for now; kept for future diagnostics symmetry.
  }

  void notePdkeyAllFailed() {
    _pdkeyAllFailedCount += 1;
  }

  bool get pdkeyHealthAlert =>
      _pdkeyAllFailedCount > 0 &&
      _pdkeyAllFailedCount >= (_assetTargets.length ~/ 2);

  Future<String?> decryptMouflonSegment(String encryptedSegment, String pdkey) {
    if (_disposed) {
      throw StateError('Stripchat LL-HLS session is disposed.');
    }
    final cacheKey = '$encryptedSegment|$pdkey';
    final cached = _mouflonDecryptCache[cacheKey];
    if (cached != null) {
      return Future<String?>.value(cached);
    }
    return aesWorker
        .decryptStripchatMouflonSegment(
          encryptedSegment: encryptedSegment,
          pdkey: pdkey,
        )
        .then((result) {
          final normalized = result?.trim() ?? '';
          if (normalized.isEmpty) {
            return result;
          }
          _mouflonDecryptCache[cacheKey] = normalized;
          while (_mouflonDecryptCache.length >
              _stripchatMouflonDecryptCacheLimit) {
            _mouflonDecryptCache.remove(_mouflonDecryptCache.keys.first);
          }
          return normalized;
        });
  }

  void touchCachedAsset(String assetId) {
    final asset = cachedAssets.remove(assetId);
    if (asset == null) {
      return;
    }
    cachedAssets[assetId] = asset;
    while (cachedAssets.length > delivery.scCachedAssetLimit) {
      final oldestKey = cachedAssets.keys.first;
      cachedAssets.remove(oldestKey);
    }
  }

  void enqueueWarmAssets(
    Iterable<String> assetIds, {
    required bool prioritize,
  }) {
    if (_disposed) {
      return;
    }
    for (final assetId in assetIds) {
      if (assetId.isEmpty) {
        continue;
      }
      if (cachedAssets.containsKey(assetId) ||
          _pendingWarmAssets.containsKey(assetId)) {
        continue;
      }
      if (_warmQueued.contains(assetId)) {
        if (!prioritize) {
          continue;
        }
        // Re-queue at front for player-requested urgency.
        _warmQueue.remove(assetId);
        _warmQueue.addFirst(assetId);
        continue;
      }
      if (prioritize) {
        _warmQueue.addFirst(assetId);
      } else {
        _warmQueue.addLast(assetId);
      }
      _warmQueued.add(assetId);
    }
  }

  String? takeNextWarmAssetId() {
    while (_warmQueue.isNotEmpty) {
      final assetId = _warmQueue.removeFirst();
      _warmQueued.remove(assetId);
      if (cachedAssets.containsKey(assetId) ||
          _pendingWarmAssets.containsKey(assetId)) {
        continue;
      }
      return assetId;
    }
    return null;
  }

  void noteWarmStarted(String assetId, Future<void> future) {
    _pendingWarmAssets[assetId] = future;
    _warmInFlightCount += 1;
  }

  void noteWarmFinished(String assetId) {
    _pendingWarmAssets.remove(assetId);
    if (_warmInFlightCount > 0) {
      _warmInFlightCount -= 1;
    }
  }

  Future<_StripchatCachedAsset?> waitForWarmAsset(
    String assetId, {
    Duration? timeout,
  }) async {
    final cached = cachedAssets[assetId];
    if (cached != null) {
      return cached;
    }
    final pending = _pendingWarmAssets[assetId];
    if (pending == null) {
      return null;
    }
    try {
      // Bound wait so a slow CDN prefetch cannot stall mpv forever.
      await pending.timeout(timeout ?? delivery.scWarmWaitTimeout);
    } catch (_) {
      // Fall through: caller will fetch on demand.
    }
    return cachedAssets[assetId];
  }

  Future<void> dispose() async {
    _disposed = true;
    startupPrimeInFlight = null;
    playlistPumpTimer?.cancel();
    playlistPumpTimer = null;
    playlistPumpInterval = null;
    autoPrewarmInFlight = null;
    materializeInFlightByKey.clear();
    refreshInFlightByKey.clear();
    mediaStickyByKey.clear();
    shouldDropMap = null;
    _warmQueue.clear();
    _warmQueued.clear();
    final pending = _pendingWarmAssets.values.toList(growable: false);
    if (pending.isNotEmpty) {
      try {
        await Future.wait(pending).timeout(const Duration(milliseconds: 500));
      } catch (_) {}
    }
    _pendingWarmAssets.clear();
    _warmInFlightCount = 0;
    cachedAssets.clear();
    _mouflonDecryptCache.clear();
    lastSuccessfulPlaylist = null;
    lastSuccessfulPlaylistAt = null;
    lastStickyMediaKey = null;
    lastAssetIds = const <String>[];
    lastRawAssetIds = const <String>[];
    lastMediaSegmentCount = 0;
    await aesWorker.dispose();
  }
}

/// Per media-path sticky playlist for Auto ABR (one slot per host+path).
class _StripchatMediaStickySlot {
  const _StripchatMediaStickySlot({
    required this.mediaKey,
    required this.manifest,
    required this.assetIds,
    required this.rawAssetIds,
    required this.mediaSegmentCount,
    required this.playlistUri,
    required this.updatedAt,
  });

  final String mediaKey;
  final String manifest;
  final List<String> assetIds;
  final List<String> rawAssetIds;
  final int mediaSegmentCount;
  final Uri playlistUri;
  final DateTime updatedAt;
}

/// Bitrate class for delivery thickness only (not platform ABR).
enum _StripchatTierClass { high, mid, low }

class _StripchatPublishPolicy {
  const _StripchatPublishPolicy({
    required this.tier,
    required this.minMedia,
    required this.preferMedia,
    required this.maxHistoryExtras,
    required this.firstWait,
    required this.backgroundWait,
    required this.retryWait,
    required this.stickyMaxAge,
    required this.backgroundMinInterval,
    required this.pumpInterval,
  });

  final _StripchatTierClass tier;
  final int minMedia;
  /// History thicken target (high=6 so multi-window runway).
  final int preferMedia;
  final int maxHistoryExtras;
  final Duration firstWait;
  final Duration backgroundWait;
  final Duration retryWait;
  final Duration stickyMaxAge;
  final Duration backgroundMinInterval;
  final Duration pumpInterval;
}

class _StripchatCachedAsset {
  const _StripchatCachedAsset({
    required this.bytes,
    required this.contentType,
    required this.sourceUrl,
  });

  final Uint8List bytes;
  final ContentType? contentType;
  final String sourceUrl;
}

class _StripchatAssetTargets {
  const _StripchatAssetTargets({required this.uris, this.segmentKey = ''});

  final List<Uri> uris;
  final String segmentKey;
}

class _FetchedPlaylist {
  const _FetchedPlaylist({
    required this.statusCode,
    required this.body,
    required this.finalUri,
  });

  final int statusCode;
  final String body;
  final Uri finalUri;
}

class _OpenedAssetResponse {
  const _OpenedAssetResponse({required this.uri, required this.response});

  final Uri uri;
  final HttpClientResponse response;
}

class _StripchatRewrittenPlaylist {
  const _StripchatRewrittenPlaylist({
    required this.manifest,
    this.assetIds = const <String>[],
    this.mediaSegmentCount = 0,
  });

  final String manifest;
  final List<String> assetIds;
  /// Count of EXTINF media segments when known (0 = unspecified/full rewrite).
  final int mediaSegmentCount;
}

class _StripchatFilteredPlaylist {
  const _StripchatFilteredPlaylist({
    required this.manifest,
    required this.assetIds,
    required this.mediaSegmentCount,
  });

  final String manifest;
  final List<String> assetIds;
  final int mediaSegmentCount;
}

class _StripchatMediaPair {
  const _StripchatMediaPair({
    required this.extinfLine,
    required this.uriLine,
    required this.assetId,
  });

  final String extinfLine;
  final String uriLine;
  final String assetId;
}

class _StripchatResolvedAssetTargets {
  const _StripchatResolvedAssetTargets({
    required this.primary,
    this.segmentKey = '',
    this.fallback = const <Uri>[],
  });

  final Uri primary;
  final String segmentKey;
  final List<Uri> fallback;
}

class _StripchatManifestFailure {
  const _StripchatManifestFailure({required this.code, required this.detail});

  final String code;
  final String detail;

  String get responseBody => 'stripchat proxy failure: $code ($detail)';
}

class _StripchatPlaylistAuth {
  const _StripchatPlaylistAuth({required this.scheme, required this.pkey});

  final String scheme;
  final String pkey;
}

_StripchatPlaylistAuth? _parseMouflonAuth(String line) {
  final match = RegExp(
    r'^#EXT-X-MOUFLON:PSCH:([^:]+):(.+)$',
  ).firstMatch(line.trim());
  if (match == null) {
    return null;
  }
  final scheme = match.group(1)?.trim() ?? '';
  final pkey = match.group(2)?.trim() ?? '';
  if (scheme.isEmpty || pkey.isEmpty) {
    return null;
  }
  return _StripchatPlaylistAuth(scheme: scheme, pkey: pkey);
}

Uri _appendPlaylistAuth(Uri uri, _StripchatPlaylistAuth? auth) {
  if (auth == null) {
    return uri;
  }
  final queryParameters = Map<String, String>.from(uri.queryParameters);
  queryParameters.putIfAbsent('psch', () => auth.scheme);
  queryParameters.putIfAbsent('pkey', () => auth.pkey);
  return uri.replace(queryParameters: queryParameters);
}

Uri _resolveStripchatTarget({
  required Uri playlistUri,
  required String? rawValue,
  required _StripchatPlaylistAuth? auth,
}) {
  final resolved = playlistUri.resolve((rawValue ?? '').trim());
  if (resolved.path.toLowerCase().endsWith('.m3u8')) {
    return _appendPlaylistAuth(resolved, auth);
  }
  return resolved;
}

Future<_StripchatResolvedAssetTargets> _resolveMouflonAssetTargets({
  required String rawUri,
  required Uri playlistUri,
  required _StripchatPlaylistAuth? auth,
  required bool enablePdkeyFallback,
  required List<String> candidatePkeys,
  required StripchatMouflonKeyCache keyCache,
  required _StripchatMouflonDecryptor decryptMouflonSegment,
  void Function(String phase, {required String pkey, required String source})?
  tracePdkey,
  void Function(String message)? traceDecision,
  void Function()? onPdkeyAllFailed,
  bool kDebugMode = false,
  void Function(String)? debugPrint,
}) async {
  final direct = _resolveStripchatTarget(
    playlistUri: playlistUri,
    rawValue: rawUri,
    auth: auth,
  );
  final segmentInfo = stripchat_runtime.stripchatParseMouflonSegmentInfo(
    direct.path,
  );
  if (!enablePdkeyFallback) {
    traceDecision?.call(
      'mouflon bridge-primary segment=${segmentInfo?.key ?? '-'} fallback=disabled',
    );
    return _StripchatResolvedAssetTargets(
      primary: direct,
      segmentKey: segmentInfo?.key ?? '',
    );
  }
  final decoded = await _decodeMouflonUri(
    rawUri,
    candidatePkeys: candidatePkeys,
    keyCache: keyCache,
    decryptMouflonSegment: decryptMouflonSegment,
    tracePdkey: tracePdkey,
    kDebugMode: kDebugMode,
    debugPrint: debugPrint,
  );
  if (decoded.uri == null || decoded.uri!.trim().isEmpty) {
    if (decoded.failure != null) {
      onPdkeyAllFailed?.call();
    }
    traceDecision?.call(
      'mouflon bridge-primary segment=${segmentInfo?.key ?? '-'} fallback=unavailable',
    );
    return _StripchatResolvedAssetTargets(
      primary: direct,
      segmentKey: segmentInfo?.key ?? '',
    );
  }
  final decodedTarget = _resolveStripchatTarget(
    playlistUri: playlistUri,
    rawValue: decoded.uri,
    auth: auth,
  );
  traceDecision?.call(
    'mouflon bridge-primary segment=${segmentInfo?.key ?? '-'} fallback=$decodedTarget',
  );
  return _StripchatResolvedAssetTargets(
    primary: direct,
    segmentKey: segmentInfo?.key ?? '',
    fallback: <Uri>[decodedTarget],
  );
}

List<String> _orderedMouflonPkeys({
  required String? currentPkey,
  required String? upstreamPkey,
  required List<String> seenPkeys,
  required StripchatMouflonKeyCache keyCache,
}) {
  final effectiveKeyCache = keyCache.withTrustedFallbacks();
  final ordered = <String>[];

  void add(String? value) {
    final normalized = value?.trim() ?? '';
    if (normalized.isEmpty || ordered.contains(normalized)) {
      return;
    }
    ordered.add(normalized);
  }

  add(currentPkey);
  add(upstreamPkey);
  for (final seenPkey in seenPkeys) {
    add(seenPkey);
  }
  for (final record in effectiveKeyCache.records) {
    add(record.pkey);
  }

  final cached = <String>[];
  final uncached = <String>[];
  for (final candidate in ordered) {
    final record = effectiveKeyCache.lookup(candidate);
    if (record != null && !_shouldIgnorePdkeyRecord(record)) {
      cached.add(candidate);
    } else {
      uncached.add(candidate);
    }
  }
  return <String>[...cached, ...uncached];
}

Future<_DecodedMouflonUri> _decodeMouflonUri(
  String rawUri, {
  required List<String> candidatePkeys,
  required StripchatMouflonKeyCache keyCache,
  required _StripchatMouflonDecryptor decryptMouflonSegment,
  void Function(String phase, {required String pkey, required String source})?
  tracePdkey,
  bool kDebugMode = false,
  void Function(String)? debugPrint,
}) async {
  final effectiveKeyCache = keyCache.withTrustedFallbacks();
  final trimmed = rawUri.trim();
  if (trimmed.isEmpty) {
    return const _DecodedMouflonUri(uri: '');
  }
  final encryptedMatch = _matchMouflonUri(trimmed);
  if (encryptedMatch == null) {
    return _DecodedMouflonUri(uri: trimmed);
  }
  if (kDebugMode && debugPrint != null) {
    debugPrint('[pdkey-seg] rawUri=$trimmed');
    debugPrint(
      '[pdkey-seg] encryptedSegment=${encryptedMatch.encryptedSegment}',
    );
  }
  final normalizedPkeys = <String>[];
  for (final candidatePkey in candidatePkeys) {
    final normalized = candidatePkey.trim();
    if (normalized.isEmpty || normalizedPkeys.contains(normalized)) {
      continue;
    }
    normalizedPkeys.add(normalized);
  }
  if (normalizedPkeys.isEmpty) {
    return const _DecodedMouflonUri(
      failure: _StripchatManifestFailure(
        code: 'missing-pdkey',
        detail: 'playlist did not expose pkey',
      ),
    );
  }
  final encryptedSegment = encryptedMatch.encryptedSegment;
  final missingPkeys = <String>[];
  final failedPkeys = <String>[];

  Future<String?> tryDecrypt(String pkey, String pdkey) async {
    final result = await decryptMouflonSegment(encryptedSegment, pdkey);
    if (result != null && result.trim().isNotEmpty) {
      return result;
    }
    return null;
  }

  for (final normalizedPkey in normalizedPkeys) {
    final record = effectiveKeyCache.lookup(normalizedPkey);
    if (record != null && !_shouldIgnorePdkeyRecord(record)) {
      final source = record.captureSource.isEmpty
          ? record.source.name
          : record.captureSource;
      tracePdkey?.call('candidate', pkey: normalizedPkey, source: source);
      final decryptedSegment = await tryDecrypt(normalizedPkey, record.pdkey);
      if (decryptedSegment != null) {
        tracePdkey?.call('resolved', pkey: normalizedPkey, source: source);
        return _DecodedMouflonUri(
          uri: encryptedMatch.rebuild(decryptedSegment),
        );
      }
      tracePdkey?.call('decrypt-failed', pkey: normalizedPkey, source: source);
      failedPkeys.add(normalizedPkey);
    }
    final hardcodedPdkey = lookupStripchatHardcodedPdkey(normalizedPkey);
    if (hardcodedPdkey != null &&
        (record == null || hardcodedPdkey != record.pdkey)) {
      tracePdkey?.call(
        'candidate',
        pkey: normalizedPkey,
        source: 'hardcoded-fallback',
      );
      final decryptedSegment = await tryDecrypt(normalizedPkey, hardcodedPdkey);
      if (decryptedSegment != null) {
        tracePdkey?.call(
          'resolved',
          pkey: normalizedPkey,
          source: 'hardcoded-fallback',
        );
        return _DecodedMouflonUri(
          uri: encryptedMatch.rebuild(decryptedSegment),
        );
      }
      if (!failedPkeys.contains(normalizedPkey)) {
        failedPkeys.add(normalizedPkey);
      }
    }
    if (record == null && hardcodedPdkey == null) {
      missingPkeys.add(normalizedPkey);
    }
  }

  if (failedPkeys.isNotEmpty) {
    return _DecodedMouflonUri(
      failure: _StripchatManifestFailure(
        code: 'decrypt-failed',
        detail: 'pkeys=${failedPkeys.join(",")}',
      ),
    );
  }
  return _DecodedMouflonUri(
    failure: _StripchatManifestFailure(
      code: 'missing-pdkey',
      detail: 'missing key for pkeys=${missingPkeys.join(",")}',
    ),
  );
}

bool _shouldIgnorePdkeyRecord(StripchatMouflonKeyRecord record) {
  return record.captureSource.trim().toLowerCase() == 'hash-cache-key:init-map';
}

_MatchedMouflonUri? _matchMouflonUri(String value) {
  final matched = stripchat_runtime.stripchatMatchMouflonUri(value);
  if (matched == null) {
    return null;
  }
  return _MatchedMouflonUri(
    prefix: matched.prefix,
    encryptedSegment: matched.encryptedSegment,
    suffix: matched.suffix,
  );
}

class _DecodedMouflonUri {
  const _DecodedMouflonUri({this.uri, this.failure});

  final String? uri;
  final _StripchatManifestFailure? failure;
}

class _MatchedMouflonUri {
  const _MatchedMouflonUri({
    required this.prefix,
    required this.encryptedSegment,
    required this.suffix,
  });

  final String prefix;
  final String encryptedSegment;
  final String suffix;

  String rebuild(String decryptedSegment) {
    return '$prefix$decryptedSegment$suffix';
  }
}

const _hlsUriAttributePattern = r'URI=("([^"]*)"|([^,]+))';

Uri _localAssetUri(_StripchatLlHlsSession session, String assetId) {
  return session.localBaseUri.replace(
    pathSegments: <String>[
      StripchatLlHlsProxy.routePrefix,
      session.id,
      'asset',
      assetId,
    ],
  );
}

String _escapeHlsQuotedString(String value) {
  return value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
}
