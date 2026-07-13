import 'dart:convert';
import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:live_core/live_core.dart';
import 'package:meta/meta.dart';

import 'stripchat/stripchat_mouflon_runtime_support.dart' as stripchat_runtime;

class HlsAesWorker {
  const HlsAesWorker._();

  static Future<String?> decryptStripchatMouflonSegment({
    required String encryptedSegment,
    required String pdkey,
  }) async {
    final session = HlsAesWorkerSession(debugLabel: 'single-shot');
    try {
      return await session.decryptStripchatMouflonSegment(
        encryptedSegment: encryptedSegment,
        pdkey: pdkey,
      );
    } finally {
      await session.dispose();
    }
  }
}

class HlsAesWorkerSession {
  HlsAesWorkerSession({String? debugLabel})
    : _debugLabel = _normalizeDebugLabel(debugLabel);

  final String _debugLabel;
  final Map<int, Completer<String?>> _pending = <int, Completer<String?>>{};

  RawReceivePort? _responsePort;
  RawReceivePort? _errorPort;
  RawReceivePort? _exitPort;
  Future<SendPort>? _sendPortFuture;
  Isolate? _isolate;
  Completer<SendPort>? _readyCompleter;
  bool _disposed = false;
  bool _telemetryActive = false;
  int _nextRequestId = 0;
  int _requestCount = 0;
  int _spawnCount = 0;

  Future<String?> decryptStripchatMouflonSegment({
    required String encryptedSegment,
    required String pdkey,
  }) async {
    if (_disposed) {
      throw StateError('HLS-AES worker session is disposed.');
    }
    final sendPort = await _ensureStarted();
    if (_disposed) {
      throw StateError('HLS-AES worker session is disposed.');
    }
    final id = _nextRequestId += 1;
    final completer = Completer<String?>();
    _pending[id] = completer;
    _requestCount += 1;
    _snapshotReuseIfNeeded();
    sendPort.send(<Object?>[
      id,
      _HlsAesWorkerCommand.decryptStripchatMouflonSegment,
      encryptedSegment,
      pdkey,
    ]);
    return completer.future;
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    SendPort? sendPort;
    final sendPortFuture = _sendPortFuture;
    if (sendPortFuture != null) {
      try {
        sendPort = await sendPortFuture;
      } catch (_) {}
    }
    sendPort?.send(const <Object?>[0, _HlsAesWorkerCommand.shutdown]);
    _completePendingWithError(StateError('HLS-AES worker session disposed.'));
    _isolate?.kill(priority: Isolate.beforeNextEvent);
    _isolate = null;
    _sendPortFuture = null;
    _readyCompleter = null;
    _closePorts();
    _markStopped('session=$_debugLabel requests=$_requestCount');
  }

  @visibleForTesting
  int get debugSpawnCount => _spawnCount;

  @visibleForTesting
  bool get debugHasActiveWorker => _isolate != null && _telemetryActive;

  @visibleForTesting
  Future<void> sendUnsupportedCommandForTesting() async {
    if (_disposed) {
      throw StateError('HLS-AES worker session is disposed.');
    }
    final sendPort = await _ensureStarted();
    final id = _nextRequestId += 1;
    final completer = Completer<String?>();
    _pending[id] = completer;
    sendPort.send(<Object?>[id, 'unsupported-test-command']);
    await completer.future;
  }

  Future<SendPort> _ensureStarted() {
    final existing = _sendPortFuture;
    if (existing != null) {
      return existing;
    }
    if (_disposed) {
      return Future<SendPort>.error(
        StateError('HLS-AES worker session is disposed.'),
      );
    }

    final responsePort = RawReceivePort();
    final errorPort = RawReceivePort();
    final exitPort = RawReceivePort();
    final ready = Completer<SendPort>();
    _responsePort = responsePort;
    _errorPort = errorPort;
    _exitPort = exitPort;
    _readyCompleter = ready;

    responsePort.handler = (Object? message) {
      if (!ready.isCompleted) {
        if (message is SendPort) {
          ready.complete(message);
          NfrIsolateTelemetry.markReady(
            'hls-aes-worker',
            detail: 'session=$_debugLabel model=persistent',
          );
          return;
        }
        final error = StateError('HLS-AES worker sent invalid ready message.');
        ready.completeError(error);
        _handleWorkerFailure(error);
        return;
      }
      _handleWorkerMessage(message);
    };
    errorPort.handler = (Object? message) {
      _handleWorkerFailure(
        StateError('HLS-AES worker isolate error: $message'),
      );
    };
    exitPort.handler = (_) {
      if (_disposed) {
        _markStopped('session=$_debugLabel requests=$_requestCount');
        return;
      }
      _handleWorkerFailure(StateError('HLS-AES worker exited unexpectedly.'));
    };

    _markStarted('session=$_debugLabel model=persistent');
    _spawnCount += 1;
    _sendPortFuture =
        Isolate.spawn(
              _hlsAesWorkerMain,
              responsePort.sendPort,
              debugName: 'hls-aes-worker',
              onError: errorPort.sendPort,
              onExit: exitPort.sendPort,
            )
            .then((isolate) async {
              _isolate = isolate;
              return ready.future;
            })
            .catchError((Object error) {
              _handleWorkerFailure(error);
              throw error;
            });
    return _sendPortFuture!;
  }

