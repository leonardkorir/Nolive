import 'dart:convert';
import 'dart:io';

import '../model/local_sync_peer_info.dart';
import '../model/sync_data_category.dart';
import '../model/sync_snapshot.dart';
import '../model/sync_snapshot_codec.dart';

abstract class LocalSyncServer {
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
    Future<LocalSyncPeerInfo> Function()? readInfo,
    this.host = '0.0.0.0',
    this.port = 23234,
  })  : _exportSnapshot = exportSnapshot,
        _importSnapshot = importSnapshot,
        _exportCategory = exportCategory,
        _importCategory = importCategory,
        _readInfo = readInfo ??
            (() async => const LocalSyncPeerInfo(
                  displayName: 'nolive-device',
                  deviceId: 'nolive-device',
                  platform: 'unknown',
                ));

  final Future<SyncSnapshot> Function() _exportSnapshot;
  final Future<void> Function(SyncSnapshot snapshot) _importSnapshot;
  final Future<SyncSnapshot> Function(SyncDataCategory category)
      _exportCategory;
  final Future<void> Function(
    SyncDataCategory category,
    SyncSnapshot snapshot,
  ) _importCategory;
  final Future<LocalSyncPeerInfo> Function() _readInfo;
  final String host;
  final int port;

  HttpServer? _server;

  bool get isRunning => _server != null;

  Uri get endpoint => Uri.parse(
      'http://${host == '0.0.0.0' ? '127.0.0.1' : host}:$port/snapshot');

  @override
  Future<void> start() async {
    if (_server != null) {
      return;
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
  Future<LocalSyncPeerInfo> readInfo() => _readInfo();

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      if (request.uri.path == '/info' && request.method == 'GET') {
        final info = await readInfo();
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(info.toJson()));
        await request.response.close();
        return;
      }
      if (request.uri.pathSegments.length == 2 &&
          request.uri.pathSegments.first == 'sync') {
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
          final payload = await utf8.decoder.bind(request).join();
          final snapshot = SyncSnapshotJsonCodec.decode(payload);
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
        final snapshot = await exportSnapshot();
        request.response.headers.contentType = ContentType.json;
        request.response.write(SyncSnapshotJsonCodec.encode(snapshot));
        await request.response.close();
        return;
      }
      if (request.method == 'POST') {
        final payload = await utf8.decoder.bind(request).join();
        final snapshot = SyncSnapshotJsonCodec.decode(payload);
        await _importSnapshot(snapshot);
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'ok': true}));
        await request.response.close();
        return;
      }
      request.response.statusCode = HttpStatus.methodNotAllowed;
      await request.response.close();
    } catch (_) {
      request.response.statusCode = HttpStatus.internalServerError;
      await request.response.close();
    }
  }
}
