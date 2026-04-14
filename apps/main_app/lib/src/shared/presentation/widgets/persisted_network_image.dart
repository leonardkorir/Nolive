import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

enum PersistedImageBucket { avatar, categoryIcon, roomCover }

typedef PersistedImageDecodeSize = ({int? cacheWidth, int? cacheHeight});

const int _avatarMaxDecodeDimension = 256;
const int _categoryIconMaxDecodeDimension = 192;
const int _roomCoverMaxDecodeDimension = 1920;
const int _maxInMemoryFileEntries = 256;

@visibleForTesting
PersistedImageDecodeSize resolvePersistedImageDecodeSize({
  required PersistedImageBucket bucket,
  required BoxConstraints constraints,
  required double devicePixelRatio,
}) {
  int? cacheWidth;
  int? cacheHeight;
  if (constraints.hasBoundedWidth && constraints.maxWidth > 0) {
    cacheWidth = math.max(
      1,
      (constraints.maxWidth * devicePixelRatio).round(),
    );
  }
  if (constraints.hasBoundedHeight && constraints.maxHeight > 0) {
    cacheHeight = math.max(
      1,
      (constraints.maxHeight * devicePixelRatio).round(),
    );
  }
  if (cacheWidth == null && cacheHeight == null) {
    return (cacheWidth: null, cacheHeight: null);
  }
  final maxDimension = switch (bucket) {
    PersistedImageBucket.avatar => _avatarMaxDecodeDimension,
    PersistedImageBucket.categoryIcon => _categoryIconMaxDecodeDimension,
    PersistedImageBucket.roomCover => _roomCoverMaxDecodeDimension,
  };
  if (cacheWidth != null && cacheHeight != null) {
    final largest = math.max(cacheWidth, cacheHeight);
    if (largest > maxDimension) {
      final scale = maxDimension / largest;
      cacheWidth = math.max(1, (cacheWidth * scale).round());
      cacheHeight = math.max(1, (cacheHeight * scale).round());
    }
  } else if (cacheWidth != null && cacheWidth > maxDimension) {
    cacheWidth = maxDimension;
  } else if (cacheHeight != null && cacheHeight > maxDimension) {
    cacheHeight = maxDimension;
  }
  return (cacheWidth: cacheWidth, cacheHeight: cacheHeight);
}

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
    return LayoutBuilder(
      builder: (context, constraints) {
        final decodeSize = resolvePersistedImageDecodeSize(
          bucket: widget.bucket,
          constraints: constraints,
          devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
        );
        ImageProvider imageProvider = FileImage(file);
        if (decodeSize.cacheWidth != null || decodeSize.cacheHeight != null) {
          imageProvider = ResizeImage(
            imageProvider,
            width: decodeSize.cacheWidth,
            height: decodeSize.cacheHeight,
            policy: ResizeImagePolicy.fit,
          );
        }
        return Image(
          image: imageProvider,
          fit: widget.fit,
          alignment: widget.alignment,
          filterQuality: widget.filterQuality,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => widget.fallback,
        );
      },
    );
  }
}

class _PersistedImageCache {
  _PersistedImageCache._(this.bucketName);

  final String bucketName;
  final Map<String, Future<File?>> _inFlight = <String, Future<File?>>{};
  static final LinkedHashMap<String, File> _memoryFiles =
      LinkedHashMap<String, File>();

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
    final cached = _memoryFiles.remove(url);
    if (cached == null) {
      return null;
    }
    _memoryFiles[url] = cached;
    return cached;
  }

  Future<File?> resolve(String url) {
    final normalizedUrl = url.trim();
    if (normalizedUrl.isEmpty) {
      return Future<File?>.value();
    }
    final inMemory = peek(normalizedUrl);
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
            _rememberInMemory(normalizedUrl, file);
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
      _rememberInMemory(url, file);
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

  static void _rememberInMemory(String url, File file) {
    _memoryFiles.remove(url);
    _memoryFiles[url] = file;
    while (_memoryFiles.length > _maxInMemoryFileEntries) {
      _memoryFiles.remove(_memoryFiles.keys.first);
    }
  }
}
