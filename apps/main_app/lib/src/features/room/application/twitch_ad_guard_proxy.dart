import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:live_core/live_core.dart';
import 'package:live_providers/live_providers.dart';

class TwitchAdGuardProxy {
  TwitchAdGuardProxy({
    HttpClient? client,
    Duration sessionTtl = const Duration(minutes: 12),
    bool? enabledOverride,
  })  : _client = client ?? HttpClient(),
        _sessionTtl = sessionTtl,
        _enabledOverride = enabledOverride {
    _client.connectionTimeout = const Duration(seconds: 8);
    _client.idleTimeout = const Duration(seconds: 8);
  }

  static const String _routePrefix = 'twitch-ad-guard';
  static const int _maxPlaylistProbeAttempts = 3;
  static const Duration _playlistProbeRetryDelay = Duration(milliseconds: 350);

  final HttpClient _client;
  final Duration _sessionTtl;
  final bool? _enabledOverride;
  final Map<String, _TwitchAdGuardSession> _sessions =
      <String, _TwitchAdGuardSession>{};

  HttpServer? _server;
  Uri? _endpoint;

  Future<List<LivePlayUrl>> wrapPlayUrls({
    required LivePlayQuality quality,
    required List<LivePlayUrl> playUrls,
  }) async {
    if (!_supportsPlatform || playUrls.isEmpty) {
      return playUrls;
    }

    final hasGroups = TwitchPlaybackQualityGroup.listFromJson(
      quality.metadata?['twitchPlaybackGroups'],
    ).isNotEmpty;
    final hasCandidates = TwitchPlaybackCandidate.listFromJson(
      quality.metadata?['twitchPlaybackCandidates'],
    ).isNotEmpty;
    final fixedGroup = TwitchPlaybackQualityGroup.fromJson(
      quality.metadata?['twitchPlaybackGroup'],
    );
    if (!hasGroups && !hasCandidates && fixedGroup == null) {
      return playUrls;
    }
    if (kDebugMode) {
      debugPrint(
        '[TwitchAdGuardProxy] wrap quality=${quality.id}/${quality.label} '
        'playUrls=${playUrls.length} '
        'groups=${hasGroups ? 'yes' : 'no'} '
        'candidates=${hasCandidates ? 'yes' : 'no'}',
      );
    }

    await _ensureStarted();
    _purgeExpiredSessions();

    final wrapped = <LivePlayUrl>[];
    for (var index = 0; index < playUrls.length; index += 1) {
      final session = _createSession(
        quality: quality,
        playUrls: playUrls,
        preferredIndex: index,
      );
      _sessions[session.id] = session;
      wrapped.add(
        LivePlayUrl(
          url: _sessionUri(session.id).toString(),
          headers: const {},
          lineLabel: playUrls[index].lineLabel,
          metadata: {
            ...?playUrls[index].metadata,
            'proxied': true,
            'upstreamUrl': playUrls[index].url,
          },
        ),
      );
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

  Uri _sessionUri(String sessionId) {
    final endpoint = _endpoint;
    if (endpoint == null) {
      throw StateError('TwitchAdGuardProxy has not been started.');
    }
    return endpoint.replace(path: '${endpoint.path}/$sessionId/stream.m3u8');
  }

  _TwitchAdGuardSession _createSession({
    required LivePlayQuality quality,
    required List<LivePlayUrl> playUrls,
    required int preferredIndex,
  }) {
    final sessionId = _randomToken(18);
    final preferredUrl = playUrls[preferredIndex];
    final autoGroups = TwitchPlaybackQualityGroup.listFromJson(
      quality.metadata?['twitchPlaybackGroups'],
    );
    if (quality.id == 'auto' && autoGroups.isNotEmpty) {
      final startupAuto = quality.metadata?['twitchStartupAuto'] == true;
      final preferredPlayerType =
          preferredUrl.metadata?['playerType']?.toString().trim() ?? '';
      final groups = autoGroups
          .map(
            (group) {
              final orderedCandidates = _orderedCandidates(
                candidates: group.candidates,
                preferredPlayerType: preferredPlayerType,
                preferCompatibleCodecs:
                    _hasMixedHevcCompatibility(group.candidates),
              );
              final manifestCandidate =
                  _manifestCandidateForGroup(orderedCandidates);
              return _TwitchAdGuardVariantGroup(
                id: _sanitizeKey(group.id),
                label: group.label,
                sortOrder: group.sortOrder,
                bandwidth: manifestCandidate?.bandwidth ?? group.bandwidth,
                width: manifestCandidate?.width ?? group.width,
                height: manifestCandidate?.height ?? group.height,
                frameRate: manifestCandidate?.frameRate ?? group.frameRate,
                codecs: manifestCandidate?.codecs ?? group.codecs,
                candidates: orderedCandidates,
              );
            },
          )
          .where((group) => group.candidates.isNotEmpty)
          .toList(growable: false);
      return _TwitchAdGuardSession.auto(
        id: sessionId,
        groups: startupAuto
            ? _selectStartupAutoGroups(_orderAutoGroups(groups))
            : _orderAutoGroups(groups),
      );
    }

    final fixedGroup = TwitchPlaybackQualityGroup.fromJson(
      quality.metadata?['twitchPlaybackGroup'],
    );
    final fixedCandidates = fixedGroup?.candidates ??
        playUrls
            .map(
              (item) => TwitchPlaybackCandidate(
                playlistUrl: item.url,
                headers: item.headers,
                playerType:
                    item.metadata?['playerType']?.toString().trim() ?? 'popout',
                platform:
                    item.metadata?['platform']?.toString().trim() ?? 'web',
                lineLabel: item.lineLabel ?? '线路',
                source: item.metadata?['source']?.toString().trim(),
                bandwidth: _readInt(item.metadata?['bandwidth']) ?? 0,
                width: _readInt(item.metadata?['width']),
                height: _readInt(item.metadata?['height']),
                frameRate: _readDouble(item.metadata?['frameRate']),
                codecs: item.metadata?['codecs']?.toString().trim(),
              ),
            )
            .toList(growable: false);
    return _TwitchAdGuardSession.fixed(
      id: sessionId,
      candidates: _orderedCandidates(
        candidates: fixedCandidates,
        preferredUrl: preferredUrl.url,
      ),
    );
  }

  List<TwitchPlaybackCandidate> _orderedCandidates({
    required List<TwitchPlaybackCandidate> candidates,
    String preferredUrl = '',
    String preferredPlayerType = '',
    bool preferCompatibleCodecs = false,
  }) {
    final ordered = List<TwitchPlaybackCandidate>.from(candidates);
    ordered.sort((left, right) {
      if (preferCompatibleCodecs) {
        final codecCompare =
            _codecPriority(left.codecs).compareTo(_codecPriority(right.codecs));
        if (codecCompare != 0) {
          return codecCompare;
        }
      }
      final leftPreferred = left.playlistUrl == preferredUrl ||
          (preferredPlayerType.isNotEmpty &&
              left.playerType == preferredPlayerType);
      final rightPreferred = right.playlistUrl == preferredUrl ||
          (preferredPlayerType.isNotEmpty &&
              right.playerType == preferredPlayerType);
      if (leftPreferred != rightPreferred) {
        return leftPreferred ? -1 : 1;
      }
      final playerTypeCompare = _playerTypePriority(left.playerType)
          .compareTo(_playerTypePriority(right.playerType));
      if (playerTypeCompare != 0) {
        return playerTypeCompare;
      }
      return right.bandwidth.compareTo(left.bandwidth);
    });
    return ordered;
  }

  TwitchPlaybackCandidate? _manifestCandidateForGroup(
    List<TwitchPlaybackCandidate> candidates,
  ) {
    if (candidates.isEmpty) {
      return null;
    }
    final ordered = List<TwitchPlaybackCandidate>.from(candidates);
    ordered.sort((left, right) {
      final codecCompare =
          _codecPriority(left.codecs).compareTo(_codecPriority(right.codecs));
      if (codecCompare != 0) {
        return codecCompare;
      }
      final playerTypeCompare = _playerTypePriority(left.playerType).compareTo(
        _playerTypePriority(right.playerType),
      );
      if (playerTypeCompare != 0) {
        return playerTypeCompare;
      }
      return right.bandwidth.compareTo(left.bandwidth);
    });
    return ordered.first;
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
      if (action == 'stream.m3u8') {
        if (session.mode == _TwitchAdGuardMode.auto) {
          await _writeSyntheticMasterPlaylist(response, session);
        } else {
          await _writeVariantPlaylist(
            response,
            session: session,
            candidates: session.fixedCandidates,
          );
        }
        return;
      }
      if (action == 'variant' && segments.length >= 4) {
        final groupKey = segments[3].replaceAll('.m3u8', '');
        final group = session.groupsById[groupKey];
        if (group == null) {
          response.statusCode = HttpStatus.notFound;
          await response.close();
          return;
        }
        if (kDebugMode) {
          debugPrint(
            '[TwitchAdGuardProxy] variant request '
            'group=${group.label}/${group.id} '
            'sort=${group.sortOrder} '
            'candidates=${group.candidates.length}',
          );
        }
        await _writeVariantPlaylist(
          response,
          session: session,
          candidates: group.candidates,
        );
        return;
      }
      if (action == 'asset' && segments.length >= 4) {
        final asset = session.assets[segments[3]];
        if (asset == null) {
          response.statusCode = HttpStatus.notFound;
          await response.close();
          return;
        }
        await _pipeAsset(response, asset);
        return;
      }
      response.statusCode = HttpStatus.notFound;
      await response.close();
    } catch (error) {
      debugPrint('TwitchAdGuardProxy request failed: $error');
      response.statusCode = HttpStatus.internalServerError;
      await response.close();
    }
  }

  Future<void> _writeSyntheticMasterPlaylist(
    HttpResponse response,
    _TwitchAdGuardSession session,
  ) async {
    final endpoint = _endpoint;
    if (endpoint == null || session.autoGroups.isEmpty) {
      response.statusCode = HttpStatus.internalServerError;
      await response.close();
      return;
    }
    final buffer = StringBuffer()..writeln('#EXTM3U');
    for (final group in session.autoGroups) {
      final attributes = <String>[
        if (group.bandwidth > 0) 'BANDWIDTH=${group.bandwidth}',
        if (group.width != null && group.height != null)
          'RESOLUTION=${group.width}x${group.height}',
        if (group.frameRate != null && group.frameRate! > 0)
          'FRAME-RATE=${group.frameRate!.toStringAsFixed(3)}',
        if (group.codecs?.trim().isNotEmpty == true)
          'CODECS="${group.codecs!.trim()}"',
      ];
      buffer.writeln('#EXT-X-STREAM-INF:${attributes.join(',')}');
      final variantUri = endpoint.replace(
        path: '${endpoint.path}/${session.id}/variant/${group.id}.m3u8',
      );
      buffer.writeln(variantUri.toString());
    }
    response.headers.contentType =
        ContentType('application', 'vnd.apple.mpegurl', charset: 'utf-8');
    response.write(buffer.toString());
    await response.close();
  }

  Future<void> _writeVariantPlaylist(
    HttpResponse response, {
    required _TwitchAdGuardSession session,
    required List<TwitchPlaybackCandidate> candidates,
  }) async {
    final selected = await _selectPlayablePlaylist(candidates);
    if (selected == null) {
      response.statusCode = HttpStatus.badGateway;
      await response.close();
      return;
    }
    if (kDebugMode) {
      debugPrint(
        '[TwitchAdGuardProxy] variant '
        'playerType=${selected.candidate.playerType} '
        'line=${selected.candidate.lineLabel} '
        'hadAds=${selected.hadAds} '
        'url=${selected.candidate.playlistUrl}',
      );
    }
    final playlist = _rewritePlaylist(
      session: session,
      sourceUrl: selected.candidate.playlistUrl,
      headers: selected.candidate.headers,
      text: selected.text,
      stripPrefetch: selected.hadAds,
    );
    response.headers.contentType =
        ContentType('application', 'vnd.apple.mpegurl', charset: 'utf-8');
    response.write(playlist);
    await response.close();
  }

  Future<_TwitchLoadedPlaylist?> _selectPlayablePlaylist(
    List<TwitchPlaybackCandidate> candidates,
  ) async {
    for (var attempt = 0; attempt < _maxPlaylistProbeAttempts; attempt += 1) {
      final loaded = (await Future.wait(
        List.generate(
          candidates.length,
          (index) => _loadCandidatePlaylist(
            candidates[index],
            candidateIndex: index,
          ),
        ),
      ))
          .whereType<_TwitchLoadedPlaylist>()
          .toList(growable: false);
      for (final playlist in loaded) {
        if (!playlist.hadAds && playlist.segmentCount > 0) {
          return playlist;
        }
      }
      final fallback = _selectBestAdFallback(loaded);
      if (fallback != null) {
        if (fallback.segmentCount > 0 ||
            attempt >= _maxPlaylistProbeAttempts - 1) {
          return fallback;
        }
      }
      if (attempt < _maxPlaylistProbeAttempts - 1) {
        await Future<void>.delayed(_playlistProbeRetryDelay);
      }
    }
    return null;
  }

  Future<_TwitchLoadedPlaylist?> _loadCandidatePlaylist(
    TwitchPlaybackCandidate candidate, {
    required int candidateIndex,
  }) async {
    try {
      final text = await _fetchText(
        candidate.playlistUrl,
        headers: candidate.headers,
      );
      final sanitized = _sanitizePlaylist(text);
      final loaded = _TwitchLoadedPlaylist(
        candidate: candidate,
        text: sanitized.text,
        hadAds: sanitized.hasAds,
        hasPrefetch: sanitized.hasPrefetch,
        segmentCount: sanitized.playableSegmentCount,
        candidateIndex: candidateIndex,
      );
      if (kDebugMode) {
        debugPrint(
          '[TwitchAdGuardProxy] probe '
          'playerType=${candidate.playerType} '
          'line=${candidate.lineLabel} '
          'hadAds=${loaded.hadAds} '
          'prefetch=${loaded.hasPrefetch} '
          'segments=${loaded.segmentCount} '
          'url=${candidate.playlistUrl}',
        );
      }
      return loaded;
    } catch (error) {
      if (kDebugMode) {
        debugPrint(
          '[TwitchAdGuardProxy] probe failed '
          'playerType=${candidate.playerType} '
          'line=${candidate.lineLabel} '
          'url=${candidate.playlistUrl} '
          'error=$error',
        );
      }
      return null;
    }
  }

  _TwitchLoadedPlaylist? _selectBestAdFallback(
    List<_TwitchLoadedPlaylist> loaded,
  ) {
    if (loaded.isEmpty) {
      return null;
    }
    final ordered = List<_TwitchLoadedPlaylist>.from(loaded);
    ordered.sort((left, right) {
      final liveSegmentCompare =
          right.segmentCount.compareTo(left.segmentCount);
      if (liveSegmentCompare != 0) {
        return liveSegmentCompare;
      }
      final playerTypeCompare = _adFallbackPlayerTypePriority(
        left.candidate.playerType,
      ).compareTo(
        _adFallbackPlayerTypePriority(right.candidate.playerType),
      );
      if (playerTypeCompare != 0) {
        return playerTypeCompare;
      }
      final codecCompare = _codecPriority(
        left.candidate.codecs,
      ).compareTo(_codecPriority(right.candidate.codecs));
      if (codecCompare != 0) {
        return codecCompare;
      }
      final bandwidthCompare =
          left.candidate.bandwidth.compareTo(right.candidate.bandwidth);
      if (bandwidthCompare != 0) {
        return bandwidthCompare;
      }
      return left.candidateIndex.compareTo(right.candidateIndex);
    });
    return ordered.first;
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
        'Twitch proxy upstream request failed with ${response.statusCode}.',
        uri: Uri.parse(url),
      );
    }
    return utf8.decode(await consolidateHttpClientResponseBytes(response));
  }

  String _rewritePlaylist({
    required _TwitchAdGuardSession session,
    required String sourceUrl,
    required Map<String, String> headers,
    required String text,
    required bool stripPrefetch,
  }) {
    final lines = text.split(RegExp(r'\r?\n'));
    final rewritten = <String>[];
    for (var index = 0; index < lines.length; index += 1) {
      final line = lines[index];
      if (stripPrefetch && line.startsWith('#EXT-X-TWITCH-PREFETCH:')) {
        continue;
      }
      if (line.trim().isEmpty) {
        rewritten.add(line);
        continue;
      }
      if (!line.startsWith('#')) {
        rewritten.add(
          _registerAssetUrl(
            session: session,
            baseUrl: sourceUrl,
            rawUrl: line,
            headers: headers,
          ),
        );
        continue;
      }
      if (line.contains('URI="')) {
        rewritten.add(
          line.replaceAllMapped(
            RegExp(r'URI="([^"]+)"'),
            (match) => 'URI="${_registerAssetUrl(
              session: session,
              baseUrl: sourceUrl,
              rawUrl: match.group(1) ?? '',
              headers: headers,
            )}"',
          ),
        );
        continue;
      }
      rewritten.add(line);
    }
    return rewritten.join('\n');
  }

  String _registerAssetUrl({
    required _TwitchAdGuardSession session,
    required String baseUrl,
    required String rawUrl,
    required Map<String, String> headers,
  }) {
    final endpoint = _endpoint;
    if (endpoint == null) {
      return rawUrl;
    }
    final absoluteUrl = Uri.parse(baseUrl).resolve(rawUrl).toString();
    final assetId = session.registerAsset(
      url: absoluteUrl,
      headers: headers,
    );
    return endpoint
        .replace(
          path: '${endpoint.path}/${session.id}/asset/$assetId',
        )
        .toString();
  }

  Future<void> _pipeAsset(
    HttpResponse response,
    _TwitchAdGuardAsset asset,
  ) async {
    final request = await _client.getUrl(Uri.parse(asset.url));
    asset.headers.forEach(request.headers.set);
    final upstream = await request.close();
    response.statusCode = upstream.statusCode;
    if (upstream.contentLength >= 0) {
      response.contentLength = upstream.contentLength;
    }
    final contentType = upstream.headers.contentType;
    if (contentType != null) {
      response.headers.contentType = contentType;
    }
    final cacheControl = upstream.headers.value(HttpHeaders.cacheControlHeader);
    if (cacheControl != null && cacheControl.isNotEmpty) {
      response.headers.set(HttpHeaders.cacheControlHeader, cacheControl);
    }
    await upstream.pipe(response);
  }

  _TwitchSanitizedPlaylist _sanitizePlaylist(String text) {
    final lines = text.split(RegExp(r'\r?\n'));
    final sanitized = <String>[];
    final segmentBuffer = <String>[];
    var inCueOut = false;
    var hasAds = false;
    var hasPrefetch = false;
    var playableSegmentCount = 0;
    var pendingDiscontinuity = false;
    var segmentMarkedAd = false;

    void addSegmentLine(String line) {
      segmentBuffer.add(line);
    }

    void clearSegmentBuffer() {
      segmentBuffer.clear();
      segmentMarkedAd = false;
    }

    for (var index = 0; index < lines.length; index += 1) {
      final line = lines[index];
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        if (segmentBuffer.isEmpty) {
          sanitized.add(line);
        } else {
          addSegmentLine(line);
        }
        continue;
      }
      if (_isTwitchPrefetchTag(trimmed)) {
        hasPrefetch = true;
        continue;
      }
      if (_isTwitchCueOutTag(trimmed)) {
        hasAds = true;
        inCueOut = true;
        pendingDiscontinuity = true;
        continue;
      }
      if (_isTwitchCueInTag(trimmed)) {
        hasAds = true;
        inCueOut = false;
        continue;
      }
      if (_isTwitchAdMetadataTag(trimmed)) {
        hasAds = true;
        segmentMarkedAd = true;
        pendingDiscontinuity = true;
        continue;
      }
      if (_isTwitchDiscontinuityTag(trimmed)) {
        pendingDiscontinuity = true;
        continue;
      }
      if (_isSegmentScopedTag(trimmed)) {
        if (_isAdExtInfTag(trimmed)) {
          hasAds = true;
          segmentMarkedAd = true;
          pendingDiscontinuity = true;
        }
        addSegmentLine(line);
        continue;
      }
      if (_isGlobalPlaylistTag(trimmed) && segmentBuffer.isEmpty) {
        sanitized.add(line);
        continue;
      }
      if (!trimmed.startsWith('#')) {
        final isAdSegment =
            inCueOut || segmentMarkedAd || _looksLikeTwitchAdSegment(trimmed);
        if (isAdSegment) {
          hasAds = true;
          pendingDiscontinuity = true;
          clearSegmentBuffer();
          continue;
        }
        if (pendingDiscontinuity &&
            sanitized.isNotEmpty &&
            sanitized.last.trim() != '#EXT-X-DISCONTINUITY') {
          sanitized.add('#EXT-X-DISCONTINUITY');
        }
        sanitized.addAll(segmentBuffer);
        sanitized.add(line);
        playableSegmentCount += 1;
        pendingDiscontinuity = false;
        clearSegmentBuffer();
        continue;
      }
      addSegmentLine(line);
    }
    return _TwitchSanitizedPlaylist(
      text: sanitized.join('\n'),
      hasAds: hasAds,
      hasPrefetch: hasPrefetch,
      playableSegmentCount: playableSegmentCount,
    );
  }

  List<_TwitchAdGuardVariantGroup> _orderAutoGroups(
    List<_TwitchAdGuardVariantGroup> groups,
  ) {
    final ordered = List<_TwitchAdGuardVariantGroup>.from(groups);
    ordered.sort((left, right) {
      final sortCompare = left.sortOrder.compareTo(right.sortOrder);
      if (sortCompare != 0) {
        return sortCompare;
      }
      final bandwidthCompare = left.bandwidth.compareTo(right.bandwidth);
      if (bandwidthCompare != 0) {
        return bandwidthCompare;
      }
      return _codecPriority(left.codecs)
          .compareTo(_codecPriority(right.codecs));
    });
    return ordered;
  }

  List<_TwitchAdGuardVariantGroup> _selectStartupAutoGroups(
    List<_TwitchAdGuardVariantGroup> groups,
  ) {
    if (groups.length <= 1) {
      return groups;
    }
    final starterGroups = groups.where((group) {
      final height = group.height;
      if (height != null) {
        return height <= 480;
      }
      return group.sortOrder <= 480;
    }).toList(growable: false);
    if (starterGroups.isNotEmpty) {
      return starterGroups.take(3).toList(growable: false);
    }
    return groups.take(min(2, groups.length)).toList(growable: false);
  }

  void _purgeExpiredSessions() {
    if (_sessions.isEmpty) {
      return;
    }
    final threshold = DateTime.now().subtract(_sessionTtl);
    final expired = _sessions.entries
        .where((entry) => entry.value.lastAccessAt.isBefore(threshold))
        .map((entry) => entry.key)
        .toList(growable: false);
    for (final key in expired) {
      _sessions.remove(key);
    }
  }

  String _randomToken(int length) {
    const alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final buffer = StringBuffer();
    final random = Random.secure();
    while (buffer.length < length) {
      buffer.write(alphabet[random.nextInt(alphabet.length)]);
    }
    return buffer.toString();
  }

  int _playerTypePriority(String playerType) {
    switch (playerType) {
      case 'embed':
        return 0;
      case 'site':
        return 1;
      case 'popout':
        return 2;
      case 'autoplay':
        return 3;
    }
    return 99;
  }

  int _adFallbackPlayerTypePriority(String playerType) {
    switch (playerType) {
      case 'embed':
        return 0;
      case 'site':
        return 1;
      case 'autoplay':
        return 2;
      case 'popout':
        return 3;
    }
    return 99;
  }

  int _codecPriority(String? codecs) {
    final family = _codecFamily(codecs);
    switch (family) {
      case _CodecFamily.compatible:
        return 0;
      case _CodecFamily.unknown:
        return 1;
      case _CodecFamily.hevc:
        return 2;
    }
  }

  bool _hasMixedHevcCompatibility(List<TwitchPlaybackCandidate> candidates) {
    var hasCompatible = false;
    var hasHevc = false;
    for (final candidate in candidates) {
      final family = _codecFamily(candidate.codecs);
      if (family == _CodecFamily.compatible) {
        hasCompatible = true;
      } else if (family == _CodecFamily.hevc) {
        hasHevc = true;
      }
    }
    return hasCompatible && hasHevc;
  }

  _CodecFamily _codecFamily(String? codecs) {
    final normalized = codecs?.trim().toLowerCase() ?? '';
    if (normalized.isEmpty) {
      return _CodecFamily.unknown;
    }
    final primaryCodec = normalized.split(',').first.trim();
    if (primaryCodec.startsWith('hev') || primaryCodec.startsWith('hvc')) {
      return _CodecFamily.hevc;
    }
    return _CodecFamily.compatible;
  }

  String _sanitizeKey(String value) {
    final normalized = value.trim().replaceAll(RegExp(r'[^a-zA-Z0-9_-]+'), '-');
    return normalized.isEmpty ? _randomToken(8) : normalized;
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
}

