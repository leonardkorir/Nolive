import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:live_player/live_player.dart';
import 'package:live_storage/live_storage.dart';
import 'package:nolive_app/src/app/platform/app_platform_capabilities.dart';
import 'package:nolive_app/src/shared/application/player_runtime_controller.dart';

enum PlayerScaleMode { contain, cover, fill, fitWidth, fitHeight }

const String kDefaultMpvVideoOutputDriver = 'gpu-next';
const String kDefaultMpvHardwareDecoder = 'auto-safe';
/// Linux embed (libmpv + Flutter texture): prefer copy-mode HW decode so
/// VAAPI/NVDEC still count as hardware even when zero-copy interop is flaky.
const String kDefaultMpvHardwareDecoderLinux = 'auto-copy';

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
  'vaapi-copy': 'vaapi-copy',
  'nvdec': 'nvdec',
  'nvdec-copy': 'nvdec-copy',
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
      if (key == 'vaapi' || key == 'vaapi-copy') return isLinux;
      if (key == 'nvdec' || key == 'nvdec-copy') return isLinux || isWindows;
      return true;
    }),
  );
}

/// VO drivers that open an independent OS window instead of embedding into the
/// app texture (media_kit). On desktop these leave an "external MPV" window
/// that users cannot close without killing the whole process.
const Set<String> kDesktopWindowOpeningMpvVideoOutputs = <String>{
  'gpu',
  'gpu-next',
  'sdl',
  'vaapi',
  'dmabuf-wayland',
  'direct3d',
  'xv',
  'x11',
  'wayland',
};

/// Embed-safe default for desktop custom-output paths.
const String kDesktopEmbedSafeMpvVideoOutputDriver = 'libmpv';

/// Env flag for A/B: independent native mpv VO window (gpu-next etc.).
const String kNoliveAllowExternalMpvWindowEnv =
    'NOLIVE_ALLOW_EXTERNAL_MPV_WINDOW';

/// Optional VO override when external window mode is enabled (default gpu-next).
const String kNoliveExternalMpvVoEnv = 'NOLIVE_MPV_EXTERNAL_VO';

bool _envFlagTruthy(String? raw) {
  final value = raw?.trim().toLowerCase() ?? '';
  return value == '1' ||
      value == 'true' ||
      value == 'yes' ||
      value == 'on';
}

Map<String, String> _defaultProcessEnvironment() {
  if (kIsWeb) {
    return const <String, String>{};
  }
  try {
    return Platform.environment;
  } catch (_) {
    return const <String, String>{};
  }
}

/// True when settings and/or env opt into the external native mpv window path.
bool resolveAllowExternalNativeMpvWindow({
  required bool preferenceEnabled,
  Map<String, String>? environment,
}) {
  final env = environment ?? _defaultProcessEnvironment();
  if (_envFlagTruthy(env[kNoliveAllowExternalMpvWindowEnv])) {
    return true;
  }
  return preferenceEnabled;
}

/// Optional VO from env; null when unset / empty.
String? resolveExternalMpvVoFromEnvironment([
  Map<String, String>? environment,
]) {
  final env = environment ?? _defaultProcessEnvironment();
  final raw = env[kNoliveExternalMpvVoEnv]?.trim() ?? '';
  if (raw.isEmpty) {
    return null;
  }
  return raw;
}

