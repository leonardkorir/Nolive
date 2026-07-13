import '../provider_json.dart';
import 'youtube_api_client.dart';
import 'youtube_page_parser.dart';
import 'youtube_playback_source.dart';

class YouTubePlaybackExtractor {
  static const int _maxContextMergeDepth = 64;

  static Map<String, dynamic> extractPlayerClientContext(
    YouTubePageBootstrap bootstrap,
  ) {
    final context = _asMap(bootstrap.innertubeContext);
    final clientContext = _asMap(context['client']);
    if (clientContext.isNotEmpty) {
      return clientContext;
    }
    return context;
  }

  static Map<String, dynamic> mergeMaps(
    Map<String, dynamic> base,
    Map<String, dynamic> overlay, {
    int depth = 0,
  }) {
    final merged = <String, dynamic>{...base};
    for (final entry in overlay.entries) {
      final baseValue = merged[entry.key];
      final overlayValue = entry.value;
      if (baseValue is Map && overlayValue is Map) {
        if (depth >= _maxContextMergeDepth) {
          merged[entry.key] = <String, dynamic>{
            ..._asMap(baseValue),
            ..._asMap(overlayValue),
          };
          continue;
        }
        merged[entry.key] = mergeMaps(
          _asMap(baseValue),
          _asMap(overlayValue),
          depth: depth + 1,
        );
        continue;
      }
      merged[entry.key] = overlayValue;
    }
    return merged;
  }

  static Map<String, dynamic> buildPlayerClientContext({
    required Map<String, dynamic> baseContext,
    required YouTubePlayerClientProfile clientProfile,
    required String sourcePageUrl,
  }) {
    if (clientProfile.streamlinkPlayerRequest) {
      return {
        'clientName': clientProfile.clientName,
        'clientVersion': clientProfile.clientVersion,
        'platform': clientProfile.platform,
        if ((clientProfile.clientScreen?.isNotEmpty ?? false))
          'clientScreen': clientProfile.clientScreen,
        'clientFormFactor': clientProfile.clientFormFactor,
        if ((clientProfile.browserName?.isNotEmpty ?? false))
          'browserName': clientProfile.browserName,
      };
    }
    final visitorData = baseContext['visitorData']?.toString().trim() ?? '';
    return {
      'clientName': clientProfile.clientName,
      'clientVersion': clientProfile.clientVersion,
      'platform': clientProfile.platform,
      'hl': baseContext['hl']?.toString().trim().isNotEmpty == true
          ? baseContext['hl']!.toString().trim()
          : 'en',
      'gl': baseContext['gl']?.toString().trim().isNotEmpty == true
          ? baseContext['gl']!.toString().trim()
          : 'US',
      'originalUrl': clientProfile.rewriteOriginalUrl(sourcePageUrl),
      'clientScreen':
          clientProfile.clientScreen ??
          (baseContext['clientScreen']?.toString().trim().isNotEmpty == true
              ? baseContext['clientScreen']!.toString().trim()
              : 'WATCH'),
      'clientFormFactor': clientProfile.clientFormFactor,
      'userAgent': clientProfile.userAgent,
      'osName': clientProfile.osName,
      'osVersion': clientProfile.osVersion,
      if (visitorData.isNotEmpty) 'visitorData': visitorData,
      if ((clientProfile.browserName?.isNotEmpty ?? false))
        'browserName': clientProfile.browserName,
      if ((clientProfile.browserVersion?.isNotEmpty ?? false))
        'browserVersion': clientProfile.browserVersion,
      if ((clientProfile.deviceMake?.isNotEmpty ?? false))
        'deviceMake': clientProfile.deviceMake,
      if ((clientProfile.deviceModel?.isNotEmpty ?? false))
        'deviceModel': clientProfile.deviceModel,
    };
  }

  static List<YouTubePlaybackSource> extractHlsSources(
    YouTubePlayerResponseCandidate candidate,
    Map<String, String> Function(YouTubePlayerClientProfile, String)
    buildPlaybackHeaders,
  ) {
    final manifestUrl =
        _asMap(
          candidate.playerResponse['streamingData'],
        )['hlsManifestUrl']?.toString().trim() ??
        '';
    if (manifestUrl.isEmpty) {
      return const [];
    }
    return [
      YouTubePlaybackSource(
        strategy: 'hls',
        clientProfile: candidate.profile,
        lineLabel: '${candidate.profile.lineLabel} HLS',
        url: manifestUrl,
        headers: buildPlaybackHeaders(
          candidate.profile,
          candidate.sourcePageUrl,
        ),
      ),
    ];
  }

