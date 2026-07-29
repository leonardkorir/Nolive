import 'package:flutter/foundation.dart';

import 'player_backend.dart';

enum PlaybackBufferProfile {
  defaultLowLatency,

  /// Foreign live (Twitch/YouTube, etc.) on phone and desktop: cache on,
  /// multi-second readahead. Delivery-only; does not change Auto quality policy.
  desktopStableLive,
  edgeLowLatencyHls,
  loopbackStableHls,
  chaturbateLlHlsProxyStable,
  heavyStreamStable,
}

enum PlaybackStatus {
  idle,
  initializing,
  ready,
  buffering,
  playing,
  paused,
  completed,
  error,
}

class PlayerState {
  const PlayerState({
    this.status = PlaybackStatus.idle,
    this.position = Duration.zero,
    this.buffered = Duration.zero,
    this.duration,
    this.errorMessage,
    this.volume = 1,
    this.source,
    this.backend,
  });

  final PlaybackStatus status;
  final Duration position;
  final Duration buffered;
  final Duration? duration;
  final String? errorMessage;
  final double volume;
  final PlaybackSource? source;
  final PlayerBackend? backend;

  PlayerState copyWith({
    PlaybackStatus? status,
    Duration? position,
    Duration? buffered,
    Duration? duration,
    String? errorMessage,
    bool clearErrorMessage = false,
    double? volume,
    PlaybackSource? source,
    bool clearSource = false,
    PlayerBackend? backend,
  }) {
    return PlayerState(
      status: status ?? this.status,
      position: position ?? this.position,
      buffered: buffered ?? this.buffered,
      duration: duration ?? this.duration,
      errorMessage: clearErrorMessage
          ? null
          : errorMessage ?? this.errorMessage,
      volume: volume ?? this.volume,
      source: clearSource ? null : source ?? this.source,
      backend: backend ?? this.backend,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is PlayerState &&
            status == other.status &&
            position == other.position &&
            buffered == other.buffered &&
            duration == other.duration &&
            errorMessage == other.errorMessage &&
            volume == other.volume &&
            source == other.source &&
            backend == other.backend;
  }

  @override
  int get hashCode => Object.hash(
    status,
    position,
    buffered,
    duration,
    errorMessage,
    volume,
    source,
    backend,
  );
}

class PlaybackSource {
  const PlaybackSource({
    required this.url,
    this.headers = const {},
    this.externalAudio,
    this.masterPlaylistUrl,
    this.masterPlaylistContent,
    this.bufferProfile = PlaybackBufferProfile.defaultLowLatency,
    this.hlsBitrate,
  });

  final Uri url;
  final Map<String, String> headers;
  final PlaybackExternalMedia? externalAudio;
  final Uri? masterPlaylistUrl;
  final String? masterPlaylistContent;
  final PlaybackBufferProfile bufferProfile;
  final String? hlsBitrate;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is PlaybackSource &&
            url == other.url &&
            mapEquals(headers, other.headers) &&
            externalAudio == other.externalAudio &&
            masterPlaylistUrl == other.masterPlaylistUrl &&
            masterPlaylistContent == other.masterPlaylistContent &&
            bufferProfile == other.bufferProfile &&
            hlsBitrate == other.hlsBitrate;
  }

  @override
  int get hashCode => Object.hash(
    url,
    _mapHash(headers),
    externalAudio,
    masterPlaylistUrl,
    masterPlaylistContent,
    bufferProfile,
    hlsBitrate,
  );
}

class PlaybackExternalMedia {
  const PlaybackExternalMedia({
    required this.url,
    this.headers = const {},
    this.label,
    this.mimeType,
  });

  final Uri url;
  final Map<String, String> headers;
  final String? label;
  final String? mimeType;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is PlaybackExternalMedia &&
            url == other.url &&
            mapEquals(headers, other.headers) &&
            label == other.label &&
            mimeType == other.mimeType;
  }

  @override
  int get hashCode => Object.hash(url, _mapHash(headers), label, mimeType);
}

int _mapHash(Map<String, String> values) {
  final entries = values.entries.toList(growable: false)
    ..sort((left, right) => left.key.compareTo(right.key));
  return Object.hashAll(
    entries.map((entry) => Object.hash(entry.key, entry.value)),
  );
}
