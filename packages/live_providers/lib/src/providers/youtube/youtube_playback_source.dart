import 'youtube_api_client.dart';

class YouTubePlaybackBundle {
  const YouTubePlaybackBundle({
    required this.detailPlayerResponse,
    required this.playerClientContext,
    required this.playbackAudioSources,
    required this.playbackSources,
    required this.primarySource,
    this.playbackUnavailableReason,
    this.playbackDiagnostics = const [],
  });

  final Map<String, dynamic> detailPlayerResponse;
  final Map<String, dynamic> playerClientContext;
  final List<YouTubePlaybackAudioSource> playbackAudioSources;
  final List<YouTubePlaybackSource> playbackSources;
  final YouTubePlaybackSource? primarySource;
  final String? playbackUnavailableReason;
  final List<Map<String, Object?>> playbackDiagnostics;
}

class YouTubePlayerResponseCandidate {
  const YouTubePlayerResponseCandidate({
    required this.profile,
    required this.sourcePageUrl,
    required this.playerResponse,
    required this.requestClientContext,
  });

  final YouTubePlayerClientProfile profile;
  final String sourcePageUrl;
  final Map<String, dynamic> playerResponse;
  final Map<String, dynamic> requestClientContext;
}

class YouTubePlaybackAudioSource {
  const YouTubePlaybackAudioSource({
    required this.clientProfile,
    required this.lineLabel,
    required this.url,
    required this.headers,
    required this.bitrate,
    this.mimeType,
  });

  final YouTubePlayerClientProfile clientProfile;
  final String lineLabel;
  final String url;
  final Map<String, String> headers;
  final int bitrate;
  final String? mimeType;

  YouTubePlaybackAudioSource copyWith({String? url}) {
    return YouTubePlaybackAudioSource(
      clientProfile: clientProfile,
      lineLabel: lineLabel,
      url: url ?? this.url,
      headers: headers,
      bitrate: bitrate,
      mimeType: mimeType,
    );
  }

  int get score {
    final mimeBonus = (mimeType?.toLowerCase().contains('mp4') ?? false)
        ? 1000
        : 0;
    return bitrate + mimeBonus;
  }

  Map<String, Object?> toMetadata() {
    return {
      'clientProfile': clientProfile.id,
      'lineLabel': lineLabel,
      'url': url,
      'headers': headers,
      if (bitrate > 0) 'bitrate': bitrate,
      if (mimeType != null) 'mimeType': mimeType,
    };
  }

  Map<String, Object?> toPlaybackMetadata() {
    return {
      'audioUrl': url,
      'audioHeaders': headers,
      'audioLineLabel': lineLabel,
      'audioClientProfile': clientProfile.id,
      if (bitrate > 0) 'audioBitrate': bitrate,
      if (mimeType != null) 'audioMimeType': mimeType,
    };
  }

  static YouTubePlaybackAudioSource fromMetadata(Map<String, dynamic> raw) {
    final clientId = raw['clientProfile']?.toString().trim() ?? '';
    final clientProfile = YouTubePlayerClientProfile.values.firstWhere(
      (item) => item.id == clientId,
      orElse: () => YouTubePlayerClientProfile.streamlinkAndroid,
    );
    final headers = <String, String>{};
    final rawHeaders = raw['headers'];
    if (rawHeaders is Map) {
      for (final entry in rawHeaders.entries) {
        final key = entry.key.toString().trim();
        final value = entry.value?.toString().trim() ?? '';
        if (key.isEmpty || value.isEmpty) {
          continue;
        }
        headers[key] = value;
      }
    }
    return YouTubePlaybackAudioSource(
      clientProfile: clientProfile,
      lineLabel: raw['lineLabel']?.toString().trim() ?? clientProfile.lineLabel,
      url: raw['url']?.toString().trim() ?? '',
      headers: headers,
      bitrate: int.tryParse(raw['bitrate']?.toString() ?? '') ?? 0,
      mimeType: raw['mimeType']?.toString().trim(),
    );
  }
}

class YouTubePlaybackSource {
  const YouTubePlaybackSource({
    required this.strategy,
    required this.clientProfile,
    required this.lineLabel,
    required this.url,
    required this.headers,
    this.qualityId,
    this.qualityLabel,
    this.sortOrder = 0,
    this.mimeType,
    this.audioUrl,
    this.audioHeaders = const {},
    this.audioLineLabel,
    this.audioBitrate,
    this.audioMimeType,
  });

