import 'package:flutter/material.dart';
import 'package:nolive_app/src/app/routing/app_routes.dart';
import 'package:nolive_app/src/features/settings/application/manage_player_preferences_use_case.dart';
import 'package:nolive_app/src/features/settings/application/manage_room_ui_preferences_use_case.dart';
import 'package:nolive_app/src/features/settings/application/settings_page_dependencies.dart';
import 'package:nolive_app/src/shared/presentation/widgets/app_surface_card.dart';
import 'package:nolive_app/src/shared/presentation/widgets/section_header.dart';

class RoomSettingsPage extends StatefulWidget {
  const RoomSettingsPage({required this.dependencies, super.key});

  final RoomSettingsDependencies dependencies;

  @override
  State<RoomSettingsPage> createState() => _RoomSettingsPageState();
}

class _RoomSettingsPageState extends State<RoomSettingsPage> {
  PlayerPreferences? _playerPreferences;
  RoomUiPreferences? _roomUiPreferences;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final playerPreferences = await widget.dependencies.loadPlayerPreferences();
    final roomUiPreferences = await widget.dependencies.loadRoomUiPreferences();
    if (!mounted) {
      return;
    }
    setState(() {
      _playerPreferences = playerPreferences;
      _roomUiPreferences = roomUiPreferences;
    });
  }

  Future<void> _updatePlayer(PlayerPreferences next) async {
    setState(() {
      _playerPreferences = next;
    });
    await widget.dependencies.updatePlayerPreferences(next);
  }

  Future<void> _updateRoomUi(RoomUiPreferences next) async {
    setState(() {
      _roomUiPreferences = next;
    });
    await widget.dependencies.updateRoomUiPreferences(next);
  }

  @override
  Widget build(BuildContext context) {
    final playerPreferences = _playerPreferences;
    final roomUiPreferences = _roomUiPreferences;
    if (playerPreferences == null || roomUiPreferences == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator.adaptive()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('直播间设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        children: [
          const SectionHeader(
            title: '直播间设置',
            subtitle: '把观看期最常改的房间、聊天区和播放器偏好收口到独立页面。',
          ),
          const SizedBox(height: 12),
          AppSurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '播放器',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: playerPreferences.androidBackgroundAutoPauseEnabled,
                  title: const Text('进入后台自动暂停'),
                  onChanged: (value) {
                    _updatePlayer(
                      playerPreferences.copyWith(
                        androidBackgroundAutoPauseEnabled: value,
                      ),
                    );
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('画面尺寸'),
                  trailing: Text(_scaleModeLabel(playerPreferences.scaleMode)),
                  onTap: () {
                    final modes = PlayerScaleMode.values;
                    final index = modes.indexOf(playerPreferences.scaleMode);
                    _updatePlayer(
                      playerPreferences.copyWith(
                        scaleMode: modes[(index + 1) % modes.length],
                      ),
                    );
                  },
                ),
                const Divider(height: 1),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: playerPreferences.forceHttpsEnabled,
                  title: const Text('使用 HTTPS 链接'),
                  subtitle: const Text('优先将可替换的 http 播放地址切到 https'),
                  onChanged: (value) {
                    _updatePlayer(
                      playerPreferences.copyWith(forceHttpsEnabled: value),
                    );
                  },
                ),
                const Divider(height: 1),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: playerPreferences.androidAutoFullscreenEnabled,
                  title: const Text('进入直播间自动全屏'),
                  onChanged: (value) {
                    _updatePlayer(
                      playerPreferences.copyWith(
                        androidAutoFullscreenEnabled: value,
                      ),
                    );
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('默认清晰度'),
                  subtitle: Text(
                    playerPreferences.preferHighestQuality
                        ? '优先最高可用画质'
                        : '使用平台默认推荐画质',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    _updatePlayer(
                      playerPreferences.copyWith(
                        preferHighestQuality:
                            !playerPreferences.preferHighestQuality,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          AppSurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '聊天区',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                _StepperTile(
                  title: '文字大小',
                  value: roomUiPreferences.chatTextSize.round(),
                  onChanged: (next) {
                    _updateRoomUi(
                      roomUiPreferences.copyWith(
                        chatTextSize: next.clamp(12, 22).toDouble(),
                      ),
                    );
                  },
                ),
                const Divider(height: 1),
                _StepperTile(
                  title: '上下间隔',
                  value: roomUiPreferences.chatTextGap.round(),
                  onChanged: (next) {
                    _updateRoomUi(
                      roomUiPreferences.copyWith(
                        chatTextGap: next.clamp(0, 12).toDouble(),
                      ),
                    );
                  },
                ),
                const Divider(height: 1),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: roomUiPreferences.chatBubbleStyle,
                  title: const Text('气泡样式'),
                  onChanged: (value) {
                    _updateRoomUi(
                      roomUiPreferences.copyWith(chatBubbleStyle: value),
                    );
                  },
                ),
                const Divider(height: 1),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: roomUiPreferences.showPlayerSuperChat,
                  title: const Text('播放器中显示 SC'),
                  onChanged: (value) {
                    _updateRoomUi(
                      roomUiPreferences.copyWith(showPlayerSuperChat: value),
                    );
                  },
                ),
                const Divider(height: 1),
                _StepperTile(
                  title: 'SC 展示时长',
                  value: roomUiPreferences.playerSuperChatDisplaySeconds,
                  suffix: '秒',
                  onChanged: (next) {
                    _updateRoomUi(
                      roomUiPreferences.copyWith(
                        playerSuperChatDisplaySeconds: next.clamp(3, 30),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          AppSurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '更多设置',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('关键词屏蔽'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.of(context).pushNamed(
                    AppRoutes.danmakuShield,
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('弹幕设置'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.of(context).pushNamed(
                    AppRoutes.danmakuSettings,
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('播放器高级设置'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.of(context).pushNamed(
                    AppRoutes.playerSettings,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _scaleModeLabel(PlayerScaleMode mode) {
    return switch (mode) {
      PlayerScaleMode.contain => '适应',
      PlayerScaleMode.cover => '铺满',
      PlayerScaleMode.fill => '拉伸',
      PlayerScaleMode.fitWidth => '宽度优先',
      PlayerScaleMode.fitHeight => '高度优先',
    };
  }
}

class _StepperTile extends StatelessWidget {
  const _StepperTile({
    required this.title,
    required this.value,
    required this.onChanged,
    this.suffix = '',
  });

  final String title;
  final int value;
  final ValueChanged<int> onChanged;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: () => onChanged(value - 1),
            icon: const Icon(Icons.remove_rounded),
          ),
          SizedBox(
            width: suffix.isEmpty ? 36 : 56,
            child: Text(
              '$value$suffix',
              textAlign: TextAlign.center,
            ),
          ),
          IconButton(
            onPressed: () => onChanged(value + 1),
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
    );
  }
}
