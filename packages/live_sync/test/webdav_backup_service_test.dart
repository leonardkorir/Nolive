import 'dart:convert';
import 'dart:io';

import 'package:live_storage/live_storage.dart';
import 'package:live_sync/live_sync.dart';
import 'package:test/test.dart';

void main() {
  test('http webdav backup service uploads and restores snapshot', () async {
    String? uploadedBody;
    final requests = <String>[];
    final createdDirectories = <String>{};
    final server = await HttpServer.bind('127.0.0.1', 0);
    server.listen((request) async {
      requests.add('${request.method} ${request.uri.path}');
      if (request.method == 'PROPFIND') {
        request.response.statusCode = HttpStatus.multiStatus;
        await request.response.close();
        return;
      }
      if (request.method == 'MKCOL') {
        request.response.statusCode = createdDirectories.add(request.uri.path)
            ? HttpStatus.created
            : HttpStatus.methodNotAllowed;
        await request.response.close();
        return;
      }
      if (request.method == 'PUT') {
        uploadedBody = await utf8.decoder.bind(request).join();
        request.response.statusCode = HttpStatus.created;
        await request.response.close();
        return;
      }
      if (request.method == 'GET') {
        request.response.headers.contentType = ContentType.json;
        request.response.write(uploadedBody ?? '{}');
        await request.response.close();
        return;
      }
      request.response.statusCode = HttpStatus.methodNotAllowed;
      await request.response.close();
    });

    final service = HttpWebDavBackupService(
      config: WebDavBackupConfig(
        baseUrl: 'http://127.0.0.1:${server.port}/dav',
        remotePath: 'nolive/backup.json',
      ),
    );
    final snapshot = SyncSnapshot(
      settings: const {'theme_mode': 'dark'},
      follows: const [
        FollowRecord(providerId: 'bilibili', roomId: '1', streamerName: '主播'),
      ],
    );

    await service.uploadSnapshot(snapshot);
    final restored = await service.restoreLatest();

    expect(requests, contains('MKCOL /dav/nolive/'));
    expect(requests, contains('PUT /dav/nolive/backup.json'));
    expect(requests, contains('GET /dav/nolive/backup.json'));
    expect(restored, isNotNull);
    expect(restored!.settings['theme_mode'], 'dark');
    expect(restored.follows.single.roomId, '1');

    await server.close(force: true);
  });
}
