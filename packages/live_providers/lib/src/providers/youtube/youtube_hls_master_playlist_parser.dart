class YouTubeHlsVariant {
  const YouTubeHlsVariant({
    required this.url,
    required this.bandwidth,
    required this.label,
    this.width,
    this.height,
    this.frameRate,
    this.audioGroupId,
    this.audioUrl,
    this.codecs,
    this.streamInfAttributes = const {},
    this.audioAttributes = const {},
  });

  final String url;
  final int bandwidth;
  final String label;
  final int? width;
  final int? height;
  final double? frameRate;
  final String? audioGroupId;
  final String? audioUrl;
  final String? codecs;
  final Map<String, String> streamInfAttributes;
  final Map<String, String> audioAttributes;

  int get sortOrder => height ?? bandwidth;

  int get compatibilityScore {
    final normalizedCodecs = (codecs ?? '').toLowerCase();
    var score = 0;
    if (audioUrl?.trim().isNotEmpty == true ||
        normalizedCodecs.contains('mp4a')) {
      score += 1000;
    }
    if (normalizedCodecs.contains('avc1') ||
        normalizedCodecs.contains('h264')) {
      score += 4000;
    } else if (normalizedCodecs.contains('hvc1') ||
        normalizedCodecs.contains('hev1')) {
      score += 2000;
    } else if (normalizedCodecs.contains('vp09') ||
        normalizedCodecs.contains('vp9')) {
      score += 1000;
    } else if (normalizedCodecs.contains('av01') ||
        normalizedCodecs.contains('av1')) {
      score -= 2000;
    }
    return score;
  }
}

class _YouTubeHlsAudioRendition {
  const _YouTubeHlsAudioRendition({
    required this.url,
    required this.attributes,
  });

  final String url;
  final Map<String, String> attributes;
}

class YouTubeHlsMasterPlaylistParser {
  const YouTubeHlsMasterPlaylistParser();

  static final RegExp _attributePattern = RegExp(
    r'([A-Z0-9-]+)=("([^"]*)"|[^,]+)',
  );

  List<YouTubeHlsVariant> parse({
    required String playlistUrl,
    required String source,
  }) {
    final lines = source
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    final audioGroups = _parseAudioGroups(
      playlistUrl: playlistUrl,
      lines: lines,
    );
    final variants = <YouTubeHlsVariant>[];
    for (var index = 0; index < lines.length; index += 1) {
      final line = lines[index];
      if (!line.startsWith('#EXT-X-STREAM-INF:')) {
        continue;
      }
      final attributes = _parseAttributes(
        line.substring('#EXT-X-STREAM-INF:'.length),
      );
      final nextLine = _nextUriLine(lines, index + 1);
      if (nextLine == null) {
        continue;
      }
      final resolution = attributes['RESOLUTION'] ?? '';
      final dimensions = resolution.split('x');
      final width = dimensions.length == 2
          ? int.tryParse(dimensions.first)
          : null;
      final height = dimensions.length == 2
          ? int.tryParse(dimensions.last)
          : null;
      final frameRate = double.tryParse(attributes['FRAME-RATE'] ?? '');
      final bandwidth = int.tryParse(attributes['BANDWIDTH'] ?? '') ?? 0;
      final audioGroupId = attributes['AUDIO']?.trim();
      final audioRendition = audioGroupId == null
          ? null
          : audioGroups[audioGroupId];
      variants.add(
        YouTubeHlsVariant(
          url: Uri.parse(playlistUrl).resolve(nextLine).toString(),
          bandwidth: bandwidth,
          label: _resolveLabel(
            height: height,
            frameRate: frameRate,
            bandwidth: bandwidth,
          ),
          width: width,
          height: height,
          frameRate: frameRate,
          audioGroupId: audioGroupId,
          audioUrl: audioRendition?.url,
          codecs: attributes['CODECS']?.trim(),
          streamInfAttributes: Map<String, String>.unmodifiable(attributes),
          audioAttributes: Map<String, String>.unmodifiable(
            audioRendition?.attributes ?? const <String, String>{},
          ),
        ),
      );
    }
    variants.sort((left, right) {
      final compare = right.sortOrder.compareTo(left.sortOrder);
      if (compare != 0) {
        return compare;
      }
      final compatibilityCompare = right.compatibilityScore.compareTo(
        left.compatibilityScore,
      );
      if (compatibilityCompare != 0) {
        return compatibilityCompare;
      }
      return right.bandwidth.compareTo(left.bandwidth);
    });
    return variants;
  }

  Map<String, _YouTubeHlsAudioRendition> _parseAudioGroups({
    required String playlistUrl,
    required List<String> lines,
  }) {
    final resolvedPlaylistUrl = Uri.parse(playlistUrl);
    final groups = <String, _YouTubeHlsAudioRendition>{};
    for (final line in lines) {
      if (!line.startsWith('#EXT-X-MEDIA:')) {
        continue;
      }
      final attributes = _parseAttributes(
        line.substring('#EXT-X-MEDIA:'.length),
      );
      final type = attributes['TYPE']?.trim().toUpperCase() ?? '';
      final groupId = attributes['GROUP-ID']?.trim() ?? '';
      final uri = attributes['URI']?.trim() ?? '';
      if (type != 'AUDIO' || groupId.isEmpty || uri.isEmpty) {
        continue;
      }
      if (groups.containsKey(groupId) &&
          (attributes['DEFAULT']?.trim().toUpperCase() ?? '') != 'YES') {
        continue;
      }
      groups[groupId] = _YouTubeHlsAudioRendition(
        url: resolvedPlaylistUrl.resolve(uri).toString(),
        attributes: Map<String, String>.unmodifiable(attributes),
      );
    }
    return groups;
  }

  Map<String, String> _parseAttributes(String raw) {
    final result = <String, String>{};
    for (final match in _attributePattern.allMatches(raw)) {
      final key = match.group(1)?.trim() ?? '';
      final value = (match.group(3) ?? match.group(2) ?? '').trim();
      if (key.isEmpty || value.isEmpty) {
        continue;
      }
      result[key] = value;
    }
    return result;
  }

  String? _nextUriLine(List<String> lines, int startIndex) {
    for (var index = startIndex; index < lines.length; index += 1) {
      final line = lines[index];
      if (line.startsWith('#EXT-X-STREAM-INF:')) {
        return null;
      }
      if (!line.startsWith('#')) {
        return line;
      }
    }
    return null;
  }

  String _resolveLabel({
    required int? height,
    required double? frameRate,
    required int bandwidth,
  }) {
    if (height != null && height > 0) {
      final roundedFrameRate = frameRate?.round() ?? 0;
      if (roundedFrameRate >= 50) {
        return '${height}p$roundedFrameRate';
      }
      return '${height}p';
    }
    if (bandwidth > 0) {
      return '${(bandwidth / 1000000).toStringAsFixed(1)}Mbps';
    }
    return 'HLS';
  }
}
