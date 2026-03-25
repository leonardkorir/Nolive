import 'dart:convert';
import 'dart:io';

class YouTubeFixtureLoader {
  const YouTubeFixtureLoader._();

  static const List<String> _requiredArtifacts = <String>[
    'www.youtube.com.har',
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
    return 'missing local YouTube fixtures: ${missing.join(', ')}';
  }

  static String loadChannelPageHtml() {
    for (final entry in _entries('www.youtube.com.har')) {
      final request = _asMap(entry['request']);
      final url = request['url']?.toString() ?? '';
      if (url != 'https://www.youtube.com/channel/UC4R8DWoMoI7CAwX8_LjQHig') {
        continue;
      }
      final html = _responseText(entry);
      if (html.isNotEmpty) {
        return html;
      }
    }
    throw StateError('YouTube channel page fixture was not found.');
  }

  static Map<String, dynamic> loadPlayerResponse(String videoId) {
    for (final entry in _entries('www.youtube.com.har')) {
      final request = _asMap(entry['request']);
      final url = request['url']?.toString() ?? '';
      if (!url.contains('/youtubei/v1/player')) {
        continue;
      }
      final postData = _asMap(request['postData']);
      final requestText = postData['text']?.toString() ?? '';
      if (!requestText.contains('"videoId":"$videoId"')) {
        continue;
      }
      final decoded = jsonDecode(_responseText(entry));
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.cast<String, dynamic>();
      }
      break;
    }
    throw StateError(
        'YouTube player response fixture for $videoId was not found.');
  }

  static String loadLiveChatPageHtml() {
    for (final entry in _entries('www.youtube.com.har')) {
      final request = _asMap(entry['request']);
      final url = request['url']?.toString() ?? '';
      if (!url.contains('/live_chat?continuation=')) {
        continue;
      }
      final html = _responseText(entry);
      if (html.isNotEmpty) {
        return html;
      }
    }
    throw StateError('YouTube live chat page fixture was not found.');
  }

  static List<Map<String, dynamic>> loadLiveChatResponses({int limit = 2}) {
    final responses = <Map<String, dynamic>>[];
    for (final entry in _entries('www.youtube.com.har')) {
      final request = _asMap(entry['request']);
      final url = request['url']?.toString() ?? '';
      if (!url.contains('/youtubei/v1/live_chat/get_live_chat')) {
        continue;
      }
      final decoded = jsonDecode(_responseText(entry));
      if (decoded is Map<String, dynamic>) {
        responses.add(decoded);
      } else if (decoded is Map) {
        responses.add(decoded.cast<String, dynamic>());
      }
      if (responses.length >= limit) {
        return responses;
      }
    }
    if (responses.isNotEmpty) {
      return responses;
    }
    throw StateError('YouTube live chat response fixtures were not found.');
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

  static File _resolveArtifact(String name) {
    final file = _resolveArtifactIfExists(name);
    if (file != null) {
      return file;
    }
    throw StateError('Could not locate YouTube artifact: $name');
  }

  static File? _resolveArtifactIfExists(String name) {
    final current = Directory.current;
    final candidates = <String>{
      current.path,
      current.parent.path,
      current.parent.parent.path,
    };
    for (final base in candidates) {
      final file = File('$base/youtube/$name');
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