/// Reject cross-platform leftovers after sync (e.g. Android mediacodec on Linux).
/// On desktop, also rewrite window-opening VO drivers to [libmpv] so playback
/// stays inside the app — unless [allowExternalNativeWindow] is true (opt-in A).
String sanitizeMpvVideoOutputDriverForPlatform(
  String? raw, {
  required bool isAndroid,
  required bool isLinux,
  required bool isWindows,
  required bool isApple,
  bool allowExternalNativeWindow = false,
}) {
  final key = raw?.trim() ?? '';
  final allowed = mpvVideoOutputDriversForPlatform(
    isAndroid: isAndroid,
    isLinux: isLinux,
    isWindows: isWindows,
    isApple: isApple,
  );
  final isDesktop = isLinux || isWindows || isApple;
  if (key.isEmpty || !allowed.containsKey(key)) {
    if (isAndroid) {
      return kDefaultMpvVideoOutputDriver;
    }
    if (isDesktop && allowExternalNativeWindow) {
      return kDefaultMpvVideoOutputDriver;
    }
    return kDesktopEmbedSafeMpvVideoOutputDriver;
  }
  if (isDesktop &&
      !allowExternalNativeWindow &&
      kDesktopWindowOpeningMpvVideoOutputs.contains(key)) {
    return kDesktopEmbedSafeMpvVideoOutputDriver;
  }
  return key;
}

String sanitizeMpvHardwareDecoderForPlatform(
  String? raw, {
  required bool isAndroid,
  required bool isLinux,
  required bool isWindows,
  required bool isApple,
}) {
  final key = raw?.trim() ?? '';
  final allowed = mpvHardwareDecodersForPlatform(
    isAndroid: isAndroid,
    isLinux: isLinux,
    isWindows: isWindows,
    isApple: isApple,
  );
  if (key.isEmpty || !allowed.containsKey(key)) {
    if (isLinux) {
      return kDefaultMpvHardwareDecoderLinux;
    }
    return kDefaultMpvHardwareDecoder;
  }
  // Linux: auto-safe often never activates VAAPI under libmpv embed; promote
  // the default preference to auto-copy when the user has not chosen a backend.
  if (isLinux && (key == 'auto-safe' || key == 'auto')) {
    return kDefaultMpvHardwareDecoderLinux;
  }
  return key;
}

String sanitizeMpvAudioOutputDriverForPlatform(
  String? raw, {
  required bool isAndroid,
  required bool isLinux,
  required bool isWindows,
  required bool isApple,
}) {
  final key = raw?.trim() ?? '';
  final allowed = mpvAudioOutputDriversForPlatform(
    isAndroid: isAndroid,
    isLinux: isLinux,
    isWindows: isWindows,
    isApple: isApple,
  );
  if (key.isEmpty || !allowed.containsKey(key)) {
    return kDefaultMpvAudioOutputDriver;
  }
  return key;
}

class PlayerPreferences {
  const PlayerPreferences({
    required this.autoPlayEnabled,
    required this.preferHighestQuality,
    required this.autoQualityEnabled,
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
    this.mpvAllowExternalNativeWindow = false,
  });

  final bool autoPlayEnabled;
  final bool preferHighestQuality;

  /// When true, providers that expose an adaptive "auto" tier start on auto
  /// (warmup-friendly). When false, network / prefer-highest picks fixed tiers.
  final bool autoQualityEnabled;
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

  /// Desktop opt-in: play via independent mpv VO window (gpu-next) instead of
  /// Flutter texture embed. Used to validate native smoothness (plan A).
  final bool mpvAllowExternalNativeWindow;
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
    bool? autoQualityEnabled,
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
    bool? mpvAllowExternalNativeWindow,
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
      autoQualityEnabled: autoQualityEnabled ?? this.autoQualityEnabled,
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
      mpvAllowExternalNativeWindow:
          mpvAllowExternalNativeWindow ?? this.mpvAllowExternalNativeWindow,
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
  LoadPlayerPreferencesUseCase(
    this.settingsRepository, {
    AppPlatformCapabilities? platformCapabilities,
  }) : _platformCapabilities =
           platformCapabilities ?? AppPlatformCapabilities.current();

  final SettingsRepository settingsRepository;
  final AppPlatformCapabilities _platformCapabilities;

