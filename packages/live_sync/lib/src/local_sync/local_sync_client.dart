import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../model/discovered_peer.dart';
import '../model/local_sync_peer_info.dart';
import '../model/sync_data_category.dart';
import '../model/sync_snapshot.dart';
import '../model/sync_snapshot_codec.dart';

abstract class LocalSyncClient {
  Future<LocalSyncPeerInfo> fetchInfo({required DiscoveredPeer peer});

  Future<SyncSnapshot> fetchSnapshot({required DiscoveredPeer peer});

  Future<void> pushSnapshot({
    required DiscoveredPeer peer,
    required SyncSnapshot snapshot,
  });

  Future<void> pushCategory({
    required DiscoveredPeer peer,
    required SyncDataCategory category,
    required SyncSnapshot snapshot,
  });
}

class HttpLocalSyncClient implements LocalSyncClient {
  HttpLocalSyncClient({HttpClient? client}) : _client = client ?? HttpClient() {
    _client.connectionTimeout = _kRequestTimeout;
    _client.idleTimeout = _kRequestTimeout;
  }

  static const Duration _kRequestTimeout = Duration(seconds: 5);

  final HttpClient _client;

  @override
  Future<LocalSyncPeerInfo> fetchInfo({required DiscoveredPeer peer}) async {
    final response = await _send(
      method: 'GET',
      uri: Uri.parse('http://${peer.address}:${peer.port}/info'),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Local sync info failed with status ${response.statusCode}.',
      );
    }
    final payload = await utf8.decoder.bind(response).join();
    final decoded = json.decode(payload);
    if (decoded is! Map) {
      throw const FormatException('Invalid local sync peer info payload.');
    }
    return LocalSyncPeerInfo.fromJson(decoded.cast<String, dynamic>());
  }

  @override
  Future<void> pushSnapshot({
    required DiscoveredPeer peer,
    required SyncSnapshot snapshot,
  }) async {
    final response = await _send(
      method: 'POST',
      uri: Uri.parse('http://${peer.address}:${peer.port}/snapshot'),
      contentType: ContentType.json,
      body: SyncSnapshotJsonCodec.encode(snapshot),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Local sync push failed with status ${response.statusCode}.',
      );
    }
    await utf8.decoder.bind(response).join();
  }

  @override
  Future<SyncSnapshot> fetchSnapshot({required DiscoveredPeer peer}) async {
    final response = await _send(
      method: 'GET',
      uri: Uri.parse('http://${peer.address}:${peer.port}/snapshot'),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Local sync snapshot fetch failed with status ${response.statusCode}.',
      );
    }
    final payload = await utf8.decoder.bind(response).join();
    return SyncSnapshotJsonCodec.decode(payload);
  }

  @override
  Future<void> pushCategory({
    required DiscoveredPeer peer,
    required SyncDataCategory category,
    required SyncSnapshot snapshot,
  }) async {
    final response = await _send(
      method: 'POST',
      uri: Uri.parse(
        'http://${peer.address}:${peer.port}/sync/${category.apiValue}',
      ),
      contentType: ContentType.json,
      body: SyncSnapshotJsonCodec.encode(snapshot),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Local sync ${category.apiValue} push failed with status ${response.statusCode}.',
      );
    }
    await utf8.decoder.bind(response).join();
  }

  Future<HttpClientResponse> _send({
    required String method,
    required Uri uri,
    ContentType? contentType,
    String? body,
  }) async {
    try {
      final request =
          await _client.openUrl(method, uri).timeout(_kRequestTimeout);
      if (contentType != null) {
        request.headers.contentType = contentType;
      }
      if (body != null) {
        request.write(body);
      }
      return await request.close().timeout(_kRequestTimeout);
    } on TimeoutException {
      throw HttpException('Local sync request timed out.', uri: uri);
    } on SocketException catch (error) {
      throw HttpException(
        'Local sync connection failed: ${error.message}.',
        uri: uri,
      );
    }
  }
}
