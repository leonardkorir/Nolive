part of 'mpv_player.dart';

class MpvHlsManifestService {
  const MpvHlsManifestService();

  String buildSplitMasterPlaylistContent(PlaybackSource source) {
    return buildSplitHlsMasterPlaylistContent(source);
  }

  Future<File> writeSplitMasterPlaylistFile(PlaybackSource source) {
    return writeSplitHlsMasterPlaylistFile(source);
  }

  String rewriteManifestWithAbsoluteUris({
    required Uri playlistUri,
    required String manifest,
  }) {
    return rewriteHlsManifestWithAbsoluteUris(
      playlistUri: playlistUri,
      manifest: manifest,
    );
  }
}

extension MpvPlayerHlsManifestLifecycle on MpvPlayer {
  Future<_MpvOpenPlan> _resolveOpenPlan(PlaybackSource source) async {
    if (shouldInlineSplitHlsAudioIntoSource(source)) {
      final resolvedMasterFile =
          await maybeWriteResolvedSplitHlsMasterPlaylistFile(source);
      if (resolvedMasterFile != null) {
        _activeSyntheticPlaylistFile = resolvedMasterFile;
        return _MpvOpenPlan(
          mediaUri: resolvedMasterFile.uri,
          httpHeaders:
              _sharedHttpHeadersForSplitHls(source) ?? const <String, String>{},
          loadsAudioInsideMedia: true,
          strategy: 'resolved-inline-hls-master',
        );
      }
      if (shouldFallbackToSyntheticSplitMaster(source)) {
        final file = await writeSplitHlsMasterPlaylistFile(source);
        _activeSyntheticPlaylistFile = file;
        return _MpvOpenPlan(
          mediaUri: file.uri,
          httpHeaders:
              _sharedHttpHeadersForSplitHls(source) ?? const <String, String>{},
          loadsAudioInsideMedia: true,
          strategy: 'inline-hls-master',
        );
      }
    }
    final rewrittenManifestFile =
        await maybeWriteResolvedSingleSourceHlsPlaylistFile(source);
    if (rewrittenManifestFile != null) {
      _activeSyntheticPlaylistFile = rewrittenManifestFile;
      return _MpvOpenPlan(
        mediaUri: rewrittenManifestFile.uri,
        httpHeaders: source.headers,
        loadsAudioInsideMedia: false,
        strategy: 'resolved-hls-manifest',
      );
    }
    _activeSyntheticPlaylistFile = null;
    return _MpvOpenPlan(
      mediaUri: source.url,
      httpHeaders: source.headers,
      loadsAudioInsideMedia: false,
      strategy: source.externalAudio == null
          ? 'single-source'
          : 'external-audio',
    );
  }

  Future<void> _deleteSyntheticPlaylistFile(
    File? file, {
    bool preserveIfSameAsActive = false,
  }) async {
    if (file == null) {
      return;
    }
    if (preserveIfSameAsActive &&
        _activeSyntheticPlaylistFile?.path == file.path) {
      return;
    }
    try {
      final parent = file.parent;
      if (await file.exists()) {
        await file.delete();
      }
      if (await parent.exists()) {
        await parent.delete(recursive: true);
      }
    } catch (_) {
      // Best-effort cleanup for transient synthetic manifests.
    }
  }
}

class _MpvOpenPlan {
  const _MpvOpenPlan({
    required this.mediaUri,
    required this.httpHeaders,
    required this.loadsAudioInsideMedia,
    required this.strategy,
  });

  final Uri mediaUri;
  final Map<String, String> httpHeaders;
  final bool loadsAudioInsideMedia;
  final String strategy;
}

bool shouldForceSeekableForSource(
  PlaybackSource source, {
  bool isAndroid = false,
}) {
  if (source.url.host == '127.0.0.1' &&
      source.url.path.contains('/twitch-ad-guard/')) {
    return true;
  }
  // media_kit: Android open path does load→pause→seek; for live FLV
  // that seek fails and flashes black. force-seekable=yes suppresses it.
  if (isAndroid && _looksLikeLiveNonSeekableSource(source)) {
    return true;
  }
  return false;
}

