import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';

DanmakuBatchMask? tryCreateRustDanmakuBatchMask({
  Duration window = const Duration(seconds: 8),
  int burstLimit = 2,
}) {
  if (!Platform.isAndroid) {
    return null;
  }
  final library = _openRustMaskLibrary();
  if (library == null) {
    return null;
  }
  try {
    return _RustDanmakuBatchMask(
      library: library,
      window: window,
      burstLimit: burstLimit,
    );
  } catch (_) {
    return null;
  }
}

DynamicLibrary? _openRustMaskLibrary() {
  for (final name in const <String>[
    'libnolive_danmaku_mask.so',
    'nolive_danmaku_mask.dll',
    'libnolive_danmaku_mask.dylib',
  ]) {
    try {
      return DynamicLibrary.open(name);
    } catch (_) {
      continue;
    }
  }
  return null;
}

final class _RustDanmakuBatchMask implements DanmakuBatchMask {
  _RustDanmakuBatchMask({
    required DynamicLibrary library,
    required Duration window,
    required int burstLimit,
  })  : _fallback = WindowedDanmakuBatchMask(
          window: window,
          burstLimit: burstLimit,
        ),
        _create = library.lookupFunction<_CreateNative, _CreateDart>(
          'nolive_danmaku_mask_create',
        ),
        _filter = library.lookupFunction<_FilterNative, _FilterDart>(
          'nolive_danmaku_mask_filter',
        ),
        _freeString =
            library.lookupFunction<_FreeStringNative, _FreeStringDart>(
          'nolive_danmaku_mask_free_string',
        ),
        _destroy = library.lookupFunction<_DestroyNative, _DestroyDart>(
          'nolive_danmaku_mask_destroy',
        ) {
    _handle = _create(window.inMilliseconds, burstLimit.clamp(1, 32));
    if (_handle == nullptr) {
      throw StateError('Failed to create native danmaku mask.');
    }
  }

  final WindowedDanmakuBatchMask _fallback;
  final _CreateDart _create;
  final _FilterDart _filter;
  final _FreeStringDart _freeString;
  final _DestroyDart _destroy;

  Pointer<Void>? _handle;
  bool _healthy = true;

  @override
  List<LiveMessage> allowListBatch(
    Iterable<LiveMessage> messages, {
    DateTime? now,
  }) {
    final source = List<LiveMessage>.from(messages, growable: false);
    if (!_healthy || _handle == null || _handle == nullptr) {
      return _fallback.allowListBatch(source, now: now);
    }

    final payload = jsonEncode(
      source.map<String?>((message) {
        return switch (message.type) {
          LiveMessageType.chat => message.content,
          LiveMessageType.notice => message.content,
          LiveMessageType.gift => message.content,
          LiveMessageType.member => message.content,
          LiveMessageType.superChat => null,
          LiveMessageType.online => null,
        };
      }).toList(growable: false),
    );
    final payloadPtr = payload.toNativeUtf8();
    Pointer<Utf8>? resultPtr;
    try {
      resultPtr = _filter(
        _handle!,
        (now ?? DateTime.now()).millisecondsSinceEpoch,
        payloadPtr,
      );
      if (resultPtr == nullptr) {
        throw const FormatException('Native danmaku mask returned null.');
      }
      final decoded = json.decode(resultPtr.toDartString());
      if (decoded is! List || decoded.length != source.length) {
        throw const FormatException('Unexpected native danmaku mask payload.');
      }
      final allowed = <LiveMessage>[];
      for (var index = 0; index < source.length; index += 1) {
        if (decoded[index] == true) {
          allowed.add(source[index]);
        }
      }
      return List<LiveMessage>.unmodifiable(allowed);
    } catch (_) {
      _healthy = false;
      return _fallback.allowListBatch(source, now: now);
    } finally {
      calloc.free(payloadPtr);
      if (resultPtr != null && resultPtr != nullptr) {
        _freeString(resultPtr);
      }
    }
  }

  @override
  void dispose() {
    final handle = _handle;
    if (handle == null || handle == nullptr) {
      return;
    }
    _destroy(handle);
    _handle = nullptr;
  }
}

typedef _CreateNative = Pointer<Void> Function(
    Uint64 windowMs, Uint32 burstLimit);
typedef _CreateDart = Pointer<Void> Function(int windowMs, int burstLimit);

typedef _FilterNative = Pointer<Utf8> Function(
  Pointer<Void> mask,
  Uint64 nowMs,
  Pointer<Utf8> payload,
);
typedef _FilterDart = Pointer<Utf8> Function(
  Pointer<Void> mask,
  int nowMs,
  Pointer<Utf8> payload,
);

typedef _FreeStringNative = Void Function(Pointer<Utf8> value);
typedef _FreeStringDart = void Function(Pointer<Utf8> value);

typedef _DestroyNative = Void Function(Pointer<Void> mask);
typedef _DestroyDart = void Function(Pointer<Void> mask);
