import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../model/sync_snapshot.dart';
import '../model/sync_snapshot_codec.dart';

abstract class WebDavBackupService {
  Future<void> testConnection();

  Future<void> uploadSnapshot(SyncSnapshot snapshot);

  Future<SyncSnapshot?> restoreLatest();
}

class WebDavBackupConfig {
  const WebDavBackupConfig({
    required this.baseUrl,
    required this.remotePath,
    this.username = '',
    this.password = '',
  });

  final String baseUrl;
  final String remotePath;
  final String username;
  final String password;

  bool get isConfigured =>
      baseUrl.trim().isNotEmpty && remotePath.trim().isNotEmpty;
}

class HttpWebDavBackupService implements WebDavBackupService {
  HttpWebDavBackupService({required this.config, HttpClient? client})
      : _client = client ?? HttpClient() {
    _client.connectionTimeout = _kRequestTimeout;
    _client.idleTimeout = _kRequestTimeout;
  }

  static const Duration _kRequestTimeout = Duration(seconds: 10);

  final WebDavBackupConfig config;
  final HttpClient _client;

  @override
  Future<void> testConnection() async {
    _assertConfigured();
    await _probeUri(_baseUri());
    await _ensureRemoteDirectories();
    await _probeUri(_parentDirectoryUri());
  }

  @override
  Future<void> uploadSnapshot(SyncSnapshot snapshot) async {
    await testConnection();
    final request = await _openRequest('PUT', _fileUri());
    request.headers.contentType = ContentType.json;
    request.write(SyncSnapshotJsonCodec.encode(snapshot));
    final response = await request.close().timeout(_kRequestTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      await _throwStatus(
        action: 'WebDAV 上传失败',
        response: response,
        uri: _fileUri(),
      );
    }
    await response.drain<void>();
  }

  @override
  Future<SyncSnapshot?> restoreLatest() async {
    await testConnection();
    final request = await _openRequest('GET', _fileUri());
    final response = await request.close().timeout(_kRequestTimeout);
    if (response.statusCode == HttpStatus.notFound) {
      await response.drain<void>();
      return null;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      await _throwStatus(
        action: 'WebDAV 恢复失败',
        response: response,
        uri: _fileUri(),
      );
    }
    final payload = await utf8.decoder.bind(response).join();
    return SyncSnapshotJsonCodec.decode(payload);
  }

  Future<void> _probeUri(Uri uri) async {
    final response = await _send(
      'PROPFIND',
      uri,
      headers: const {
        'Depth': '0',
        HttpHeaders.contentTypeHeader: 'text/xml; charset=utf-8',
      },
      body:
          '<d:propfind xmlns:d="DAV:"><d:prop><d:resourcetype/></d:prop></d:propfind>',
    );
    switch (response.statusCode) {
      case HttpStatus.ok:
      case HttpStatus.noContent:
      case HttpStatus.multiStatus:
      case HttpStatus.movedPermanently:
      case HttpStatus.found:
        await response.drain<void>();
        return;
      case HttpStatus.unauthorized:
      case HttpStatus.forbidden:
        await _throwStatus(
          action: 'WebDAV 鉴权失败',
          response: response,
          uri: uri,
        );
      case HttpStatus.methodNotAllowed:
      case HttpStatus.notImplemented:
        await response.drain<void>();
        return _probeWithHead(uri);
      default:
        await _throwStatus(
          action: 'WebDAV 连接测试失败',
          response: response,
          uri: uri,
        );
    }
  }

  Future<void> _probeWithHead(Uri uri) async {
    final response = await _send('HEAD', uri);
    switch (response.statusCode) {
      case HttpStatus.ok:
      case HttpStatus.noContent:
      case HttpStatus.movedPermanently:
      case HttpStatus.found:
        await response.drain<void>();
        return;
      default:
        await _throwStatus(
          action: 'WebDAV 连接测试失败',
          response: response,
          uri: uri,
        );
    }
  }

