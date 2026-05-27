import 'dart:collection';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../model/local_sync_peer_info.dart';
import '../model/sync_data_category.dart';
import '../model/sync_snapshot.dart';
import '../model/sync_snapshot_codec.dart';

abstract class LocalSyncServer {
  bool get isRunning;

  Uri get endpoint;

  Future<void> start();

  Future<void> stop();

  Future<SyncSnapshot> exportSnapshot();

  Future<SyncSnapshot> exportCategory(SyncDataCategory category);

  Future<void> importCategory(
    SyncDataCategory category,
    SyncSnapshot snapshot,
  );

  Future<LocalSyncPeerInfo> readInfo();
}

class HttpLocalSyncServer implements LocalSyncServer {
  HttpLocalSyncServer({
    required Future<SyncSnapshot> Function() exportSnapshot,
    required Future<void> Function(SyncSnapshot snapshot) importSnapshot,
    required Future<SyncSnapshot> Function(SyncDataCategory category)
        exportCategory,
    required Future<void> Function(
      SyncDataCategory category,
      SyncSnapshot snapshot,
    ) importCategory,
    Future<void> Function(
      SyncDataCategory category,
      SyncSnapshot snapshot,
    )? rollbackCategory,
    Future<LocalSyncPeerInfo> Function()? readInfo,
    this.host = '0.0.0.0',
    this.port = 23234,
    this.maxRequestBytes = 1024 * 1024,
    String? accessToken,
    Future<String?> Function()? accessTokenResolver,
    void Function(Object error, StackTrace stackTrace)? onUnexpectedError,
  })  : _exportSnapshot = exportSnapshot,
        _importSnapshot = importSnapshot,
        _exportCategory = exportCategory,
        _importCategory = importCategory,
        _rollbackCategory = rollbackCategory ?? importCategory,
        _onUnexpectedError = onUnexpectedError ?? _defaultUnexpectedErrorLogger,
        _staticAccessToken = _normalizeAccessToken(accessToken),
        _accessTokenResolver = accessTokenResolver,
        _readInfo = readInfo ??
            (() async => const LocalSyncPeerInfo(
                  displayName: 'nolive-device',
                  deviceId: 'nolive-device',
                  platform: 'unknown',
                )) {
    if (_isWildcardHost(host) &&
        _staticAccessToken == null &&
        _accessTokenResolver == null) {
      throw ArgumentError.value(
        host,
        'host',
        'Wildcard local sync binding requires an access token.',
      );
    }
  }

  final Future<SyncSnapshot> Function() _exportSnapshot;
  final Future<void> Function(SyncSnapshot snapshot) _importSnapshot;
  final Future<SyncSnapshot> Function(SyncDataCategory category)
      _exportCategory;
  final Future<void> Function(
    SyncDataCategory category,
    SyncSnapshot snapshot,
  ) _importCategory;
  final Future<void> Function(
    SyncDataCategory category,
    SyncSnapshot snapshot,
  ) _rollbackCategory;
  final void Function(Object error, StackTrace stackTrace) _onUnexpectedError;
  final String? _staticAccessToken;
  final Future<String?> Function()? _accessTokenResolver;
  final Future<LocalSyncPeerInfo> Function() _readInfo;
  final String host;
  final int port;
  final int maxRequestBytes;

  HttpServer? _server;
  final LinkedHashMap<String, DateTime> _seenAuthNonces =
      LinkedHashMap<String, DateTime>();

  static const Duration _authTimestampSkew = Duration(minutes: 5);
  static const int _maxSeenAuthNonces = 1000;
  static const String _timestampHeader = 'X-Nolive-Sync-Timestamp';
  static const String _nonceHeader = 'X-Nolive-Sync-Nonce';
  static const String _signatureHeader = 'X-Nolive-Sync-Signature';

  @override
  bool get isRunning => _server != null;