  Future<PlayerPreferences> call() async {
    final autoPlay =
        await settingsRepository.readValue<bool>('player_auto_play') ?? true;
    final preferHighestQuality =
        await settingsRepository.readValue<bool>(
          'player_prefer_highest_quality',
        ) ??
        false;
    final autoQualityEnabled =
        await settingsRepository.readValue<bool>(
          'player_auto_quality_enabled',
        ) ??
        true;
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
    final mpvAllowExternalNativeWindowPreference =
        await settingsRepository.readValue<bool>(
          'player_mpv_allow_external_native_window',
        ) ??
        false;
    final rawVideoOutputDriver =
        await settingsRepository.readValue<String>(
          'player_mpv_video_output_driver',
        );
    final rawHardwareDecoder =
        await settingsRepository.readValue<String>(
          'player_mpv_hardware_decoder',
        );
    final rawAudioOutputDriver =
        await settingsRepository.readValue<String>(
          'player_mpv_audio_output_driver',
        );
    final platform = _platformCapabilities;
    // Env can force the A/B path without touching settings persistence.
    final mpvAllowExternalNativeWindow = platform.isDesktop &&
        resolveAllowExternalNativeMpvWindow(
          preferenceEnabled: mpvAllowExternalNativeWindowPreference,
        );
    final envVoOverride = resolveExternalMpvVoFromEnvironment();
    final mpvVideoOutputDriver = sanitizeMpvVideoOutputDriverForPlatform(
      envVoOverride ?? rawVideoOutputDriver,
      isAndroid: platform.isAndroid,
      isLinux: platform.isLinux,
      isWindows: platform.isWindows,
      isApple: platform.isIOS || platform.isMacOS,
      allowExternalNativeWindow: mpvAllowExternalNativeWindow,
    );
    final mpvHardwareDecoder = sanitizeMpvHardwareDecoderForPlatform(
      rawHardwareDecoder,
      isAndroid: platform.isAndroid,
      isLinux: platform.isLinux,
      isWindows: platform.isWindows,
      isApple: platform.isIOS || platform.isMacOS,
    );
    final mpvAudioOutputDriver = sanitizeMpvAudioOutputDriverForPlatform(
      rawAudioOutputDriver,
      isAndroid: platform.isAndroid,
      isLinux: platform.isLinux,
      isWindows: platform.isWindows,
      isApple: platform.isIOS || platform.isMacOS,
    );
    // Persist platform-safe values so Android mediacodec leftovers from sync
    // cannot keep poisoning cold starts / room enter on Linux desktop.
    // Do not rewrite storage when only env forced an external VO override.
    if (envVoOverride == null &&
        rawVideoOutputDriver != mpvVideoOutputDriver) {
      await settingsRepository.writeValue(
        'player_mpv_video_output_driver',
        mpvVideoOutputDriver,
      );
    }
    if (rawHardwareDecoder != mpvHardwareDecoder) {
      await settingsRepository.writeValue(
        'player_mpv_hardware_decoder',
        mpvHardwareDecoder,
      );
    }
    if (rawAudioOutputDriver != mpvAudioOutputDriver) {
      await settingsRepository.writeValue(
        'player_mpv_audio_output_driver',
        mpvAudioOutputDriver,
      );
    }
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
      autoQualityEnabled: autoQualityEnabled,
      backend: _decodeBackend(backendRaw),
      volume: volume.clamp(0.0, 1.0),
      mpvHardwareAccelerationEnabled: mpvHardwareAccelerationEnabled,
      mpvCompatModeEnabled: mpvCompatModeEnabled,
      mpvDoubleBufferingEnabled: mpvDoubleBufferingEnabled,
      mpvCustomOutputEnabled: mpvCustomOutputEnabled,
      mpvVideoOutputDriver: mpvVideoOutputDriver,
      mpvAudioOutputDriver: mpvAudioOutputDriver,
      mpvHardwareDecoder: mpvHardwareDecoder,
      mpvLogEnabled: mpvLogEnabled,
      mpvAllowExternalNativeWindow: mpvAllowExternalNativeWindow,
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
      'player_auto_quality_enabled',
      preferences.autoQualityEnabled,
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
      'player_mpv_allow_external_native_window',
      preferences.mpvAllowExternalNativeWindow,
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
          current.mpvAllowExternalNativeWindow !=
              next.mpvAllowExternalNativeWindow ||
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
