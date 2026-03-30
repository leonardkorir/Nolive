import 'package:live_player/live_player.dart';
import 'package:live_storage/live_storage.dart';

enum PlayerScaleMode {
  contain,
  cover,
  fill,
  fitWidth,
  fitHeight,
}

const String kDefaultMpvVideoOutputDriver = 'gpu-next';
const String kDefaultMpvHardwareDecoder = 'auto-safe';

const Map<String, String> kMpvVideoOutputDrivers = <String, String>{
  'gpu': 'gpu',
  'gpu-next': 'gpu-next',
  'libmpv': 'libmpv',
  'mediacodec_embed': 'mediacodec_embed',
};

const Map<String, String> kMpvHardwareDecoders = <String, String>{
  'auto': '自动',
  'auto-safe': '自动（稳妥）',
  'auto-copy': '自动（拷贝）',
  'mediacodec': 'MediaCodec',
  'mediacodec-copy': 'MediaCodec Copy',
  'no': '关闭硬解',
};

class PlayerPreferences {
  const PlayerPreferences({
    required this.autoPlayEnabled,
    required this.preferHighestQuality,
    required this.backend,
    required this.volume,
    required this.mpvHardwareAccelerationEnabled,
    required this.mpvCompatModeEnabled,
    required this.mpvDoubleBufferingEnabled,
    required this.mpvCustomOutputEnabled,
    required this.mpvVideoOutputDriver,
    required this.mpvHardwareDecoder,
    required this.mpvLogEnabled,
    required this.mdkLowLatencyEnabled,
    required this.mdkAndroidTunnelEnabled,
    required this.forceHttpsEnabled,
    required this.androidAutoFullscreenEnabled,
    required this.androidBackgroundAutoPauseEnabled,
    required this.androidPipHideDanmakuEnabled,
    required this.scaleMode,
  });

  final bool autoPlayEnabled;
  final bool preferHighestQuality;
  final PlayerBackend backend;
  final double volume;
  final bool mpvHardwareAccelerationEnabled;
  final bool mpvCompatModeEnabled;
  final bool mpvDoubleBufferingEnabled;
  final bool mpvCustomOutputEnabled;
  final String mpvVideoOutputDriver;
  final String mpvHardwareDecoder;
  final bool mpvLogEnabled;
  final bool mdkLowLatencyEnabled;
  final bool mdkAndroidTunnelEnabled;
  final bool forceHttpsEnabled;
  final bool androidAutoFullscreenEnabled;
  final bool androidBackgroundAutoPauseEnabled;
  final bool androidPipHideDanmakuEnabled;
  final PlayerScaleMode scaleMode;

  PlayerPreferences copyWith({
    bool? autoPlayEnabled,
    bool? preferHighestQuality,
    PlayerBackend? backend,
    double? volume,
    bool? mpvHardwareAccelerationEnabled,
    bool? mpvCompatModeEnabled,
    bool? mpvDoubleBufferingEnabled,
    bool? mpvCustomOutputEnabled,
    String? mpvVideoOutputDriver,
    String? mpvHardwareDecoder,
    bool? mpvLogEnabled,
    bool? mdkLowLatencyEnabled,
    bool? mdkAndroidTunnelEnabled,
    bool? forceHttpsEnabled,
    bool? androidAutoFullscreenEnabled,
    bool? androidBackgroundAutoPauseEnabled,
    bool? androidPipHideDanmakuEnabled,
    PlayerScaleMode? scaleMode,
  }) {
    return PlayerPreferences(
      autoPlayEnabled: autoPlayEnabled ?? this.autoPlayEnabled,
      preferHighestQuality: preferHighestQuality ?? this.preferHighestQuality,
      backend: backend ?? this.backend,
      volume: volume ?? this.volume,
      mpvHardwareAccelerationEnabled:
          mpvHardwareAccelerationEnabled ?? this.mpvHardwareAccelerationEnabled,
      mpvCompatModeEnabled: mpvCompatModeEnabled ?? this.mpvCompatModeEnabled,
      mpvDoubleBufferingEnabled:
          mpvDoubleBufferingEnabled ?? this.mpvDoubleBufferingEnabled,
      mpvCustomOutputEnabled:
          mpvCustomOutputEnabled ?? this.mpvCustomOutputEnabled,
      mpvVideoOutputDriver: mpvVideoOutputDriver ?? this.mpvVideoOutputDriver,
      mpvHardwareDecoder: mpvHardwareDecoder ?? this.mpvHardwareDecoder,
      mpvLogEnabled: mpvLogEnabled ?? this.mpvLogEnabled,
      mdkLowLatencyEnabled: mdkLowLatencyEnabled ?? this.mdkLowLatencyEnabled,
      mdkAndroidTunnelEnabled:
          mdkAndroidTunnelEnabled ?? this.mdkAndroidTunnelEnabled,
      forceHttpsEnabled: forceHttpsEnabled ?? this.forceHttpsEnabled,
      androidAutoFullscreenEnabled:
          androidAutoFullscreenEnabled ?? this.androidAutoFullscreenEnabled,
      androidBackgroundAutoPauseEnabled: androidBackgroundAutoPauseEnabled ??
          this.androidBackgroundAutoPauseEnabled,
      androidPipHideDanmakuEnabled:
          androidPipHideDanmakuEnabled ?? this.androidPipHideDanmakuEnabled,
      scaleMode: scaleMode ?? this.scaleMode,
    );
  }
}