bool _looksLikeLiveNonSeekableSource(PlaybackSource source) {
  final path = source.url.path.toLowerCase();
  final host = source.url.host.toLowerCase();
  if (path.endsWith('.flv') || path.contains('.flv?')) {
    return true;
  }
  if (path.contains('.m3u8') || path.endsWith('.m3u8')) {
    return true;
  }
  // Common live CDNs without a file extension in the path.
  if (host.contains('douyucdn') ||
      host.contains('huya.com') ||
      host.contains('bilivideo') ||
      host.contains('douyin') ||
      host.contains('live-')) {
    return true;
  }
  return source.bufferProfile == PlaybackBufferProfile.heavyStreamStable ||
      source.bufferProfile == PlaybackBufferProfile.edgeLowLatencyHls ||
      source.bufferProfile == PlaybackBufferProfile.loopbackStableHls ||
      source.bufferProfile == PlaybackBufferProfile.chaturbateLlHlsProxyStable;
}

bool shouldInlineSplitHlsAudioIntoSource(PlaybackSource source) {
  // CB/mmcdn split LL-HLS is more stable when mpv demuxes audio + video inside
  // a single HLS session instead of attaching audio afterwards via audio-add.
  // This now applies to both legacy live-hls and v1/edge split LL-HLS, but we
  // keep single-source master localization restricted to true edge masters.
  return _looksLikeMmcdnSplitLowLatencyHlsSource(source) &&
      _sharedHttpHeadersForSplitHls(source) != null;
}

bool shouldFallbackToSyntheticSplitMaster(PlaybackSource source) {
  // The simplified synthetic master drops LL-HLS attributes that the updated
  // /v1/edge streams depend on. Keep it only for older split-HLS layouts.
  return !_looksLikeMmcdnEdgeSplitHls(source.url);
}

bool shouldUseAudioFilesPropertyForSource(PlaybackSource source) {
  // `audio-files` is a path-list option in mpv. Passing HTTPS URLs via the
  // string property API causes the URL to be tokenized as separate entries
  // (`https`, `//host/...`), which matches the "Can not open external file
  // https." failures seen in the latest Chaturbate logs. Keep split HLS audio
  // on either the synthetic master or runtime `audio-add` paths instead.
  return false;
}

Map<String, String>? _sharedHttpHeadersForSplitHls(PlaybackSource source) {
  final externalAudio = source.externalAudio;
  if (externalAudio == null) {
    return null;
  }
  if (source.headers.isEmpty && externalAudio.headers.isEmpty) {
    return const <String, String>{};
  }
  if (source.headers.isEmpty) {
    return Map<String, String>.unmodifiable(
      Map<String, String>.from(externalAudio.headers),
    );
  }
  if (externalAudio.headers.isEmpty) {
    return Map<String, String>.unmodifiable(
      Map<String, String>.from(source.headers),
    );
  }
  if (_sameHttpHeaders(source.headers, externalAudio.headers)) {
    return Map<String, String>.unmodifiable(
      Map<String, String>.from(source.headers),
    );
  }
  return null;
}

bool _sameHttpHeaders(Map<String, String> left, Map<String, String> right) {
  if (identical(left, right)) {
    return true;
  }
  if (left.length != right.length) {
    return false;
  }
  for (final entry in left.entries) {
    if (right[entry.key] != entry.value) {
      return false;
    }
  }
  return true;
}

String buildSplitHlsMasterPlaylistContent(PlaybackSource source) {
  final externalAudio = source.externalAudio;
  if (externalAudio == null) {
    throw ArgumentError(
      'Split HLS master playlist requires an external audio source.',
    );
  }
  final audioLabel = _escapeHlsQuotedString(
    externalAudio.label?.trim().isNotEmpty == true
        ? externalAudio.label!.trim()
        : 'external',
  );
  final videoUrl = source.url.toString();
  final audioUrl = _escapeHlsQuotedString(externalAudio.url.toString());
  final bandwidth = _estimateSyntheticHlsBandwidth(source);
  return <String>[
    '#EXTM3U',
    '#EXT-X-VERSION:6',
    '#EXT-X-INDEPENDENT-SEGMENTS',
    '#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",NAME="$audioLabel",DEFAULT=YES,AUTOSELECT=YES,URI="$audioUrl"',
    '#EXT-X-STREAM-INF:BANDWIDTH=$bandwidth,AUDIO="audio"',
    videoUrl,
  ].join('\n');
}