class _TwitchLoadedPlaylist {
  const _TwitchLoadedPlaylist({
    required this.candidate,
    required this.text,
    required this.hadAds,
    required this.hasPrefetch,
    required this.segmentCount,
    required this.candidateIndex,
  });

  final TwitchPlaybackCandidate candidate;
  final String text;
  final bool hadAds;
  final bool hasPrefetch;
  final int segmentCount;
  final int candidateIndex;
}

class _TwitchSanitizedPlaylist {
  const _TwitchSanitizedPlaylist({
    required this.text,
    required this.hasAds,
    required this.hasPrefetch,
    required this.playableSegmentCount,
  });

  final String text;
  final bool hasAds;
  final bool hasPrefetch;
  final int playableSegmentCount;
}

enum _CodecFamily { compatible, hevc, unknown }

enum _TwitchAdGuardMode { fixed, auto }

class _TwitchAdGuardSession {
  _TwitchAdGuardSession.fixed({
    required this.id,
    required List<TwitchPlaybackCandidate> candidates,
  })  : mode = _TwitchAdGuardMode.fixed,
        fixedCandidates = candidates,
        autoGroups = const [],
        groupsById = const {};

  _TwitchAdGuardSession.auto({
    required this.id,
    required List<_TwitchAdGuardVariantGroup> groups,
  })  : mode = _TwitchAdGuardMode.auto,
        fixedCandidates = const [],
        autoGroups = groups,
        groupsById = {
          for (final group in groups) group.id: group,
        };

