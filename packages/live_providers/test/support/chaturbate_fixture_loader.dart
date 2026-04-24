import 'dart:convert';
import 'dart:io';

class ChaturbateFixtureLoader {
  const ChaturbateFixtureLoader._();

  static const List<String> _requiredArtifacts = <String>[
    'chaturbate.com.har',
    'discover-female.har',
    'room-page-realcest.har',
    'room-page-realcest-auto.har',
    'room-page-realcest-auto-0415.har',
    'search-global.har',
    'view-source_https___chaturbate.com_kittengirlxo_.html',
  ];
  static final Map<String, Map<String, dynamic>> _harCache = {};
  static final Map<String, String> _roomPageCache = {};
  static final Map<String, ChaturbateHlsPlaylistFixture> _hlsPlaylistCache = {};

  static List<String> get missingArtifacts => [
        for (final name in _requiredArtifacts)
          if (_resolveArtifactIfExists(name) == null) name,
      ];

  static String? get skipReason {
    final missing = missingArtifacts;
    if (missing.isEmpty) {
      return null;
    }
    return 'missing local Chaturbate fixtures: ${missing.join(', ')}';
  }

  static Map<String, dynamic> loadCarousel(
    String carouselId, {
    String harName = 'chaturbate.com.har',
    String genders = '',
  }) {
    final entries = _entries(harName);
    for (final entry in entries) {
      final request = _asMap(entry['request']);
      final url = request['url']?.toString() ?? '';
      if (!url.contains('/api/ts/discover/carousels/$carouselId/')) {
        continue;
      }
      if (genders.isNotEmpty && !url.contains('genders=$genders')) {
        continue;
      }
      final response = _asMap(entry['response']);
      final content = _asMap(response['content']);
      final text = content['text']?.toString() ?? '';
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.cast<String, dynamic>();
      }
      break;
    }

    throw StateError(
      'Carousel fixture $carouselId was not found in HAR $harName.',
    );
  }

  static Map<String, dynamic> loadSearchResponse({
    required String query,
    String harName = 'search-global.har',
    String? genders,
    int offset = 0,
  }) {
    final entries = _entries(harName);
    for (final entry in entries) {
      final request = _asMap(entry['request']);
      final url = request['url']?.toString() ?? '';
      if (!url.contains('/api/ts/roomlist/room-list/')) {
        continue;
      }
      if (!url.contains('keywords=$query')) {
        continue;
      }
      if (!url.contains('offset=$offset')) {
        continue;
      }
      if ((genders?.isNotEmpty ?? false) && !url.contains('genders=$genders')) {
        continue;
      }
      if ((genders == null || genders.isEmpty) && url.contains('genders=')) {
        continue;
      }

      final response = _asMap(entry['response']);
      final content = _asMap(response['content']);
      final text = content['text']?.toString() ?? '';
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.cast<String, dynamic>();
      }
      break;
    }

    throw StateError(
      'Search fixture query=$query genders=${genders ?? ''} was not found in $harName.',
    );
  }

  static String loadRoomPage([String roomId = 'kittengirlxo']) {
    return _roomPageCache.putIfAbsent(
      roomId,
      () => _resolveArtifact(
        'view-source_https___chaturbate.com_${roomId}_.html',
      ).readAsStringSync(),
    );
  }

  static ChaturbateHlsPlaylistFixture loadHlsMasterPlaylist({
    String harName = 'room-page-realcest.har',
  }) {
    return _hlsPlaylistCache.putIfAbsent(
      harName,
      () {
        final entries = _entries(harName);
        for (final entry in entries) {
          final request = _asMap(entry['request']);
          final url = request['url']?.toString() ?? '';
          final response = _asMap(entry['response']);
          final content = _asMap(response['content']);
          final text = content['text']?.toString() ?? '';
          if (url.isEmpty || text.isEmpty) {
            continue;
          }
          if (!url.contains('.m3u8')) {
            continue;
          }
          if (!text.contains('#EXT-X-STREAM-INF:')) {
            continue;
          }
          return ChaturbateHlsPlaylistFixture(
            url: url,
            content: text,
          );
        }
        throw StateError(
            'HLS master playlist fixture was not found in $harName.');
      },
    );
  }

  static Map<String, dynamic> loadPushAuthResponse({
    String harName = 'room-page-realcest-auto.har',
  }) {
    final entries = _entries(harName);
    for (final entry in entries) {
      final request = _asMap(entry['request']);
      final url = request['url']?.toString() ?? '';
      if (!url.contains('/push_service/auth/')) {
        continue;
      }
      final response = _asMap(entry['response']);
      final content = _asMap(response['content']);
      final text = content['text']?.toString() ?? '';
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.cast<String, dynamic>();
      }
      break;
    }
    throw StateError('push_service/auth fixture was not found in $harName.');
  }

  static List<Map<String, dynamic>> loadRoomHistory({
    String harName = 'room-page-realcest-auto.har',
  }) {
    final entries = _entries(harName);
    for (final entry in entries) {
      final request = _asMap(entry['request']);
      final url = request['url']?.toString() ?? '';
      if (!url.contains('/push_service/room_history/')) {
        continue;
      }
      final response = _asMap(entry['response']);
      final content = _asMap(response['content']);
      final text = content['text']?.toString() ?? '';
      final decoded = jsonDecode(text);
      if (decoded is List) {
        return decoded
            .map((item) => _asMap(item))
            .where((item) => item.isNotEmpty)
            .toList(growable: false);
      }
      break;
    }
    throw StateError('room_history fixture was not found in $harName.');
  }

  static List<Map<String, dynamic>> loadWebSocketMessages({
    String harName = 'room-page-realcest-auto.har',
  }) {
    final entries = _entries(harName);
    for (final entry in entries) {
      final messages = entry['_webSocketMessages'];
      if (messages is! List || messages.isEmpty) {
        continue;
      }
      return messages
          .map((item) => _asMap(item))
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
    }
    throw StateError('WebSocket fixture was not found in $harName.');
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

  static File _resolveArtifact(String name) {
    final file = _resolveArtifactIfExists(name);
    if (file != null) {
      return file;
    }
    throw StateError('Could not locate chaturbate artifact: $name');
  }

  static File? _resolveArtifactIfExists(String name) {
    final current = Directory.current;
    final candidates = <String>{
      current.path,
      current.parent.path,
      current.parent.parent.path,
    };
    for (final base in candidates) {
      final file = File('$base/chaturbate/$name');
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

class ChaturbateHlsPlaylistFixture {
  const ChaturbateHlsPlaylistFixture({
    required this.url,
    required this.content,
  });

  final String url;
  final String content;
}
