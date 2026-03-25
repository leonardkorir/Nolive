import 'player_backend.dart';

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
      errorMessage:
          clearErrorMessage ? null : errorMessage ?? this.errorMessage,
      volume: volume ?? this.volume,
      source: clearSource ? null : source ?? this.source,
      backend: backend ?? this.backend,
    );
  }
}

class PlaybackSource {
  const PlaybackSource({
    required this.url,
    this.headers = const {},
    this.externalAudio,
  });

  final Uri url;
  final Map<String, String> headers;
  final PlaybackExternalMedia? externalAudio;
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
}