  final String id;
  final _TwitchAdGuardMode mode;
  final List<TwitchPlaybackCandidate> fixedCandidates;
  final List<_TwitchAdGuardVariantGroup> autoGroups;
  final Map<String, _TwitchAdGuardVariantGroup> groupsById;
  final Map<String, _TwitchAdGuardAsset> assets =
      <String, _TwitchAdGuardAsset>{};

  DateTime lastAccessAt = DateTime.now();
  int _assetCounter = 0;

  void touch() {
    lastAccessAt = DateTime.now();
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
    final assetId = (++_assetCounter).toString();
    assets[assetId] = _TwitchAdGuardAsset(url: url, headers: headers);
    return assetId;
  }
}

class _TwitchAdGuardVariantGroup {
  const _TwitchAdGuardVariantGroup({
    required this.id,
    required this.label,
    required this.sortOrder,
    required this.candidates,
    this.bandwidth = 0,
    this.width,
    this.height,
    this.frameRate,
    this.codecs,
  });

  final String id;
  final String label;
  final int sortOrder;
  final List<TwitchPlaybackCandidate> candidates;
  final int bandwidth;
  final int? width;
  final int? height;
  final double? frameRate;
  final String? codecs;
}

class _TwitchAdGuardAsset {
  const _TwitchAdGuardAsset({
    required this.url,
    required this.headers,
  });