Future<File> writeSplitHlsMasterPlaylistFile(PlaybackSource source) async {
  final manifest = buildSplitHlsMasterPlaylistContent(source);
  return writeSyntheticHlsPlaylistFile(
    manifest,
    prefix: 'nolive-mpv-hls-',
    fileName: 'inline-master.m3u8',
  );
}

Future<File?> maybeWriteResolvedSplitHlsMasterPlaylistFile(
  PlaybackSource source,
) async {
  final masterPlaylistUrl = source.masterPlaylistUrl;
  if (masterPlaylistUrl == null || source.externalAudio == null) {
    return null;
  }
  final embeddedManifest = source.masterPlaylistContent?.trim() ?? '';
  if (embeddedManifest.isNotEmpty) {
    final rewritten = rewriteHlsManifestWithAbsoluteUris(
      playlistUri: masterPlaylistUrl,
      manifest: embeddedManifest,
    );
    if (!rewritten.contains('#EXT-X-STREAM-INF:')) {
      return null;
    }
    final selectedManifest = buildResolvedSelectedSplitHlsMasterPlaylistContent(
      source: source,
      manifest: rewritten,
    );
    return writeSyntheticHlsPlaylistFile(
      selectedManifest,
      prefix: 'nolive-mpv-hls-',
      fileName: 'resolved-inline-master.m3u8',
    );
  }
  try {
    final manifest = await _fetchHlsManifest(
      masterPlaylistUrl,
      headers: _sharedHttpHeadersForSplitHls(source) ?? source.headers,
    );
    if (!manifest.contains('#EXT-X-STREAM-INF:')) {
      return null;
    }
    final rewritten = rewriteHlsManifestWithAbsoluteUris(
      playlistUri: masterPlaylistUrl,
      manifest: manifest,
    );
    final selectedManifest = buildResolvedSelectedSplitHlsMasterPlaylistContent(
      source: source,
      manifest: rewritten,
    );
    return writeSyntheticHlsPlaylistFile(
      selectedManifest,
      prefix: 'nolive-mpv-hls-',
      fileName: 'resolved-inline-master.m3u8',
    );
  } catch (_) {
    return null;
  }
}

bool shouldRewriteSingleSourceHlsManifest(PlaybackSource source) {
  if (source.externalAudio != null || !_looksLikeHlsPlaylist(source.url)) {
    return false;
  }
  final manifestUri = source.masterPlaylistUrl ?? source.url;
  if (_hasEmbeddedGooglevideoMasterPlaylist(source)) {
    return true;
  }
  return _looksLikeMmcdnEdgeLowLatencyMasterUri(source.url) ||
      _looksLikeMmcdnEdgeLowLatencyMasterUri(manifestUri) ||
      _looksLikeDoppioLowLatencyHlsUri(source.url) ||
      _looksLikeDoppioLowLatencyHlsUri(manifestUri);
}

bool _isSingleSourceLocalizedLowLatencyMaster(PlaybackSource source) {
  if (source.externalAudio != null) {
    return false;
  }
  final manifestUri = source.masterPlaylistUrl ?? source.url;
  return _looksLikeMmcdnEdgeLowLatencyMasterUri(source.url) ||
      _looksLikeMmcdnEdgeLowLatencyMasterUri(manifestUri) ||
      _looksLikeDoppioLowLatencyHlsUri(source.url) ||
      _looksLikeDoppioLowLatencyHlsUri(manifestUri);
}

String rewriteHlsManifestWithAbsoluteUris({
  required Uri playlistUri,
  required String manifest,
}) {
  final lines = manifest.split('\n');
  final rewritten = <String>[];
  String? pendingMouflonUri;

  for (final originalLine in lines) {
    final trimmed = originalLine.trim();
    if (trimmed.startsWith('#EXT-X-MOUFLON:URI:')) {
      pendingMouflonUri = trimmed.substring('#EXT-X-MOUFLON:URI:'.length);
      continue;
    }
    final line = _rewriteHlsManifestLine(
      playlistUri: playlistUri,
      line: originalLine,
      pendingMouflonUri: pendingMouflonUri,
    );
    if (pendingMouflonUri != null &&
        _consumedPendingMouflonUri(originalLine.trim())) {
      pendingMouflonUri = null;
    }
    rewritten.add(line);
  }

  return rewritten.join('\n');
}

