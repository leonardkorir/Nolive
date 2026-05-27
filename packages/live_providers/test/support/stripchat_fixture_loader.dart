import 'dart:convert';
import 'dart:io';

class StripchatHARFixture {
  const StripchatHARFixture({
    required this.requestUrl,
    required this.responseBody,
  });

  final String requestUrl;
  final String responseBody;
}

class StripchatFixtureLoader {
  const StripchatFixtureLoader._();

  static const String _baseDir = 'stripchat';

  static const Map<String, String> _harToApiPattern = {
    'zh.stripchat.com-initial.har': 'initial-dynamic',
    'zh.stripchat.com-list.har': '/api/front/models',
    'zh.stripchat.com-search.har': '/api/front/v5/models/search',
    'zh.stripchat.com-room.har': '/api/front/v2/models/username',
    'zh.stripchat.com-play.har': '/api/front/v1/broadcasts',
    'zh.stripchat.com-play1-ws.har': 'initial-dynamic',
  };

  static final Map<String, List<StripchatHARFixture>> _cache = {};

  static List<String> get missingArtifacts {
    final projectRoot = _findProjectRoot();
    return [
      for (final name in _harToApiPattern.keys)
        if (!File('$projectRoot/$_baseDir/$name').existsSync()) name,
    ];
  }

  static String? get skipReason {
    final missing = missingArtifacts;
    if (missing.isEmpty) return null;
    return 'Stripchat fixture-backed tests require local HAR files from '
        'stripchat/ directory (${missing.join(', ')}). '
        'Extract them from the original HAR before running these tests.';
  }

  static List<StripchatHARFixture> loadFixtures(String apiPattern) {
    if (_cache.containsKey(apiPattern)) {
      return _cache[apiPattern]!;
    }

    final fixtures = <StripchatHARFixture>[];
    final projectRoot = _findProjectRoot();

    for (final entry in _harToApiPattern.entries) {
      if (entry.value != apiPattern) continue;

      final file = File('$projectRoot/$_baseDir/${entry.key}');
      if (!file.existsSync()) continue;

      try {
        final raw = file.readAsStringSync();
        final har = jsonDecode(raw) as Map<String, dynamic>;
        final log = har['log'] as Map<String, dynamic>;
        final entries = (log['entries'] as List).cast<Map<String, dynamic>>();

        for (final harEntry in entries) {
          final request = harEntry['request'] as Map<String, dynamic>;
          final url = request['url']?.toString() ?? '';
          final response = harEntry['response'] as Map<String, dynamic>;
          final content = response['content'] as Map<String, dynamic>? ?? {};
          final text = content['text']?.toString() ?? '';
          final encoding = content['encoding']?.toString() ?? '';

          if (text.isEmpty) continue;

          String responseBody;
          if (encoding == 'base64') {
            try {
              responseBody = utf8.decode(base64Decode(text));
            } on FormatException {
              responseBody = text;
            }
          } else {
            responseBody = text;
          }

          fixtures.add(StripchatHARFixture(
            requestUrl: url,
            responseBody: responseBody,
          ));
        }
      } on FormatException catch (e, s) {
        print('Warning: Failed to parse HAR file ${entry.key} as JSON: $e\n$s');
      } on FileSystemException catch (e, s) {
        print('Warning: Failed to read HAR file ${entry.key}: $e\n$s');
      }
    }

    _cache[apiPattern] = fixtures;
    return fixtures;
  }

  static Map<String, dynamic>? loadInitialDynamic() {
    final fixtures = loadFixtures('initial-dynamic');
    for (final fixture in fixtures) {
      if (!fixture.requestUrl.contains('initial-dynamic')) continue;
      try {
        final decoded =
            jsonDecode(fixture.responseBody) as Map<String, dynamic>;
        final inner = decoded['initialDynamic'] as Map<String, dynamic>?;
        if (inner != null) return inner;
      } on FormatException {
        // fixture response is not valid JSON, skip this entry
      }
    }
    return null;
  }

  static Map<String, dynamic>? loadRecommendResponse() {
    final fixtures = loadFixtures('/api/front/models');
    for (final fixture in fixtures) {
      if (!fixture.requestUrl.contains('/v2/models')) continue;
      try {
        return jsonDecode(fixture.responseBody) as Map<String, dynamic>;
      } on FormatException {
        // fixture response is not valid JSON, skip this entry
      }
    }
    return null;
  }

  static Map<String, dynamic>? loadSearchResponse() {
    final fixtures = loadFixtures('/api/front/v5/models/search');
    for (final fixture in fixtures) {
      if (!fixture.requestUrl.contains('search/group/all')) continue;
      try {
        String body = fixture.responseBody;
        try {
          return jsonDecode(body) as Map<String, dynamic>;
        } on FormatException {
          final decoded = base64Decode(body);
          return jsonDecode(utf8.decode(decoded)) as Map<String, dynamic>;
        }
      } on FormatException {
        // fixture response is not valid JSON (plain or base64), skip
      }
    }
    return null;
  }

  static Map<String, dynamic>? loadCamResponse(String username) {
    final fixtures = loadFixtures('/api/front/v2/models/username');
    for (final fixture in fixtures) {
      if (!fixture.requestUrl.contains('/$username/cam')) continue;
      try {
        return jsonDecode(fixture.responseBody) as Map<String, dynamic>;
      } on FormatException {
        // fixture response is not valid JSON, skip this entry
      }
    }
    return null;
  }

  static Map<String, dynamic>? loadBroadcastResponse(String username) {
    final fixtures = loadFixtures('/api/front/v1/broadcasts');
    for (final fixture in fixtures) {
      if (!fixture.requestUrl.contains('/broadcasts/$username')) continue;
      try {
        return jsonDecode(fixture.responseBody) as Map<String, dynamic>;
      } on FormatException {
        // fixture response is not valid JSON, skip this entry
      }
    }
    return null;
  }

  static String? _findProjectRoot() {
    var dir = Directory.current;
    while (true) {
      if (File('${dir.path}/pubspec.yaml').existsSync()) {
        if (File('${dir.path}/$_baseDir').existsSync()) {
          return dir.path;
        }
      }
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }
    return Directory.current.path;
  }
}
