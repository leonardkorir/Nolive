import 'player_backend.dart';

class PlayerDiagnostics {
  const PlayerDiagnostics({
    required this.backend,
    this.width,
    this.height,
    this.buffering = false,
    this.buffered = Duration.zero,
    this.lowLatencyMode = false,
    this.rebufferCount = 0,
    this.lastRebufferDuration,
    this.videoParams = const <String, String>{},
    this.audioParams = const <String, String>{},
    this.error,
    this.debugLogEnabled = false,
    this.recentLogs = const <String>[],
  });

  final PlayerBackend backend;
  final int? width;
  final int? height;
  final bool buffering;
  final Duration buffered;
  final bool lowLatencyMode;
  final int rebufferCount;
  final Duration? lastRebufferDuration;
  final Map<String, String> videoParams;
  final Map<String, String> audioParams;
  final String? error;
  final bool debugLogEnabled;
  final List<String> recentLogs;

  factory PlayerDiagnostics.empty(PlayerBackend backend) {
    return PlayerDiagnostics(backend: backend);
  }

  PlayerDiagnostics copyWith({
    PlayerBackend? backend,
    int? width,
    bool clearWidth = false,
    int? height,
    bool clearHeight = false,
    bool? buffering,
    Duration? buffered,
    bool? lowLatencyMode,
    int? rebufferCount,
    Duration? lastRebufferDuration,
    bool clearLastRebufferDuration = false,
    Map<String, String>? videoParams,
    Map<String, String>? audioParams,
    String? error,
    bool clearError = false,
    bool? debugLogEnabled,
    List<String>? recentLogs,
  }) {
    return PlayerDiagnostics(
      backend: backend ?? this.backend,
      width: clearWidth ? null : width ?? this.width,
      height: clearHeight ? null : height ?? this.height,
      buffering: buffering ?? this.buffering,
      buffered: buffered ?? this.buffered,
      lowLatencyMode: lowLatencyMode ?? this.lowLatencyMode,
      rebufferCount: rebufferCount ?? this.rebufferCount,
      lastRebufferDuration: clearLastRebufferDuration
          ? null
          : lastRebufferDuration ?? this.lastRebufferDuration,
      videoParams: videoParams ?? this.videoParams,
      audioParams: audioParams ?? this.audioParams,
      error: clearError ? null : error ?? this.error,
      debugLogEnabled: debugLogEnabled ?? this.debugLogEnabled,
      recentLogs: recentLogs ?? this.recentLogs,
    );
  }
}