String buildResolvedSelectedSplitHlsMasterPlaylistContent({
  required PlaybackSource source,
  required String manifest,
}) {
  final externalAudio = source.externalAudio;
  if (externalAudio == null) {
    throw ArgumentError(
      'Resolved split HLS master playlist requires an external audio source.',
    );
  }
  final lines = manifest.split('\n');
  String? versionLine;
  var hasIndependentSegments = false;
  final audioLinesByGroupId = <String, String>{};
  String? matchedAudioLine;
  String? matchedStreamInfLine;
  String? matchedVideoUri;
  String? matchedAudioGroupId;

  for (var index = 0; index < lines.length; index += 1) {
    final trimmed = lines[index].trim();
    if (trimmed.isEmpty) {
      continue;
    }
    if (versionLine == null && trimmed.startsWith('#EXT-X-VERSION:')) {
      versionLine = trimmed;
      continue;
    }
    if (trimmed == '#EXT-X-INDEPENDENT-SEGMENTS') {
      hasIndependentSegments = true;
      continue;
    }
    if (trimmed.startsWith('#EXT-X-MEDIA:TYPE=AUDIO')) {
      final audioGroupId = _extractHlsAttributeValue(
        trimmed,
        'GROUP-ID',
      )?.trim();
      if (audioGroupId != null && audioGroupId.isNotEmpty) {
        audioLinesByGroupId[audioGroupId] = trimmed;
      }
      final audioUri = _extractHlsAttributeValue(trimmed, 'URI');
      if (_hlsUrisMatch(audioUri, externalAudio.url.toString())) {
        matchedAudioLine = trimmed;
      }
      continue;
    }
    if (trimmed.startsWith('#EXT-X-STREAM-INF:')) {
      final videoUri = _nextHlsUriLine(lines, startIndex: index + 1);
      if (!_hlsUrisMatch(videoUri, source.url.toString())) {
        continue;
      }
      matchedStreamInfLine = trimmed;
      matchedVideoUri = videoUri;
      final audioGroupId = _extractHlsAttributeValue(trimmed, 'AUDIO')?.trim();
      if (audioGroupId != null && audioGroupId.isNotEmpty) {
        matchedAudioGroupId = audioGroupId;
      }
    }
  }

  if (matchedAudioGroupId != null && matchedAudioGroupId.isNotEmpty) {
    matchedAudioLine =
        audioLinesByGroupId[matchedAudioGroupId] ?? matchedAudioLine;
  }

  if (matchedAudioLine == null ||
      matchedStreamInfLine == null ||
      matchedVideoUri == null) {
    return buildSplitHlsMasterPlaylistContent(source);
  }

  return <String>[
    '#EXTM3U',
    versionLine ?? '#EXT-X-VERSION:6',
    if (hasIndependentSegments) '#EXT-X-INDEPENDENT-SEGMENTS',
    matchedAudioLine,
    matchedStreamInfLine,
    matchedVideoUri,
  ].join('\n');
}

Future<File> writeSyntheticHlsPlaylistFile(
  String manifest, {
  required String prefix,
  required String fileName,
}) async {
  final directory = await Directory.systemTemp.createTemp(prefix);
  final file = File('${directory.path}${Platform.pathSeparator}$fileName');
  await file.writeAsString(manifest, encoding: utf8, flush: true);
  return file;
}

Future<File?> maybeWriteResolvedSingleSourceHlsPlaylistFile(
  PlaybackSource source,
) async {
  if (!shouldRewriteSingleSourceHlsManifest(source)) {
    return null;
  }
  final manifestUri = source.masterPlaylistUrl ?? source.url;
  try {
    final embeddedManifest = source.masterPlaylistContent?.trim() ?? '';
    final manifest = embeddedManifest.isNotEmpty
        ? embeddedManifest
        : await _fetchHlsManifest(manifestUri, headers: source.headers);
    final rewritten = rewriteHlsManifestWithAbsoluteUris(
      playlistUri: manifestUri,
      manifest: manifest,
    );
    if (rewritten == manifest &&
        !shouldAlwaysLocalizeSingleSourceHlsManifest(source)) {
      return null;
    }
    return writeSyntheticHlsPlaylistFile(
      rewritten,
      prefix: 'nolive-mpv-hls-',
      fileName: 'resolved-master.m3u8',
    );
  } catch (_) {
    return null;
  }
}

