import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:live_core/live_core.dart';
import 'package:live_providers/src/providers/twitch/twitch_playback_manifest.dart';
import 'package:meta/meta.dart';
import '../hls_proxy_delivery_knobs.dart';
import '../hls_proxy_platform_adapter.dart';

class TwitchAdGuardProxy {
  TwitchAdGuardProxy({
    required HlsProxyPlatformAdapter platformAdapter,
    HttpClient? client,
    Duration sessionTtl = const Duration(minutes: 12),
    bool? enabledOverride,
    HlsProxyDeliveryKnobs? deliveryKnobs,
  }) : _platformAdapter = platformAdapter,
       _client = client ?? HttpClient(),
       _sessionTtl = sessionTtl,
       _enabledOverride = enabledOverride,
       _d = deliveryKnobs ?? HlsProxyDeliveryKnobs.fromActiveProfile() {
    _client.connectionTimeout = const Duration(seconds: 8);
    _client.idleTimeout = const Duration(seconds: 8);
    // Desktop: concurrent asset prefetch + mpv multi-segment demand.
    // Mobile release left maxConnectionsPerHost unset.
    final maxHost = _d.twitchMaxConnectionsPerHost;
    if (maxHost != null) {
      _client.maxConnectionsPerHost = maxHost;
    }
  }

  static const String _routePrefix = 'twitch-ad-guard';
  static const int _maxPlaylistProbeAttempts = 3;
  static const Duration _playlistProbeRetryDelay = Duration(milliseconds: 350);
  static const Duration _playlistCandidateProbeTimeout = Duration(seconds: 2);
  static const Duration _playlistPlayableSelectionHedgeDelay = Duration(
    milliseconds: 150,
  );

  final HlsProxyPlatformAdapter _platformAdapter;
  final HttpClient _client;
  final Duration _sessionTtl;
  final bool? _enabledOverride;
  final HlsProxyDeliveryKnobs _d;
  final Map<String, _TwitchAdGuardSession> _sessions =
      <String, _TwitchAdGuardSession>{};

  HttpServer? _server;
  Uri? _endpoint;

