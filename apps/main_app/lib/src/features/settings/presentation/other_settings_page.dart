import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nolive_app/src/app/bootstrap/bootstrap.dart';
import 'package:nolive_app/src/shared/presentation/widgets/app_surface_card.dart';
import 'package:nolive_app/src/shared/presentation/widgets/section_header.dart';
import 'package:nolive_app/src/shared/presentation/widgets/settings_action_buttons.dart';

class OtherSettingsPage extends StatefulWidget {
  const OtherSettingsPage({required this.bootstrap, super.key});

  final AppBootstrap bootstrap;

  @override
  State<OtherSettingsPage> createState() => _OtherSettingsPageState();
}

class _OtherSettingsPageState extends State<OtherSettingsPage> {
  bool _busy = false;

  bool get _supportsInlineSave =>
      kIsWeb || Platform.isAndroid || Platform.isIOS;

  Future<void> _copySnapshotJson() async {
    setState(() {
      _busy = true;
    });
    try {
      final payload = await widget.bootstrap.exportSyncSnapshotJson();
      await Clipboard.setData(ClipboardData(text: payload));
      _showSnack('快照 JSON 已复制到剪贴板');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _exportConfigFile() async {
    setState(() {
      _busy = true;
    });
    try {
      final payload = await widget.bootstrap.exportLegacyConfigJson();
      final bytes = Uint8List.fromList(utf8.encode(payload));
      final path = await FilePicker.platform.saveFile(
        dialogTitle: '导出配置文件',
        fileName: 'nolive_config.json',
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

      _showSnack('配置文件已导出');
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

  Future<void> _importConfigFile() async {
    setState(() {
      _busy = true;
    });
    try {
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: '导入配置文件',
        type: FileType.custom,
        allowedExtensions: const ['json'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) {
        return;
      }

      final file = result.files.single;
      final payload = await _readPickedFileText(file);
      final legacyConfigOnly = _looksLikeLegacyConfigPayload(payload);
      final snapshot = await widget.bootstrap.importSyncSnapshotJson(payload);
      _showImportSummary(
        snapshot,
        sourceLabel: file.name,
        legacyConfigOnly: legacyConfigOnly,
      );
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

  Future<void> _importSnapshotJson() async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('导入快照 JSON'),
          content: SizedBox(
            width: 480,
            child: TextField(
              controller: controller,
              autofocus: true,
              maxLines: 12,
              decoration: const InputDecoration(
                hintText: '粘贴当前项目导出的 snapshot JSON，或旧版兼容配置 JSON',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('导入'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) {
      return;
    }

    setState(() {
      _busy = true;
    });
    try {
      final legacyConfigOnly = _looksLikeLegacyConfigPayload(controller.text);
      final snapshot = await widget.bootstrap.importSyncSnapshotJson(
        controller.text,
      );
      _showImportSummary(
        snapshot,
        sourceLabel: '文本',
        legacyConfigOnly: legacyConfigOnly,
      );
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

  void _showImportSummary(
    dynamic snapshot, {
    required String sourceLabel,
    required bool legacyConfigOnly,
  }) {
    if (legacyConfigOnly) {
      _showSnack(
        '$sourceLabel 已导入：设置 ${snapshot.settings.length} · 屏蔽词 '
        '${snapshot.blockedKeywords.length}。检测到这是旧版兼容配置：'
        '文件本身缺少 `settings / follows / history / tags` 快照字段，'
        '所以不会继承关注 / 历史 / 标签。若需一次迁移全部内容，请使用当前项目重新导出的配置文件。',
      );
      return;
    }
    _showSnack(
      '$sourceLabel 已导入：设置 ${snapshot.settings.length} · 屏蔽词 '
      '${snapshot.blockedKeywords.length} · 关注 ${snapshot.follows.length} · 历史 ${snapshot.history.length}',
    );
  }

  bool _looksLikeLegacyConfigPayload(String rawJson) {
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is! Map<String, dynamic>) {
        return false;
      }
      if (decoded['type'] != 'simple_live') {
        return false;
      }
      if (!(decoded.containsKey('config') || decoded.containsKey('shield'))) {
        return false;
      }
      final isFullSnapshot = decoded.containsKey('settings') ||
          decoded.containsKey('blocked_keywords') ||
          decoded.containsKey('tags') ||
          decoded.containsKey('history') ||
          decoded.containsKey('follows');
      return !isFullSnapshot;
    } catch (_) {
      return false;
    }
  }

  void _showSnack(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _resetAppData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('重置本地数据'),
          content: const Text('这会清空当前关注、历史、标签和设置，并恢复默认值。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('确认重置'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) {
      return;
    }

    setState(() {
      _busy = true;
    });
    try {
      await widget.bootstrap.resetAppData();
      _showSnack('已恢复默认本地数据');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('其他设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        children: [
          const SectionHeader(title: '其他设置'),
          const SizedBox(height: 12),
          AppSurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '数据维护',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                SettingsActionGrid(
                  actions: [
                    SettingsAction(
                      label: '导出配置文件',
                      icon: Icons.save_alt_outlined,
                      onPressed: _busy ? null : _exportConfigFile,
                    ),
                    SettingsAction(
                      label: '导入配置文件',
                      icon: Icons.folder_open_outlined,
                      onPressed: _busy ? null : _importConfigFile,
                    ),
                    SettingsAction(
                      label: '导出快照',
                      icon: Icons.copy_all_outlined,
                      onPressed: _busy ? null : _copySnapshotJson,
                    ),
                    SettingsAction(
                      label: '导入快照',
                      icon: Icons.input_outlined,
                      onPressed: _busy ? null : _importSnapshotJson,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SettingsActionButton(
                  expanded: true,
                  action: SettingsAction(
                    label: '恢复默认',
                    icon: Icons.restart_alt_outlined,
                    onPressed: _busy ? null : _resetAppData,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