bool shouldAlwaysLocalizeSingleSourceHlsManifest(PlaybackSource source) {
  final manifestUri = source.masterPlaylistUrl ?? source.url;
  if (_hasEmbeddedGooglevideoMasterPlaylist(source)) {
    return true;
  }
  return _looksLikeMmcdnEdgeLowLatencyMasterUri(source.url) ||
      _looksLikeMmcdnEdgeLowLatencyMasterUri(manifestUri) ||
      _looksLikeDoppioLowLatencyHlsUri(source.url) ||
      _looksLikeDoppioLowLatencyHlsUri(manifestUri);
}

bool _hasEmbeddedGooglevideoMasterPlaylist(PlaybackSource source) {
  final embeddedManifest = source.masterPlaylistContent?.trim() ?? '';
  if (!embeddedManifest.contains('#EXT-X-STREAM-INF:')) {
    return false;
  }
  final manifestUri = source.masterPlaylistUrl ?? source.url;
  return _looksLikeGooglevideoHlsUri(source.url) ||
      _looksLikeGooglevideoHlsUri(manifestUri);
}

Future<String> _fetchHlsManifest(
  Uri uri, {
  required Map<String, String> headers,
}) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(uri);
    headers.forEach(request.headers.set);
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        'Unexpected HLS manifest status ${response.statusCode}',
        uri: uri,
      );
    }
    return await response.transform(utf8.decoder).join();
  } finally {
    client.close(force: true);
  }
}

const _hlsUriAttributePattern = r'URI=("([^"]*)"|([^,]+))';

String? _extractHlsAttributeValue(String line, String attribute) {
  final match = RegExp('$attribute=("([^"]*)"|([^,]+))').firstMatch(line);
  if (match == null) {
    return null;
  }
  return match.group(2) ?? match.group(3);
}

String? _nextHlsUriLine(List<String> lines, {required int startIndex}) {
  for (var index = startIndex; index < lines.length; index += 1) {
    final trimmed = lines[index].trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) {
      continue;
    }
    return trimmed;
  }
  return null;
}

bool _hlsUrisMatch(String? left, String? right) {
  final normalizedLeft = left?.trim() ?? '';
  final normalizedRight = right?.trim() ?? '';
  if (normalizedLeft.isEmpty || normalizedRight.isEmpty) {
    return false;
  }
  if (normalizedLeft == normalizedRight) {
    return true;
  }
  final leftKey = _canonicalHlsUriMatchKey(normalizedLeft);
  final rightKey = _canonicalHlsUriMatchKey(normalizedRight);
  if (leftKey != null && leftKey == rightKey) {
    return true;
  }
  final leftLeaf = _hlsUriLeafName(normalizedLeft);
  final rightLeaf = _hlsUriLeafName(normalizedRight);
  return leftLeaf.isNotEmpty && leftLeaf == rightLeaf;
}

String? _canonicalHlsUriMatchKey(String raw) {
  final uri = Uri.tryParse(raw);
  if (uri == null) {
    return null;
  }
  final normalizedPairs = <String>[];
  final keys = uri.queryParametersAll.keys.toList()..sort();
  for (final key in keys) {
    final values = [...?uri.queryParametersAll[key]]..sort();
    if (values.isEmpty) {
      normalizedPairs.add(key);
      continue;
    }
    for (final value in values) {
      normalizedPairs.add('$key=$value');
    }
  }
  return '${uri.path}?${normalizedPairs.join('&')}';
}

String _hlsUriLeafName(String raw) {
  final uri = Uri.tryParse(raw);
  if (uri != null && uri.pathSegments.isNotEmpty) {
    return uri.pathSegments.last;
  }
  final index = raw.lastIndexOf('/');
  if (index >= 0 && index + 1 < raw.length) {
    return raw.substring(index + 1);
  }
  return raw;
}

