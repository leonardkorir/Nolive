import 'package:flutter/material.dart';
import 'package:nolive_app/src/shared/presentation/settings_page_chrome.dart';
import 'package:live_player/live_player.dart';
import 'package:nolive_app/src/features/settings/application/manage_player_preferences_use_case.dart';
import 'package:nolive_app/src/features/settings/application/settings_page_dependencies.dart';
import 'package:nolive_app/src/shared/presentation/widgets/app_surface_card.dart';
import 'package:nolive_app/src/shared/presentation/widgets/section_header.dart';

class PlayerSettingsPage extends StatefulWidget {
  const PlayerSettingsPage({required this.dependencies, super.key});

  final PlayerSettingsDependencies dependencies;

  @override
  State<PlayerSettingsPage> createState() => _PlayerSettingsPageState();
}

class _PlayerSettingsPageState extends State<PlayerSettingsPage> {
  late Future<PlayerPreferences> _future;
  /// Optimistic UI copy so toggles (especially custom output) feel instant
  /// and do not snap back to [_fallbackPreferences] while Future reloads.
  PlayerPreferences? _preferences;
  bool _saving = false;
  int _updateGeneration = 0;

  @override
  void initState() {
    super.initState();
    _future = _loadPreferencesForDisplay();
  }

  Future<PlayerPreferences> _loadPreferencesForDisplay() async {
    final preferences = await widget.dependencies.loadPlayerPreferences();
    if (!widget.dependencies.usesSystemMediaVolume) {
      return preferences;
    }
    final mediaVolume = await widget.dependencies.loadSystemMediaVolume?.call();
    if (mediaVolume == null) {
      return preferences;
    }
    return preferences.copyWith(volume: mediaVolume);
  }