class LoadPlayerPreferencesUseCase {
  const LoadPlayerPreferencesUseCase(this.settingsRepository);

  final SettingsRepository settingsRepository;

  Future<PlayerPreferences> call() async {
    final autoPlay =
        await settingsRepository.readValue<bool>('player_auto_play') ?? true;
    final preferHighestQuality = await settingsRepository
            .readValue<bool>('player_prefer_highest_quality') ??
        false;
    final backendRaw =
        await settingsRepository.readValue<String>('player_backend');
    final volume =
        await settingsRepository.readValue<double>('player_volume') ?? 1.0;
    final mpvHardwareAccelerationEnabled = await settingsRepository
            .readValue<bool>('player_mpv_hardware_acceleration') ??
        true;
    final mpvCompatModeEnabled =
        await settingsRepository.readValue<bool>('player_mpv_compat_mode') ??
            false;
    final mpvDoubleBufferingEnabled = await settingsRepository
            .readValue<bool>('player_mpv_double_buffering') ??
        false;
    final mpvCustomOutputEnabled =
        await settingsRepository.readValue<bool>('player_mpv_custom_output') ??
            false;
    final mpvVideoOutputDriver = await settingsRepository
            .readValue<String>('player_mpv_video_output_driver') ??
        kDefaultMpvVideoOutputDriver;
    final mpvHardwareDecoder = await settingsRepository
            .readValue<String>('player_mpv_hardware_decoder') ??
        kDefaultMpvHardwareDecoder;
    final mpvLogEnabled =
        await settingsRepository.readValue<bool>('player_mpv_log_enable') ??
            false;
    final mdkLowLatencyEnabled =
        await settingsRepository.readValue<bool>('player_mdk_low_latency') ??
            true;
    final mdkAndroidTunnelEnabled =
        await settingsRepository.readValue<bool>('player_mdk_android_tunnel') ??
            false;
    final forceHttpsEnabled =
        await settingsRepository.readValue<bool>('player_force_https') ?? false;
    final androidAutoFullscreenEnabled = await settingsRepository
            .readValue<bool>('player_android_auto_fullscreen') ??
        true;
    final androidBackgroundAutoPauseEnabled = await settingsRepository
            .readValue<bool>('player_android_background_auto_pause') ??
        true;
    final androidPipHideDanmakuEnabled = await settingsRepository
            .readValue<bool>('player_android_pip_hide_danmaku') ??
        true;
    final scaleModeRaw =
        await settingsRepository.readValue<String>('player_scale_mode');
    return PlayerPreferences(
      autoPlayEnabled: autoPlay,
      preferHighestQuality: preferHighestQuality,
      backend: _decodeBackend(backendRaw),
      volume: volume.clamp(0.0, 1.0),
      mpvHardwareAccelerationEnabled: mpvHardwareAccelerationEnabled,
      mpvCompatModeEnabled: mpvCompatModeEnabled,
      mpvDoubleBufferingEnabled: mpvDoubleBufferingEnabled,
      mpvCustomOutputEnabled: mpvCustomOutputEnabled,
      mpvVideoOutputDriver: _decodeMpvVideoOutputDriver(mpvVideoOutputDriver),
      mpvHardwareDecoder: _decodeMpvHardwareDecoder(mpvHardwareDecoder),
      mpvLogEnabled: mpvLogEnabled,
      mdkLowLatencyEnabled: mdkLowLatencyEnabled,
      mdkAndroidTunnelEnabled: mdkAndroidTunnelEnabled,
      forceHttpsEnabled: forceHttpsEnabled,
      androidAutoFullscreenEnabled: androidAutoFullscreenEnabled,
      androidBackgroundAutoPauseEnabled: androidBackgroundAutoPauseEnabled,
      androidPipHideDanmakuEnabled: androidPipHideDanmakuEnabled,
      scaleMode: _decodeScaleMode(scaleModeRaw),
    );
  }

