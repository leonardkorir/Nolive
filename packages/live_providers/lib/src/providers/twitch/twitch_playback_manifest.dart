class TwitchPlaybackCandidate {
  const TwitchPlaybackCandidate({
    required this.playlistUrl,
    required this.headers,
    required this.playerType,
    required this.platform,
    required this.lineLabel,
    this.source,
    this.bandwidth = 0,
    this.width,
    this.height,
    this.frameRate,
    this.codecs,
  });

  final String playlistUrl;
  final Map<String, String> headers;
  final String playerType;
  final String platform;
  final String lineLabel;
  final String? source;
  final int bandwidth;
  final int? width;
  final int? height;
  final double? frameRate;
  final String? codecs;

  Map<String, Object?> toJson() {
    return {
      'playlistUrl': playlistUrl,
      'headers': headers,
      'playerType': playerType,
      'platform': platform,
      'lineLabel': lineLabel,
      'source': source,
      'bandwidth': bandwidth,
      'width': width,
      'height': height,
      'frameRate': frameRate,
      'codecs': codecs,
    };
  }

  static TwitchPlaybackCandidate? fromJson(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final playlistUrl = raw['playlistUrl']?.toString().trim() ?? '';
    final playerType = raw['playerType']?.toString().trim() ?? '';
    final platform = raw['platform']?.toString().trim() ?? '';
    final lineLabel = raw['lineLabel']?.toString().trim() ?? '';
    if (playlistUrl.isEmpty ||
        playerType.isEmpty ||
        platform.isEmpty ||
        lineLabel.isEmpty) {
      return null;
    }
    return TwitchPlaybackCandidate(
      playlistUrl: playlistUrl,
      headers: _readHeaders(raw['headers']),
      playerType: playerType,
      platform: platform,
      lineLabel: lineLabel,
      source: _readOptionalString(raw['source']),
      bandwidth: _readInt(raw['bandwidth']) ?? 0,
      width: _readInt(raw['width']),
      height: _readInt(raw['height']),
      frameRate: _readDouble(raw['frameRate']),
      codecs: _readOptionalString(raw['codecs']),
    );
  }

  static List<TwitchPlaybackCandidate> listFromJson(Object? raw) {
    if (raw is! List) {
      return const [];
    }
    final items = <TwitchPlaybackCandidate>[];
    for (final item in raw) {
      final parsed = TwitchPlaybackCandidate.fromJson(item);
      if (parsed != null) {
        items.add(parsed);
      }
    }
    return items;
  }
}

class TwitchPlaybackQualityGroup {
  const TwitchPlaybackQualityGroup({
    required this.id,
    required this.label,
    required this.sortOrder,
    required this.candidates,
    this.bandwidth = 0,
    this.width,
    this.height,
    this.frameRate,
    this.codecs,
  });

  final String id;
  final String label;
  final int sortOrder;
  final List<TwitchPlaybackCandidate> candidates;
  final int bandwidth;
  final int? width;
  final int? height;
  final double? frameRate;
  final String? codecs;

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'label': label,
      'sortOrder': sortOrder,
      'bandwidth': bandwidth,
      'width': width,
      'height': height,
      'frameRate': frameRate,
      'codecs': codecs,
      'candidates': candidates.map((item) => item.toJson()).toList(),
    };
  }

  static TwitchPlaybackQualityGroup? fromJson(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final id = raw['id']?.toString().trim() ?? '';
    final label = raw['label']?.toString().trim() ?? '';
    if (id.isEmpty || label.isEmpty) {
      return null;
    }
    final candidates = TwitchPlaybackCandidate.listFromJson(raw['candidates']);
    if (candidates.isEmpty) {
      return null;
    }
    return TwitchPlaybackQualityGroup(
      id: id,
      label: label,
      sortOrder: _readInt(raw['sortOrder']) ?? 0,
      candidates: candidates,
      bandwidth: _readInt(raw['bandwidth']) ?? 0,
      width: _readInt(raw['width']),
      height: _readInt(raw['height']),
      frameRate: _readDouble(raw['frameRate']),
      codecs: _readOptionalString(raw['codecs']),
    );
  }

  static List<TwitchPlaybackQualityGroup> listFromJson(Object? raw) {
    if (raw is! List) {
      return const [];
    }
    final items = <TwitchPlaybackQualityGroup>[];
    for (final item in raw) {
      final parsed = TwitchPlaybackQualityGroup.fromJson(item);
      if (parsed != null) {
        items.add(parsed);
      }
    }
    return items;
  }
}

Map<String, String> _readHeaders(Object? raw) {
  if (raw is Map<String, String>) {
    return raw;
  }
  if (raw is Map) {
    final headers = <String, String>{};
    for (final entry in raw.entries) {
      final key = entry.key.toString().trim();
      final value = entry.value?.toString().trim() ?? '';
      if (key.isEmpty || value.isEmpty) {
        continue;
      }
      headers[key] = value;
    }
    return headers;
  }
  return const {};
}

String? _readOptionalString(Object? raw) {
  final text = raw?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}

int? _readInt(Object? raw) {
  if (raw is int) {
    return raw;
  }
  if (raw is num) {
    return raw.toInt();
  }
  return int.tryParse(raw?.toString() ?? '');
}

double? _readDouble(Object? raw) {
  if (raw is double) {
    return raw;
  }
  if (raw is num) {
    return raw.toDouble();
  }
  return double.tryParse(raw?.toString() ?? '');
}
