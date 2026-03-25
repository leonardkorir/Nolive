class TwitchHlsVariant {
  const TwitchHlsVariant({
    required this.url,
    required this.bandwidth,
    required this.label,
    this.stableVariantId,
    this.source,
    this.width,
    this.height,
    this.frameRate,
    this.codecs,
  });

  final String url;
  final int bandwidth;
  final String label;
  final String? stableVariantId;
  final String? source;
  final int? width;
  final int? height;
  final double? frameRate;
  final String? codecs;

  int get sortOrder => height ?? bandwidth;
}

class TwitchHlsMasterPlaylistParser {
  const TwitchHlsMasterPlaylistParser();

  static final RegExp _attributePattern = RegExp(
    r'([A-Z0-9-]+)=("([^"]*)"|[^,]+)',
  );

  List<TwitchHlsVariant> parse({
    required String playlistUrl,
    required String source,
  }) {
    final lines = source
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    final variants = <TwitchHlsVariant>[];
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
      final width =
          dimensions.length == 2 ? int.tryParse(dimensions.first) : null;
      final height =
          dimensions.length == 2 ? int.tryParse(dimensions.last) : null;
      final frameRate = double.tryParse(attributes['FRAME-RATE'] ?? '');
      final bandwidth = int.tryParse(attributes['BANDWIDTH'] ?? '') ?? 0;
      variants.add(
        TwitchHlsVariant(
          url: Uri.parse(playlistUrl).resolve(nextLine).toString(),
          bandwidth: bandwidth,
          label: _resolveLabel(
            explicitLabel: attributes['IVS-NAME'],
            stableVariantId: attributes['STABLE-VARIANT-ID'],
            height: height,
            frameRate: frameRate,
            bandwidth: bandwidth,
          ),
          stableVariantId: attributes['STABLE-VARIANT-ID'],
          source: attributes['IVS-VARIANT-SOURCE'],
          width: width,
          height: height,
          frameRate: frameRate,
          codecs: attributes['CODECS'],
        ),
      );
    }
    variants.sort((left, right) {
      final compare = right.sortOrder.compareTo(left.sortOrder);
      if (compare != 0) {
        return compare;
      }
      return right.bandwidth.compareTo(left.bandwidth);
    });
    return variants;
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
      if (line.startsWith('#')) {
        continue;
      }
      return line;
    }
    return null;
  }

  String _resolveLabel({
    required String? explicitLabel,
    required String? stableVariantId,
    required int? height,
    required double? frameRate,
    required int bandwidth,
  }) {
    final direct = explicitLabel?.trim() ?? '';
    if (direct.isNotEmpty) {
      return direct;
    }
    final stable = stableVariantId?.trim() ?? '';
    if (stable.isNotEmpty) {
      return stable;
    }
    final resolvedHeight = height;
    if (resolvedHeight != null && resolvedHeight > 0) {
      final roundedFrameRate = frameRate?.round() ?? 0;
      if (roundedFrameRate >= 50) {
        return '${resolvedHeight}p$roundedFrameRate';
      }
      return '${resolvedHeight}p';
    }
    if (bandwidth > 0) {
      final roundedMbps = (bandwidth / 1000000).toStringAsFixed(1);
      return '${roundedMbps}Mbps';
    }
    return 'HLS';
  }
}
