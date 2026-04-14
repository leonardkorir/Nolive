import 'package:flutter/material.dart';
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

  @override
  void initState() {
    super.initState();
    _future = widget.dependencies.loadPlayerPreferences();
  }

  Future<void> _update({
    required PlayerPreferences current,
    required PlayerPreferences next,
  }) async {
    await widget.dependencies.updatePlayerPreferences(next);
    await widget.dependencies.applyPlayerPreferencesToRuntime(
      current: current,
      next: next,
    );
    setState(() {
      _future = widget.dependencies.loadPlayerPreferences();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('播放器设置')),
      body: FutureBuilder<PlayerPreferences>(
        future: _future,
        builder: (context, snapshot) {
          final preferences = snapshot.data ?? _fallbackPreferences;
          final rawBackends =
              widget.dependencies.playerRuntime.supportedBackends;
          final supportedBackends = widget.dependencies.isLiveMode
              ? rawBackends
                  .where((backend) => backend != PlayerBackend.memory)
                  .toList(growable: false)
              : rawBackends;

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
            children: [
              const SectionHeader(
                title: '观看与播放',
                subtitle: '优先保留直播观看时最常改的项目，把底层调试参数放到后面。',
              ),
              const SizedBox(height: 12),
              AppSurfaceCard(
                child: Column(
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
                      value: preferences.preferHighestQuality,
                      title: const Text('优先高画质'),
                      subtitle: const Text('进入房间时优先尝试更高的清晰度'),
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
                                next:
                                    preferences.copyWith(scaleMode: scaleMode),
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
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
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
                  next: preferences.copyWith(
                    mpvDoubleBufferingEnabled: value,
                  ),
                );
              },
            ),
            const Divider(height: 1),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              key: const Key('player-mpv-custom-output-switch'),
              value: preferences.mpvCustomOutputEnabled,
              title: const Text('自定义输出驱动'),
              subtitle: const Text('手动指定 MPV 输出驱动，优先级高于兼容模式'),
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
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Text(
                '视频输出驱动',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              key: const Key('player-mpv-video-output-dropdown'),
              initialValue: preferences.mpvVideoOutputDriver,
              items: kMpvVideoOutputDrivers.entries
                  .map(
                    (entry) => DropdownMenuItem<String>(
                      value: entry.key,
                      child: Text(entry.value),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                _update(
                  current: preferences,
                  next: preferences.copyWith(mpvVideoOutputDriver: value),
                );
              },
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '硬件解码器',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              key: const Key('player-mpv-hardware-decoder-dropdown'),
              initialValue: preferences.mpvHardwareDecoder,
              items: kMpvHardwareDecoders.entries
                  .map(
                    (entry) => DropdownMenuItem<String>(
                      value: entry.key,
                      child: Text(entry.value),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                _update(
                  current: preferences,
                  next: preferences.copyWith(mpvHardwareDecoder: value),
                );
              },
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
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
                  next: preferences.copyWith(
                    mdkAndroidTunnelEnabled: value,
                  ),
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
}

const PlayerPreferences _fallbackPreferences = PlayerPreferences(
  autoPlayEnabled: true,
  preferHighestQuality: false,
  backend: PlayerBackend.mpv,
  volume: 1,
  mpvHardwareAccelerationEnabled: true,
  mpvCompatModeEnabled: false,
  mpvDoubleBufferingEnabled: false,
  mpvCustomOutputEnabled: false,
  mpvVideoOutputDriver: kDefaultMpvVideoOutputDriver,
  mpvHardwareDecoder: kDefaultMpvHardwareDecoder,
  mpvLogEnabled: false,
  mdkLowLatencyEnabled: true,
  mdkAndroidTunnelEnabled: false,
  mdkAndroidHardwareVideoDecoderEnabled: true,
  forceHttpsEnabled: false,
  androidAutoFullscreenEnabled: true,
  androidBackgroundAutoPauseEnabled: true,
  androidPipHideDanmakuEnabled: true,
  scaleMode: PlayerScaleMode.contain,
);