  static List<YouTubePlaybackSource> extractDashSources(
    YouTubePlayerResponseCandidate candidate,
    Map<String, String> Function(YouTubePlayerClientProfile, String)
    buildPlaybackHeaders,
  ) {
    final manifestUrl =
        _asMap(
          candidate.playerResponse['streamingData'],
        )['dashManifestUrl']?.toString().trim() ??
        '';
    if (manifestUrl.isEmpty) {
      return const [];
    }
    return [
      YouTubePlaybackSource(
        strategy: 'dash',
        clientProfile: candidate.profile,
        lineLabel: '${candidate.profile.lineLabel} DASH',
        url: manifestUrl,
        headers: buildPlaybackHeaders(
          candidate.profile,
          candidate.sourcePageUrl,
        ),
      ),
    ];
  }

  static List<YouTubePlaybackSource> extractDirectSources(
    YouTubePlayerResponseCandidate candidate,
    Map<String, String> Function(YouTubePlayerClientProfile, String)
    buildPlaybackHeaders,
  ) {
    final streamingData = _asMap(candidate.playerResponse['streamingData']);
    final selectedByQuality = <String, _DirectFormatSelection>{};
    final adaptiveAudio = _selectBestAdaptiveAudioSource(
      candidate,
      buildPlaybackHeaders,
    ).best;

    void considerFormat(Map<String, dynamic> format) {
      final url = format['url']?.toString().trim() ?? '';
      final mimeType = format['mimeType']?.toString().trim() ?? '';
      if (url.isEmpty || mimeType.isEmpty || !mimeType.startsWith('video/')) {
        return;
      }
      final hasBundledAudio = _formatContainsBundledAudio(format);
      if (!hasBundledAudio && adaptiveAudio == null) {
        return;
      }
      final qualityId = _formatQualityId(format);
      final existing = selectedByQuality[qualityId];
      final selection = _DirectFormatSelection(
        format: format,
        audio: hasBundledAudio ? null : adaptiveAudio,
      );
      if (existing == null ||
          _directFormatScore(selection.format) >
              _directFormatScore(existing.format)) {
        selectedByQuality[qualityId] = selection;
      }
    }

    for (final item in _asList(streamingData['formats'])) {
      considerFormat(_asMap(item));
    }
    for (final item in _asList(streamingData['adaptiveFormats'])) {
      considerFormat(_asMap(item));
    }
    final sources = selectedByQuality.values
        .map(
          (selection) => YouTubePlaybackSource(
            strategy: 'direct',
            clientProfile: candidate.profile,
            lineLabel: '${candidate.profile.lineLabel} Direct',
            url: selection.format['url']!.toString(),
            headers: buildPlaybackHeaders(
              candidate.profile,
              candidate.sourcePageUrl,
            ),
            qualityId: _formatQualityId(selection.format),
            qualityLabel: _formatQualityLabel(selection.format),
            sortOrder: _formatSortOrder(selection.format),
            mimeType: selection.format['mimeType']?.toString(),
            audioUrl: selection.audio?.url,
            audioHeaders: selection.audio?.headers ?? const <String, String>{},
            audioLineLabel: selection.audio?.lineLabel,
            audioBitrate: selection.audio?.bitrate,
            audioMimeType: selection.audio?.mimeType,
          ),
        )
        .toList(growable: false);
    sources.sort((left, right) => right.sortOrder.compareTo(left.sortOrder));
    return sources;
  }

  static List<YouTubePlaybackAudioSource> extractAudioSources(
    YouTubePlayerResponseCandidate candidate,
    Map<String, String> Function(YouTubePlayerClientProfile, String)
    buildPlaybackHeaders,
    void Function(String) debugLog,
  ) {
    final selection = _selectBestAdaptiveAudioSource(
      candidate,
      buildPlaybackHeaders,
    );
    final best = selection.best;
    if (best == null) {
      debugLog(
        'audio sources profile=${candidate.profile.id} '
        'audioFormats=${selection.audioFormatCount} '
        'direct=${selection.directUrlCount} cipher=${selection.cipherCount} '
        'selected=-',
      );
      return const [];
    }
    debugLog(
      'audio sources profile=${candidate.profile.id} '
      'audioFormats=${selection.audioFormatCount} '
      'direct=${selection.directUrlCount} cipher=${selection.cipherCount} '
      'selected=${Uri.tryParse(best.url)?.host ?? '-'}${Uri.tryParse(best.url)?.path ?? ''} '
      'bitrate=${best.bitrate}',
    );
    return [best];
  }

