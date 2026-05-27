import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import 'package:live_core/live_core.dart';
import 'package:live_player/live_player.dart';
import 'package:nolive_app/src/app/platform/app_platform_capabilities.dart';
import 'package:nolive_app/src/features/room/presentation/room_controls_action_context.dart';
import 'package:path_provider/path_provider.dart';

typedef RoomPickScreenshotSavePath =
    Future<String?> Function({
      required String dialogTitle,
      required String fileName,
      required FileType type,
      List<String>? allowedExtensions,
    });

typedef RoomResolveScreenshotDirectory = Future<Directory?> Function();

typedef RoomSaveScreenshotToGallery =
    Future<dynamic> Function(
      Uint8List bytes, {
      required String name,
      required int quality,
    });

const String _kScreenshotGalleryTarget = 'gallery';
const String _kScreenshotBackupPrefix = 'backup:';

class RoomControlsUtilityActions {
  RoomControlsUtilityActions({
    required this.context,
    required this.notifyChanged,
    RoomPersistScreenshot? persistScreenshot,
    RoomPickScreenshotSavePath? pickScreenshotSavePath,
    bool? mobileScreenshotPersistence,
    AppPlatformCapabilities? platformCapabilities,
    RoomResolveScreenshotDirectory? resolveScreenshotDirectory,
    RoomSaveScreenshotToGallery? saveScreenshotToGallery,
  }) : _persistScreenshot = persistScreenshot,
       _pickScreenshotSavePath = pickScreenshotSavePath,
       _mobileScreenshotPersistence = mobileScreenshotPersistence,
       _platformCapabilities =
           platformCapabilities ?? AppPlatformCapabilities.current(),
       _resolveScreenshotDirectory = resolveScreenshotDirectory,
       _saveScreenshotToGallery = saveScreenshotToGallery;

  final RoomControlsActionContext context;
  VoidCallback notifyChanged;
  final RoomPersistScreenshot? _persistScreenshot;
  final RoomPickScreenshotSavePath? _pickScreenshotSavePath;
  final bool? _mobileScreenshotPersistence;
  final AppPlatformCapabilities _platformCapabilities;
  final RoomResolveScreenshotDirectory? _resolveScreenshotDirectory;
  final RoomSaveScreenshotToGallery? _saveScreenshotToGallery;

  Timer? _autoCloseTimer;
  DateTime? _scheduledCloseAt;

