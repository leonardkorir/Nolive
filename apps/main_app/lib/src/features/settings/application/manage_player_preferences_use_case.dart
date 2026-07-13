import 'package:live_player/live_player.dart';
import 'package:live_storage/live_storage.dart';
import 'package:nolive_app/src/shared/application/player_runtime_controller.dart';

enum PlayerScaleMode { contain, cover, fill, fitWidth, fitHeight }

const String kDefaultMpvVideoOutputDriver = 'gpu-next';
const String kDefaultMpvHardwareDecoder = 'auto-safe';

const String kDefaultMpvAudioOutputDriver = 'auto';

const Map<String, String> kMpvVideoOutputDrivers = <String, String>{
  'gpu': 'gpu',
  'gpu-next': 'gpu-next',
  'libmpv': 'libmpv',
  'mediacodec_embed': 'mediacodec_embed (Android)',
  'sdl': 'sdl',
  'dmabuf-wayland': 'dmabuf-wayland',
  'vaapi': 'vaapi',
  'direct3d': 'direct3d (Windows)',
  'null': 'null',
};

const Map<String, String> kMpvAudioOutputDrivers = <String, String>{
  'auto': '自动',
  'audiotrack': 'audiotrack (Android)',
  'opensles': 'opensles (Android)',
  'aaudio': 'aaudio (Android)',
  'pulse': 'pulse (Linux)',
  'pipewire': 'pipewire (Linux)',
  'alsa': 'alsa (Linux)',
  'wasapi': 'wasapi (Windows)',
  'coreaudio': 'coreaudio (macOS)',
  'sdl': 'sdl',
  'null': 'null',
};

const Map<String, String> kMpvHardwareDecoders = <String, String>{
  'auto': '自动',
  'auto-safe': '自动（稳妥）',
  'auto-copy': '自动（拷贝）',
  'mediacodec': 'MediaCodec',
  'mediacodec-copy': 'MediaCodec Copy',
  'd3d11va': 'd3d11va',
  'd3d11va-copy': 'd3d11va-copy',
  'videotoolbox': 'videotoolbox',
  'vaapi': 'vaapi',
  'nvdec': 'nvdec',
  'no': '关闭硬解',
};

Map<String, String> mpvVideoOutputDriversForPlatform({
  required bool isAndroid,
  required bool isLinux,
  required bool isWindows,
  required bool isApple,
}) {
  return Map<String, String>.fromEntries(
    kMpvVideoOutputDrivers.entries.where((entry) {
      final key = entry.key;
      if (key == 'mediacodec_embed') return isAndroid;
      if (key == 'direct3d') return isWindows;
      if (key == 'dmabuf-wayland' || key == 'vaapi') return isLinux;
      return true;
    }),
  );
}

Map<String, String> mpvAudioOutputDriversForPlatform({
  required bool isAndroid,
  required bool isLinux,
  required bool isWindows,
  required bool isApple,
}) {
  return Map<String, String>.fromEntries(
    kMpvAudioOutputDrivers.entries.where((entry) {
      final key = entry.key;
      if (key == 'auto' || key == 'sdl' || key == 'null') return true;
      if (key == 'audiotrack' || key == 'opensles' || key == 'aaudio') {
        return isAndroid;
      }
      if (key == 'pulse' || key == 'pipewire' || key == 'alsa') return isLinux;
      if (key == 'wasapi') return isWindows;
      if (key == 'coreaudio') return isApple;
      return true;
    }),
  );
}

