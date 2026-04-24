import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class AppLog {
  AppLog._();

  static final AppLog instance = AppLog._();

  static const int _maxLogFiles = 7;
  static const int _maxLogFileBytes = 8 * 1024 * 1024;
  static const String _logFilePrefix = 'nolive-mobile';
  static const Duration _flushDebounce = Duration(milliseconds: 250);
  static final RegExp _sensitiveUrlParameterPattern = RegExp(
    r'([?&](?:token|sig|signature|session|auth|authorization|wsauth|cookie|csrfmiddlewaretoken|cf_clearance|__cf_bm)=)([^&#\s]+)',
    caseSensitive: false,
  );
  static final RegExp _quotedSensitiveHeaderPattern = RegExp(
    r'"((?:cookie|set-cookie|authorization|proxy-authorization)\s*:\s*)((?:\\.|[^"\\])*)"',
    caseSensitive: false,
  );
  static final RegExp _inlineSensitiveHeaderPattern = RegExp(
    r'(?<!")((?:cookie|set-cookie|authorization|proxy-authorization)\s*:\s*)([^\r\n]+)',
    caseSensitive: false,
    multiLine: true,
  );
  static final RegExp _sensitiveHeaderAssignmentPattern = RegExp(
    r'((?:^|[\s\[{,(])(?:cookie|set-cookie|authorization|proxy-authorization)\s*=\s*)([^\r\n,\]]+)',
    caseSensitive: false,
    multiLine: true,
  );
  static final RegExp _sensitiveJsonFieldPattern = RegExp(
    r'("(?:token|cookie|authorization|requestCookie|csrfToken)"\s*:\s*")([^"]+)(")',
    caseSensitive: false,
  );

  Future<void>? _initializeFuture;
  Future<void> _writeChain = Future<void>.value();
  IOSink? _sink;
  Directory? _logDirectory;
  Timer? _flushTimer;
  String? _currentLogPath;
  String? _currentDateStamp;
  int _currentSegmentIndex = 0;
  int _currentFileSize = 0;

  String? get currentLogPath => _currentLogPath;

  Future<void> ensureInitialized() {
    return _initializeFuture ??= _initialize();
  }

  void debug(String tag, String message) {
    _write('DEBUG', tag, message);
  }

  void info(String tag, String message) {
    _write('INFO', tag, message);
  }

  void warn(String tag, String message) {
    _write('WARN', tag, message);
  }

  void error(
    String tag,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    final buffer = StringBuffer(message);
    if (error != null) {
      buffer.write(' error=$error');
    }
    _write('ERROR', tag, buffer.toString(), stackTrace: stackTrace);
  }

  Future<void> flush() async {
    await ensureInitialized();
    _cancelScheduledFlush();
    await _writeChain;
    await _sink?.flush();
  }

  Future<void> _initialize() async {
    final logDirectory = _logDirectory ??= await _resolveLogDirectory();
    await logDirectory.create(recursive: true);
    await _cleanupOldLogs(logDirectory);
    final now = DateTime.now();
    await _ensureWritableSink(timestamp: now);
    _writeUnlocked(
      'INFO',
      'logger',
      'initialized path=$_currentLogPath maxFileBytes=$_maxLogFileBytes',
      timestamp: now,
    );
    await _sink?.flush();
  }

  Future<Directory> _resolveLogDirectory() async {
    if (!kIsWeb && Platform.isAndroid) {
      final externalDirectory = await getExternalStorageDirectory();
      if (externalDirectory != null) {
        return Directory(
          '${externalDirectory.path}${Platform.pathSeparator}logs',
        );
      }
    }
    final supportDirectory = await getApplicationSupportDirectory();
    return Directory('${supportDirectory.path}${Platform.pathSeparator}logs');
  }

  Future<void> _cleanupOldLogs(Directory directory) async {
    final files = <File>[];
    await for (final entity in directory.list()) {
      if (entity is File &&
          entity.path.endsWith('.log') &&
          entity.uri.pathSegments.last.startsWith(_logFilePrefix)) {
        files.add(entity);
      }
    }
    files.sort((left, right) => left.path.compareTo(right.path));
    while (files.length >= _maxLogFiles) {
      final file = files.removeAt(0);
      try {
        await file.delete();
      } on FileSystemException {
        // Ignore cleanup failures to avoid blocking app startup.
      }
    }
  }

  void _write(
    String level,
    String tag,
    String message, {
    StackTrace? stackTrace,
  }) {
    final run = _writeChain.then((_) async {
      await ensureInitialized();
      await _ensureWritableSink();
      _writeUnlocked(level, tag, message, stackTrace: stackTrace);
      if (shouldFlushAppLogRecord(level: level, tag: tag)) {
        _cancelScheduledFlush();
        await _sink?.flush();
      } else {
        _scheduleFlush();
      }
    });
    _writeChain = run.catchError((Object _, StackTrace __) {});
  }

  Future<void> _ensureWritableSink({DateTime? timestamp}) async {
    final now = timestamp ?? DateTime.now();
    final nextDateStamp = _dateStamp(now);
    final needsNewDate = _currentDateStamp != nextDateStamp;
    final needsRotation = _sink == null || _currentFileSize >= _maxLogFileBytes;
    if (!needsNewDate && !needsRotation) {
      return;
    }
    final logDirectory = _logDirectory ??= await _resolveLogDirectory();
    await logDirectory.create(recursive: true);
    final target = await _selectWritableLogFile(
      directory: logDirectory,
      dateStamp: nextDateStamp,
      startIndex: needsNewDate ? 0 : _currentSegmentIndex,
    );
    await _openSink(
      file: target.file,
      dateStamp: nextDateStamp,
      segmentIndex: target.segmentIndex,
    );
    await _cleanupOldLogs(logDirectory);
  }

  Future<_WritableLogTarget> _selectWritableLogFile({
    required Directory directory,
    required String dateStamp,
    required int startIndex,
  }) async {
    var segmentIndex = startIndex;
    while (true) {
      final file = File(_buildLogFilePath(directory, dateStamp, segmentIndex));
      final exists = await file.exists();
      if (!exists) {
        return _WritableLogTarget(file: file, segmentIndex: segmentIndex);
      }
      final size = await file.length();
      if (size < _maxLogFileBytes) {
        return _WritableLogTarget(file: file, segmentIndex: segmentIndex);
      }
      segmentIndex += 1;
    }
  }

  Future<void> _openSink({
    required File file,
    required String dateStamp,
    required int segmentIndex,
  }) async {
    _cancelScheduledFlush();
    await _sink?.flush();
    await _sink?.close();
    if (!await file.exists()) {
      await file.create(recursive: true);
    }
    _sink = file.openWrite(mode: FileMode.append);
    _currentLogPath = file.path;
    _currentDateStamp = dateStamp;
    _currentSegmentIndex = segmentIndex;
    _currentFileSize = await file.length();
  }

  void _writeUnlocked(
    String level,
    String tag,
    String message, {
    DateTime? timestamp,
    StackTrace? stackTrace,
  }) {
    final sink = _sink;
    if (sink == null) {
      return;
    }
    final stamp = (timestamp ?? DateTime.now()).toIso8601String();
    final normalized = sanitizeMessageForPersistence(message).trimRight();
    final lines =
        normalized.isEmpty ? const <String>[''] : normalized.split('\n');
    for (final line in lines) {
      final record = '$stamp [$level] [$tag] $line';
      sink.writeln(record);
      _currentFileSize += _recordSize(record);
      if (kDebugMode) {
        debugPrint(record);
      }
    }
    if (stackTrace == null) {
      return;
    }
    for (final line in stackTrace.toString().trimRight().split('\n')) {
      final record = '$stamp [$level] [$tag] # $line';
      sink.writeln(record);
      _currentFileSize += _recordSize(record);
      if (kDebugMode) {
        debugPrint(record);
      }
    }
  }

  int _recordSize(String record) {
    return utf8.encode(record).length + utf8.encode('\n').length;
  }

  String _buildLogFilePath(
    Directory directory,
    String dateStamp,
    int segmentIndex,
  ) {
    final suffix =
        segmentIndex == 0 ? '' : '-${segmentIndex.toString().padLeft(2, '0')}';
    return '${directory.path}${Platform.pathSeparator}'
        '$_logFilePrefix-$dateStamp$suffix.log';
  }

  String _dateStamp(DateTime value) {
    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  @visibleForTesting
  static bool shouldFlushAppLogRecord({
    required String level,
    required String tag,
  }) {
    if (level == 'ERROR') {
      return true;
    }
    return tag == 'room' || tag == 'player' || tag.startsWith('player/');
  }

  @visibleForTesting
  static String sanitizeMessageForPersistence(String message) {
    return message.replaceAllMapped(_sensitiveUrlParameterPattern, (match) {
      return '${match.group(1)}<redacted>';
    }).replaceAllMapped(_sensitiveJsonFieldPattern, (match) {
      return '${match.group(1)}<redacted>${match.group(3)}';
    }).replaceAllMapped(_quotedSensitiveHeaderPattern, (match) {
      return '"${match.group(1)}<redacted>"';
    }).replaceAllMapped(_inlineSensitiveHeaderPattern, (match) {
      return '${match.group(1)}<redacted>';
    }).replaceAllMapped(_sensitiveHeaderAssignmentPattern, (match) {
      return '${match.group(1)}<redacted>';
    });
  }

  void _scheduleFlush() {
    if (_flushTimer != null) {
      return;
    }
    _flushTimer = Timer(_flushDebounce, () {
      _flushTimer = null;
      final run = _writeChain.then((_) async {
        await _sink?.flush();
      });
      _writeChain = run.catchError((Object _, StackTrace __) {});
    });
  }

  void _cancelScheduledFlush() {
    _flushTimer?.cancel();
    _flushTimer = null;
  }
}

class _WritableLogTarget {
  const _WritableLogTarget({
    required this.file,
    required this.segmentIndex,
  });

  final File file;
  final int segmentIndex;
}