  DateTime? get scheduledCloseAt => _scheduledCloseAt;
  bool get supportsPlayerCapture =>
      context.runtime.supportsScreenshot ||
      context.captureRenderedPlayerSurface != null;

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
    if (!context.resolvePlaybackAvailable()) {
      context.showMessage('当前暂无可截图画面');
      return;
    }
    _trace('capture start');
    try {
      var bytes = await context.runtime.captureScreenshot();
      if ((bytes == null || bytes.isEmpty) &&
          context.captureRenderedPlayerSurface != null) {
        _trace('capture fallback=rendered-surface');
        bytes = await context.captureRenderedPlayerSurface!.call();
      }
      if (bytes == null || bytes.isEmpty) {
        throw const FormatException('未获取到图像数据');
      }
      final fileName =
          'nolive-${context.providerId.value}-${context.roomId}-${DateTime.now().millisecondsSinceEpoch}.png';
      final savedTarget = await (_persistScreenshot ?? persistScreenshot)(
        bytes: bytes,
        fileName: fileName,
      );
      _trace(
        'capture complete bytes=${bytes.length} '
        'target=${savedTarget ?? 'cancelled'}',
      );
      final message = switch (savedTarget) {
        null => '已取消截图保存',
        String path when path == _kScreenshotGalleryTarget => '已保存截图到系统相册',
        String path when path.startsWith(_kScreenshotBackupPrefix) =>
          '系统相册保存失败，已备份截图到 ${path.substring(_kScreenshotBackupPrefix.length)}',
        String path => '已保存截图到 $path',
      };
      context.showMessage(message);
    } catch (error) {
      _trace('capture failed error=$error');
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
    if (_usesMobileScreenshotPersistence) {
      Object? galleryError;
      try {
        final result =
            await (_saveScreenshotToGallery ??
                _saveScreenshotToGalleryWithPlugin)(
              bytes,
              name: fileName.replaceAll('.png', ''),
              quality: 100,
            );
        final savedTarget = _resolveGallerySaveResult(result);
        _trace('persist gallery result=$savedTarget');
        return savedTarget == _kScreenshotGalleryTarget
            ? _kScreenshotGalleryTarget
            : savedTarget;
      } catch (error) {
        galleryError = error;
        _trace('persist gallery failed error=$error');
      }
      try {
        final backupPath = await _persistMobileScreenshotBackup(
          bytes: bytes,
          fileName: fileName,
        );
        _trace('persist mobile backup=$backupPath');
        return '$_kScreenshotBackupPrefix$backupPath';
      } catch (backupError) {
        _trace(
          'persist backup failed error=$backupError galleryError=$galleryError',
        );
        throw StateError('系统相册保存失败，且无法写入备份截图：$backupError');
      }
    }
    final pickSavePath =
        _pickScreenshotSavePath ?? _pickScreenshotSavePathWithFilePicker;
    final path = await pickSavePath(
      dialogTitle: '保存截图',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: const ['png'],
    );
    if (path == null || path.trim().isEmpty) {
      return null;
    }
    final file = File(path);
    await file.writeAsBytes(bytes, flush: true);
    _trace('persist desktop path=${file.path}');
    return file.path;
  }

  Future<String?> _pickScreenshotSavePathWithFilePicker({
    required String dialogTitle,
    required String fileName,
    required FileType type,
    List<String>? allowedExtensions,
  }) {
    return FilePicker.platform.saveFile(
      dialogTitle: dialogTitle,
      fileName: fileName,
      type: type,
      allowedExtensions: allowedExtensions,
    );
  }

  bool get _usesMobileScreenshotPersistence =>
      _mobileScreenshotPersistence ?? _platformCapabilities.isMobile;

  Future<dynamic> _saveScreenshotToGalleryWithPlugin(
    Uint8List bytes, {
    required String name,
    required int quality,
  }) async {
    return await ImageGallerySaverPlus.saveImage(
      bytes,
      name: name,
      quality: quality,
    );
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
      final isSuccess =
          normalized['isSuccess'] == true ||
          normalized['success'] == true ||
          normalized['ok'] == true;
      if (!isSuccess) {
        throw StateError('系统相册返回保存失败');
      }
      final filePath = normalized['filePath']?.toString().trim();
      if (filePath != null && filePath.isNotEmpty) {
        return _kScreenshotGalleryTarget;
      }
      return _kScreenshotGalleryTarget;
    }
    if (result == true || result == 1 || result?.toString() == '1') {
      return _kScreenshotGalleryTarget;
    }
    throw StateError('系统相册返回未知结果');
  }

  Future<String> _persistMobileScreenshotBackup({
    required Uint8List bytes,
    required String fileName,
  }) async {
    final baseDirectory =
        await (_resolveScreenshotDirectory ??
            _resolveDefaultScreenshotDirectory)();
    if (baseDirectory == null) {
      throw StateError('无法获取截图保存目录');
    }
    final directory = Directory(
      '${baseDirectory.path}${Platform.pathSeparator}screenshots',
    );
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    final file = File('${directory.path}${Platform.pathSeparator}$fileName');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<Directory?> _resolveDefaultScreenshotDirectory() {
    if (_platformCapabilities.isAndroid) {
      return getExternalStorageDirectory();
    }
    return getApplicationDocumentsDirectory();
  }

  void _trace(String message) {
    context.trace('screenshot $message');
  }
}
