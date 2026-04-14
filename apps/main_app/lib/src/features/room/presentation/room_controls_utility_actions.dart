import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import 'package:live_core/live_core.dart';
import 'package:live_player/live_player.dart';
import 'package:nolive_app/src/features/room/presentation/room_controls_action_context.dart';

class RoomControlsUtilityActions {
  RoomControlsUtilityActions({
    required this.context,
    required this.notifyChanged,
    RoomPersistScreenshot? persistScreenshot,
  }) : _persistScreenshot = persistScreenshot;

  final RoomControlsActionContext context;
  VoidCallback notifyChanged;
  final RoomPersistScreenshot? _persistScreenshot;

  Timer? _autoCloseTimer;
  DateTime? _scheduledCloseAt;

  DateTime? get scheduledCloseAt => _scheduledCloseAt;
  bool get supportsPlayerCapture => context.runtime.supportsScreenshot;

  void dispose() {
    _autoCloseTimer?.cancel();
  }

  Future<void> copyRoomLink({
    required LiveRoomDetail room,
    PlaybackSource? playbackSource,
  }) async {
    final content = room.sourceUrl?.isNotEmpty == true
        ? room.sourceUrl!
        : (playbackSource?.url.toString() ?? room.roomId);
    await Clipboard.setData(ClipboardData(text: content));
    context.showMessage('直播间链接已复制');
  }

  Future<void> shareRoomLink({
    required LiveRoomDetail room,
    PlaybackSource? playbackSource,
  }) {
    return copyRoomLink(room: room, playbackSource: playbackSource);
  }

  Future<void> captureScreenshot() async {
    if (!supportsPlayerCapture) {
      context.showMessage('当前版本暂不支持截图');
      return;
    }
    try {
      final bytes = await context.runtime.captureScreenshot();
      if (bytes == null || bytes.isEmpty) {
        throw const FormatException('未获取到图像数据');
      }
      final fileName =
          'nolive-${context.providerId.value}-${context.roomId}-${DateTime.now().millisecondsSinceEpoch}.png';
      final savedTarget = await (_persistScreenshot ?? persistScreenshot)(
        bytes: bytes,
        fileName: fileName,
      );
      final message = switch (savedTarget) {
        null => '已取消截图保存',
        String path when path == 'gallery' => '已保存截图到系统相册',
        String path => '已保存截图到 $path',
      };
      context.showMessage(message);
    } catch (error) {
      context.showMessage('截图失败：$error');
    }
  }

  void setAutoCloseTimer(Duration? duration) {
    _autoCloseTimer?.cancel();
    _autoCloseTimer = null;
    if (duration == null) {
      _replaceScheduledCloseAt(null);
      return;
    }
    final scheduled = DateTime.now().add(duration);
    _replaceScheduledCloseAt(scheduled);
    _autoCloseTimer = Timer(duration, () async {
      _autoCloseTimer = null;
      _replaceScheduledCloseAt(null);
      try {
        await context.leaveRoom();
      } catch (error) {
        context.showMessage('定时关闭失败：$error');
      }
    });
    context.showMessage('已设置 ${duration.inMinutes} 分钟后自动关闭');
  }

  Future<String?> persistScreenshot({
    required Uint8List bytes,
    required String fileName,
  }) async {
    if (Platform.isAndroid || Platform.isIOS) {
      final result = await ImageGallerySaverPlus.saveImage(
        bytes,
        name: fileName.replaceAll('.png', ''),
        quality: 100,
      );
      return _resolveGallerySaveResult(result);
    }
    final path = await FilePicker.platform.saveFile(
      dialogTitle: '保存截图',
      fileName: fileName,
      type: FileType.image,
      allowedExtensions: const ['png'],
    );
    if (path == null || path.trim().isEmpty) {
      return null;
    }
    final file = File(path);
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  void _replaceScheduledCloseAt(DateTime? next) {
    if (_scheduledCloseAt == next) {
      return;
    }
    _scheduledCloseAt = next;
    notifyChanged();
  }

  String _resolveGallerySaveResult(dynamic result) {
    if (result is Map) {
      final normalized = Map<Object?, Object?>.from(result);
      final isSuccess = normalized['isSuccess'] == true ||
          normalized['success'] == true ||
          normalized['ok'] == true;
      if (!isSuccess) {
        throw StateError('系统相册返回保存失败');
      }
      final filePath = normalized['filePath']?.toString().trim();
      if (filePath != null && filePath.isNotEmpty) {
        return filePath;
      }
      return 'gallery';
    }
    if (result == true || result == 1 || result?.toString() == '1') {
      return 'gallery';
    }
    throw StateError('系统相册返回未知结果');
  }
}