  Future<void> _update({
    required PlayerPreferences current,
    required PlayerPreferences next,
  }) async {
    final generation = ++_updateGeneration;
    setState(() {
      _saving = true;
      _preferences = next;
    });
    try {
      await widget.dependencies.updatePlayerPreferences(next);
      await widget.dependencies.applyPlayerPreferencesToRuntime(
        current: current,
        next: next,
      );
      if (!mounted || generation != _updateGeneration) {
        return;
      }
      final reloaded = await _loadPreferencesForDisplay();
      if (!mounted || generation != _updateGeneration) {
        return;
      }
      setState(() {
        _preferences = reloaded;
        _future = Future<PlayerPreferences>.value(reloaded);
        _saving = false;
      });
    } catch (_) {
      if (!mounted || generation != _updateGeneration) {
        return;
      }
      setState(() {
        _preferences = current;
        _saving = false;
      });
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('播放器设置')),
      body: FutureBuilder<PlayerPreferences>(
        future: _future,
        builder: (context, snapshot) {
          final preferences =
              _preferences ?? snapshot.data ?? _fallbackPreferences;
          if (_preferences == null && snapshot.hasData) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted || _preferences != null) {
                return;
              }
              setState(() {
                _preferences = snapshot.data;
              });
            });
          }
          final rawBackends =
              widget.dependencies.playerRuntime.supportedBackends;
          final supportedBackends = widget.dependencies.isLiveMode
              ? rawBackends
                    .where((backend) => backend != PlayerBackend.memory)
                    .toList(growable: false)
              : rawBackends;
          final qualityPreferenceEnabled = !preferences.preferHighestQuality;

          return ListView(
            padding: kSettingsPagePadding,
            children: [
              const SectionHeader(
                title: '观看与播放',
                subtitle: '优先保留直播观看时最常改的项目，把底层调试参数放到后面。',
              ),
              const SizedBox(height: 12),
              AppSurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: preferences.autoPlayEnabled,
                      title: const Text('进入房间后自动播放'),
                      subtitle: const Text('关闭后先加载房间和线路，由你手动点播'),
                      onChanged: (value) {
                        _update(
                          current: preferences,
                          next: preferences.copyWith(autoPlayEnabled: value),
                        );
                      },
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      key: const Key('player-prefer-highest-quality-switch'),
                      value: preferences.preferHighestQuality,
                      title: const Text('优先高画质'),
                      subtitle: Text(
                        preferences.preferHighestQuality
                            ? '开启后始终选最高清晰度，下方默认清晰度不生效'
                            : '关闭后按下方 Wi‑Fi / 数据网络默认清晰度进入房间',
                      ),
                      onChanged: (value) {
                        _update(
                          current: preferences,
                          next: preferences.copyWith(
                            preferHighestQuality: value,
                          ),
                        );
                      },
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      key: const Key('player-auto-quality-switch'),
                      value: preferences.autoQualityEnabled,
                      title: const Text('自动画质（Auto）'),
                      subtitle: Text(
                        preferences.autoQualityEnabled
                            ? '含 Auto 的平台（Twitch / SC / CB 等）进房只用 Auto；YouTube 不含 Auto，按固定档/高画质处理'
                            : '关闭后：优先高画质/默认「最高」会先 Auto 热身再切最高档（二次加载；YouTube 仍走固定档）',
                      ),
                      onChanged: (value) {
                        _update(
                          current: preferences,
                          next: preferences.copyWith(
                            autoQualityEnabled: value,
                          ),
                        );
                      },
                    ),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: Text(
                        '默认清晰度（Wi‑Fi）',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      qualityPreferenceEnabled
                          ? '进入房间时在可用清晰度中按偏好挑选'
                          : '已开启「优先高画质」，此项暂不生效',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final preference
                            in NetworkQualityPreference.values)
                          ChoiceChip(
                            key: Key('player-wifi-quality-${preference.name}'),
                            label: Text(_labelOfQuality(preference)),
                            selected:
                                preferences.wifiQualityPreference ==
                                preference,
                            onSelected: !qualityPreferenceEnabled
                                ? null
                                : (_) {
                                    _update(
                                      current: preferences,
                                      next: preferences.copyWith(
                                        wifiQualityPreference: preference,
                                      ),
                                    );
                                  },
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '默认清晰度（数据网络）',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final preference
                            in NetworkQualityPreference.values)
                          ChoiceChip(
                            key: Key(
                              'player-cellular-quality-${preference.name}',
                            ),
                            label: Text(_labelOfQuality(preference)),
                            selected:
                                preferences.cellularQualityPreference ==
                                preference,
                            onSelected: !qualityPreferenceEnabled
                                ? null
                                : (_) {
                                    _update(
                                      current: preferences,
                                      next: preferences.copyWith(
                                        cellularQualityPreference: preference,
                                      ),
                                    );
                                  },
                          ),
                      ],
                    ),
                    const Divider(height: 20),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      key: const Key('player-force-https-switch'),
                      value: preferences.forceHttpsEnabled,
                      title: const Text('优先 HTTPS 播放源'),
                      subtitle: const Text('网络允许时优先选择更稳妥的 HTTPS 线路'),
                      onChanged: (value) {
                        _update(
                          current: preferences,
                          next: preferences.copyWith(forceHttpsEnabled: value),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const SectionHeader(
                title: '直播间与小窗',
                subtitle: 'Android 观看行为设置，进入房间后可以直接生效。',
              ),
              const SizedBox(height: 12),
              AppSurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      key: const Key('player-auto-fullscreen-switch'),
                      value: preferences.androidAutoFullscreenEnabled,
                      title: const Text('进入房间自动全屏'),
                      subtitle: const Text('更接近原生直播 App 的默认观看方式'),
                      onChanged: (value) {
                        _update(
                          current: preferences,
                          next: preferences.copyWith(
                            androidAutoFullscreenEnabled: value,
                          ),
                        );
                      },
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      key: const Key('player-background-auto-pause-switch'),
                      value: preferences.androidBackgroundAutoPauseEnabled,
                      title: const Text('切到后台自动暂停'),
                      subtitle: const Text('返回前台时恢复到刚才的播放状态'),
                      onChanged: (value) {
                        _update(
                          current: preferences,
                          next: preferences.copyWith(
                            androidBackgroundAutoPauseEnabled: value,
                          ),
                        );
                      },
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      key: const Key('player-pip-hide-danmaku-switch'),
                      value: preferences.androidPipHideDanmakuEnabled,
                      title: const Text('小窗时隐藏弹幕'),
                      subtitle: const Text('进入 Android PiP 后让画面更干净、避免遮挡'),
                      onChanged: (value) {
                        _update(
                          current: preferences,
                          next: preferences.copyWith(
                            androidPipHideDanmakuEnabled: value,
                          ),
                        );
                      },
                    ),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: Text(
                        '画面尺寸',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (final scaleMode in PlayerScaleMode.values)
                          ChoiceChip(
                            key: Key('player-scale-mode-${scaleMode.name}'),
                            label: Text(_labelOfScaleMode(scaleMode)),
                            selected: preferences.scaleMode == scaleMode,
                            onSelected: (_) {
                              _update(
                                current: preferences,
                                next: preferences.copyWith(
                                  scaleMode: scaleMode,
                                ),
                              );
                            },
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const SectionHeader(
                title: '播放器内核',
                subtitle: 'Android 首发默认 MPV，必要时可切到 MDK。',
              ),
              const SizedBox(height: 12),
              AppSurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '当前运行时：${widget.dependencies.playerRuntime.backend.name.toUpperCase()}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (final backend in supportedBackends)
                          ChoiceChip(
                            label: Text(_labelOf(backend)),
                            selected: preferences.backend == backend,
                            onSelected: (_) {
                              _update(
                                current: preferences,
                                next: preferences.copyWith(backend: backend),
                              );
                            },
                          ),
                      ],
                    ),
                    if (!widget.dependencies.isLiveMode) ...[
                      const SizedBox(height: 10),
                      Text(
                        '预览环境会额外展示 Memory 后端，方便测试。',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              AppSurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('音量', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Slider(
                      key: const Key('player-volume-slider'),
                      value: preferences.volume,
                      onChanged: (value) {
                        _update(
                          current: preferences,
                          next: preferences.copyWith(volume: value),
                        );
                      },
                    ),
                    Text('当前音量：${(preferences.volume * 100).round()}%'),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              AppSurfaceCard(
                child: _buildAdvancedOptions(context, preferences),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildAdvancedOptions(
    BuildContext context,
    PlayerPreferences preferences,
  ) {
    final titleStyle = Theme.of(context).textTheme.titleMedium;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: switch (preferences.backend) {
        PlayerBackend.mpv => [
          Text('MPV 高级设置', style: titleStyle),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            key: const Key('player-mpv-hardware-switch'),
            value: preferences.mpvHardwareAccelerationEnabled,
            title: const Text('硬件解码'),
            subtitle: const Text('优先使用设备硬解，降低功耗并更适合长时间观看'),
            onChanged: (value) {
              _update(
                current: preferences,
                next: preferences.copyWith(
                  mpvHardwareAccelerationEnabled: value,
                ),
              );
            },
          ),
          const Divider(height: 1),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            key: const Key('player-mpv-compat-switch'),
            value: preferences.mpvCompatModeEnabled,
            title: const Text('兼容模式'),
            subtitle: const Text('遇到黑屏、花屏或个别机型异常时再开启'),
            onChanged: (value) {
              _update(
                current: preferences,
                next: preferences.copyWith(mpvCompatModeEnabled: value),
              );
            },
          ),
          const Divider(height: 1),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            key: const Key('player-mpv-double-buffering-switch'),
            value: preferences.mpvDoubleBufferingEnabled,
            title: const Text('双缓冲'),
            subtitle: const Text('直播弱网场景下更稳，但会占用更多缓存'),
            onChanged: (value) {
              _update(
                current: preferences,
                next: preferences.copyWith(mpvDoubleBufferingEnabled: value),
              );
            },
          ),
          const Divider(height: 1),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            key: const Key('player-mpv-custom-output-switch'),
            value: preferences.mpvCustomOutputEnabled,
            title: const Text('自定义输出驱动'),
            subtitle: Text(
              preferences.mpvCustomOutputEnabled
                  ? '已开启：下方 vo/ao/hwdec 立即生效（需重建播放器）'
                  : '开启后可手动指定 MPV vo/ao/hwdec，优先级高于兼容模式',
            ),
            onChanged: (value) {
              _update(
                current: preferences,
                next: preferences.copyWith(mpvCustomOutputEnabled: value),
              );
            },
          ),
          const Divider(height: 1),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            key: const Key('player-mpv-external-native-window-switch'),
            value: preferences.mpvAllowExternalNativeWindow,
            title: const Text('独立原生 MPV 窗口'),
            subtitle: Text(
              preferences.mpvAllowExternalNativeWindow
                  ? '已开启：视频在系统独立窗口（默认 gpu-next），App 内为占位；用于验证原生流畅度'
                  : '可选：用 mpv 原生 VO 开独立窗口，绕过 Flutter Texture（默认关闭）',
            ),
            onChanged: (value) {
              final nextVo = value
                  ? (kDesktopWindowOpeningMpvVideoOutputs.contains(
                          preferences.mpvVideoOutputDriver,
                        )
                        ? preferences.mpvVideoOutputDriver
                        : kDefaultMpvVideoOutputDriver)
                  : kDesktopEmbedSafeMpvVideoOutputDriver;
              _update(
                current: preferences,
                next: preferences.copyWith(
                  mpvAllowExternalNativeWindow: value,
                  // External path needs an explicit VO; keep embed-safe when off.
                  mpvCustomOutputEnabled:
                      value ? true : preferences.mpvCustomOutputEnabled,
                  mpvVideoOutputDriver: nextVo,
                ),
              );
            },
          ),
          const Divider(height: 1),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            key: const Key('player-mpv-log-enable-switch'),
            value: preferences.mpvLogEnabled,
            title: const Text('调试日志'),
            subtitle: const Text('打开后会采集更多播放器日志，便于定位问题'),
            onChanged: (value) {
              _update(
                current: preferences,
                next: preferences.copyWith(mpvLogEnabled: value),
              );
            },
          ),
          const Divider(height: 20),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '视频输出驱动 (--vo)',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            key: ValueKey(
              'player-mpv-video-output-'
              '${preferences.mpvCustomOutputEnabled}-'
              '${preferences.mpvAllowExternalNativeWindow}-'
              '${preferences.mpvVideoOutputDriver}',
            ),
            initialValue: preferences.mpvVideoOutputDriver,
            items: kMpvVideoOutputDrivers.entries
                .map(
                  (entry) => DropdownMenuItem<String>(
                    value: entry.key,
                    child: Text(
                      kDesktopWindowOpeningMpvVideoOutputs.contains(entry.key)
                          ? '${entry.value}（独立窗口）'
                          : entry.value,
                    ),
                  ),
                )
                .toList(growable: false),
            onChanged:
                (preferences.mpvCustomOutputEnabled ||
                        preferences.mpvAllowExternalNativeWindow) &&
                    !_saving
                ? (value) {
                    if (value == null) {
                      return;
                    }
                    _update(
                      current: preferences,
                      next: preferences.copyWith(mpvVideoOutputDriver: value),
                    );
                  }
                : null,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              isDense: true,
              helperText: preferences.mpvAllowExternalNativeWindow
                  ? '独立窗口模式：推荐 gpu-next / gpu / dmabuf-wayland'
                  : preferences.mpvCustomOutputEnabled
                  ? '当前已启用自定义输出（桌面默认仍会把独立窗口 VO 改回 libmpv，除非开启「独立原生 MPV 窗口」）'
                  : '需开启「自定义输出驱动」或「独立原生 MPV 窗口」后生效',
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '音频输出驱动 (--ao)',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            key: ValueKey(
              'player-mpv-audio-output-${preferences.mpvCustomOutputEnabled}-${preferences.mpvAudioOutputDriver}',
            ),
            initialValue: preferences.mpvAudioOutputDriver,
            items: kMpvAudioOutputDrivers.entries
                .map(
                  (entry) => DropdownMenuItem<String>(
                    value: entry.key,
                    child: Text(entry.value),
                  ),
                )
                .toList(growable: false),
            onChanged: preferences.mpvCustomOutputEnabled && !_saving
                ? (value) {
                    if (value == null) {
                      return;
                    }
                    _update(
                      current: preferences,
                      next: preferences.copyWith(mpvAudioOutputDriver: value),
                    );
                  }
                : null,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              isDense: true,
              helperText: preferences.mpvCustomOutputEnabled
                  ? '当前已启用自定义输出'
                  : '需开启「自定义输出驱动」后生效',
            ),
          ),
          const SizedBox(height: 12),
          Text('硬件解码器 (--hwdec)', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            key: ValueKey(
              'player-mpv-hardware-decoder-${preferences.mpvCustomOutputEnabled}-${preferences.mpvHardwareDecoder}',
            ),
            initialValue: preferences.mpvHardwareDecoder,
            items: kMpvHardwareDecoders.entries
                .map(
                  (entry) => DropdownMenuItem<String>(
                    value: entry.key,
                    child: Text(entry.value),
                  ),
                )
                .toList(growable: false),
            onChanged: preferences.mpvCustomOutputEnabled && !_saving
                ? (value) {
                    if (value == null) {
                      return;
                    }
                    _update(
                      current: preferences,
                      next: preferences.copyWith(mpvHardwareDecoder: value),
                    );
                  }
                : null,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              isDense: true,
              helperText: preferences.mpvCustomOutputEnabled
                  ? '当前已启用自定义输出'
                  : '需开启「自定义输出驱动」后生效',
            ),
          ),
        ],
        PlayerBackend.mdk => [
          Text('MDK 高级设置', style: titleStyle),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            key: const Key('player-mdk-low-latency-switch'),
            value: preferences.mdkLowLatencyEnabled,
            title: const Text('低延迟模式'),
            subtitle: const Text('更适合直播场景，但弱网下更容易抖动'),
            onChanged: (value) {
              _update(
                current: preferences,
                next: preferences.copyWith(mdkLowLatencyEnabled: value),
              );
            },
          ),
          const Divider(height: 1),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            key: const Key('player-mdk-tunnel-switch'),
            value: preferences.mdkAndroidTunnelEnabled,
            title: const Text('Android Tunnel'),
            subtitle: const Text('某些设备上更稳、更省电，但兼容性取决于机型'),
            onChanged: (value) {
              _update(
                current: preferences,
                next: preferences.copyWith(mdkAndroidTunnelEnabled: value),
              );
            },
          ),
          const Divider(height: 1),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            key: const Key('player-mdk-hardware-video-decoder-switch'),
            value: preferences.mdkAndroidHardwareVideoDecoderEnabled,
            title: const Text('优先使用 Android 硬解'),
            subtitle: const Text('优先尝试 MediaCodec / AMediaCodec 解码视频'),
            onChanged: (value) {
              _update(
                current: preferences,
                next: preferences.copyWith(
                  mdkAndroidHardwareVideoDecoderEnabled: value,
                ),
              );
            },
          ),
        ],
        PlayerBackend.memory => [
          Text('Memory 预览后端', style: titleStyle),
          const SizedBox(height: 8),
          Text(
            '仅用于预览和测试环境，不建议作为 Android 实际观看后端。',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      },
    );
  }

  String _labelOf(PlayerBackend backend) {
    return switch (backend) {
      PlayerBackend.memory => 'Memory',
      PlayerBackend.mpv => 'MPV',
      PlayerBackend.mdk => 'MDK',
    };
  }

  String _labelOfScaleMode(PlayerScaleMode scaleMode) {
    return switch (scaleMode) {
      PlayerScaleMode.contain => '适应',
      PlayerScaleMode.cover => '铺满',
      PlayerScaleMode.fill => '拉伸',
      PlayerScaleMode.fitWidth => '按宽适配',
      PlayerScaleMode.fitHeight => '按高适配',
    };
  }

  String _labelOfQuality(NetworkQualityPreference preference) {
    return switch (preference) {
      NetworkQualityPreference.highest => '最高',
      NetworkQualityPreference.middle => '中等',
      NetworkQualityPreference.lowest => '最低',
    };
  }
}

const PlayerPreferences _fallbackPreferences = PlayerPreferences(
  autoPlayEnabled: true,
  preferHighestQuality: false,
  autoQualityEnabled: true,
  backend: PlayerBackend.mpv,
  volume: 1,
  mpvHardwareAccelerationEnabled: true,
  mpvCompatModeEnabled: false,
  mpvDoubleBufferingEnabled: false,
  mpvCustomOutputEnabled: false,
  mpvVideoOutputDriver: kDefaultMpvVideoOutputDriver,
  mpvAudioOutputDriver: kDefaultMpvAudioOutputDriver,
  mpvHardwareDecoder: kDefaultMpvHardwareDecoder,
  mpvLogEnabled: false,
  wifiQualityPreference: NetworkQualityPreference.middle,
  cellularQualityPreference: NetworkQualityPreference.lowest,
  mdkLowLatencyEnabled: true,
  mdkAndroidTunnelEnabled: false,
  mdkAndroidHardwareVideoDecoderEnabled: true,
  forceHttpsEnabled: false,
  androidAutoFullscreenEnabled: true,
  androidBackgroundAutoPauseEnabled: true,
  androidPipHideDanmakuEnabled: true,
  scaleMode: PlayerScaleMode.contain,
);