  Future<void> _ensureRemoteDirectories() async {
    final segments = _directorySegments();
    if (segments.isEmpty) {
      return;
    }
    final builtSegments = <String>[];
    for (final segment in segments) {
      builtSegments.add(segment);
      final response = await _send(
        'MKCOL',
        _appendPath(_baseUri(), builtSegments, directory: true),
      );
      switch (response.statusCode) {
        case HttpStatus.ok:
        case HttpStatus.created:
        case HttpStatus.noContent:
        case HttpStatus.multiStatus:
        case HttpStatus.movedPermanently:
        case HttpStatus.found:
        case HttpStatus.methodNotAllowed:
          await response.drain<void>();
          continue;
        default:
          await _throwStatus(
            action: 'WebDAV 创建远端目录失败',
            response: response,
            uri: _appendPath(_baseUri(), builtSegments, directory: true),
          );
      }
    }
  }

  Future<HttpClientRequest> _openRequest(String method, Uri uri) async {
    try {
      final request =
          await _client.openUrl(method, uri).timeout(_kRequestTimeout);
      _applyHeaders(request);
      return request;
    } on TimeoutException {
      throw HttpException('WebDAV 请求超时。', uri: uri);
    } on HandshakeException catch (error) {
      throw HttpException('WebDAV TLS 连接失败：$error', uri: uri);
    } on SocketException catch (error) {
      throw HttpException('WebDAV 连接失败：${error.message}', uri: uri);
    }
  }

  Future<HttpClientResponse> _send(
    String method,
    Uri uri, {
    Map<String, String> headers = const {},
    String? body,
  }) async {
    final request = await _openRequest(method, uri);
    for (final entry in headers.entries) {
      request.headers.set(entry.key, entry.value);
    }
    if (body != null) {
      request.write(body);
    }
    try {
      return await request.close().timeout(_kRequestTimeout);
    } on TimeoutException {
      throw HttpException('WebDAV 请求超时。', uri: uri);
    } on HandshakeException catch (error) {
      throw HttpException('WebDAV TLS 连接失败：$error', uri: uri);
    } on SocketException catch (error) {
      throw HttpException('WebDAV 连接失败：${error.message}', uri: uri);
    }
  }

  Future<Never> _throwStatus({
    required String action,
    required HttpClientResponse response,
    required Uri uri,
  }) async {
    final detail = await _readResponseText(response);
    final suffix = detail.isEmpty ? '' : '：$detail';
    throw HttpException('$action：HTTP ${response.statusCode}$suffix', uri: uri);
  }

  Future<String> _readResponseText(HttpClientResponse response) async {
    final body = await utf8.decoder.bind(response).join();
    final trimmed = body.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    return trimmed.length <= 160 ? trimmed : '${trimmed.substring(0, 160)}...';
  }

  Uri _baseUri() {
    final base = Uri.parse(config.baseUrl.trim());
    final normalizedPath =
        base.path.endsWith('/') ? base.path : '${base.path}/';
    return base.replace(path: normalizedPath, query: null, fragment: null);
  }

  Uri _parentDirectoryUri() {
    final segments = _directorySegments();
    if (segments.isEmpty) {
      return _baseUri();
    }
    return _appendPath(_baseUri(), segments, directory: true);
  }

  Uri _fileUri() {
    return _appendPath(_baseUri(), _remotePathSegments());
  }

  Uri _appendPath(
    Uri base,
    List<String> segments, {
    bool directory = false,
  }) {
    final prefix = base.path.endsWith('/') ? base.path : '${base.path}/';
    final encoded = segments.map(Uri.encodeComponent).join('/');
    final suffix = directory ? '/' : '';
    return base.replace(path: '$prefix$encoded$suffix');
  }

  List<String> _remotePathSegments() {
    final raw = config.remotePath.trim();
    return raw
        .split('/')
        .map((segment) => segment.trim())
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
  }

  List<String> _directorySegments() {
    final segments = _remotePathSegments();
    if (segments.length <= 1) {
      return const [];
    }
    return segments.sublist(0, segments.length - 1);
  }

  void _applyHeaders(HttpClientRequest request) {
    final auth = _buildAuthorizationHeader();
    if (auth != null) {
      request.headers.set(HttpHeaders.authorizationHeader, auth);
    }
    request.headers
        .set(HttpHeaders.acceptHeader, 'application/json, text/xml, */*');
  }

  String? _buildAuthorizationHeader() {
    if (config.username.isEmpty && config.password.isEmpty) {
      return null;
    }
    final token =
        base64Encode(utf8.encode('${config.username}:${config.password}'));
    return 'Basic $token';
  }

  void _assertConfigured() {
    if (config.isConfigured) {
      return;
    }
    throw const FormatException('请先填写 WebDAV Base URL 和远端文件路径。');
  }
}