  Future<List<LivePlayUrl>> wrapPlayUrls({
    required String roomId,
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
    if (_platformAdapter.kDebugMode) {
      _platformAdapter.debugPrint(
        '[TwitchAdGuardProxy] wrap quality=${quality.id}/${quality.label} '
        'playUrls=${playUrls.length} '
        'groups=${hasGroups ? 'yes' : 'no'} '
        'candidates=${hasCandidates ? 'yes' : 'no'}',
      );
    }

    await ensureStarted();
    _purgeExpiredSessions();

    final wrapped = <LivePlayUrl>[];
    for (var index = 0; index < playUrls.length; index += 1) {
      final session = _createSession(
        roomId: roomId,
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

  Future<void>? _startFuture;
  bool _disposed = false;

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
    await _server?.close(force: true);
    _server = null;
    _endpoint = null;
    _sessions.clear();
    _client.close(force: true);
    _startFuture = null;
  }

  void unregisterSession(String roomId) {
    _sessions.removeWhere((id, session) => session.roomId == roomId);
  }

  Future<void> ensureStarted() async {
    if (_disposed) {
      throw StateError('TwitchAdGuardProxy is disposed.');
    }
    if (_server != null && _endpoint != null) {
      return;
    }
    final existing = _startFuture;
    if (existing != null) {
      await existing;
      // Concurrent joiners must fail closed after dispose aborts bind.
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

  /// Fail closed: dispose-aborted bind and post-await dispose must not
  /// look like a successful start to callers (wrapPlayUrls etc.).
  void _ensureRunningAfterStart() {
    if (_disposed) {
      throw StateError('TwitchAdGuardProxy is disposed.');
    }
    if (_server == null || _endpoint == null) {
      throw StateError('TwitchAdGuardProxy failed to start.');
    }
  }

  Future<void> _startServer() async {
    if (_server != null && _endpoint != null) {
      return;
    }
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    if (_disposed) {
      await server.close(force: true);
      // Propagate so ensureStarted / concurrent waiters fail closed.
      throw StateError('TwitchAdGuardProxy is disposed.');
    }
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
    required String roomId,
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
      final preferStartupLadder =
          startupAuto || _d.twitchPreferStartupAutoLadder;
      final preferredPlayerType =
          preferredUrl.metadata?['playerType']?.toString().trim() ?? '';
      final groups = autoGroups
          .map((group) {
            final orderedCandidates = _orderedCandidates(
              candidates: group.candidates,
              preferredPlayerType: preferredPlayerType,
              preferCompatibleCodecs: _hasMixedHevcCompatibility(
                group.candidates,
              ),
            );
            final manifestCandidate = _manifestCandidateForGroup(
              orderedCandidates,
            );
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
          })
          .where((group) => group.candidates.isNotEmpty)
          .toList(growable: false);
      final ordered = _orderAutoGroups(groups);
      final sessionGroups = preferStartupLadder
          ? _selectStartupAutoGroups(ordered)
          : ordered;
      final session = _TwitchAdGuardSession.auto(
        roomId: roomId,
        id: sessionId,
        delivery: _d,
        groups: sessionGroups,
      );
      _prewarmAutoVariantGroups(session);
      return session;
    }

    final fixedGroup = TwitchPlaybackQualityGroup.fromJson(
      quality.metadata?['twitchPlaybackGroup'],
    );
    final fixedCandidates =
        fixedGroup?.candidates ??
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
      roomId: roomId,
      id: sessionId,
      delivery: _d,
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
        final codecCompare = _codecPriority(
          left.codecs,
        ).compareTo(_codecPriority(right.codecs));
        if (codecCompare != 0) {
          return codecCompare;
        }
      }
      final leftPreferred =
          left.playlistUrl == preferredUrl ||
          (preferredPlayerType.isNotEmpty &&
              left.playerType == preferredPlayerType);
      final rightPreferred =
          right.playlistUrl == preferredUrl ||
          (preferredPlayerType.isNotEmpty &&
              right.playerType == preferredPlayerType);
      if (leftPreferred != rightPreferred) {
        return leftPreferred ? -1 : 1;
      }
      final playerTypeCompare = _playerTypePriority(
        left.playerType,
      ).compareTo(_playerTypePriority(right.playerType));
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
      final codecCompare = _codecPriority(
        left.codecs,
      ).compareTo(_codecPriority(right.codecs));
      if (codecCompare != 0) {
        return codecCompare;
      }
      final playerTypeCompare = _playerTypePriority(
        left.playerType,
      ).compareTo(_playerTypePriority(right.playerType));
      if (playerTypeCompare != 0) {
        return playerTypeCompare;
      }
      return right.bandwidth.compareTo(left.bandwidth);
    });
    return ordered.first;
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final gate = TwitchProxyResponseGate(request.response);
    try {
      _purgeExpiredSessions();
      final segments = request.uri.pathSegments;
      if (segments.length < 3 || segments.first != _routePrefix) {
        await gate.commitStatusAndClose(HttpStatus.notFound);
        return;
      }
      final session = _sessions[segments[1]];
      if (session == null) {
        await gate.commitStatusAndClose(HttpStatus.gone);
        return;
      }
      session.touch();
      final action = segments[2];
      if (action == 'stream.m3u8') {
        if (session.mode == _TwitchAdGuardMode.auto) {
          await _writeSyntheticMasterPlaylist(gate, session);
        } else {
          await _writeVariantPlaylist(
            gate,
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
          await gate.commitStatusAndClose(HttpStatus.notFound);
          return;
        }
        if (_platformAdapter.kDebugMode) {
          _platformAdapter.debugPrint(
            '[TwitchAdGuardProxy] variant request '
            'group=${group.label}/${group.id} '
            'sort=${group.sortOrder} '
            'candidates=${group.candidates.length}',
          );
        }
        await _writeVariantPlaylist(
          gate,
          session: session,
          groupId: group.id,
          candidates: group.candidates,
        );
        return;
      }
      if (action == 'asset' && segments.length >= 4) {
        final assetId = segments[3];
        final asset = session.assets[assetId];
        if (asset == null) {
          await gate.commitStatusAndClose(HttpStatus.notFound);
          return;
        }
        await _pipeAsset(gate, session: session, assetId: assetId, asset: asset);
        return;
      }
      await gate.commitStatusAndClose(HttpStatus.notFound);
    } catch (error) {
      _platformAdapter.log(
        'twitch/proxy',
        'TwitchAdGuardProxy request failed: $error',
      );
      // Never throw "Header already sent" — only write status if still open.
      await gate.commitStatusAndClose(HttpStatus.internalServerError);
    }
  }

  Future<void> _writeSyntheticMasterPlaylist(
    TwitchProxyResponseGate gate,
    _TwitchAdGuardSession session,
  ) async {
    final endpoint = _endpoint;
    if (endpoint == null || session.autoGroups.isEmpty) {
      await gate.commitStatusAndClose(HttpStatus.internalServerError);
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
    await gate.writePlaylistBody(buffer.toString());
  }

  Future<void> _writeVariantPlaylist(
    TwitchProxyResponseGate gate, {
    required _TwitchAdGuardSession session,
    String? groupId,
    required List<TwitchPlaybackCandidate> candidates,
  }) async {
    final stickyTtl = _d.twitchVariantPlaylistStickyTtl;
    if (groupId != null && stickyTtl > Duration.zero) {
      final cached = session.variantPlaylistByGroup[groupId];
      final cachedUntil = session.variantPlaylistUntilByGroup[groupId];
      if (cached != null &&
          cachedUntil != null &&
          DateTime.now().isBefore(cachedUntil) &&
          cached.trim().isNotEmpty) {
        if (_platformAdapter.kDebugMode) {
          _platformAdapter.debugPrint(
            '[TwitchAdGuardProxy] variant sticky hit group=$groupId',
          );
        }
        await gate.writePlaylistBody(cached);
        return;
      }
    }

    final selected = await _selectPlayablePlaylist(
      candidates,
      session: session,
    );
    if (selected == null) {
      await gate.commitStatusAndClose(HttpStatus.badGateway);
      return;
    }
    if (_platformAdapter.kDebugMode) {
      _platformAdapter.debugPrint(
        '[TwitchAdGuardProxy] variant '
        'playerType=${selected.candidate.playerType} '
        'line=${selected.candidate.lineLabel} '
        'hadAds=${selected.hadAds} '
        'url=${selected.candidate.playlistUrl}',
      );
    }
    final warmAssetIds = <String>[];
    final playlist = _rewritePlaylist(
      session: session,
      sourceUrl: selected.candidate.playlistUrl,
      headers: selected.candidate.headers,
      text: selected.text,
      stripPrefetch: selected.hadAds,
      warmAssetIds: warmAssetIds,
    );
    if (groupId != null &&
        stickyTtl > Duration.zero &&
        !selected.hadAds &&
        selected.segmentCount > 0) {
      session.variantPlaylistByGroup[groupId] = playlist;
      session.variantPlaylistUntilByGroup[groupId] = DateTime.now().add(
        stickyTtl,
      );
    }
    await gate.writePlaylistBody(playlist);
    final warmLimit = _d.twitchAssetWarmPrefetchLimit;
    if (warmLimit > 0) {
      session.warmAssets(
        warmAssetIds.take(warmLimit),
        _prefetchAsset,
      );
    }
  }

  /// Best-effort: probe lowest Auto variants so first mpv ABR hop is warm.
  void _prewarmAutoVariantGroups(_TwitchAdGuardSession session) {
    final count = _d.twitchPrewarmStartupVariants;
    if (count <= 0 || session.mode != _TwitchAdGuardMode.auto) {
      return;
    }
    final groups = session.autoGroups.take(count).toList(growable: false);
    for (final group in groups) {
      unawaited(() async {
        try {
          final selected = await _selectPlayablePlaylist(
            group.candidates,
            session: session,
          );
          if (selected == null || selected.hadAds || selected.segmentCount <= 0) {
            return;
          }
          final warmAssetIds = <String>[];
          final playlist = _rewritePlaylist(
            session: session,
            sourceUrl: selected.candidate.playlistUrl,
            headers: selected.candidate.headers,
            text: selected.text,
            stripPrefetch: selected.hadAds,
            warmAssetIds: warmAssetIds,
          );
          final stickyTtl = _d.twitchVariantPlaylistStickyTtl;
          if (stickyTtl > Duration.zero) {
            session.variantPlaylistByGroup[group.id] = playlist;
            session.variantPlaylistUntilByGroup[group.id] = DateTime.now().add(
              stickyTtl,
            );
          }
          final warmLimit = _d.twitchAssetWarmPrefetchLimit;
          if (warmLimit > 0) {
            session.warmAssets(warmAssetIds.take(warmLimit), _prefetchAsset);
          }
          if (_platformAdapter.kDebugMode) {
            _platformAdapter.debugPrint(
              '[TwitchAdGuardProxy] prewarm ok group=${group.id} '
              'segs=${selected.segmentCount}',
            );
          }
        } catch (_) {
          // Best-effort only.
        }
      }());
    }
  }

  Future<_TwitchLoadedPlaylist?> _selectPlayablePlaylist(
    List<TwitchPlaybackCandidate> candidates, {
    _TwitchAdGuardSession? session,
  }) async {
    // Sticky: reuse a known-good no-ad candidate without full multi-probe.
    // Mobile release had no sticky candidate path.
    if (_d.twitchEnableStickyCandidate) {
      final sticky = session?.stickyCandidate;
      final stickyUntil = session?.stickyCandidateUntil;
      if (sticky != null &&
          stickyUntil != null &&
          DateTime.now().isBefore(stickyUntil)) {
        final stickyIndex = candidates.indexWhere(
          (candidate) =>
              candidate.playlistUrl == sticky.playlistUrl &&
              candidate.playerType == sticky.playerType &&
              candidate.lineLabel == sticky.lineLabel,
        );
        if (stickyIndex >= 0) {
          final loaded = await _loadCandidatePlaylist(
            candidates[stickyIndex],
            candidateIndex: stickyIndex,
          );
          if (loaded != null && !loaded.hadAds && loaded.segmentCount > 0) {
            session?.rememberStickyCandidate(sticky, ttl: _d.twitchStickyCandidateTtl);
            if (_platformAdapter.kDebugMode) {
              _platformAdapter.debugPrint(
                '[TwitchAdGuardProxy] sticky hit '
                'playerType=${sticky.playerType} line=${sticky.lineLabel}',
              );
            }
            return loaded;
          }
          session?.clearStickyCandidate();
        }
      }
    }

    for (var attempt = 0; attempt < _maxPlaylistProbeAttempts; attempt += 1) {
      final pending = <int, Future<_TwitchPlaylistProbeEvent>>{
        for (var index = 0; index < candidates.length; index += 1)
          index: _loadCandidatePlaylist(
            candidates[index],
            candidateIndex: index,
          )
              .timeout(_playlistCandidateProbeTimeout, onTimeout: () => null)
              .then(
                (playlist) => _TwitchPlaylistProbeEvent.playlist(
                  index: index,
                  playlist: playlist,
                ),
              ),
      };
      final loadedByIndex = List<_TwitchLoadedPlaylist?>.filled(
        candidates.length,
        null,
      );
      var hedgeSequence = 0;
      int? activeHedgeSequence;
      int? hedgeTargetIndex;
      Future<_TwitchPlaylistProbeEvent>? hedgeFuture;
      while (pending.isNotEmpty || hedgeFuture != null) {
        final event = await Future.any<_TwitchPlaylistProbeEvent>([
          ...pending.values,
          if (hedgeFuture != null) hedgeFuture,
        ]);
        if (event.index != null) {
          pending.remove(event.index);
          final playlist = event.playlist;
          if (playlist != null) {
            loadedByIndex[event.index!] = playlist;
          }
        } else if (event.hedgeSequence != activeHedgeSequence) {
          continue;
        }
        final bestPlayable = _bestPlayableLoadedPlaylist(loadedByIndex);
        if (bestPlayable == null) {
          continue;
        }
        final hasHigherPriorityPending = pending.keys.any(
          (index) => index < bestPlayable.candidateIndex,
        );
        if (!hasHigherPriorityPending) {
          if (!bestPlayable.hadAds) {
            session?.rememberStickyCandidate(bestPlayable.candidate);
          }
          return bestPlayable;
        }
        if (event.hedgeSequence == activeHedgeSequence &&
            hedgeTargetIndex == bestPlayable.candidateIndex) {
          if (!bestPlayable.hadAds) {
            session?.rememberStickyCandidate(bestPlayable.candidate);
          }
          return bestPlayable;
        }
        if (hedgeTargetIndex != bestPlayable.candidateIndex) {
          hedgeTargetIndex = bestPlayable.candidateIndex;
          activeHedgeSequence = ++hedgeSequence;
          final sequence = activeHedgeSequence;
          hedgeFuture = Future.delayed(
            _playlistPlayableSelectionHedgeDelay,
          ).then((_) => _TwitchPlaylistProbeEvent.hedge(sequence));
        }
      }
      final loaded = [
        for (final playlist in loadedByIndex)
          if (playlist != null) playlist,
      ];
      final fallback = _selectBestAdFallback(loaded);
      if (fallback != null) {
        if (fallback.segmentCount > 0 ||
            attempt >= _maxPlaylistProbeAttempts - 1) {
          // Do not sticky ad-bearing fallbacks — keep probing next refresh.
          return fallback;
        }
      }
      if (attempt < _maxPlaylistProbeAttempts - 1) {
        await Future<void>.delayed(_playlistProbeRetryDelay);
      }
    }
    return null;
  }

  _TwitchLoadedPlaylist? _bestPlayableLoadedPlaylist(
    List<_TwitchLoadedPlaylist?> loadedByIndex,
  ) {
    for (final playlist in loadedByIndex) {
      if (playlist == null) {
        continue;
      }
      if (!playlist.hadAds && playlist.segmentCount > 0) {
        return playlist;
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
      if (_platformAdapter.kDebugMode) {
        _platformAdapter.debugPrint(
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
      if (_platformAdapter.kDebugMode) {
        _platformAdapter.debugPrint(
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
      final liveSegmentCompare = right.segmentCount.compareTo(
        left.segmentCount,
      );
      if (liveSegmentCompare != 0) {
        return liveSegmentCompare;
      }
      final playerTypeCompare = _adFallbackPlayerTypePriority(
        left.candidate.playerType,
      ).compareTo(_adFallbackPlayerTypePriority(right.candidate.playerType));
      if (playerTypeCompare != 0) {
        return playerTypeCompare;
      }
      final codecCompare = _codecPriority(
        left.candidate.codecs,
      ).compareTo(_codecPriority(right.candidate.codecs));
      if (codecCompare != 0) {
        return codecCompare;
      }
      final bandwidthCompare = left.candidate.bandwidth.compareTo(
        right.candidate.bandwidth,
      );
      if (bandwidthCompare != 0) {
        return bandwidthCompare;
      }
      return left.candidateIndex.compareTo(right.candidateIndex);
    });
    for (final playlist in ordered) {
      if (playlist.segmentCount > 0) {
        return playlist;
      }
    }
    return null;
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
    return utf8.decode(
      await response.fold<List<int>>(
        <int>[],
        (buffer, chunk) => buffer..addAll(chunk),
      ),
    );
  }

  String _rewritePlaylist({
    required _TwitchAdGuardSession session,
    required String sourceUrl,
    required Map<String, String> headers,
    required String text,
    required bool stripPrefetch,
    List<String>? warmAssetIds,
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
            warmAssetIds: warmAssetIds,
          ),
        );
        continue;
      }
      if (line.contains('URI="')) {
        rewritten.add(
          line.replaceAllMapped(
            RegExp(r'URI="([^"]+)"'),
            (match) =>
                'URI="${_registerAssetUrl(session: session, baseUrl: sourceUrl, rawUrl: match.group(1) ?? '', headers: headers, warmAssetIds: warmAssetIds)}"',
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
    List<String>? warmAssetIds,
  }) {
    final endpoint = _endpoint;
    if (endpoint == null) {
      return rawUrl;
    }
    final absoluteUrl = Uri.parse(baseUrl).resolve(rawUrl).toString();
    final assetId = session.registerAsset(url: absoluteUrl, headers: headers);
    warmAssetIds?.add(assetId);
    return endpoint
        .replace(path: '${endpoint.path}/${session.id}/asset/$assetId')
        .toString();
  }

  Future<void> _pipeAsset(
    TwitchProxyResponseGate gate, {
    required _TwitchAdGuardSession session,
    required String assetId,
    required _TwitchAdGuardAsset asset,
  }) async {
    final cached = session.cachedBytes[assetId];
    if (cached != null) {
      session.touchCachedBytes(assetId);
      await gate.writeBytes(
        statusCode: HttpStatus.ok,
        bytes: cached.bytes,
        contentType: cached.contentType,
      );
      return;
    }

    final request = await _client.getUrl(Uri.parse(asset.url));
    asset.headers.forEach(request.headers.set);
    final upstream = await request.close();
    final contentType = upstream.headers.contentType;
    final cacheControl = upstream.headers.value(HttpHeaders.cacheControlHeader);
    // Always stream to the player first (release-era pipe semantics).
    // Optionally collect bytes for warm/reuse — never block the demuxer on a
    // full-segment fold before the first chunk is written (phone underruns).
    final canByteCache =
        session.delivery.twitchEnableAssetByteCache &&
        session.delivery.twitchAssetBytesCacheLimit > 0;
    final contentLength = upstream.contentLength >= 0
        ? upstream.contentLength
        : null;
    if (upstream.statusCode != HttpStatus.ok) {
      await gate.pipeUpstream(
        statusCode: upstream.statusCode,
        upstream: upstream,
        contentType: contentType,
        cacheControl: cacheControl,
        contentLength: contentLength,
      );
      return;
    }
    final collected = canByteCache ? <int>[] : null;
    await gate.streamChunks(
      statusCode: upstream.statusCode,
      contentType: contentType,
      cacheControl: cacheControl,
      contentLength: contentLength,
      chunks: upstream,
      onChunk: collected == null
          ? null
          : (chunk) {
              collected.addAll(chunk);
            },
    );
    if (collected != null && collected.isNotEmpty) {
      session.putCachedBytes(
        assetId,
        _TwitchCachedAssetBytes(
          bytes: Uint8List.fromList(collected),
          contentType: contentType,
        ),
      );
    }
  }

  Future<void> _prefetchAsset(
    _TwitchAdGuardSession session,
    String assetId,
  ) async {
    if (session.cachedBytes.containsKey(assetId)) {
      session.touchCachedBytes(assetId);
      return;
    }
    final asset = session.assets[assetId];
    if (asset == null) {
      return;
    }
    try {
      final request = await _client.getUrl(Uri.parse(asset.url));
      asset.headers.forEach(request.headers.set);
      final upstream = await request.close();
      if (upstream.statusCode != HttpStatus.ok) {
        await upstream.drain<void>();
        return;
      }
      final contentType = upstream.headers.contentType;
      final bytes = await upstream.fold<List<int>>(
        <int>[],
        (buffer, chunk) => buffer..addAll(chunk),
      );
      final payload = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
      session.putCachedBytes(
        assetId,
        _TwitchCachedAssetBytes(bytes: payload, contentType: contentType),
      );
    } catch (_) {
      // Best-effort warm; mpv will fetch on demand.
    }
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
      return _codecPriority(
        left.codecs,
      ).compareTo(_codecPriority(right.codecs));
    });
    return ordered;
  }

  List<_TwitchAdGuardVariantGroup> _selectStartupAutoGroups(
    List<_TwitchAdGuardVariantGroup> groups,
  ) {
    if (groups.length <= 1) {
      return groups;
    }
    final starterGroups = groups
        .where((group) {
          final height = group.height;
          if (height != null) {
            return height <= 480;
          }
          return group.sortOrder <= 480;
        })
        .toList(growable: false);
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
    return _platformAdapter.supportsHeadlessWebView;
  }
}

/// Single-commit gate for [HttpResponse] so cancel/error paths never throw
/// `Bad state: Header already sent` after a successful write has begun.
@visibleForTesting
class TwitchProxyResponseGate {
  TwitchProxyResponseGate(this.response);

  final HttpResponse response;
  bool _statusCommitted = false;
  bool _closed = false;

  bool get isClosed => _closed;
  bool get canSetStatus => !_statusCommitted && !_closed;

  Future<void> commitStatusAndClose(int statusCode) async {
    if (_closed) {
      return;
    }
    if (_statusCommitted) {
      await _closeQuietly();
      return;
    }
    try {
      response.statusCode = statusCode;
      _statusCommitted = true;
      await response.close();
      _closed = true;
    } catch (_) {
      await _closeQuietly();
    }
  }

  Future<void> writePlaylistBody(String body) async {
    if (_closed) {
      return;
    }
    try {
      if (!_statusCommitted) {
        response.statusCode = HttpStatus.ok;
        _statusCommitted = true;
      }
      response.headers.contentType = ContentType(
        'application',
        'vnd.apple.mpegurl',
        charset: 'utf-8',
      );
      response.write(body);
      await response.close();
      _closed = true;
    } catch (_) {
      await _closeQuietly();
    }
  }

  Future<void> writeBytes({
    required int statusCode,
    required List<int> bytes,
    ContentType? contentType,
  }) async {
    if (_closed) {
      return;
    }
    try {
      if (!_statusCommitted) {
        response.statusCode = statusCode;
        _statusCommitted = true;
      }
      response.contentLength = bytes.length;
      if (contentType != null) {
        response.headers.contentType = contentType;
      }
      response.add(bytes);
      await response.close();
      _closed = true;
    } catch (_) {
      await _closeQuietly();
    }
  }

  Future<void> pipeUpstream({
    required int statusCode,
    required HttpClientResponse upstream,
    ContentType? contentType,
    String? cacheControl,
    int? contentLength,
  }) async {
    if (_closed) {
      try {
        await upstream.drain<void>();
      } catch (_) {}
      return;
    }
    try {
      if (!_statusCommitted) {
        response.statusCode = statusCode;
        _statusCommitted = true;
      }
      if (contentType != null) {
        response.headers.contentType = contentType;
      }
      if (cacheControl != null && cacheControl.isNotEmpty) {
        response.headers.set(HttpHeaders.cacheControlHeader, cacheControl);
      }
      if (contentLength != null && contentLength >= 0) {
        response.contentLength = contentLength;
      }
      await upstream.pipe(response);
      _closed = true;
    } catch (_) {
      try {
        await upstream.drain<void>();
      } catch (_) {}
      await _closeQuietly();
    }
  }

  Future<void> streamChunks({
    required int statusCode,
    required Stream<List<int>> chunks,
    ContentType? contentType,
    String? cacheControl,
    int? contentLength,
    void Function(List<int> chunk)? onChunk,
  }) async {
    if (_closed) {
      // Mirror pipeUpstream: drain so the upstream response is not left pinned.
      try {
        await chunks.drain<void>();
      } catch (_) {}
      return;
    }
    try {
      if (!_statusCommitted) {
        response.statusCode = statusCode;
        _statusCommitted = true;
      }
      if (contentType != null) {
        response.headers.contentType = contentType;
      }
      if (cacheControl != null && cacheControl.isNotEmpty) {
        response.headers.set(HttpHeaders.cacheControlHeader, cacheControl);
      }
      if (contentLength != null && contentLength >= 0) {
        response.contentLength = contentLength;
      }
      await for (final chunk in chunks) {
        response.add(chunk);
        onChunk?.call(chunk);
      }
      await response.close();
      _closed = true;
    } catch (_) {
      try {
        await chunks.drain<void>();
      } catch (_) {}
      await _closeQuietly();
    }
  }

  Future<void> _closeQuietly() async {
    if (_closed) {
      return;
    }
    try {
      await response.close();
    } catch (_) {}
    _closed = true;
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

class _TwitchPlaylistProbeEvent {
  const _TwitchPlaylistProbeEvent._({
    this.index,
    this.playlist,
    this.hedgeSequence,
  });

  const _TwitchPlaylistProbeEvent.playlist({
    required int index,
    required _TwitchLoadedPlaylist? playlist,
  }) : this._(index: index, playlist: playlist);

  const _TwitchPlaylistProbeEvent.hedge(int hedgeSequence)
    : this._(hedgeSequence: hedgeSequence);

  final int? index;
  final _TwitchLoadedPlaylist? playlist;
  final int? hedgeSequence;
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
    required this.roomId,
    required this.id,
    required this.delivery,
    required List<TwitchPlaybackCandidate> candidates,
  }) : mode = _TwitchAdGuardMode.fixed,
       fixedCandidates = candidates,
       autoGroups = const [],
       groupsById = const {};

  _TwitchAdGuardSession.auto({
    required this.roomId,
    required this.id,
    required this.delivery,
    required List<_TwitchAdGuardVariantGroup> groups,
  }) : mode = _TwitchAdGuardMode.auto,
       fixedCandidates = const [],
       autoGroups = groups,
       groupsById = {for (final group in groups) group.id: group};

  final String roomId;
  final String id;
  final HlsProxyDeliveryKnobs delivery;
  final _TwitchAdGuardMode mode;
  final List<TwitchPlaybackCandidate> fixedCandidates;
  final List<_TwitchAdGuardVariantGroup> autoGroups;
  final Map<String, _TwitchAdGuardVariantGroup> groupsById;
  final Map<String, _TwitchAdGuardAsset> assets =
      <String, _TwitchAdGuardAsset>{};
  final Map<String, _TwitchCachedAssetBytes> cachedBytes =
      <String, _TwitchCachedAssetBytes>{};
  final Map<String, Future<void>> _pendingWarmAssets = <String, Future<void>>{};
  /// Rewritten media playlist per Auto group (skip CDN multi-probe on ABR hop).
  final Map<String, String> variantPlaylistByGroup = <String, String>{};
  final Map<String, DateTime> variantPlaylistUntilByGroup = <String, DateTime>{};

  DateTime lastAccessAt = DateTime.now();
  int _assetCounter = 0;
  TwitchPlaybackCandidate? stickyCandidate;
  DateTime? stickyCandidateUntil;

  void touch() {
    lastAccessAt = DateTime.now();
  }

  void rememberStickyCandidate(
    TwitchPlaybackCandidate candidate, {
    Duration? ttl,
  }) {
    if (!delivery.twitchEnableStickyCandidate) {
      return;
    }
    stickyCandidate = candidate;
    stickyCandidateUntil = DateTime.now().add(
      ttl ?? delivery.twitchStickyCandidateTtl,
    );
  }

  void clearStickyCandidate() {
    stickyCandidate = null;
    stickyCandidateUntil = null;
  }

  String registerAsset({
    required String url,
    required Map<String, String> headers,
  }) {
    for (final entry in assets.entries) {
      if (entry.value.url == url && _mapEquals(entry.value.headers, headers)) {
        return entry.key;
      }
    }
    final assetId = (++_assetCounter).toString();
    assets[assetId] = _TwitchAdGuardAsset(url: url, headers: headers);
    return assetId;
  }

  void putCachedBytes(String assetId, _TwitchCachedAssetBytes payload) {
    if (!delivery.twitchEnableAssetByteCache ||
        delivery.twitchAssetBytesCacheLimit <= 0) {
      return;
    }
    cachedBytes.remove(assetId);
    cachedBytes[assetId] = payload;
    while (cachedBytes.length > delivery.twitchAssetBytesCacheLimit) {
      cachedBytes.remove(cachedBytes.keys.first);
    }
  }

  void touchCachedBytes(String assetId) {
    final existing = cachedBytes.remove(assetId);
    if (existing == null) {
      return;
    }
    cachedBytes[assetId] = existing;
  }

  void warmAssets(
    Iterable<String> assetIds,
    Future<void> Function(_TwitchAdGuardSession session, String assetId) task,
  ) {
    for (final assetId in assetIds) {
      if (cachedBytes.containsKey(assetId) ||
          _pendingWarmAssets.containsKey(assetId)) {
        continue;
      }
      final future = task(this, assetId).whenComplete(() {
        _pendingWarmAssets.remove(assetId);
      });
      _pendingWarmAssets[assetId] = future;
      unawaited(future);
    }
  }
}

class _TwitchCachedAssetBytes {
  const _TwitchCachedAssetBytes({
    required this.bytes,
    required this.contentType,
  });

  final Uint8List bytes;
  final ContentType? contentType;
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
  const _TwitchAdGuardAsset({required this.url, required this.headers});

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

bool _mapEquals(Map<dynamic, dynamic>? a, Map<dynamic, dynamic>? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return false;
  if (a.length != b.length) return false;
  for (final key in a.keys) {
    if (!b.containsKey(key) || b[key] != a[key]) {
      return false;
    }
  }
  return true;
}