  void _handleWorkerMessage(Object? message) {
    if (message is! List || message.length < 3 || message.first is! int) {
      _handleWorkerFailure(
        StateError('HLS-AES worker sent malformed response.'),
      );
      return;
    }
    final id = message[0] as int;
    final completer = _pending.remove(id);
    if (completer == null || completer.isCompleted) {
      return;
    }
    final success = message[1] == true;
    if (success) {
      final result = message[2];
      completer.complete(result is String ? result : null);
      return;
    }
    final errorText = message[2]?.toString() ?? 'HLS-AES worker failed.';
    final stackText = message.length > 3 ? message[3]?.toString() ?? '' : '';
    completer.completeError(
      StateError(errorText),
      stackText.isEmpty ? StackTrace.current : StackTrace.fromString(stackText),
    );
  }

  void _handleWorkerFailure(Object error) {
    final readyCompleter = _readyCompleter;
    if (readyCompleter != null && !readyCompleter.isCompleted) {
      readyCompleter.completeError(error);
    }
    _completePendingWithError(error);
    _sendPortFuture = null;
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _closePorts();
    _markFailed(error, 'session=$_debugLabel requests=$_requestCount');
  }

  void _completePendingWithError(Object error) {
    final pending = _pending.values.toList(growable: false);
    _pending.clear();
    for (final completer in pending) {
      if (!completer.isCompleted) {
        completer.completeError(error);
      }
    }
  }

  void _closePorts() {
    _responsePort?.close();
    _errorPort?.close();
    _exitPort?.close();
    _responsePort = null;
    _errorPort = null;
    _exitPort = null;
  }

  void _snapshotReuseIfNeeded() {
    if (_requestCount != 1 && _requestCount % 8 != 0) {
      return;
    }
    NfrIsolateTelemetry.snapshot(
      'hls-aes-worker',
      detail:
          'session=$_debugLabel requests=$_requestCount model=persistent reused=true',
    );
  }

  void _markStarted(String detail) {
    if (_telemetryActive) {
      return;
    }
    _telemetryActive = true;
    NfrIsolateTelemetry.markStarted('hls-aes-worker', detail: detail);
  }

  void _markStopped(String detail) {
    if (!_telemetryActive) {
      return;
    }
    _telemetryActive = false;
    NfrIsolateTelemetry.markStopped('hls-aes-worker', detail: detail);
  }

  void _markFailed(Object error, String detail) {
    if (!_telemetryActive) {
      return;
    }
    _telemetryActive = false;
    NfrIsolateTelemetry.markFailed('hls-aes-worker', error, detail: detail);
  }

  static String _normalizeDebugLabel(String? value) {
    final normalized = value?.trim() ?? '';
    if (normalized.isEmpty) {
      return 'session';
    }
    return normalized.replaceAll(RegExp(r'\s+'), '-');
  }
}

class _HlsAesWorkerCommand {
  const _HlsAesWorkerCommand._();

  static const String decryptStripchatMouflonSegment =
      'decrypt-stripchat-mouflon-segment';
  static const String shutdown = 'shutdown';
}

void _hlsAesWorkerMain(SendPort mainPort) {
  final commandPort = ReceivePort();
  mainPort.send(commandPort.sendPort);
  commandPort.listen((Object? message) {
    if (message is! List || message.length < 2 || message.first is! int) {
      mainPort.send(<Object?>[
        -1,
        false,
        'Malformed HLS-AES worker request.',
        '',
      ]);
      return;
    }
    final id = message[0] as int;
    final command = message[1];
    if (command == _HlsAesWorkerCommand.shutdown) {
      commandPort.close();
      return;
    }
    if (command == _HlsAesWorkerCommand.decryptStripchatMouflonSegment) {
      try {
        final result = _decryptStripchatMouflonSegment(
          encryptedSegment: message[2] as String,
          pdkey: message[3] as String,
        );
        mainPort.send(<Object?>[id, true, result]);
      } catch (error, stackTrace) {
        mainPort.send(<Object?>[
          id,
          false,
          error.toString(),
          stackTrace.toString(),
        ]);
      }
      return;
    }
    mainPort.send(<Object?>[
      id,
      false,
      'Unsupported HLS-AES worker command: $command',
      '',
    ]);
  });
}

String? _decryptStripchatMouflonSegment({
  required String encryptedSegment,
  required String pdkey,
}) {
  try {
    final reversedSegment = stripchat_runtime.stripchatReverseString(
      encryptedSegment,
    );
    final bytes = base64.decode(
      stripchat_runtime.stripchatPadBase64(reversedSegment),
    );
    final hashBytes = sha256.convert(utf8.encode(pdkey)).bytes;
    final output = Uint8List(bytes.length);
    for (var index = 0; index < bytes.length; index += 1) {
      output[index] = bytes[index] ^ hashBytes[index % hashBytes.length];
    }
    final decoded = utf8.decode(output);
    if (!_isLikelyMouflonSegment(decoded)) {
      return null;
    }
    return decoded;
  } catch (_) {
    return null;
  }
}

bool _isLikelyMouflonSegment(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty || trimmed.length < 6 || trimmed.length > 160) {
    return false;
  }
  return RegExp(r'^[A-Za-z0-9._~:/?#[\]@!$&()*+,;=%-]+$').hasMatch(trimmed);
}
