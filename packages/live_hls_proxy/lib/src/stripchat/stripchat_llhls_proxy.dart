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
import '../hls_proxy_platform_adapter.dart';
import 'stripchat_mouflon_key_cache.dart';
import 'stripchat_mouflon_runtime_support.dart' as stripchat_runtime;

const _stripchatCachedAssetLimit = 160;
const _stripchatWarmAssetPrefetchLimit = 3;
const _stripchatUpstreamQueryParam = 'upstream';
const _stripchatBridgeWarmUpfrontWait = Duration(milliseconds: 1500);
const _stripchatBridgeLookupTimeout = Duration(seconds: 4);
const _stripchatBridgeLookupPollInterval = Duration(milliseconds: 150);
const List<String> _stripchatKnownCdnDomains = <String>[
  'doppiocdn.com',
  'doppiocdn.org',
  'doppiocdn.net',
  'doppiocdn.media',
];

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
  }) : _platformAdapter = platformAdapter,
       _client = client ?? HttpClient(),
       _sessionTtl = sessionTtl,
       _enabledOverride = enabledOverride,
       _enablePdkeyFallback = enablePdkeyFallback,
       _enablePriming = enablePriming,
       _pdkeyResolver = pdkeyResolver,
       _decodedUrlResolver = decodedUrlResolver,
       _warmDecodedUrlBridge = warmDecodedUrlBridge {
    _client.connectionTimeout = const Duration(seconds: 15);
    _client.idleTimeout = const Duration(seconds: 15);
    _client.maxConnectionsPerHost = 24;
  }

  static const String routePrefix = 'stripchat-llhls';

  final HlsProxyPlatformAdapter _platformAdapter;
  final HttpClient _client;
  final Duration _sessionTtl;
  final bool? _enabledOverride;
  final bool _enablePdkeyFallback;
  final bool _enablePriming;

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
    _disposed = true;
    final sessions = _sessions.values.toList(growable: false);
    _sessions.clear();
    final server = _server;
    _server = null;
    _endpoint = null;
    final serverLoop = _serverLoop;
    _serverLoop = null;
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
      'upstreamUrl': playUrl.url,
      'pdkeyHealthAlertChecker': () => session.pdkeyHealthAlert,
    };
  }

  _StripchatLlHlsSession _createSession(
    LivePlayUrl playUrl, {
    required String roomId,
    required StripchatMouflonKeyCache keyCache,
  }) {
    final endpoint = _endpoint;
    if (endpoint == null) {
      throw StateError('Stripchat LL-HLS proxy endpoint unavailable.');
    }
    final sessionId = _randomId();
    return _StripchatLlHlsSession(
      roomId: roomId,
      id: sessionId,
      upstreamUri: Uri.parse(playUrl.url),
      headers: Map<String, String>.from(playUrl.headers),
      createdAt: DateTime.now(),
      lastAccessedAt: DateTime.now(),
      localBaseUri: endpoint,
      keyCache: keyCache,
      roomUrl: playUrl.metadata?['stripchatRoomUrl']?.toString().trim() ?? '',
      aesWorker: HlsAesWorkerSession(debugLabel: 'stripchat:$sessionId'),
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
    if (_server != null && _endpoint != null) {
      return;
    }
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
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
    final upstreamUri = _resolvePlaylistUpstreamUri(
      session: session,
      requestUri: request.requestedUri,
    );
    _FetchedPlaylist upstream;
    try {
      upstream = await _fetchPlaylistWithFallbacks(
        session: session,
        uri: upstreamUri,
        headers: session.headers,
      );
    } on Object catch (error, stackTrace) {
      if (_disposed || session._disposed) {
        await _sendServiceUnavailable(request);
        return;
      }
      final stalePlaylist = session.lastSuccessfulPlaylist;
      if (stalePlaylist == null) {
        Error.throwWithStackTrace(error, stackTrace);
      }
      _trace(
        'playlist upstream transient failure session=${session.id} '
        'uri=$upstreamUri error=$error stale=true',
      );
      request.response.headers.contentType = ContentType(
        'application',
        'vnd.apple.mpegurl',
        charset: 'utf-8',
      );
      request.response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
      request.response.statusCode = HttpStatus.ok;
      request.response.write(stalePlaylist);
      await request.response.close();
      return;
    }
    if (_disposed || session._disposed) {
      await _sendServiceUnavailable(request);
      return;
    }
    request.response.headers.contentType = ContentType(
      'application',
      'vnd.apple.mpegurl',
      charset: 'utf-8',
    );
    request.response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    if (upstream.statusCode == HttpStatus.forbidden ||
        upstream.statusCode == 418) {
      final pkeyUris = _buildPkeyFallbackUris(upstreamUri, session.keyCache);
      for (final pkeyUri in pkeyUris) {
        if (_disposed || session._disposed) break;
        _FetchedPlaylist alt;
        try {
          alt = await _fetchPlaylistWithFallbacks(
            session: session,
            uri: pkeyUri,
            headers: session.headers,
          );
        } on Object {
          continue;
        }
        if (alt.statusCode == HttpStatus.ok) {
          final altRewritten = await _rewritePlaylist(
            session: session,
            playlistUri: alt.finalUri,
            manifest: alt.body,
          );
          if (_disposed || session._disposed) {
            await _sendServiceUnavailable(request);
            return;
          }
          _trace(
            'playlist pkey fallback session=${session.id} '
            'from=${upstreamUri.queryParameters['pkey']} '
            'to=${pkeyUri.queryParameters['pkey']}',
          );
          session.playlistUri = alt.finalUri;
          session.lastSuccessfulPlaylist = altRewritten.manifest;
          if (session.roomUrl.isNotEmpty) {
            unawaited(_warmDecodedUrlBridge?.call(session.roomUrl));
          }
          session.warmAssets(
            altRewritten.assetIds.take(_stripchatWarmAssetPrefetchLimit),
            _prefetchAsset,
          );
          request.response.statusCode = HttpStatus.ok;
          request.response.write(altRewritten.manifest);
          await request.response.close();
          return;
        }
      }
    }
    if (upstream.statusCode != HttpStatus.ok) {
      _trace(
        'playlist upstream failed session=${session.id} '
        'status=${upstream.statusCode} uri=$upstreamUri',
      );
      request.response.statusCode = upstream.statusCode;
      request.response.write(upstream.body);
      await request.response.close();
      return;
    }
    final rewritten = await _rewritePlaylist(
      session: session,
      playlistUri: upstream.finalUri,
      manifest: upstream.body,
    );
    if (_disposed || session._disposed) {
      await _sendServiceUnavailable(request);
      return;
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
    session.lastSuccessfulPlaylist = rewritten.manifest;
    if (session.roomUrl.isNotEmpty) {
      unawaited(_warmDecodedUrlBridge?.call(session.roomUrl));
    }
    session.warmAssets(
      rewritten.assetIds.take(_stripchatWarmAssetPrefetchLimit),
      _prefetchAsset,
    );
    request.response.statusCode = HttpStatus.ok;
    request.response.write(rewritten.manifest);
    await request.response.close();
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
    final cached = shouldBypassCache ? null : session.cachedAssets[assetId];
    if (cached != null &&
        assetUris.any((uri) => uri.toString() == cached.sourceUrl)) {
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
      final warmed = await session.waitForWarmAsset(assetId);
      if (_disposed || session._disposed) {
        await _sendServiceUnavailable(request);
        return;
      }
      if (warmed != null &&
          assetUris.any((uri) => uri.toString() == warmed.sourceUrl)) {
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
    try {
      final assetTarget = session.resolveAssetTarget(assetId);
      if (assetTarget == null) {
        return;
      }
      final assetUris = assetTarget.uris;
      final existing = session.cachedAssets[assetId];
      if (existing != null &&
          assetUris.any((uri) => uri.toString() == existing.sourceUrl)) {
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
    } catch (error) {
      _trace(
        'asset prefetch failed session=${session.id} asset=$assetId '
        'error=$error',
      );
    }
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
      final upstreamUri = _resolvePlaylistUpstreamUri(
        session: session,
        requestUri: session.upstreamUri,
      );
      final masterFetched = await _fetchPlaylistWithFallbacks(
        session: session,
        uri: upstreamUri,
        headers: session.headers,
      );
      if (session._disposed) return;
      if (masterFetched.statusCode != HttpStatus.ok) {
        return;
      }

      final childUrls = <Uri>[];
      for (final rawLine in const LineSplitter().convert(masterFetched.body)) {
        final line = rawLine.trim();
        if (line.isEmpty || line.startsWith('#')) {
          continue;
        }
        final target = _resolvePlaylistTarget(
          playlistUri: masterFetched.finalUri,
          rawValue: line,
          auth: null,
        );
        if (target.path.toLowerCase().endsWith('.m3u8')) {
          childUrls.add(target);
        }
      }

      final childUri = childUrls.isNotEmpty
          ? childUrls.first
          : masterFetched.finalUri;
      final childFetched = await _fetchPlaylistWithFallbacks(
        session: session,
        uri: childUri,
        headers: session.headers,
      );
      if (session._disposed) return;
      var resolvedChildFetched = childFetched;
      if (resolvedChildFetched.statusCode == HttpStatus.forbidden ||
          resolvedChildFetched.statusCode == 418) {
        final pkeyUris = _buildPkeyFallbackUris(childUri, session.keyCache);
        for (final pkeyUri in pkeyUris) {
          if (session._disposed) return;
          final alt = await _fetchPlaylistWithFallbacks(
            session: session,
            uri: pkeyUri,
            headers: session.headers,
          );
          if (alt.statusCode == HttpStatus.ok) {
            _trace(
              'prime pkey fallback session=${session.id} '
              'from=${childUri.queryParameters['pkey'] ?? 'none'} '
              'to=${pkeyUri.queryParameters['pkey']}',
            );
            resolvedChildFetched = alt;
            break;
          }
        }
      }
      if (resolvedChildFetched.statusCode != HttpStatus.ok) {
        return;
      }

      final rewritten = await _rewritePlaylist(
        session: session,
        playlistUri: resolvedChildFetched.finalUri,
        manifest: resolvedChildFetched.body,
      );
      if (session._disposed) return;

      session.warmAssets(
        rewritten.assetIds.take(_stripchatWarmAssetPrefetchLimit),
        _prefetchAsset,
      );
    } catch (error) {
      _trace('session prime failed session=${session.id} error=$error');
    }
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
        .timeout(const Duration(seconds: 8));
    _buildUpstreamHeaders(headers).forEach(request.headers.set);
    final response = await request.close().timeout(const Duration(seconds: 8));
    final body = await response
        .transform(utf8.decoder)
        .join()
        .timeout(const Duration(seconds: 10));
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

    _FetchedPlaylist? primaryFetched;
    primaryFetched = await tryFetch(uri, isPrimary: true);
    if (primaryFetched != null &&
        primaryFetched.statusCode != HttpStatus.forbidden) {
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
      if (fallback.statusCode < HttpStatus.badRequest) {
        _trace(
          'playlist upstream host fallback session=${session.id} '
          'from=${(primaryFetched?.finalUri ?? uri).host} to=${fallback.finalUri.host}',
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
      if (sibling.statusCode < HttpStatus.badRequest) {
        _trace(
          'playlist upstream sibling fallback session=${session.id} '
          'from=${fallbackBaseUri.pathSegments.isNotEmpty ? fallbackBaseUri.pathSegments.last : fallbackBaseUri.path} '
          'to=${sibling.finalUri.pathSegments.isNotEmpty ? sibling.finalUri.pathSegments.last : sibling.finalUri.path}',
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

    for (final rawLine in const LineSplitter().convert(manifest)) {
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
        final resolvedTargets = await _resolveMouflonAssetTargets(
          rawUri: line.substring('#EXT-X-MOUFLON:URI:'.length),
          playlistUri: playlistUri,
          auth: auth,
          enablePdkeyFallback: _enablePdkeyFallback,
          candidatePkeys: _orderedMouflonPkeys(
            currentPkey: auth?.pkey,
            upstreamPkey: playlistUri.queryParameters['pkey'],
            seenPkeys: seenPkeys,
            keyCache: session.keyCache,
          ),
          keyCache: session.keyCache,
          tracePdkey: (phase, {required pkey, required source}) {
            _trace('pdkey $phase pkey=$pkey source=$source');
          },
          traceDecision: (message) => _trace(message),
          onPdkeyAllFailed: session.notePdkeyAllFailed,
          decryptMouflonSegment: session.decryptMouflonSegment,
          kDebugMode: _platformAdapter.kDebugMode,
          debugPrint: _platformAdapter.debugPrint,
        );
        pendingMouflonTargets = resolvedTargets;
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
    final domains = <String>[
      ...preferredCdnDomains,
      ..._stripchatKnownCdnDomains,
    ];
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
    final base = parsedUpstream ?? session.playlistUri ?? session.upstreamUri;
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
    return _platformAdapter.isMobile;
  }

  void _trace(String message) {
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
  final HlsAesWorkerSession aesWorker;
  final List<String> playlistCdnDomains;
  Uri? playlistUri;
  String? lastSuccessfulPlaylist;
  bool? shouldDropMap;
  Future<void>? startupPrimeInFlight;
  final Map<String, _StripchatAssetTargets> _assetTargets =
      <String, _StripchatAssetTargets>{};
  final Map<String, String> _assetIdsByKey = <String, String>{};
  final Map<String, _StripchatCachedAsset> cachedAssets =
      <String, _StripchatCachedAsset>{};
  final Map<String, Future<void>> _pendingWarmAssets = <String, Future<void>>{};
  int _pdkeyAllFailedCount = 0;
  bool _disposed = false;

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
    return aesWorker.decryptStripchatMouflonSegment(
      encryptedSegment: encryptedSegment,
      pdkey: pdkey,
    );
  }

  void touchCachedAsset(String assetId) {
    final asset = cachedAssets.remove(assetId);
    if (asset == null) {
      return;
    }
    cachedAssets[assetId] = asset;
    while (cachedAssets.length > _stripchatCachedAssetLimit) {
      final oldestKey = cachedAssets.keys.first;
      cachedAssets.remove(oldestKey);
    }
  }

  void warmAssets(
    Iterable<String> assetIds,
    Future<void> Function(_StripchatLlHlsSession session, String assetId) task,
  ) {
    if (_disposed) {
      return;
    }
    for (final assetId in assetIds) {
      if (_pendingWarmAssets.containsKey(assetId)) {
        continue;
      }
      final future = task(this, assetId).whenComplete(() {
        _pendingWarmAssets.remove(assetId);
      });
      _pendingWarmAssets[assetId] = future;
      unawaited(future);
    }
  }

  Future<_StripchatCachedAsset?> waitForWarmAsset(String assetId) async {
    final pending = _pendingWarmAssets[assetId];
    if (pending == null) {
      return cachedAssets[assetId];
    }
    await pending;
    return cachedAssets[assetId];
  }

  Future<void> dispose() async {
    _disposed = true;
    startupPrimeInFlight = null;
    shouldDropMap = null;
    final pending = _pendingWarmAssets.values.toList(growable: false);
    if (pending.isNotEmpty) {
      try {
        await Future.wait(pending);
      } catch (_) {}
    }
    _pendingWarmAssets.clear();
    cachedAssets.clear();
    await aesWorker.dispose();
  }
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
  });

  final String manifest;
  final List<String> assetIds;
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
