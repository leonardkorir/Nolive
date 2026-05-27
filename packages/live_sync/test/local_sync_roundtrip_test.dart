import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:live_storage/live_storage.dart';
import 'package:live_sync/live_sync.dart';
import 'package:test/test.dart';

void main() {
  test('http local sync server accepts pushed snapshot', () async {
    SyncSnapshot current = const SyncSnapshot();
    final server = HttpLocalSyncServer(
      host: '127.0.0.1',
      exportSnapshot: () async => current,
      importSnapshot: (snapshot) async {
        current = snapshot;
      },
      exportCategory: (_) async => current,
      importCategory: (_, snapshot) async {
        current = snapshot;
      },
      port: 28234,
    );
    await server.start();

    final client = HttpLocalSyncClient();
    await client.pushSnapshot(
      peer: DiscoveredPeer(
        deviceId: 'dev-1',
        displayName: '桌面端',
        address: '127.0.0.1',
        port: 28234,
        lastSeenAt: DateTime(2026, 3, 30),
      ),
      snapshot: const SyncSnapshot(
        tags: ['常看'],
        follows: [
          FollowRecord(providerId: 'douyu', roomId: '999', streamerName: '主播A'),
        ],
      ),
    );

    final exported = await server.exportSnapshot();
    expect(exported.tags, ['常看']);
    expect(exported.follows.single.roomId, '999');

    await server.stop();
  });

  test('http local sync server exposes peer info', () async {
    final server = HttpLocalSyncServer(
      host: '127.0.0.1',
      exportSnapshot: () async => const SyncSnapshot(),
      importSnapshot: (_) async {},
      exportCategory: (_) async => const SyncSnapshot(),
      importCategory: (_, __) async {},
      readInfo: () async => const LocalSyncPeerInfo(
        displayName: '测试设备',
        deviceId: 'test-device',
        platform: 'linux',
      ),
      port: 28235,
    );
    await server.start();

    final client = HttpLocalSyncClient();
    final info = await client.fetchInfo(
      peer: DiscoveredPeer(
        deviceId: 'dev-2',
        displayName: '手机',
        address: '127.0.0.1',
        port: 28235,
        lastSeenAt: DateTime(2026, 3, 30),
      ),
    );

    expect(info.displayName, '测试设备');
    expect(info.deviceId, 'test-device');
    expect(info.platform, 'linux');
    expect(info.snapshotPath, '/snapshot');

    await server.stop();
  });

  test('manual local discovery service closes streams on dispose', () async {
    final service = ManualLocalDiscoveryService();
    final events = <List<DiscoveredPeer>>[];
    final done = Completer<void>();
    final subscription = service.watchPeers().listen(
          events.add,
          onDone: done.complete,
        );
    addTearDown(subscription.cancel);

    await service.start();
    service.addOrReplacePeer(
      DiscoveredPeer(
        deviceId: 'peer-1',
        displayName: 'Peer',
        address: '192.168.1.20',
        port: 23234,
        lastSeenAt: DateTime(2026, 5, 2),
      ),
    );
    await pumpEventQueue();

    expect(events, hasLength(2));
    expect(events.last.single.deviceId, 'peer-1');

    await service.dispose();
    await done.future.timeout(const Duration(seconds: 1));

    service.addOrReplacePeer(
      DiscoveredPeer(
        deviceId: 'peer-2',
        displayName: 'Peer 2',
        address: '192.168.1.21',
        port: 23234,
        lastSeenAt: DateTime(2026, 5, 2),
      ),
    );
    await pumpEventQueue();

    expect(events, hasLength(3));
    expect(events.last, isEmpty);
  });

  test('http local sync server rejects malformed snapshot payloads as 400',
      () async {
    final server = HttpLocalSyncServer(
      host: '127.0.0.1',
      exportSnapshot: () async => const SyncSnapshot(),
      importSnapshot: (_) async {},
      exportCategory: (_) async => const SyncSnapshot(),
      importCategory: (_, __) async {},
      port: 28236,
    );
    await server.start();
    addTearDown(server.stop);

    final client = HttpClient();
    addTearDown(client.close);

    Future<HttpClientResponse> post(String path, String body) async {
      final request =
          await client.postUrl(Uri.parse('http://127.0.0.1:28236$path'));
      request.headers.contentType = ContentType.json;
      request.write(body);
      return request.close();
    }

    final snapshotResponse = await post('/snapshot', '{"settings":');
    expect(snapshotResponse.statusCode, HttpStatus.badRequest);
    expect(
      jsonDecode(await utf8.decoder.bind(snapshotResponse).join()),
      containsPair('error', 'invalid_snapshot'),
    );

    final categoryResponse = await post('/sync/settings', '[]');
    expect(categoryResponse.statusCode, HttpStatus.badRequest);
    expect(
      jsonDecode(await utf8.decoder.bind(categoryResponse).join()),
      containsPair('error', 'invalid_snapshot'),
    );
  });

  test('http local sync server rejects oversized snapshot payloads as 413',
      () async {
    final server = HttpLocalSyncServer(
      host: '127.0.0.1',
      exportSnapshot: () async => const SyncSnapshot(),
      importSnapshot: (_) async {},
      exportCategory: (_) async => const SyncSnapshot(),
      importCategory: (_, __) async {},
      port: 28237,
      maxRequestBytes: 32,
    );
    await server.start();
    addTearDown(server.stop);

    final client = HttpClient();
    addTearDown(client.close);

    final request =
        await client.postUrl(Uri.parse('http://127.0.0.1:28237/snapshot'));
    request.headers.contentType = ContentType.json;
    request.write('{"settings":{"theme_mode":"${'x' * 64}"}}');
    final response = await request.close();

    expect(response.statusCode, HttpStatus.requestEntityTooLarge);
    expect(
      jsonDecode(await utf8.decoder.bind(response).join()),
      containsPair('error', 'payload_too_large'),
    );
  });

  test('http local sync server logs unexpected import failures as 500',
      () async {
    Object? loggedError;
    StackTrace? loggedStackTrace;
    final server = HttpLocalSyncServer(
      host: '127.0.0.1',
      exportSnapshot: () async => const SyncSnapshot(),
      importSnapshot: (_) async {
        throw StateError('boom');
      },
      exportCategory: (_) async => const SyncSnapshot(),
      importCategory: (_, __) async {},
      port: 28238,
      onUnexpectedError: (error, stackTrace) {
        loggedError = error;
        loggedStackTrace = stackTrace;
      },
    );
    await server.start();
    addTearDown(server.stop);

    final client = HttpClient();
    addTearDown(client.close);

    final request =
        await client.postUrl(Uri.parse('http://127.0.0.1:28238/snapshot'));
    request.headers.contentType = ContentType.json;
    request.write(SyncSnapshotJsonCodec.encode(const SyncSnapshot()));
    final response = await request.close();

    expect(response.statusCode, HttpStatus.internalServerError);
    expect(loggedError.toString(), contains('snapshot import rollback failed'));
    expect(loggedStackTrace, isNotNull);
  });

  test('wildcard local sync server requires and validates access token',
      () async {
    expect(
      () => HttpLocalSyncServer(
        exportSnapshot: () async => const SyncSnapshot(),
        importSnapshot: (_) async {},
        exportCategory: (_) async => const SyncSnapshot(),
        importCategory: (_, __) async {},
      ),
      throwsArgumentError,
    );

    final resolverWithoutToken = HttpLocalSyncServer(
      exportSnapshot: () async => const SyncSnapshot(),
      importSnapshot: (_) async {},
      exportCategory: (_) async => const SyncSnapshot(),
      importCategory: (_, __) async {},
      accessTokenResolver: () async => '',
      port: 28241,
    );
    await expectLater(resolverWithoutToken.start(), throwsArgumentError);

    final server = HttpLocalSyncServer(
      exportSnapshot: () async => const SyncSnapshot(tags: ['secure']),
      importSnapshot: (_) async {},
      exportCategory: (_) async => const SyncSnapshot(),
      importCategory: (_, __) async {},
      accessToken: 'sync-token',
      port: 28239,
    );
    await server.start();
    addTearDown(server.stop);

    final client = HttpClient();
    addTearDown(client.close);

    final unauthorized =
        await client.getUrl(Uri.parse('http://127.0.0.1:28239/snapshot'));
    final unauthorizedResponse = await unauthorized.close();
    expect(unauthorizedResponse.statusCode, HttpStatus.unauthorized);

    final infoRequest =
        await client.getUrl(Uri.parse('http://127.0.0.1:28239/info'));
    final infoResponse = await infoRequest.close();
    await utf8.decoder.bind(infoResponse).join();
    expect(infoResponse.statusCode, HttpStatus.unauthorized);

    final syncClient = HttpLocalSyncClient();
    addTearDown(syncClient.close);
    final info = await syncClient.fetchInfo(
      peer: DiscoveredPeer(
        deviceId: 'dev-3',
        displayName: '手机',
        address: '127.0.0.1',
        port: 28239,
        accessToken: 'sync-token',
        lastSeenAt: DateTime(2026, 3, 30),
      ),
    );
    expect(info.toJson(), isNot(containsPair('accessToken', anything)));
    expect((await server.readInfo()).accessToken, 'sync-token');

    final snapshot = await syncClient.fetchSnapshot(
      peer: DiscoveredPeer(
        deviceId: 'dev-3',
        displayName: '手机',
        address: '127.0.0.1',
        port: 28239,
        accessToken: 'sync-token',
        lastSeenAt: DateTime(2026, 3, 30),
      ),
    );
    expect(snapshot.tags, ['secure']);
  });

  test('http local sync server rejects replayed signed requests', () async {
    final server = HttpLocalSyncServer(
      host: '127.0.0.1',
      exportSnapshot: () async => const SyncSnapshot(tags: ['secure']),
      importSnapshot: (_) async {},
      exportCategory: (_) async => const SyncSnapshot(),
      importCategory: (_, __) async {},
      accessToken: 'sync-token',
      port: 28242,
    );
    await server.start();
    addTearDown(server.stop);

    final client = HttpClient();
    addTearDown(client.close);
    final headers = _signedLocalSyncHeaders(
      secret: 'sync-token',
      method: 'GET',
      path: '/snapshot',
      nonce: 'fixed-nonce',
      body: '',
    );

    Future<int> getSnapshot() async {
      final request =
          await client.getUrl(Uri.parse('http://127.0.0.1:28242/snapshot'));
      for (final entry in headers.entries) {
        request.headers.set(entry.key, entry.value);
      }
      final response = await request.close();
      await utf8.decoder.bind(response).join();
      return response.statusCode;
    }

    expect(await getSnapshot(), HttpStatus.ok);
    expect(await getSnapshot(), HttpStatus.unauthorized);
  });

  test('http local sync server bounds replay nonce cache', () async {
    final server = HttpLocalSyncServer(
      host: '127.0.0.1',
      exportSnapshot: () async => const SyncSnapshot(tags: ['secure']),
      importSnapshot: (_) async {},
      exportCategory: (_) async => const SyncSnapshot(),
      importCategory: (_, __) async {},
      accessToken: 'sync-token',
      port: 28244,
    );
    await server.start();
    addTearDown(server.stop);

    final client = HttpClient();
    addTearDown(client.close);

    Future<int> getSnapshot(String nonce) async {
      final headers = _signedLocalSyncHeaders(
        secret: 'sync-token',
        method: 'GET',
        path: '/snapshot',
        nonce: nonce,
        body: '',
      );
      final request =
          await client.getUrl(Uri.parse('http://127.0.0.1:28244/snapshot'));
      for (final entry in headers.entries) {
        request.headers.set(entry.key, entry.value);
      }
      final response = await request.close();
      await utf8.decoder.bind(response).join();
      return response.statusCode;
    }

    for (var index = 0; index < 1001; index += 1) {
      expect(await getSnapshot('nonce-$index'), HttpStatus.ok);
    }
    expect(await getSnapshot('nonce-1000'), HttpStatus.unauthorized);
    expect(await getSnapshot('nonce-0'), HttpStatus.ok);
  });

  test('http local sync client and server import category batches atomically',
      () async {
    final current = <SyncDataCategory, SyncSnapshot>{
      SyncDataCategory.settings: const SyncSnapshot(
        settings: {'theme_mode': 'dark'},
      ),
      SyncDataCategory.history: SyncSnapshot(
        history: [
          HistoryRecord(
            providerId: 'bilibili',
            roomId: '1',
            title: 'old',
            streamerName: 'old',
            viewedAt: DateTime(2026, 5, 1),
          ),
        ],
      ),
    };
    var failHistoryImport = false;
    final rolledBackCategories = <SyncDataCategory>[];
    final server = HttpLocalSyncServer(
      host: '127.0.0.1',
      exportSnapshot: () async => const SyncSnapshot(),
      importSnapshot: (_) async {},
      exportCategory: (category) async =>
          current[category] ?? const SyncSnapshot(),
      importCategory: (category, snapshot) async {
        if (category == SyncDataCategory.history && failHistoryImport) {
          throw StateError('history failed');
        }
        current[category] = snapshot;
      },
      rollbackCategory: (category, snapshot) async {
        rolledBackCategories.add(category);
        current[category] = snapshot;
      },
      accessToken: 'sync-token',
      port: 28240,
    );
    await server.start();
    addTearDown(server.stop);

    final client = HttpLocalSyncClient();
    addTearDown(client.close);
    final peer = DiscoveredPeer(
      deviceId: 'dev-4',
      displayName: '手机',
      address: '127.0.0.1',
      port: 28240,
      accessToken: 'sync-token',
      lastSeenAt: DateTime(2026, 5, 2),
    );

    await client.pushCategories(
      peer: peer,
      snapshots: {
        SyncDataCategory.settings: const SyncSnapshot(
          settings: {'theme_mode': 'light'},
        ),
        SyncDataCategory.history: SyncSnapshot(
          history: [
            HistoryRecord(
              providerId: 'douyu',
              roomId: '2',
              title: 'new',
              streamerName: 'new',
              viewedAt: DateTime(2026, 5, 2),
            ),
          ],
        ),
      },
    );

    expect(current[SyncDataCategory.settings]!.settings['theme_mode'], 'light');
    expect(current[SyncDataCategory.history]!.history.single.roomId, '2');

    failHistoryImport = true;
    await expectLater(
      client.pushCategories(
        peer: peer,
        snapshots: {
          SyncDataCategory.settings: const SyncSnapshot(
            settings: {'theme_mode': 'system'},
          ),
          SyncDataCategory.history: SyncSnapshot(
            history: [
              HistoryRecord(
                providerId: 'huya',
                roomId: '3',
                title: 'failed',
                streamerName: 'failed',
                viewedAt: DateTime(2026, 5, 3),
              ),
            ],
          ),
        },
      ),
      throwsA(isA<HttpException>()),
    );

    expect(current[SyncDataCategory.settings]!.settings['theme_mode'], 'light');
    expect(current[SyncDataCategory.history]!.history.single.roomId, '2');
    expect(rolledBackCategories, [
      SyncDataCategory.settings,
      SyncDataCategory.history,
    ]);
  });

  test('http local sync server rolls back full snapshot imports on failure',
      () async {
    var current = const SyncSnapshot(settings: {'theme_mode': 'dark'});
    final server = HttpLocalSyncServer(
      host: '127.0.0.1',
      exportSnapshot: () async => current,
      importSnapshot: (snapshot) async {
        current = snapshot;
        if (snapshot.settings['theme_mode'] == 'fail') {
          throw StateError('snapshot import failed');
        }
      },
      exportCategory: (_) async => current,
      importCategory: (_, snapshot) async {
        current = snapshot;
      },
      accessToken: 'sync-token',
      port: 28243,
    );
    await server.start();
    addTearDown(server.stop);

    final client = HttpLocalSyncClient();
    addTearDown(client.close);
    final peer = DiscoveredPeer(
      deviceId: 'dev-5',
      displayName: '手机',
      address: '127.0.0.1',
      port: 28243,
      accessToken: 'sync-token',
      lastSeenAt: DateTime(2026, 5, 2),
    );

    await expectLater(
      client.pushSnapshot(
        peer: peer,
        snapshot: const SyncSnapshot(settings: {'theme_mode': 'fail'}),
      ),
      throwsA(isA<HttpException>()),
    );

    expect(current.settings['theme_mode'], 'dark');
  });
}

Map<String, String> _signedLocalSyncHeaders({
  required String secret,
  required String method,
  required String path,
  required String nonce,
  required String body,
}) {
  final timestamp =
      (DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000).toString();
  final bodySha256 = sha256.convert(utf8.encode(body)).toString();
  final payload = '${method.toUpperCase()}$path$timestamp$nonce$bodySha256';
  final signature = Hmac(sha256, utf8.encode(secret))
      .convert(utf8.encode(payload))
      .toString();
  return {
    'X-Nolive-Sync-Timestamp': timestamp,
    'X-Nolive-Sync-Nonce': nonce,
    'X-Nolive-Sync-Signature': signature,
  };
}