  final String strategy;
  final YouTubePlayerClientProfile clientProfile;
  final String lineLabel;
  final String url;
  final Map<String, String> headers;
  final String? qualityId;
  final String? qualityLabel;
  final int sortOrder;
  final String? mimeType;
  final String? audioUrl;
  final Map<String, String> audioHeaders;
  final String? audioLineLabel;
  final int? audioBitrate;
  final String? audioMimeType;

  YouTubePlaybackSource copyWith({String? url, String? audioUrl}) {
    return YouTubePlaybackSource(
      strategy: strategy,
      clientProfile: clientProfile,
      lineLabel: lineLabel,
      url: url ?? this.url,
      headers: headers,
      qualityId: qualityId,
      qualityLabel: qualityLabel,
      sortOrder: sortOrder,
      mimeType: mimeType,
      audioUrl: audioUrl ?? this.audioUrl,
      audioHeaders: audioHeaders,
      audioLineLabel: audioLineLabel,
      audioBitrate: audioBitrate,
      audioMimeType: audioMimeType,
    );
  }

  bool get isHls => strategy == 'hls';
  bool get isDirect => strategy == 'direct';
  bool get isDash => strategy == 'dash';

  Map<String, Object?> toMetadata() {
    return {
      'strategy': strategy,
      'clientProfile': clientProfile.id,
      'lineLabel': lineLabel,
      'url': url,
      'headers': headers,
      if (qualityId != null) 'qualityId': qualityId,
      if (qualityLabel != null) 'qualityLabel': qualityLabel,
      if (sortOrder > 0) 'sortOrder': sortOrder,
      if (mimeType != null) 'mimeType': mimeType,
      if (audioUrl?.trim().isNotEmpty == true) ...{
        'audioUrl': audioUrl,
        'audioHeaders': audioHeaders,
        if (audioLineLabel != null) 'audioLineLabel': audioLineLabel,
        if (audioBitrate != null && audioBitrate! > 0)
          'audioBitrate': audioBitrate,
        if (audioMimeType != null) 'audioMimeType': audioMimeType,
      },
    };
  }

  static YouTubePlaybackSource fromMetadata(Map<String, dynamic> raw) {
    final clientId = raw['clientProfile']?.toString().trim() ?? '';
    final clientProfile = YouTubePlayerClientProfile.values.firstWhere(
      (item) => item.id == clientId,
      orElse: () => YouTubePlayerClientProfile.streamlinkAndroid,
    );
    final headers = <String, String>{};
    final rawHeaders = raw['headers'];
    if (rawHeaders is Map) {
      for (final entry in rawHeaders.entries) {
        final key = entry.key.toString().trim();
        final value = entry.value?.toString().trim() ?? '';
        if (key.isEmpty || value.isEmpty) {
          continue;
        }
        headers[key] = value;
      }
    }
    final audioHeaders = <String, String>{};
    final rawAudioHeaders = raw['audioHeaders'];
    if (rawAudioHeaders is Map) {
      for (final entry in rawAudioHeaders.entries) {
        final key = entry.key.toString().trim();
        final value = entry.value?.toString().trim() ?? '';
        if (key.isEmpty || value.isEmpty) {
          continue;
        }
        audioHeaders[key] = value;
      }
    }
    return YouTubePlaybackSource(
      strategy: raw['strategy']?.toString().trim() ?? '',
      clientProfile: clientProfile,
      lineLabel: raw['lineLabel']?.toString().trim() ?? clientProfile.lineLabel,
      url: raw['url']?.toString().trim() ?? '',
      headers: headers,
      qualityId: raw['qualityId']?.toString().trim(),
      qualityLabel: raw['qualityLabel']?.toString().trim(),
      sortOrder: int.tryParse(raw['sortOrder']?.toString() ?? '') ?? 0,
      mimeType: raw['mimeType']?.toString().trim(),
      audioUrl: raw['audioUrl']?.toString().trim(),
      audioHeaders: audioHeaders,
      audioLineLabel: raw['audioLineLabel']?.toString().trim(),
      audioBitrate: int.tryParse(raw['audioBitrate']?.toString() ?? ''),
      audioMimeType: raw['audioMimeType']?.toString().trim(),
    );
  }
}