String _rewriteHlsManifestLine({
  required Uri playlistUri,
  required String line,
  String? pendingMouflonUri,
}) {
  if (pendingMouflonUri != null && line.trim().startsWith('#EXT-X-PART:')) {
    final replacedPartLine = line.replaceAllMapped(
      RegExp(_hlsUriAttributePattern),
      (match) {
        final resolved = playlistUri.resolve(pendingMouflonUri).toString();
        if (match.group(2) != null) {
          return 'URI="${_escapeHlsQuotedString(resolved)}"';
        }
        return 'URI=$resolved';
      },
    );
    return replacedPartLine;
  }
  final replacedAttributes = line.replaceAllMapped(
    RegExp(_hlsUriAttributePattern),
    (match) {
      final raw = match.group(2) ?? match.group(3) ?? '';
      if (raw.isEmpty) {
        return match.group(0) ?? '';
      }
      final resolved = playlistUri.resolve(raw).toString();
      if (match.group(2) != null) {
        return 'URI="${_escapeHlsQuotedString(resolved)}"';
      }
      return 'URI=$resolved';
    },
  );
  final trimmed = replacedAttributes.trim();
  if (trimmed.isEmpty || trimmed.startsWith('#')) {
    return replacedAttributes;
  }
  if (pendingMouflonUri != null) {
    return playlistUri.resolve(pendingMouflonUri).toString();
  }
  return playlistUri.resolve(trimmed).toString();
}

bool _consumedPendingMouflonUri(String trimmedLine) {
  if (trimmedLine.isEmpty) {
    return false;
  }
  if (trimmedLine.startsWith('#EXT-X-PART:')) {
    return true;
  }
  return !trimmedLine.startsWith('#');
}

bool _looksLikeHlsPlaylist(Uri uri) {
  final path = uri.path.toLowerCase();
  if (path.endsWith('.m3u8') || path.contains('chunklist_')) {
    return true;
  }
  return uri.queryParameters.values.any(
    (value) => value.toLowerCase().contains('.m3u8'),
  );
}

bool _looksLikeLiveHlsSource(PlaybackSource source) {
  if (_looksLikeHlsPlaylist(source.url)) {
    return true;
  }
  final externalAudio = source.externalAudio;
  return externalAudio != null && _looksLikeHlsPlaylist(externalAudio.url);
}

bool _isMmcdnHlsUri(Uri uri) {
  return uri.host.toLowerCase().endsWith('live.mmcdn.com') &&
      _looksLikeHlsPlaylist(uri);
}

bool _looksLikeMmcdnEdgeSplitHls(Uri uri) {
  if (!_isMmcdnHlsUri(uri)) {
    return false;
  }
  final path = uri.path.toLowerCase();
  return path.contains('/v1/edge/streams/') &&
      path.contains('chunklist_') &&
      path.endsWith('.m3u8');
}

bool _looksLikeMmcdnLowLatencyHlsUri(Uri uri) {
  if (!_isMmcdnHlsUri(uri)) {
    return false;
  }
  final path = uri.path.toLowerCase();
  if (path.contains('/v1/edge/streams/')) {
    return path.contains('llhls') || path.endsWith('/llhls.m3u8');
  }
  if (path.contains('/live-hls/amlst:')) {
    return _looksLikeLowLatencyChunklist(uri);
  }
  return false;
}

bool _looksLikeChaturbateLoopbackProxySource(PlaybackSource source) {
  final uri = source.url;
  final host = uri.host.toLowerCase();
  final isLoopback =
      host == '127.0.0.1' ||
      host == 'localhost' ||
      host == '::1' ||
      host == '[::1]';
  return isLoopback && uri.path.contains('/chaturbate-llhls/');
}

bool _looksLikeStripchatLoopbackProxySource(PlaybackSource source) {
  final uri = source.url;
  final host = uri.host.toLowerCase();
  final isLoopback =
      host == '127.0.0.1' ||
      host == 'localhost' ||
      host == '::1' ||
      host == '[::1]';
  return isLoopback && uri.path.contains('/stripchat-llhls/');
}

bool _looksLikeMmcdnEdgeLowLatencyMasterUri(Uri uri) {
  if (!_isMmcdnHlsUri(uri)) {
    return false;
  }
  final path = uri.path.toLowerCase();
  return path.contains('/v1/edge/streams/') && path.endsWith('/llhls.m3u8');
}

