import 'package:flutter/material.dart';
import 'package:nolive_app/src/app/bootstrap/bootstrap.dart';
import 'package:nolive_app/src/app/routing/app_routes.dart';
import 'package:nolive_app/src/features/settings/application/manage_danmaku_preferences_use_case.dart';
import 'package:nolive_app/src/shared/presentation/widgets/app_surface_card.dart';
import 'package:nolive_app/src/shared/presentation/widgets/section_header.dart';

class DanmakuSettingsPage extends StatefulWidget {
  const DanmakuSettingsPage({required this.bootstrap, super.key});

  final AppBootstrap bootstrap;

  @override
  State<DanmakuSettingsPage> createState() => _DanmakuSettingsPageState();
}

class _DanmakuSettingsPageState extends State<DanmakuSettingsPage> {
  DanmakuPreferences? _preferences;
  int _blockedKeywordsCount = 0;
  int _saveTicket = 0;

  static const List<String> _fontWeightLabels = [
    '超极细',
    '极细',
    '很细',
    '细',
    '正常',
    '粗',
    '很粗',
    '极粗',
    '超极粗',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final preferences = await widget.bootstrap.loadDanmakuPreferences();
    final blockedKeywords = await widget.bootstrap.loadBlockedKeywords();
    if (!mounted) {
      return;
    }
    setState(() {
      _preferences = preferences;
      _blockedKeywordsCount = blockedKeywords.length;
    });
  }

  Future<void> _update(DanmakuPreferences next) async {
    setState(() {
      _preferences = next;
    });
    final ticket = ++_saveTicket;
    await widget.bootstrap.updateDanmakuPreferences(next);
    if (!mounted || ticket != _saveTicket) {
      return;
    }
  }

  void _preview(DanmakuPreferences next) {
    setState(() {
      _preferences = next;
    });
  }