Map<String, String> mpvHardwareDecodersForPlatform({
  required bool isAndroid,
  required bool isLinux,
  required bool isWindows,
  required bool isApple,
}) {
  return Map<String, String>.fromEntries(
    kMpvHardwareDecoders.entries.where((entry) {
      final key = entry.key;
      if (key.startsWith('mediacodec')) return isAndroid;
      if (key.startsWith('d3d11va')) return isWindows;
      if (key == 'videotoolbox') return isApple;
      if (key == 'vaapi') return isLinux;
      if (key == 'nvdec') return isLinux || isWindows;
      return true;
    }),
  );
}

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
    required this.mpvAudioOutputDriver,
    required this.mpvHardwareDecoder,
    required this.mpvLogEnabled,
    required this.wifiQualityPreference,
    required this.cellularQualityPreference,
    required this.mdkLowLatencyEnabled,
    required this.mdkAndroidTunnelEnabled,
    required this.mdkAndroidHardwareVideoDecoderEnabled,
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
  final String mpvAudioOutputDriver;
  final String mpvHardwareDecoder;
  final bool mpvLogEnabled;
  final NetworkQualityPreference wifiQualityPreference;
  final NetworkQualityPreference cellularQualityPreference;
  final bool mdkLowLatencyEnabled;
  final bool mdkAndroidTunnelEnabled;
  final bool mdkAndroidHardwareVideoDecoderEnabled;
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
    String? mpvAudioOutputDriver,
    String? mpvHardwareDecoder,
    bool? mpvLogEnabled,
    NetworkQualityPreference? wifiQualityPreference,
    NetworkQualityPreference? cellularQualityPreference,
    bool? mdkLowLatencyEnabled,
    bool? mdkAndroidTunnelEnabled,
    bool? mdkAndroidHardwareVideoDecoderEnabled,
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
      mpvAudioOutputDriver: mpvAudioOutputDriver ?? this.mpvAudioOutputDriver,
      mpvHardwareDecoder: mpvHardwareDecoder ?? this.mpvHardwareDecoder,
      mpvLogEnabled: mpvLogEnabled ?? this.mpvLogEnabled,
      wifiQualityPreference:
          wifiQualityPreference ?? this.wifiQualityPreference,
      cellularQualityPreference:
          cellularQualityPreference ?? this.cellularQualityPreference,
      mdkLowLatencyEnabled: mdkLowLatencyEnabled ?? this.mdkLowLatencyEnabled,
      mdkAndroidTunnelEnabled:
          mdkAndroidTunnelEnabled ?? this.mdkAndroidTunnelEnabled,
      mdkAndroidHardwareVideoDecoderEnabled:
          mdkAndroidHardwareVideoDecoderEnabled ??
          this.mdkAndroidHardwareVideoDecoderEnabled,
      forceHttpsEnabled: forceHttpsEnabled ?? this.forceHttpsEnabled,
      androidAutoFullscreenEnabled:
          androidAutoFullscreenEnabled ?? this.androidAutoFullscreenEnabled,
      androidBackgroundAutoPauseEnabled:
          androidBackgroundAutoPauseEnabled ??
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
    final preferHighestQuality =
        await settingsRepository.readValue<bool>(
          'player_prefer_highest_quality',
        ) ??
        false;
    final backendRaw = await settingsRepository.readValue<String>(
      'player_backend',
    );
    final volume =
        await settingsRepository.readValue<double>('player_volume') ?? 1.0;
    final mpvHardwareAccelerationEnabled =
        await settingsRepository.readValue<bool>(
          'player_mpv_hardware_acceleration',
        ) ??
        true;
    final mpvCompatModeEnabled =
        await settingsRepository.readValue<bool>('player_mpv_compat_mode') ??
        false;
    final mpvDoubleBufferingEnabled =
        await settingsRepository.readValue<bool>(
          'player_mpv_double_buffering',
        ) ??
        false;
    final mpvCustomOutputEnabled =
        await settingsRepository.readValue<bool>('player_mpv_custom_output') ??
        false;
    final mpvVideoOutputDriver =
        await settingsRepository.readValue<String>(
          'player_mpv_video_output_driver',
        ) ??
        kDefaultMpvVideoOutputDriver;
    final mpvHardwareDecoder =
        await settingsRepository.readValue<String>(
          'player_mpv_hardware_decoder',
        ) ??
        kDefaultMpvHardwareDecoder;
    final mpvAudioOutputDriver =
        await settingsRepository.readValue<String>(
          'player_mpv_audio_output_driver',
        ) ??
        kDefaultMpvAudioOutputDriver;
    final wifiQualityPreference = _decodeNetworkQualityPreference(
      await settingsRepository.readValue<String>('player_wifi_quality_level'),
      fallback: NetworkQualityPreference.middle,
    );
    final cellularQualityPreference = _decodeNetworkQualityPreference(
      await settingsRepository.readValue<String>(
        'player_cellular_quality_level',
      ),
      fallback: NetworkQualityPreference.lowest,
    );
    final mpvLogEnabled =
        await settingsRepository.readValue<bool>('player_mpv_log_enable') ??
        false;
    final mdkLowLatencyEnabled =
        await settingsRepository.readValue<bool>('player_mdk_low_latency') ??
        true;
    final mdkAndroidTunnelEnabled =
        await settingsRepository.readValue<bool>('player_mdk_android_tunnel') ??
        false;
    final mdkAndroidHardwareVideoDecoderEnabled =
        await settingsRepository.readValue<bool>(
          'player_mdk_android_hardware_video_decoder',
        ) ??
        true;
    final forceHttpsEnabled =
        await settingsRepository.readValue<bool>('player_force_https') ?? false;
    final androidAutoFullscreenEnabled =
        await settingsRepository.readValue<bool>(
          'player_android_auto_fullscreen',
        ) ??
        true;
    final androidBackgroundAutoPauseEnabled =
        await settingsRepository.readValue<bool>(
          'player_android_background_auto_pause',
        ) ??
        true;
    final androidPipHideDanmakuEnabled =
        await settingsRepository.readValue<bool>(
          'player_android_pip_hide_danmaku',
        ) ??
        true;
    final scaleModeRaw = await settingsRepository.readValue<String>(
      'player_scale_mode',
    );
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
      mpvAudioOutputDriver: _decodeMpvAudioOutputDriver(mpvAudioOutputDriver),
      mpvHardwareDecoder: _decodeMpvHardwareDecoder(mpvHardwareDecoder),
      mpvLogEnabled: mpvLogEnabled,
      wifiQualityPreference: wifiQualityPreference,
      cellularQualityPreference: cellularQualityPreference,
      mdkLowLatencyEnabled: mdkLowLatencyEnabled,
      mdkAndroidTunnelEnabled: mdkAndroidTunnelEnabled,
      mdkAndroidHardwareVideoDecoderEnabled:
          mdkAndroidHardwareVideoDecoderEnabled,
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

  static String _decodeMpvAudioOutputDriver(String? raw) {
    if (raw != null && kMpvAudioOutputDrivers.containsKey(raw)) {
      return raw;
    }
    return kDefaultMpvAudioOutputDriver;
  }

  static String _decodeMpvHardwareDecoder(String? raw) {
    if (raw != null && kMpvHardwareDecoders.containsKey(raw)) {
      return raw;
    }
    return kDefaultMpvHardwareDecoder;
  }

  static NetworkQualityPreference _decodeNetworkQualityPreference(
    String? raw, {
    required NetworkQualityPreference fallback,
  }) {
    final normalized = raw?.trim().toLowerCase() ?? '';
    return switch (normalized) {
      'highest' || '2' || 'high' => NetworkQualityPreference.highest,
      'lowest' || '0' || 'low' => NetworkQualityPreference.lowest,
      'middle' || '1' || 'medium' => NetworkQualityPreference.middle,
      _ => fallback,
    };
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
      'player_mpv_audio_output_driver',
      preferences.mpvAudioOutputDriver,
    );
    await settingsRepository.writeValue(
      'player_wifi_quality_level',
      preferences.wifiQualityPreference.name,
    );
    await settingsRepository.writeValue(
      'player_cellular_quality_level',
      preferences.cellularQualityPreference.name,
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
      'player_mdk_android_hardware_video_decoder',
      preferences.mdkAndroidHardwareVideoDecoderEnabled,
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

class ApplyPlayerPreferencesToRuntimeUseCase {
  const ApplyPlayerPreferencesToRuntimeUseCase(
    this.playerRuntime, {
    this.usesSystemMediaVolume = _defaultUsesSystemMediaVolume,
    this.setSystemMediaVolume,
  });

  final PlayerRuntimeController playerRuntime;
  final bool Function() usesSystemMediaVolume;
  final Future<bool> Function(double value)? setSystemMediaVolume;

  Future<void> call({
    required PlayerPreferences current,
    required PlayerPreferences next,
  }) async {
    if (current.backend != next.backend) {
      await playerRuntime.switchBackend(next.backend);
    } else if (_requiresPlayerRuntimeRefresh(current: current, next: next)) {
      await playerRuntime.refreshBackend();
    }
    final volume = next.volume.clamp(0.0, 1.0).toDouble();
    if (usesSystemMediaVolume()) {
      await playerRuntime.setVolume(1.0);
      await setSystemMediaVolume?.call(volume);
      return;
    }
    await playerRuntime.setVolume(volume);
  }
}

bool _defaultUsesSystemMediaVolume() => false;

bool _requiresPlayerRuntimeRefresh({
  required PlayerPreferences current,
  required PlayerPreferences next,
}) {
  return switch (next.backend) {
    PlayerBackend.mpv =>
      current.mpvHardwareAccelerationEnabled !=
              next.mpvHardwareAccelerationEnabled ||
          current.mpvCompatModeEnabled != next.mpvCompatModeEnabled ||
          current.mpvDoubleBufferingEnabled != next.mpvDoubleBufferingEnabled ||
          current.mpvCustomOutputEnabled != next.mpvCustomOutputEnabled ||
          current.mpvVideoOutputDriver != next.mpvVideoOutputDriver ||
          current.mpvAudioOutputDriver != next.mpvAudioOutputDriver ||
          current.mpvHardwareDecoder != next.mpvHardwareDecoder ||
          current.mpvLogEnabled != next.mpvLogEnabled,
    PlayerBackend.mdk =>
      current.mdkLowLatencyEnabled != next.mdkLowLatencyEnabled ||
          current.mdkAndroidTunnelEnabled != next.mdkAndroidTunnelEnabled ||
          current.mdkAndroidHardwareVideoDecoderEnabled !=
              next.mdkAndroidHardwareVideoDecoderEnabled,
    PlayerBackend.memory => false,
  };
}
