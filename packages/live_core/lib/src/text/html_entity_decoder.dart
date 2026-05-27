class HtmlEntityDecoder {
  const HtmlEntityDecoder._();

  static const int defaultMaxPasses = 4;

  static const Map<String, String> _namedEntities = <String, String>{
    'amp': '&',
    'lt': '<',
    'gt': '>',
    'quot': '"',
    'apos': "'",
    'nbsp': ' ',
    'copy': '©',
    'reg': '®',
    'trade': '™',
    'hellip': '…',
    'mdash': '—',
    'ndash': '–',
    'middot': '·',
    'bull': '•',
    'laquo': '«',
    'raquo': '»',
    'ldquo': '“',
    'rdquo': '”',
    'lsquo': '‘',
    'rsquo': '’',
  };

  static final RegExp _entityPattern =
      RegExp(r'&(#x?[0-9a-fA-F]+|[a-zA-Z][a-zA-Z0-9]+);');

  static String decode(
    String value, {
    int maxPasses = defaultMaxPasses,
  }) {
    if (!value.contains('&') || maxPasses <= 0) {
      return value;
    }
    var current = value;
    for (var pass = 0; pass < maxPasses; pass += 1) {
      final next = current.replaceAllMapped(_entityPattern, _decodeMatch);
      if (next == current) {
        return next;
      }
      current = next;
      if (!current.contains('&')) {
        return current;
      }
    }
    return current;
  }

  static String _decodeMatch(Match match) {
    final entity = match.group(1);
    if (entity == null) {
      return match.group(0) ?? '';
    }
    if (entity.startsWith('#x') || entity.startsWith('#X')) {
      return _decodeCodePoint(entity.substring(2), radix: 16) ??
          match.group(0) ??
          '';
    }
    if (entity.startsWith('#')) {
      return _decodeCodePoint(entity.substring(1), radix: 10) ??
          match.group(0) ??
          '';
    }
    return _namedEntities[entity.toLowerCase()] ?? match.group(0) ?? '';
  }

  static String? _decodeCodePoint(String raw, {required int radix}) {
    final codePoint = int.tryParse(raw, radix: radix);
    if (codePoint == null || codePoint < 0 || codePoint > 0x10FFFF) {
      return null;
    }
    if (codePoint >= 0xD800 && codePoint <= 0xDFFF) {
      return null;
    }
    return String.fromCharCode(codePoint);
  }
}

String decodeHtmlEntities(String value, {int maxPasses = 4}) {
  return HtmlEntityDecoder.decode(value, maxPasses: maxPasses);
}