bool _looksLikeDoppioLowLatencyHlsUri(Uri uri) {
  final host = uri.host.toLowerCase();
  if (!(host.startsWith('media-hls.') || host.startsWith('edge-hls.'))) {
    return false;
  }
  final path = uri.path.toLowerCase();
  if (!path.endsWith('.m3u8')) {
    return false;
  }
  return uri.queryParameters['playlistType']?.toLowerCase() == 'lowlatency';
}

bool _looksLikeMmcdnSplitLowLatencyHlsSource(PlaybackSource source) {
  final externalAudio = source.externalAudio;
  if (externalAudio == null) {
    return false;
  }
  return _looksLikeMmcdnLowLatencyHlsUri(source.url) &&
      _looksLikeMmcdnLowLatencyHlsUri(externalAudio.url) &&
      _looksLikeLowLatencyChunklist(source.url) &&
      _looksLikeLowLatencyChunklist(externalAudio.url);
}

bool shouldAllowUnsafePlaylistsForSource(PlaybackSource source) {
  if (_isMmcdnHlsUri(source.url) ||
      _looksLikeGooglevideoHlsUri(source.url) ||
      _looksLikeDoppioLowLatencyHlsUri(source.url) ||
      _looksLikeStripchatLoopbackProxySource(source)) {
    return true;
  }
  final masterPlaylistUrl = source.masterPlaylistUrl;
  if (masterPlaylistUrl != null &&
      (_isMmcdnHlsUri(masterPlaylistUrl) ||
          _looksLikeGooglevideoHlsUri(masterPlaylistUrl) ||
          _looksLikeDoppioLowLatencyHlsUri(masterPlaylistUrl))) {
    return true;
  }
  final externalAudio = source.externalAudio;
  return externalAudio != null &&
      (_isMmcdnHlsUri(externalAudio.url) ||
          _looksLikeGooglevideoHlsUri(externalAudio.url) ||
          _looksLikeDoppioLowLatencyHlsUri(externalAudio.url));
}

bool _looksLikeGooglevideoHlsUri(Uri uri) {
  final host = uri.host.toLowerCase();
  final isGooglevideoHost =
      host == 'manifest.googlevideo.com' || host.endsWith('.googlevideo.com');
  return isGooglevideoHost && _looksLikeHlsPlaylist(uri);
}

bool _looksLikeLiveFlv(Uri uri) {
  final host = uri.host.toLowerCase();
  if (host.split(RegExp(r'[\.\-]')).contains('flv')) {
    return true;
  }
  final path = uri.path.toLowerCase();
  if (path.endsWith('.flv') || path.contains('/live-bvc/')) {
    return true;
  }
  return uri.queryParameters.values.any(
    (value) => value.toLowerCase().contains('.flv'),
  );
}

bool _looksLikeLowLatencyChunklist(Uri uri) {
  final path = uri.path.toLowerCase();
  if (path.contains('chunklist_') || path.contains('llhls')) {
    return true;
  }
  return uri.queryParameters.keys.any(
        (key) => key.toLowerCase().contains('llhls'),
      ) ||
      uri.queryParameters.values.any(
        (value) => value.toLowerCase().contains('llhls'),
      );
}

int _estimateSyntheticHlsBandwidth(PlaybackSource source) {
  final candidates = <int>[
    _extractBandwidthFromUri(source.url),
    if (source.externalAudio != null)
      _extractBandwidthFromUri(source.externalAudio!.url),
  ].where((item) => item > 0);
  final total = candidates.fold<int>(0, (sum, item) => sum + item);
  return total > 0 ? total : 1;
}

int _extractBandwidthFromUri(Uri uri) {
  final queryBandwidth =
      int.tryParse(uri.queryParameters['bandwidth'] ?? '') ??
      int.tryParse(uri.queryParameters['bw'] ?? '');
  if (queryBandwidth != null && queryBandwidth > 0) {
    return queryBandwidth;
  }
  final path = uri.path.toLowerCase();
  final match = RegExp(r'(?:^|[_-])b(\d+)(?:[_-]|$)').firstMatch(path);
  final pathBandwidth = int.tryParse(match?.group(1) ?? '');
  return pathBandwidth != null && pathBandwidth > 0 ? pathBandwidth : 0;
}

String _escapeHlsQuotedString(String value) {
  return value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
}