  final String url;
  final Map<String, String> headers;
}

int? _readInt(Object? raw) {
  if (raw is int) {
    return raw;
  }
  if (raw is num) {
    return raw.toInt();
  }
  return int.tryParse(raw?.toString() ?? '');
}

double? _readDouble(Object? raw) {
  if (raw is double) {
    return raw;
  }
  if (raw is num) {
    return raw.toDouble();
  }
  return double.tryParse(raw?.toString() ?? '');
}

bool _isTwitchPrefetchTag(String line) {
  return line.startsWith('#EXT-X-TWITCH-PREFETCH:');
}

bool _isTwitchCueOutTag(String line) {
  return line.startsWith('#EXT-X-CUE-OUT');
}

bool _isTwitchCueInTag(String line) {
  return line.startsWith('#EXT-X-CUE-IN');
}

bool _isTwitchDiscontinuityTag(String line) {
  return line == '#EXT-X-DISCONTINUITY';
}

bool _isTwitchAdMetadataTag(String line) {
  if (line.contains('X-TV-TWITCH-AD')) {
    return true;
  }
  if (!line.startsWith('#EXT-X-DATERANGE:')) {
    return false;
  }
  final normalized = line.toLowerCase();
  return normalized.contains('class="twitch-stitched-ad"') ||
      normalized.contains('id="stitched-ad-') ||
      normalized.contains('stitched-ad');
}

