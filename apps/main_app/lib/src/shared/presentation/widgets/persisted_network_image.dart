import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

enum PersistedImageBucket { avatar, categoryIcon, roomCover }

class PersistedNetworkImage extends StatefulWidget {
  const PersistedNetworkImage({
    required this.imageUrl,
    required this.fallback,
    this.bucket = PersistedImageBucket.avatar,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.filterQuality = FilterQuality.medium,
    super.key,
  });

  final String imageUrl;
  final Widget fallback;
  final PersistedImageBucket bucket;
  final BoxFit fit;
  final Alignment alignment;
  final FilterQuality filterQuality;

  @override
  State<PersistedNetworkImage> createState() => _PersistedNetworkImageState();
}

class _PersistedNetworkImageState extends State<PersistedNetworkImage> {
  File? _resolvedFile;
  String? _resolvedUrl;

  @override
  void initState() {
    super.initState();
    _resolveImage();
  }

  @override
  void didUpdateWidget(covariant PersistedNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl ||
        oldWidget.bucket != widget.bucket) {
      _resolvedFile = null;
      _resolvedUrl = null;
      _resolveImage();
    }
  }

  void _resolveImage() {
    final url = widget.imageUrl.trim();
    if (url.isEmpty) {
      return;
    }
    final cached = _PersistedImageCache.peek(url);
    if (cached != null) {
      _resolvedFile = cached;
      _resolvedUrl = url;
    }
    unawaited(
      _PersistedImageCache.instanceFor(widget.bucket).resolve(url).then((file) {
        if (!mounted ||
            file == null ||
            _resolvedUrl == url && _resolvedFile?.path == file.path) {
          return;
        }
        setState(() {
          _resolvedFile = file;
          _resolvedUrl = url;
        });
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final file = _resolvedFile;
    if (file == null) {
      return widget.fallback;
    }
    return Image.file(
      file,
      fit: widget.fit,
      alignment: widget.alignment,
      filterQuality: widget.filterQuality,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => widget.fallback,
    );
  }
}

class _PersistedImageCache {
  _PersistedImageCache._(this.bucketName);

  final String bucketName;
  final Map<String, Future<File?>> _inFlight = <String, Future<File?>>{};
  static final Map<String, File> _memoryFiles = <String, File>{};

  static final _PersistedImageCache _avatar = _PersistedImageCache._('avatars');
  static final _PersistedImageCache _categoryIcon =
      _PersistedImageCache._('category_icons');
  static final _PersistedImageCache _roomCover =
      _PersistedImageCache._('room_covers');

  static _PersistedImageCache instanceFor(PersistedImageBucket bucket) {
    return switch (bucket) {
      PersistedImageBucket.avatar => _avatar,
      PersistedImageBucket.categoryIcon => _categoryIcon,
      PersistedImageBucket.roomCover => _roomCover,
    };
  }

  static File? peek(String url) {
    return _memoryFiles[url];
  }

  Future<File?> resolve(String url) {
    final normalizedUrl = url.trim();
    if (normalizedUrl.isEmpty) {
      return Future<File?>.value();
    }
    final inMemory = _memoryFiles[normalizedUrl];
    if (inMemory != null && inMemory.existsSync()) {
      return Future<File?>.value(inMemory);
    }
    return _inFlight.putIfAbsent(
      normalizedUrl,
      () async {
        try {
          final file = await _fileFor(normalizedUrl);
          final exists = await file.exists();
          if (exists) {
            _memoryFiles[normalizedUrl] = file;
            final stat = await file.stat();
            if (DateTime.now().difference(stat.modified) <=
                const Duration(days: 7)) {
              return file;
            }
            unawaited(_refresh(normalizedUrl, file));
            return file;
          }
          return _refresh(normalizedUrl, file);
        } finally {
          _inFlight.remove(normalizedUrl);
        }
      },
    );
  }

  Future<File?> _refresh(String url, File file) async {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      return null;
    }
    HttpClient? client;
    try {
      client = HttpClient();
      final request = await client.getUrl(uri).timeout(
            const Duration(seconds: 15),
          );
      final response = await request.close().timeout(
            const Duration(seconds: 20),
          );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return await file.exists() ? file : null;
      }
      final bytes = await consolidateHttpClientResponseBytes(response);
      if (bytes.isEmpty) {
        return await file.exists() ? file : null;
      }
      final tempFile = File('${file.path}.tmp');
      await tempFile.writeAsBytes(bytes, flush: true);
      if (await file.exists()) {
        await file.delete();
      }
      await tempFile.rename(file.path);
      _memoryFiles[url] = file;
      await FileImage(file).evict();
      return file;
    } catch (_) {
      return await file.exists() ? file : null;
    } finally {
      client?.close(force: true);
    }
  }

  Future<File> _fileFor(String url) async {
    final directory = await _directoryForBucket();
    final hash = sha1.convert(utf8.encode(url)).toString();
    final extension = _extensionFor(url);
    return File('${directory.path}${Platform.pathSeparator}$hash$extension');
  }

  Future<Directory> _directoryForBucket() async {
    final root = await _resolveCacheRoot();
    final directory = Directory(
      '${root.path}${Platform.pathSeparator}nolive_image_cache${Platform.pathSeparator}$bucketName',
    );
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  Future<Directory> _resolveCacheRoot() async {
    try {
      return await getApplicationSupportDirectory();
    } on MissingPluginException {
      return Directory.systemTemp;
    } on UnsupportedError {
      return Directory.systemTemp;
    }
  }

  String _extensionFor(String url) {
    final uri = Uri.tryParse(url);
    final lastSegment =
        uri == null || uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
    final dotIndex = lastSegment.lastIndexOf('.');
    if (dotIndex <= 0 || dotIndex == lastSegment.length - 1) {
      return '.img';
    }
    final extension = lastSegment.substring(dotIndex).toLowerCase();
    return extension.length > 8 ? '.img' : extension;
  }
}