  static PlayerBackend _decodeBackend(String? raw) {
    return PlayerBackend.values.firstWhere(
      (item) => item.name == raw,
      orElse: () => PlayerBackend.mpv,
    );
  }

  static PlayerScaleMode _decodeScaleMode(String? raw) {
    return PlayerScaleMode.values.firstWhere(
      (item) => item.name == raw,
      orElse: () => PlayerScaleMode.contain,
    );
  }

  static String _decodeMpvVideoOutputDriver(String? raw) {
    if (raw != null && kMpvVideoOutputDrivers.containsKey(raw)) {
      return raw;
    }
    return kDefaultMpvVideoOutputDriver;
  }

  static String _decodeMpvHardwareDecoder(String? raw) {
    if (raw != null && kMpvHardwareDecoders.containsKey(raw)) {
      return raw;
    }
    return kDefaultMpvHardwareDecoder;
  }
}

class UpdatePlayerPreferencesUseCase {
  const UpdatePlayerPreferencesUseCase(this.settingsRepository);

  final SettingsRepository settingsRepository;

  Future<void> call(PlayerPreferences preferences) async {
    await settingsRepository.writeValue(
      'player_auto_play',
      preferences.autoPlayEnabled,
    );
    await settingsRepository.writeValue(
      'player_prefer_highest_quality',
      preferences.preferHighestQuality,
    );
    await settingsRepository.writeValue(
      'player_backend',
      preferences.backend.name,
    );
    await settingsRepository.writeValue(
      'player_volume',
      preferences.volume.clamp(0.0, 1.0),
    );
    await settingsRepository.writeValue(
      'player_mpv_hardware_acceleration',
      preferences.mpvHardwareAccelerationEnabled,
    );
    await settingsRepository.writeValue(
      'player_mpv_compat_mode',
      preferences.mpvCompatModeEnabled,
    );
    await settingsRepository.writeValue(
      'player_mpv_double_buffering',
      preferences.mpvDoubleBufferingEnabled,
    );
    await settingsRepository.writeValue(
      'player_mpv_custom_output',
      preferences.mpvCustomOutputEnabled,
    );
    await settingsRepository.writeValue(
      'player_mpv_video_output_driver',
      preferences.mpvVideoOutputDriver,
    );
    await settingsRepository.writeValue(
      'player_mpv_hardware_decoder',
      preferences.mpvHardwareDecoder,
    );
    await settingsRepository.writeValue(
      'player_mpv_log_enable',
      preferences.mpvLogEnabled,
    );
    await settingsRepository.writeValue(
      'player_mdk_low_latency',
      preferences.mdkLowLatencyEnabled,
    );
    await settingsRepository.writeValue(
      'player_mdk_android_tunnel',
      preferences.mdkAndroidTunnelEnabled,
    );
    await settingsRepository.writeValue(
      'player_force_https',
      preferences.forceHttpsEnabled,
    );
    await settingsRepository.writeValue(
      'player_android_auto_fullscreen',
      preferences.androidAutoFullscreenEnabled,
    );
    await settingsRepository.writeValue(
      'player_android_background_auto_pause',
      preferences.androidBackgroundAutoPauseEnabled,
    );
    await settingsRepository.writeValue(
      'player_android_pip_hide_danmaku',
      preferences.androidPipHideDanmakuEnabled,
    );
    await settingsRepository.writeValue(
      'player_scale_mode',
      preferences.scaleMode.name,
    );
  }
}