  @override
  Uri get endpoint => Uri.parse(
      'http://${host == '0.0.0.0' ? '127.0.0.1' : host}:$port/snapshot');

  @override
  Future<void> start() async {
    if (_server != null) {
      return;
    }
    if (_isWildcardHost(host) && await _effectiveAccessToken() == null) {
      throw ArgumentError.value(
        host,
        'host',
        'Wildcard local sync binding requires an access token.',
      );
    }
    _server = await HttpServer.bind(host, port);
    _server!.listen(_handleRequest);
  }

  @override
  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  @override
  Future<SyncSnapshot> exportSnapshot() => _exportSnapshot();

  @override
  Future<SyncSnapshot> exportCategory(SyncDataCategory category) =>
      _exportCategory(category);

  @override
  Future<void> importCategory(
    SyncDataCategory category,
    SyncSnapshot snapshot,
  ) =>
      _importCategory(category, snapshot);

  @override
  Future<LocalSyncPeerInfo> readInfo() async {
    return _withAccessToken(await _readInfo(), await _effectiveAccessToken());
  }

  LocalSyncPeerInfo _withAccessToken(
    LocalSyncPeerInfo info,
    String? accessToken,
  ) {
    if (accessToken == null) {
      return info;
    }
    return LocalSyncPeerInfo(
      displayName: info.displayName,
      deviceId: info.deviceId,
      platform: info.platform,
      snapshotPath: info.snapshotPath,
      accessToken: accessToken,
    );
  }

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      if (request.uri.path == '/info' && request.method == 'GET') {
        if (!await _isAuthorized(request, body: '')) {
          await _rejectUnauthorized(request);
          return;
        }
        final info = await _readInfo();
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(info.toJson()));
        await request.response.close();
        return;
      }
      if (request.uri.path == '/sync/batch' && request.method == 'POST') {
        final payload = await _readPayload(request);
        if (!await _isAuthorized(request, body: payload)) {
          await _rejectUnauthorized(request);
          return;
        }
        final snapshots = _decodeBatchPayload(payload);
        await _importBatchCategories(snapshots);
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'ok': true}));
        await request.response.close();
        return;
      }
      if (request.uri.pathSegments.length == 2 &&
          request.uri.pathSegments.first == 'sync') {
        if (request.method == 'GET' &&
            !await _isAuthorized(request, body: '')) {
          await _rejectUnauthorized(request);
          return;
        }
        final category = SyncDataCategory.tryParse(request.uri.pathSegments[1]);
        if (category == null) {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
          return;
        }
        if (request.method == 'GET') {
          final snapshot = await exportCategory(category);
          request.response.headers.contentType = ContentType.json;
          request.response.write(SyncSnapshotJsonCodec.encode(snapshot));
          await request.response.close();
          return;
        }
        if (request.method == 'POST') {
          final payload = await _readPayload(request);
          if (!await _isAuthorized(request, body: payload)) {
            await _rejectUnauthorized(request);
            return;
          }
          final snapshot = _decodeSnapshotPayload(payload);
          await importCategory(category, snapshot);
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode({'ok': true}));
          await request.response.close();
          return;
        }
      }
      if (request.uri.path != '/snapshot') {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }
      if (request.method == 'GET') {
        if (!await _isAuthorized(request, body: '')) {
          await _rejectUnauthorized(request);
          return;
        }
        final snapshot = await exportSnapshot();
        request.response.headers.contentType = ContentType.json;
        request.response.write(SyncSnapshotJsonCodec.encode(snapshot));
        await request.response.close();
        return;
      }
      if (request.method == 'POST') {
        final payload = await _readPayload(request);
        if (!await _isAuthorized(request, body: payload)) {
          await _rejectUnauthorized(request);
          return;
        }
        final snapshot = _decodeSnapshotPayload(payload);
        await _importFullSnapshot(snapshot);
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'ok': true}));
        await request.response.close();
        return;
      }
      request.response.statusCode = HttpStatus.methodNotAllowed;
      await request.response.close();
    } on _PayloadTooLargeException catch (error) {
      request.response.statusCode = HttpStatus.requestEntityTooLarge;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'error': 'payload_too_large',
          'message': error.message,
        }),
      );
      await request.response.close();
    } on FormatException catch (error) {
      request.response.statusCode = HttpStatus.badRequest;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'error': 'invalid_snapshot',
          'message': error.message,
        }),
      );
      await request.response.close();
    } catch (error, stackTrace) {
      _onUnexpectedError(error, stackTrace);
      request.response.statusCode = HttpStatus.internalServerError;
      await request.response.close();
    }
  }

  Future<String> _readPayload(HttpRequest request) async {
    if (request.contentLength > maxRequestBytes) {
      throw _PayloadTooLargeException(maxRequestBytes);
    }
    final builder = BytesBuilder(copy: false);
    var total = 0;
    await for (final chunk in request) {
      total += chunk.length;
      if (total > maxRequestBytes) {
        throw _PayloadTooLargeException(maxRequestBytes);
      }
      builder.add(chunk);
    }
    return utf8.decode(builder.takeBytes());
  }

  SyncSnapshot _decodeSnapshotPayload(String payload) {
    return SyncSnapshotJsonCodec.decode(payload);
  }

  Map<SyncDataCategory, SyncSnapshot> _decodeBatchPayload(String payload) {
    final decoded = jsonDecode(payload);
    if (decoded is! Map) {
      throw const FormatException(
          'Local sync batch payload must be an object.');
    }
    final rawCategories = decoded['categories'];
    if (rawCategories is! Map || rawCategories.isEmpty) {
      throw const FormatException(
        'Local sync batch payload must include categories.',
      );
    }
    final snapshots = <SyncDataCategory, SyncSnapshot>{};
    for (final entry in rawCategories.entries) {
      final category = SyncDataCategory.tryParse(entry.key?.toString());
      if (category == null) {
        throw FormatException('Unknown local sync category: ${entry.key}.');
      }
      if (entry.value is! Map) {
        throw FormatException(
          'Local sync category ${category.apiValue} payload must be an object.',
        );
      }
      snapshots[category] = SyncSnapshotJsonCodec.decode(
        jsonEncode(entry.value),
      );
    }
    return snapshots;
  }

  Future<void> _importBatchCategories(
    Map<SyncDataCategory, SyncSnapshot> snapshots,
  ) async {
    if (snapshots.isEmpty) {
      return;
    }
    final backups = <SyncDataCategory, SyncSnapshot>{};
    for (final category in snapshots.keys) {
      backups[category] = await exportCategory(category);
    }
    try {
      for (final entry in snapshots.entries) {
        await importCategory(entry.key, entry.value);
      }
    } catch (error, stackTrace) {
      try {
        for (final entry in backups.entries) {
          await _rollbackCategory(entry.key, entry.value);
        }
      } catch (rollbackError) {
        Error.throwWithStackTrace(
          _BatchImportRollbackException(
            cause: error,
            rollbackCause: rollbackError,
          ),
          stackTrace,
        );
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> _importFullSnapshot(SyncSnapshot snapshot) async {
    final backup = await exportSnapshot();
    try {
      await _importSnapshot(snapshot);
    } catch (error, stackTrace) {
      try {
        await _importSnapshot(backup);
      } catch (rollbackError) {
        Error.throwWithStackTrace(
          _SnapshotImportRollbackException(
            cause: error,
            rollbackCause: rollbackError,
          ),
          stackTrace,
        );
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<bool> _isAuthorized(
    HttpRequest request, {
    required String body,
  }) async {
    final expected = await _effectiveAccessToken();
    if (expected == null) {
      return !_isWildcardHost(host);
    }
    _pruneExpiredNonces();
    final timestamp = request.headers.value(_timestampHeader)?.trim();
    final nonce = request.headers.value(_nonceHeader)?.trim();
    final signature = request.headers.value(_signatureHeader)?.trim();
    if (timestamp == null ||
        timestamp.isEmpty ||
        nonce == null ||
        nonce.isEmpty ||
        signature == null ||
        signature.isEmpty) {
      return false;
    }
    final seconds = int.tryParse(timestamp);
    if (seconds == null) {
      return false;
    }
    final requestTime =
        DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
    final now = DateTime.now().toUtc();
    if (requestTime.isBefore(now.subtract(_authTimestampSkew)) ||
        requestTime.isAfter(now.add(_authTimestampSkew))) {
      return false;
    }
    if (_seenAuthNonces.containsKey(nonce)) {
      return false;
    }
    final bodySha256 = sha256.convert(utf8.encode(body)).toString();
    final payload =
        '${request.method.toUpperCase()}${request.uri.path}$timestamp$nonce$bodySha256';
    final expectedSignature = Hmac(sha256, utf8.encode(expected))
        .convert(utf8.encode(payload))
        .toString();
    if (!_constantTimeEquals(signature, expectedSignature)) {
      return false;
    }
    _pruneExpiredNonces();
    while (_seenAuthNonces.length >= _maxSeenAuthNonces) {
      _seenAuthNonces.remove(_seenAuthNonces.keys.first);
    }
    _seenAuthNonces[nonce] = requestTime;
    return true;
  }

  void _pruneExpiredNonces() {
    final cutoff = DateTime.now().toUtc().subtract(_authTimestampSkew);
    _seenAuthNonces.removeWhere((_, timestamp) => timestamp.isBefore(cutoff));
  }

  bool _constantTimeEquals(String left, String right) {
    if (left.length != right.length) {
      return false;
    }
    var diff = 0;
    for (var index = 0; index < left.length; index += 1) {
      diff |= left.codeUnitAt(index) ^ right.codeUnitAt(index);
    }
    return diff == 0;
  }

  Future<String?> _effectiveAccessToken() async {
    final resolved = _normalizeAccessToken(await _accessTokenResolver?.call());
    return resolved ?? _staticAccessToken;
  }

  Future<void> _rejectUnauthorized(HttpRequest request) async {
    request.response.statusCode = HttpStatus.unauthorized;
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({'error': 'unauthorized'}));
    await request.response.close();
  }

  static bool _isWildcardHost(String host) {
    final normalized = host.trim().toLowerCase();
    return normalized == '0.0.0.0' || normalized == '::';
  }

  static String? _normalizeAccessToken(String? accessToken) {
    final normalized = accessToken?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  static void _defaultUnexpectedErrorLogger(
    Object error,
    StackTrace stackTrace,
  ) {
    developer.log(
      'Unhandled local sync server error.',
      name: 'live_sync.local_sync_server',
      error: error,
      stackTrace: stackTrace,
    );
  }
}

class _PayloadTooLargeException implements Exception {
  const _PayloadTooLargeException(this.maxBytes);

  final int maxBytes;

  String get message => '请求体超过限制，最大允许 $maxBytes 字节。';
}

class _BatchImportRollbackException implements Exception {
  const _BatchImportRollbackException({
    required this.cause,
    required this.rollbackCause,
  });

  final Object cause;
  final Object rollbackCause;

  @override
  String toString() {
    return 'Local sync batch import rollback failed '
        '(cause: $cause, rollbackCause: $rollbackCause)';
  }
}

class _SnapshotImportRollbackException implements Exception {
  const _SnapshotImportRollbackException({
    required this.cause,
    required this.rollbackCause,
  });

  final Object cause;
  final Object rollbackCause;

  @override
  String toString() {
    return 'Local sync snapshot import rollback failed '
        '(cause: $cause, rollbackCause: $rollbackCause)';
  }
}