  Future<void> _openShieldRules() async {
    await Navigator.of(context).pushNamed(AppRoutes.danmakuShield);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final preferences = _preferences;
    if (preferences == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator.adaptive()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('弹幕设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        children: [
          AppSurfaceCard(
            child: Column(
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.shield_outlined),
                  title: const Text('关键词屏蔽'),
                  subtitle: Text('已启用 $_blockedKeywordsCount 条规则'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _openShieldRules,
                ),
                const Divider(height: 1),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: preferences.enabledByDefault,
                  title: const Text('默认开关'),
                  subtitle: const Text('进入直播间时默认显示播放器弹幕层'),
                  onChanged: (value) {
                    _update(preferences.copyWith(enabledByDefault: value));
                  },
                ),
                const Divider(height: 1),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: preferences.nativeBatchMaskEnabled,
                  title: const Text('原生弹幕频控'),
                  subtitle: const Text('Android 优先尝试原生批处理过滤，失败时自动回退 Dart'),
                  onChanged: (value) {
                    _update(
                      preferences.copyWith(nativeBatchMaskEnabled: value),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const SectionHeader(
            title: '显示与速度',
            subtitle: '滚动速度越小越快；显示区域越大，可同时看到的弹幕越多。',
          ),
          const SizedBox(height: 12),
          AppSurfaceCard(
            child: Column(
              children: [
                _SliderSettingTile(
                  title: '滚动速度',
                  subtitle: '弹幕持续时间(秒)，越小速度越快',
                  valueLabel: '${preferences.speed.toStringAsFixed(0)} 秒',
                  value: preferences.speed,
                  min: 4,
                  max: 60,
                  divisions: 56,
                  onChanged: (value) {
                    _preview(
                        (_preferences ?? preferences).copyWith(speed: value));
                  },
                  onChangeEnd: (value) {
                    _update(
                        (_preferences ?? preferences).copyWith(speed: value));
                  },
                ),
                const Divider(height: 1),
                _SliderSettingTile(
                  title: '显示区域',
                  valueLabel: '${(preferences.area * 100).round()}%',
                  value: preferences.area,
                  min: 0.1,
                  max: 1.0,
                  divisions: 9,
                  onChanged: (value) {
                    _preview(
                        (_preferences ?? preferences).copyWith(area: value));
                  },
                  onChangeEnd: (value) {
                    _update(
                        (_preferences ?? preferences).copyWith(area: value));
                  },
                ),
                const Divider(height: 1),
                _SliderSettingTile(
                  title: '不透明度',
                  valueLabel: '${(preferences.opacity * 100).round()}%',
                  value: preferences.opacity,
                  min: 0.1,
                  max: 1.0,
                  divisions: 9,
                  onChanged: (value) {
                    _preview(
                      (_preferences ?? preferences).copyWith(opacity: value),
                    );
                  },
                  onChangeEnd: (value) {
                    _update(
                      (_preferences ?? preferences).copyWith(opacity: value),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const SectionHeader(
            title: '字体与布局',
            subtitle: '这组参数直接作用于直播间播放器内的滚动弹幕。',
          ),
          const SizedBox(height: 12),
          AppSurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SliderSettingTile(
                  title: '字体大小',
                  valueLabel: '${preferences.fontSize.round()} px',
                  value: preferences.fontSize,
                  min: 8,
                  max: 48,
                  divisions: 20,
                  onChanged: (value) {
                    _preview(
                      (_preferences ?? preferences).copyWith(fontSize: value),
                    );
                  },
                  onChangeEnd: (value) {
                    _update(
                      (_preferences ?? preferences).copyWith(fontSize: value),
                    );
                  },
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Text(
                    '字体粗细',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (var index = 0;
                        index < _fontWeightLabels.length;
                        index += 1)
                      ChoiceChip(
                        label: Text(_fontWeightLabels[index]),
                        selected: preferences.fontWeight == index,
                        onSelected: (_) {
                          _update(preferences.copyWith(fontWeight: index));
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                const Divider(height: 1),
                _SliderSettingTile(
                  title: '字体描边',
                  valueLabel: preferences.strokeWidth.toStringAsFixed(1),
                  value: preferences.strokeWidth,
                  min: 0,
                  max: 4,
                  divisions: 20,
                  onChanged: (value) {
                    _preview(
                      (_preferences ?? preferences)
                          .copyWith(strokeWidth: value),
                    );
                  },
                  onChangeEnd: (value) {
                    _update(
                      (_preferences ?? preferences)
                          .copyWith(strokeWidth: value),
                    );
                  },
                ),
                const Divider(height: 1),
                _SliderSettingTile(
                  title: '弹幕行高',
                  valueLabel: '${preferences.lineHeight.toStringAsFixed(1)}x',
                  value: preferences.lineHeight,
                  min: 0.8,
                  max: 2.0,
                  divisions: 12,
                  onChanged: (value) {
                    _preview(
                      (_preferences ?? preferences).copyWith(lineHeight: value),
                    );
                  },
                  onChangeEnd: (value) {
                    _update(
                      (_preferences ?? preferences).copyWith(lineHeight: value),
                    );
                  },
                ),
                const Divider(height: 1),
                _SliderSettingTile(
                  title: '顶部边距',
                  valueLabel: '${preferences.topMargin.round()} px',
                  value: preferences.topMargin,
                  min: 0,
                  max: 48,
                  divisions: 12,
                  onChanged: (value) {
                    _preview(
                      (_preferences ?? preferences).copyWith(topMargin: value),
                    );
                  },
                  onChangeEnd: (value) {
                    _update(
                      (_preferences ?? preferences).copyWith(topMargin: value),
                    );
                  },
                ),
                const Divider(height: 1),
                _SliderSettingTile(
                  title: '底部边距',
                  valueLabel: '${preferences.bottomMargin.round()} px',
                  value: preferences.bottomMargin,
                  min: 0,
                  max: 48,
                  divisions: 12,
                  onChanged: (value) {
                    _preview(
                      (_preferences ?? preferences)
                          .copyWith(bottomMargin: value),
                    );
                  },
                  onChangeEnd: (value) {
                    _update(
                      (_preferences ?? preferences)
                          .copyWith(bottomMargin: value),
                    );
                  },
                ),
                const SizedBox(height: 12),
                _DanmakuPreviewCard(preferences: preferences),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SliderSettingTile extends StatelessWidget {
  const _SliderSettingTile({
    required this.title,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
    this.onChangeEnd,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Column(
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(title),
            subtitle: subtitle == null ? null : Text(subtitle!),
            trailing: Text(
              valueLabel,
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
          Slider.adaptive(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
            onChangeEnd: onChangeEnd,
          ),
        ],
      ),
    );
  }
}

class _DanmakuPreviewCard extends StatelessWidget {
  const _DanmakuPreviewCard({required this.preferences});

  final DanmakuPreferences preferences;

  @override
  Widget build(BuildContext context) {
    final fillStyle = TextStyle(
      color: Colors.white.withValues(alpha: preferences.opacity),
      fontSize: preferences.fontSize,
      fontWeight: preferences.resolveFontWeight(),
      height: preferences.lineHeight,
    );
    final strokeStyle = fillStyle.copyWith(
      foreground: Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = preferences.strokeWidth
        ..color = Colors.black.withValues(alpha: 0.82),
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '预览效果',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Colors.white70,
                ),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Stack(
              children: [
                if (preferences.strokeWidth > 0)
                  Text('午后记得起来活动一下，顺手喝两口水。', style: strokeStyle),
                Text('午后记得起来活动一下，顺手喝两口水。', style: fillStyle),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
