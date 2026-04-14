import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:live_sync/live_sync.dart';
import 'package:nolive_app/src/features/settings/application/settings_feature_dependencies.dart';
import 'package:nolive_app/src/shared/presentation/widgets/app_surface_card.dart';
import 'package:nolive_app/src/shared/presentation/widgets/section_header.dart';
import 'package:nolive_app/src/shared/presentation/widgets/settings_action_buttons.dart';

class OtherSettingsPage extends StatefulWidget {
  const OtherSettingsPage({required this.dependencies, super.key});

  final SettingsFeatureDependencies dependencies;

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
      final payload = await widget.dependencies.exportSyncSnapshotJson();
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
      final payload = await widget.dependencies.exportLegacyConfigJson();
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

  Future<void> _exportCredentialMigrationBundle() async {
    final password = await _promptPassword(
      title: '导出受控迁移包',
      description: '为凭证迁移包设置一次性口令。该口令仅用于新设备导入，不会写入文件。',
      confirmPassword: true,
    );
    if (password == null) {
      return;
    }

    setState(() {
      _busy = true;
    });
    try {
      final payload = await widget.dependencies.exportCredentialMigrationBundle(
        password: password,
      );
      final bytes = Uint8List.fromList(utf8.encode(payload));
      final path = await FilePicker.platform.saveFile(
        dialogTitle: '导出受控迁移包',
        fileName: 'nolive_secure_migration.json',
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

      _showSnack('受控迁移包已导出');
    } on FormatException catch (error) {
      _showSnack('导出失败：${error.message}');
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
      final snapshot =
          await widget.dependencies.importSyncSnapshotJson(payload);
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

  Future<void> _importCredentialMigrationBundle() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: '导入受控迁移包',
      type: FileType.custom,
      allowedExtensions: const ['json'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) {
      return;
    }

    final password = await _promptPassword(
      title: '导入受控迁移包',
      description: '输入导出迁移包时设置的口令。',
    );
    if (password == null) {
      return;
    }

    setState(() {
      _busy = true;
    });
    try {
      final payload = await _readPickedFileText(result.files.single);
      final bundle = await widget.dependencies.importCredentialMigrationBundle(
        payload,
        password: password,
      );
      _showSnack(
        '受控迁移包已导入：恢复 ${bundle.credentials.length} 项敏感凭证',
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
      final snapshot = await widget.dependencies.importSyncSnapshotJson(
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
    SyncSnapshot snapshot, {
    required String sourceLabel,
    required bool legacyConfigOnly,
  }) {
    if (legacyConfigOnly) {
      _showSnack(
        '$sourceLabel 已导入：设置 ${snapshot.settings.length} · 屏蔽词 '
        '${snapshot.blockedKeywords.length}。检测到这是旧版兼容配置：'
        '文件本身缺少 `settings / follows / history / tags` 快照字段，'
        '所以不会继承关注 / 历史 / 标签。若需迁移敏感凭证，请单独使用受控迁移包。',
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

  Future<String?> _promptPassword({
    required String title,
    required String description,
    bool confirmPassword = false,
  }) async {
    final passwordController = TextEditingController();
    final confirmController = TextEditingController();
    String? errorText;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(title),
              content: SizedBox(
                width: 460,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      description,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: passwordController,
                      autofocus: true,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: '口令',
                        errorText: errorText,
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (_) {
                        if (errorText != null) {
                          setState(() {
                            errorText = null;
                          });
                        }
                      },
                    ),
                    if (confirmPassword) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: confirmController,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: '确认口令',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (_) {
                          if (errorText != null) {
                            setState(() {
                              errorText = null;
                            });
                          }
                        },
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () {
                    final password = passwordController.text.trim();
                    if (password.isEmpty) {
                      setState(() {
                        errorText = '口令不能为空';
                      });
                      return;
                    }
                    if (confirmPassword &&
                        password != confirmController.text.trim()) {
                      setState(() {
                        errorText = '两次输入的口令不一致';
                      });
                      return;
                    }
                    Navigator.of(context).pop(true);
                  },
                  child: const Text('确认'),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed != true) {
      return null;
    }
    return passwordController.text.trim();
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
          content: const Text(
            '这会清空当前关注、历史、标签和普通设置，并恢复默认值。账号 Cookie 与 WebDAV 密码会保留在安全存储中。',
          ),
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
      await widget.dependencies.resetAppData();
      _showSnack('已恢复默认本地数据');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _clearSensitiveCredentials() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('清除安全凭证'),
          content: const Text(
            '这会清除账号 Cookie 和 WebDAV 密码，但不会删除关注、历史、标签和普通设置。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('确认清除'),
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
      await widget.dependencies.clearSensitiveCredentials();
      _showSnack('已清除账号与同步敏感凭证');
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
              ],
            ),
          ),
          const SizedBox(height: 16),
          AppSurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '受控迁移',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  '常规快照不会携带账号 Cookie 和 WebDAV 密码。跨设备迁移这些敏感凭证时，请单独使用受控迁移包。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                SettingsActionGrid(
                  actions: [
                    SettingsAction(
                      label: '导出迁移包',
                      icon: Icons.shield_outlined,
                      onPressed:
                          _busy ? null : _exportCredentialMigrationBundle,
                    ),
                    SettingsAction(
                      label: '导入迁移包',
                      icon: Icons.security_update_good_outlined,
                      onPressed:
                          _busy ? null : _importCredentialMigrationBundle,
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
                  '重置与清理',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                SettingsActionButton(
                  expanded: true,
                  action: SettingsAction(
                    label: '清除安全凭证',
                    icon: Icons.no_encryption_gmailerrorred_outlined,
                    onPressed: _busy ? null : _clearSensitiveCredentials,
                  ),
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