  static _AdaptiveAudioSelection _selectBestAdaptiveAudioSource(
    YouTubePlayerResponseCandidate candidate,
    Map<String, String> Function(YouTubePlayerClientProfile, String)
    buildPlaybackHeaders,
  ) {
    final streamingData = _asMap(candidate.playerResponse['streamingData']);
    YouTubePlaybackAudioSource? best;
    var audioFormatCount = 0;
    var directUrlCount = 0;
    var cipherCount = 0;
    for (final item in _asList(streamingData['adaptiveFormats'])) {
      final format = _asMap(item);
      final mimeType = format['mimeType']?.toString().trim() ?? '';
      if (mimeType.isEmpty || !mimeType.startsWith('audio/')) {
        continue;
      }
      audioFormatCount += 1;
      final url = format['url']?.toString().trim() ?? '';
      if (url.isEmpty) {
        final cipher =
            format['signatureCipher']?.toString().trim() ??
            format['cipher']?.toString().trim() ??
            '';
        if (cipher.isNotEmpty) {
          cipherCount += 1;
        }
        continue;
      }
      directUrlCount += 1;
      final candidateSource = YouTubePlaybackAudioSource(
        clientProfile: candidate.profile,
        lineLabel: '${candidate.profile.lineLabel} Audio',
        url: url,
        headers: buildPlaybackHeaders(
          candidate.profile,
          candidate.sourcePageUrl,
        ),
        bitrate:
            _asInt(format['bitrate']) ?? _asInt(format['averageBitrate']) ?? 0,
        mimeType: mimeType,
      );
      if (best == null || candidateSource.score > best.score) {
        best = candidateSource;
      }
    }
    return _AdaptiveAudioSelection(
      best: best,
      audioFormatCount: audioFormatCount,
      directUrlCount: directUrlCount,
      cipherCount: cipherCount,
    );
  }

  static String _formatQualityId(Map<String, dynamic> format) {
    final qualityLabel = format['qualityLabel']?.toString().trim() ?? '';
    final fromLabel = parseQualityRank(qualityLabel);
    if (fromLabel != null) {
      return fromLabel.toString();
    }
    final height = _asInt(format['height']);
    if (height != null && height > 0) {
      return height.toString();
    }
    final bitrate =
        _asInt(format['bitrate']) ?? _asInt(format['averageBitrate']);
    if (bitrate != null && bitrate > 0) {
      return bitrate.toString();
    }
    return 'auto';
  }

  static String _formatQualityLabel(Map<String, dynamic> format) {
    final qualityLabel = format['qualityLabel']?.toString().trim() ?? '';
    if (qualityLabel.isNotEmpty) {
      return qualityLabel;
    }
    final height = _asInt(format['height']);
    if (height != null && height > 0) {
      return '${height}p';
    }
    return 'Direct';
  }

  static int _formatSortOrder(Map<String, dynamic> format) {
    return _asInt(format['height']) ??
        _asInt(format['bitrate']) ??
        _asInt(format['averageBitrate']) ??
        0;
  }

  static int _directFormatScore(Map<String, dynamic> format) {
    final mimeType = format['mimeType']?.toString().toLowerCase() ?? '';
    final audioBonus =
        (format['audioQuality']?.toString().trim().isNotEmpty ?? false)
        ? 10
        : 0;
    final mimeBonus = mimeType.contains('mp4') ? 20 : 0;
    return _formatSortOrder(format) + audioBonus + mimeBonus;
  }

  static bool _formatContainsBundledAudio(Map<String, dynamic> format) {
    final mimeType = format['mimeType']?.toString().toLowerCase() ?? '';
    if (mimeType.contains('mp4a') ||
        mimeType.contains('opus') ||
        mimeType.contains('vorbis')) {
      return true;
    }
    return format['audioQuality']?.toString().trim().isNotEmpty == true;
  }

  static int? parseQualityRank(String raw, {String? fallbackLabel}) {
    final normalized = raw.trim().isEmpty
        ? (fallbackLabel ?? '').trim()
        : raw.trim();
    if (normalized.isEmpty) {
      return null;
    }
    final heightMatch = RegExp(
      r'(\d{3,4})p',
      caseSensitive: false,
    ).firstMatch(normalized);
    if (heightMatch != null) {
      return int.tryParse(heightMatch.group(1)!);
    }
    return int.tryParse(normalized);
  }

  static int? _asInt(Object? value) {
    return ProviderJson.asInt(value, allowNum: true);
  }

  static Map<String, dynamic> _asMap(Object? value) {
    return ProviderJson.asMap(value);
  }

  static List<dynamic> _asList(Object? value) {
    return ProviderJson.asList(value);
  }
}

class _DirectFormatSelection {
  const _DirectFormatSelection({required this.format, this.audio});

  final Map<String, dynamic> format;
  final YouTubePlaybackAudioSource? audio;
}

class _AdaptiveAudioSelection {
  const _AdaptiveAudioSelection({
    required this.best,
    required this.audioFormatCount,
    required this.directUrlCount,
    required this.cipherCount,
  });

  final YouTubePlaybackAudioSource? best;
  final int audioFormatCount;
  final int directUrlCount;
  final int cipherCount;
}
