class ChaturbateHlsVariant {
  const ChaturbateHlsVariant({
    required this.url,
    required this.bandwidth,
    this.width,
    this.height,
  });

  final String url;
  final int bandwidth;
  final int? width;
  final int? height;

  String get label {
    final resolvedHeight = height;
    if (resolvedHeight != null && resolvedHeight > 0) {
      return '${resolvedHeight}p';
    }
    if (bandwidth > 0) {
      final roundedMbps = (bandwidth / 1000000).toStringAsFixed(1);
      return '${roundedMbps}Mbps';
    }
    return 'HLS';
  }

  int get sortOrder {
    final resolvedHeight = height;
    if (resolvedHeight != null && resolvedHeight > 0) {
      return resolvedHeight;
    }
    return bandwidth;
  }
}

class ChaturbateHlsMasterPlaylistParser {
  const ChaturbateHlsMasterPlaylistParser();

  static final RegExp _attributePattern = RegExp(
    r'([A-Z0-9-]+)=("([^"]*)"|[^,]+)',
  );

  List<ChaturbateHlsVariant> parse({
    required String playlistUrl,
    required String source,
  }) {
    final lines = source
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    final variants = <ChaturbateHlsVariant>[];
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
      final bandwidth = int.tryParse(attributes['BANDWIDTH'] ?? '') ?? 0;
      final resolution = attributes['RESOLUTION'] ?? '';
      final dimensions = resolution.split('x');
      final width =
          dimensions.length == 2 ? int.tryParse(dimensions.first) : null;
      final height =
          dimensions.length == 2 ? int.tryParse(dimensions.last) : null;
      variants.add(
        ChaturbateHlsVariant(
          url: Uri.parse(playlistUrl).resolve(nextLine).toString(),
          bandwidth: bandwidth,
          width: width,
          height: height,
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
}
