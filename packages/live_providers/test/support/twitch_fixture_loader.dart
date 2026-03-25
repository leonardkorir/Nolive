import 'dart:convert';
import 'dart:io';

class TwitchFixtureLoader {
  const TwitchFixtureLoader._();

  static const List<String> _requiredArtifacts = <String>[
    'www.twitch.tv.har',
    'www.twitch.tv-1.har',
  ];

  static final Map<String, Map<String, dynamic>> _harCache = {};

  static List<String> get missingArtifacts => [
        for (final name in _requiredArtifacts)
          if (_resolveArtifactIfExists(name) == null) name,
      ];

  static String? get skipReason {
    final missing = missingArtifacts;
    if (missing.isEmpty) {
      return null;
    }
    return 'missing local Twitch fixtures: ${missing.join(', ')}';
  }

  static Map<String, dynamic> loadGraphQlOperation(
    String operationName, {
    String harName = 'www.twitch.tv-1.har',
    String? requestContains,
  }) {
    for (final entry in _entries(harName)) {
      final request = _asMap(entry['request']);
      final url = request['url']?.toString() ?? '';
      if (!url.contains('gql.twitch.tv/gql')) {
        continue;
      }
      final requestText = _requestText(entry);
      if (requestContains != null && !requestText.contains(requestContains)) {
        continue;
      }
      final payload = _decodeJsonObject(requestText);
      if (payload is Map<String, dynamic>) {
        final opName = payload['operationName']?.toString() ?? '';
        if (opName != operationName) {
          continue;
        }
        final response = _decodeResponseJson(entry);
        return _asMap(response);
      }
      if (payload is List) {
        final response = _decodeResponseJson(entry);
        if (response is! List) {
          continue;
        }
        for (final item in response) {
          final decodedItem = _asMap(item);
          final extensions = _asMap(decodedItem['extensions']);
          if (extensions['operationName']?.toString() == operationName) {
            return decodedItem;
          }
        }
      }
    }
    throw StateError(
      'GraphQL operation $operationName was not found in $harName.',
    );
  }

  static Map<String, dynamic> loadPlaybackAccessToken(String roomId) {
    for (final operationName in const [
      'PlaybackAccessToken_Template',
      'PlaybackAccessToken',
    ]) {
      try {
        return loadGraphQlOperation(
          operationName,
          requestContains: '"login":"$roomId"',
        );
      } catch (_) {
        continue;
      }
    }
    throw StateError('PlaybackAccessToken fixture for $roomId was not found.');
  }

  static String loadHlsMasterPlaylist(String roomId) {
    for (final harName in _requiredArtifacts) {
      for (final entry in _entries(harName)) {
        final request = _asMap(entry['request']);
        final url = request['url']?.toString() ?? '';
        if (!url.contains('/channel/hls/$roomId.m3u8')) {
          continue;
        }
        final text = _responseText(entry);
        if (text.isNotEmpty) {
          return text;
        }
      }
    }
    throw StateError('Twitch HLS playlist fixture for $roomId was not found.');
  }

  static List<dynamic> _entries(String harName) {
    final har = _harCache.putIfAbsent(harName, () => _loadHar(harName));
    final log = _asMap(har['log']);
    final entries = log['entries'];
    if (entries is List) {
      return entries;
    }
    throw StateError('HAR log.entries payload was not a list.');
  }

  static Map<String, dynamic> _loadHar(String harName) {
    final file = _resolveArtifact(harName);
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return decoded.cast<String, dynamic>();
    }
    throw StateError('HAR fixture did not decode to a JSON object.');
  }

  static String _requestText(Map<String, dynamic> entry) {
    final request = _asMap(entry['request']);
    final postData = _asMap(request['postData']);
    return postData['text']?.toString() ?? '';
  }

  static Object? _decodeResponseJson(Map<String, dynamic> entry) {
    final text = _responseText(entry).trim();
    if (text.isEmpty) {
      return null;
    }
    return jsonDecode(text);
  }

  static String _responseText(Map<String, dynamic> entry) {
    final response = _asMap(entry['response']);
    final content = _asMap(response['content']);
    final text = content['text']?.toString() ?? '';
    if (text.isEmpty) {
      return '';
    }
    if (content['encoding']?.toString() == 'base64') {
      return utf8.decode(base64.decode(text));
    }
    return text;
  }

  static Object? _decodeJsonObject(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return jsonDecode(trimmed);
  }

  static File _resolveArtifact(String name) {
    final file = _resolveArtifactIfExists(name);
    if (file != null) {
      return file;
    }
    throw StateError('Could not locate Twitch artifact: $name');
  }

  static File? _resolveArtifactIfExists(String name) {
    final current = Directory.current;
    final candidates = <String>{
      current.path,
      current.parent.path,
      current.parent.parent.path,
    };
    for (final base in candidates) {
      final file = File('$base/twitch/$name');
      if (file.existsSync()) {
        return file;
      }
    }
    return null;
  }

  static Map<String, dynamic> _asMap(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.cast<String, dynamic>();
    }
    return const {};
  }
}