bool _isAdExtInfTag(String line) {
  if (!line.startsWith('#EXTINF')) {
    return false;
  }
  final commaIndex = line.indexOf(',');
  if (commaIndex < 0 || commaIndex >= line.length - 1) {
    return false;
  }
  final title = line.substring(commaIndex + 1).trim();
  return title.contains('Amazon');
}

bool _looksLikeTwitchAdSegment(String line) {
  final normalized = line.toLowerCase();
  return normalized.contains('stitched-ad') ||
      normalized.contains('amazon') ||
      normalized.contains('/ads?');
}

bool _isSegmentScopedTag(String line) {
  return line.startsWith('#EXTINF') ||
      line.startsWith('#EXT-X-PROGRAM-DATE-TIME') ||
      line.startsWith('#EXT-X-KEY') ||
      line.startsWith('#EXT-X-MAP') ||
      line.startsWith('#EXT-X-BYTERANGE') ||
      line.startsWith('#EXT-X-GAP');
}

bool _isGlobalPlaylistTag(String line) {
  return line.startsWith('#EXTM3U') ||
      line.startsWith('#EXT-X-VERSION') ||
      line.startsWith('#EXT-X-TARGETDURATION') ||
      line.startsWith('#EXT-X-MEDIA-SEQUENCE') ||
      line.startsWith('#EXT-X-DISCONTINUITY-SEQUENCE') ||
      line.startsWith('#EXT-X-ENDLIST') ||
      line.startsWith('#EXT-X-PLAYLIST-TYPE') ||
      line.startsWith('#EXT-X-INDEPENDENT-SEGMENTS') ||
      line.startsWith('#EXT-X-SERVER-CONTROL') ||
      line.startsWith('#EXT-X-PART-INF') ||
      line.startsWith('#EXT-X-SKIP') ||
      line.startsWith('#EXT-X-START') ||
      line.startsWith('#EXT-X-RENDITION-REPORT') ||
      line.startsWith('#EXT-X-PRELOAD-HINT');
}
