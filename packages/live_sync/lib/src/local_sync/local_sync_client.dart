import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../model/discovered_peer.dart';
import '../model/local_sync_peer_info.dart';
import '../model/sync_data_category.dart';
import '../model/sync_snapshot.dart';
import '../model/sync_snapshot_codec.dart';
import '../network/cleartext_policy.dart';

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

  Future<void> pushCategories({
    required DiscoveredPeer peer,
    required Map<SyncDataCategory, SyncSnapshot> snapshots,
  });

  Future<void> close({bool force = false});
}

class HttpLocalSyncClient implements LocalSyncClient {
  HttpLocalSyncClient({HttpClient? client})
    : _client = client ?? HttpClient(),
      _ownsClient = client == null {
    if (_ownsClient) {
      _client.connectionTimeout = _kConnectTimeout;
      _client.idleTimeout = _kTransferTimeout;
    }
  }

  /// 建连超时：目标离线时尽快失败。
  static const Duration _kConnectTimeout = Duration(seconds: 10);

  /// 传输超时：全量快照导入可能较慢，需明显高于分类同步。
  static const Duration _kTransferTimeout = Duration(seconds: 90);

  static const String _timestampHeader = 'X-Nolive-Sync-Timestamp';
  static const String _nonceHeader = 'X-Nolive-Sync-Nonce';
  static const String _signatureHeader = 'X-Nolive-Sync-Signature';

  final HttpClient _client;
  final bool _ownsClient;

  @override
  Future<void> close({bool force = false}) async {
    if (_ownsClient) {
      _client.close(force: force);
    }
  }

  @override
  Future<LocalSyncPeerInfo> fetchInfo({required DiscoveredPeer peer}) async {
    final uri = _peerUri(peer, '/info');
    final response = await _send(method: 'GET', uri: uri, peer: peer);
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
    final uri = _peerUri(peer, '/snapshot');
    final response = await _send(
      method: 'POST',
      uri: uri,
      peer: peer,
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
    final uri = _peerUri(peer, '/snapshot');
    final response = await _send(method: 'GET', uri: uri, peer: peer);
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
    final uri = _peerUri(peer, '/sync/${category.apiValue}');
    final response = await _send(
      method: 'POST',
      uri: uri,
      peer: peer,
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

  @override
  Future<void> pushCategories({
    required DiscoveredPeer peer,
    required Map<SyncDataCategory, SyncSnapshot> snapshots,
  }) async {
    if (snapshots.isEmpty) {
      return;
    }
    final uri = _peerUri(peer, '/sync/batch');
    final response = await _send(
      method: 'POST',
      uri: uri,
      peer: peer,
      contentType: ContentType.json,
      body: jsonEncode(<String, Object?>{
        'categories': {
          for (final entry in snapshots.entries)
            entry.key.apiValue: jsonDecode(
              SyncSnapshotJsonCodec.encode(entry.value),
            ),
        },
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Local sync batch push failed with status ${response.statusCode}.',
      );
    }
    await utf8.decoder.bind(response).join();
  }

  Future<HttpClientResponse> _send({
    required String method,
    required Uri uri,
    required DiscoveredPeer peer,
    ContentType? contentType,
    String? body,
  }) async {
    try {
      final request = await _client
          .openUrl(method, uri)
          .timeout(_kConnectTimeout);
      if (contentType != null) {
        request.headers.contentType = contentType;
      }
      final accessToken = peer.accessToken?.trim();
      if (accessToken != null && accessToken.isNotEmpty) {
        final authHeaders = _buildAuthHeaders(
          secret: accessToken,
          method: method,
          path: uri.path,
          body: body ?? '',
        );
        for (final entry in authHeaders.entries) {
          request.headers.set(entry.key, entry.value);
        }
      }
      if (body != null) {
        request.write(body);
      }
      return await request.close().timeout(_kTransferTimeout);
    } on TimeoutException {
      throw HttpException('Local sync request timed out.', uri: uri);
    } on SocketException catch (error) {
      throw HttpException(
        'Local sync connection failed: ${error.message}.',
        uri: uri,
      );
    }
  }

  Uri _peerUri(DiscoveredPeer peer, String path) {
    final uri = Uri(
      scheme: 'http',
      host: peer.address.trim(),
      port: peer.port,
      path: path,
    );
    assertAllowedLocalCleartext(uri, feature: '局域网同步');
    return uri;
  }

  Map<String, String> _buildAuthHeaders({
    required String secret,
    required String method,
    required String path,
    required String body,
  }) {
    final timestamp = (DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000)
        .toString();
    final nonce = _generateNonce();
    final bodySha256 = sha256.convert(utf8.encode(body)).toString();
    final payload = '${method.toUpperCase()}$path$timestamp$nonce$bodySha256';
    final signature = Hmac(
      sha256,
      utf8.encode(secret),
    ).convert(utf8.encode(payload)).toString();
    return {
      _timestampHeader: timestamp,
      _nonceHeader: nonce,
      _signatureHeader: signature,
    };
  }

  String _generateNonce() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }
}
