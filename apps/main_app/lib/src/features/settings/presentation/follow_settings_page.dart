import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nolive_app/src/features/library/application/load_library_dashboard_use_case.dart';
import 'package:nolive_app/src/features/settings/application/manage_follow_preferences_use_case.dart';
import 'package:nolive_app/src/features/settings/application/settings_page_dependencies.dart';
import 'package:nolive_app/src/shared/presentation/widgets/app_surface_card.dart';
import 'package:nolive_app/src/shared/presentation/widgets/empty_state_card.dart';
import 'package:nolive_app/src/shared/presentation/widgets/section_header.dart';
import 'package:nolive_app/src/shared/presentation/widgets/settings_action_buttons.dart';

class FollowSettingsPage extends StatefulWidget {
  const FollowSettingsPage({required this.dependencies, super.key});

  final FollowSettingsDependencies dependencies;

  @override
  State<FollowSettingsPage> createState() => _FollowSettingsPageState();
}

class _FollowSettingsPageState extends State<FollowSettingsPage> {
  late Future<_FollowSettingsPageData> _future;
  bool _busy = false;

  bool get _supportsInlineSave =>
      kIsWeb || Platform.isAndroid || Platform.isIOS;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_FollowSettingsPageData> _load() async {
    final dashboard = await widget.dependencies.loadLibraryDashboard();
    final preferences = await widget.dependencies.loadFollowPreferences();
    return _FollowSettingsPageData(
      dashboard: dashboard,
      preferences: preferences,
    );
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _load();
    });
    await _future;
  }

  Future<void> _runAction(
    Future<void> Function() action,
    String message,
  ) async {
    await action();
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
    await _refresh();
  }

  Future<void> _updateFollowPreferences(
    FollowPreferences preferences,
    String message,
  ) async {
    await _runAction(
      () => widget.dependencies.updateFollowPreferences(preferences),
      message,
    );
  }

  Future<void> _setAutoRefreshEnabled(
    FollowPreferences preferences,
    bool enabled,
  ) async {
    await _updateFollowPreferences(
      preferences.copyWith(autoRefreshEnabled: enabled),
      enabled ? '已启用关注自动刷新' : '已关闭关注自动刷新',
    );
  }

  Future<void> _pickAutoRefreshInterval(FollowPreferences preferences) async {
    final initialTime = TimeOfDay(
      hour: preferences.autoRefreshIntervalMinutes ~/ 60,
      minute: preferences.autoRefreshIntervalMinutes % 60,
    );
    final picked = await showTimePicker(
      context: context,
      initialTime: initialTime,
      initialEntryMode: TimePickerEntryMode.inputOnly,
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        );
      },
    );
    if (picked == null || (picked.hour == 0 && picked.minute == 0)) {
      return;
    }
    final minutes = picked.hour * 60 + picked.minute;
    await _updateFollowPreferences(
      preferences.copyWith(autoRefreshIntervalMinutes: minutes),
      '已更新自动刷新间隔',
    );
  }

  Future<void> _toggleFollowDisplayMode(FollowPreferences preferences) async {
    final nextDisplayMode =
        preferences.displayMode == FollowDisplayModePreference.list
            ? FollowDisplayModePreference.grid
            : FollowDisplayModePreference.list;
    await _updateFollowPreferences(
      preferences.copyWith(displayMode: nextDisplayMode),
      '已更新关注列表默认展示方式',
    );
  }

  Future<void> _exportFollowFile() async {
    setState(() {
      _busy = true;
    });
    try {
      final payload = await widget.dependencies.exportFollowListJson();
      final bytes = Uint8List.fromList(utf8.encode(payload));
      final path = await FilePicker.platform.saveFile(
        dialogTitle: '导出关注列表',
        fileName:
            'Nolive_${DateTime.now().millisecondsSinceEpoch ~/ 1000}.json',
        type: FileType.custom,
        allowedExtensions: const ['json'],
        bytes: _supportsInlineSave ? bytes : null,
      );
      if (!_supportsInlineSave) {
        if (path == null || path.isEmpty) {
          _showSnack('已取消导出');
          return;
        }
        await File(path).writeAsBytes(bytes);
      }
      _showSnack('关注列表已导出');
    } catch (error) {
      _showSnack('导出失败：$error');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _importFollowFile() async {
    setState(() {
      _busy = true;
    });
    try {
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: '导入关注列表',
        type: FileType.custom,
        allowedExtensions: const ['json'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) {
        return;
      }
      final payload = await _readPickedFileText(result.files.single);
      final summary = await widget.dependencies.importFollowListJson(payload);
      await _refresh();
      _showFollowImportSummary(summary, sourceLabel: result.files.single.name);
    } on FormatException catch (error) {
      _showSnack('导入失败：${error.message}');
    } catch (error) {
      _showSnack('导入失败：$error');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<String> _readPickedFileText(PlatformFile file) async {
    if (file.bytes != null) {
      return utf8.decode(file.bytes!, allowMalformed: true);
    }
    final path = file.path;
    if (path != null && path.isNotEmpty) {
      return File(path).readAsString();
    }
    throw const FormatException('无法读取所选文件内容。');
  }

  Future<void> _copyFollowJson() async {
    setState(() {
      _busy = true;
    });
    try {
      final payload = await widget.dependencies.exportFollowListJson();
      await Clipboard.setData(ClipboardData(text: payload));
      _showSnack('关注 JSON 已复制到剪贴板');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _importFollowText() async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: const Text('导入关注 JSON'),
              content: SizedBox(
                width: 480,
                child: TextField(
                  controller: controller,
                  autofocus: true,
                  maxLines: 12,
                  decoration: const InputDecoration(
                    hintText: '粘贴旧版兼容关注 JSON，或当前项目导出的包含 follows 的快照 JSON',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('取消'),
                ),
                TextButton(
                  onPressed: () async {
                    final data = await Clipboard.getData('text/plain');
                    if (data?.text != null) {
                      controller.text = data!.text!;
                    }
                  },
                  child: const Text('粘贴'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('导入'),
                ),
              ],
            );
          },
        ) ??
        false;
    if (!confirmed || controller.text.trim().isEmpty) {
      return;
    }
    setState(() {
      _busy = true;
    });
    try {
      final summary =
          await widget.dependencies.importFollowListJson(controller.text);
      await _refresh();
      _showFollowImportSummary(summary, sourceLabel: '文本');
    } on FormatException catch (error) {
      _showSnack('导入失败：${error.message}');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  void _showFollowImportSummary(
    dynamic summary, {
    required String sourceLabel,
  }) {
    _showSnack(
      '$sourceLabel 已导入：总计 ${summary.importedCount} · 新增 ${summary.createdCount} · 覆盖 ${summary.updatedCount} · 新增标签 ${summary.createdTagCount}',
    );
  }

  void _showSnack(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _removeTag(String tag) async {
    await _runAction(
      () => widget.dependencies.removeTag(tag),
      '已移除标签 $tag',
    );
  }

  Future<void> _showCreateTagDialog() async {
    final controller = TextEditingController();
    final created = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('新建标签'),
            content: TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(hintText: '例如：夜班 / 比赛'),
              onSubmitted: (_) => Navigator.of(context).pop(true),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('创建'),
              ),
            ],
          ),
        ) ??
        false;
    if (!created || controller.text.trim().isEmpty) {
      return;
    }
    await _runAction(
      () => widget.dependencies.createTag(controller.text.trim()),
      '已创建标签 ${controller.text.trim()}',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('关注设置')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<_FollowSettingsPageData>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator.adaptive());
            }
            if (snapshot.hasError || !snapshot.hasData) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                children: [
                  EmptyStateCard(
                    title: '关注设置加载失败',
                    message: '${snapshot.error}',
                    icon: Icons.error_outline,
                  ),
                ],
              );
            }

            final data = snapshot.data!;
            final dashboard = data.dashboard;
            final tags = dashboard.tags;

            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
              children: [
                const SectionHeader(title: '关注设置'),
                const SizedBox(height: 12),
                AppSurfaceCard(
                  child: Column(
                    children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.favorite_border),
                        title: const Text('关注记录'),
                        trailing: Text('${dashboard.snapshot.follows.length}'),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.live_tv_outlined),
                        title: const Text('列表来源'),
                        trailing: const Text('本地'),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.history),
                        title: const Text('历史记录'),
                        trailing: Text('${dashboard.snapshot.history.length}'),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.sell_outlined),
                        title: const Text('标签数量'),
                        trailing: Text('${tags.length}'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                AppSurfaceCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '标签管理',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                          FilledButton.tonalIcon(
                            key: const Key('follow-settings-add-tag-button'),
                            onPressed: _showCreateTagDialog,
                            icon: const Icon(Icons.add),
                            label: const Text('新建标签'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (tags.isEmpty)
                        const Text('当前还没有标签；可以创建后给关注房间做分组。')
                      else
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final tag in tags)
                              InputChip(
                                label: Text(tag),
                                onDeleted: () => _removeTag(tag),
                              ),
                          ],
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
                        '直播状态更新',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        secondary: const Icon(Icons.sync_outlined),
                        value: data.preferences.autoRefreshEnabled,
                        title: const Text('自动更新关注直播状态'),
                        subtitle: const Text('开启后会在关注页按设定间隔重新拉取开播状态。'),
                        onChanged: _busy
                            ? null
                            : (value) => _setAutoRefreshEnabled(
                                  data.preferences,
                                  value,
                                ),
                      ),
                      if (data.preferences.autoRefreshEnabled) ...[
                        const Divider(height: 1),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.schedule_outlined),
                          title: const Text('自动更新间隔'),
                          subtitle: Text(
                            '${data.preferences.autoRefreshIntervalMinutes ~/ 60}小时${data.preferences.autoRefreshIntervalMinutes % 60}分钟',
                          ),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: _busy
                              ? null
                              : () => _pickAutoRefreshInterval(
                                    data.preferences,
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
                      Text(
                        '列表显示',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          data.preferences.displayMode ==
                                  FollowDisplayModePreference.grid
                              ? Icons.grid_view_rounded
                              : Icons.view_agenda_outlined,
                        ),
                        title: const Text('默认展示方式'),
                        subtitle: Text(
                          data.preferences.displayMode ==
                                  FollowDisplayModePreference.grid
                              ? '网格'
                              : '列表',
                        ),
                        trailing: FilledButton.tonal(
                          onPressed: _busy
                              ? null
                              : () => _toggleFollowDisplayMode(
                                    data.preferences,
                                  ),
                          child: Text(
                            data.preferences.displayMode ==
                                    FollowDisplayModePreference.grid
                                ? '切到列表'
                                : '切到网格',
                          ),
                        ),
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
                        '关注导入导出',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 12),
                      SettingsActionGrid(
                        actions: [
                          SettingsAction(
                            label: '导出文件',
                            icon: Icons.save_alt_outlined,
                            onPressed: _busy ? null : _exportFollowFile,
                          ),
                          SettingsAction(
                            label: '导入文件',
                            icon: Icons.folder_open_outlined,
                            onPressed: _busy ? null : _importFollowFile,
                          ),
                          SettingsAction(
                            label: '导出文本',
                            icon: Icons.copy_all_outlined,
                            onPressed: _busy ? null : _copyFollowJson,
                          ),
                          SettingsAction(
                            label: '导入文本',
                            icon: Icons.input_outlined,
                            onPressed: _busy ? null : _importFollowText,
                          ),
                        ],
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
                        '整理动作',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 12),
                      SettingsActionGrid(
                        actions: [
                          SettingsAction(
                            label: '清空关注',
                            icon: Icons.favorite_outline,
                            onPressed: () => _runAction(
                              () => widget.dependencies.clearFollows(),
                              '已清空关注记录',
                            ),
                          ),
                          SettingsAction(
                            label: '清空历史',
                            icon: Icons.history_toggle_off,
                            onPressed: () => _runAction(
                              () => widget.dependencies.clearHistory(),
                              '已清空历史记录',
                            ),
                          ),
                          SettingsAction(
                            label: '清空标签',
                            icon: Icons.label_off_outlined,
                            onPressed: () => _runAction(
                              () => widget.dependencies.clearTags(),
                              '已清空所有标签',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _FollowSettingsPageData {
  const _FollowSettingsPageData({
    required this.dashboard,
    required this.preferences,
  });

  final LibraryDashboard dashboard;
  final FollowPreferences preferences;
}
