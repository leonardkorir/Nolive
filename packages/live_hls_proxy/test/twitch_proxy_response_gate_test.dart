import 'dart:async';
import 'dart:io';

import 'package:live_hls_proxy/live_hls_proxy.dart';
import 'package:test/test.dart';

// unawaited is from dart:async (2.14+)

void main() {
  test(
    'TwitchProxyResponseGate rejects second status write after body started',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        await server.close(force: true);
      });

      final errors = <Object>[];
      server.listen((request) async {
        final gate = TwitchProxyResponseGate(request.response);
        await gate.writePlaylistBody('#EXTM3U\n');
        // Simulated cancel/error path after headers+body already committed.
        try {
          await gate.commitStatusAndClose(HttpStatus.internalServerError);
        } catch (error) {
          errors.add(error);
        }
      });

      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final request = await client.getUrl(
        Uri.parse('http://${server.address.address}:${server.port}/'),
      );
      final response = await request.close();
      expect(response.statusCode, HttpStatus.ok);
      await response.drain<void>();
      expect(errors, isEmpty);
    },
  );

  test(
    'TwitchProxyResponseGate commitStatusAndClose is idempotent after error',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        await server.close(force: true);
      });

      server.listen((request) async {
        final gate = TwitchProxyResponseGate(request.response);
        await gate.commitStatusAndClose(HttpStatus.badGateway);
        await gate.commitStatusAndClose(HttpStatus.internalServerError);
        await gate.commitStatusAndClose(HttpStatus.notFound);
      });

      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final request = await client.getUrl(
        Uri.parse('http://${server.address.address}:${server.port}/'),
      );
      final response = await request.close();
      expect(response.statusCode, HttpStatus.badGateway);
      await response.drain<void>();
    },
  );

  test(
    'TwitchProxyResponseGate canSetStatus flips after first commit',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        await server.close(force: true);
      });
      final completer = Completer<void>();

      server.listen((request) async {
        final gate = TwitchProxyResponseGate(request.response);
        expect(gate.canSetStatus, isTrue);
        await gate.commitStatusAndClose(HttpStatus.gone);
        expect(gate.canSetStatus, isFalse);
        expect(gate.isClosed, isTrue);
        completer.complete();
      });

      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final request = await client.getUrl(
        Uri.parse('http://${server.address.address}:${server.port}/'),
      );
      final response = await request.close();
      expect(response.statusCode, HttpStatus.gone);
      await response.drain<void>();
      await completer.future;
    },
  );

  test(
    'TwitchProxyResponseGate streamChunks drains when already closed',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        await server.close(force: true);
      });
      final drained = Completer<void>();

      server.listen((request) async {
        final gate = TwitchProxyResponseGate(request.response);
        await gate.commitStatusAndClose(HttpStatus.ok);
        expect(gate.isClosed, isTrue);

        final controller = StreamController<List<int>>();
        // streamChunks must drain even when the client response is already closed.
        unawaited(
          gate
              .streamChunks(
                statusCode: HttpStatus.ok,
                chunks: controller.stream,
              )
              .whenComplete(() {
                if (!drained.isCompleted) {
                  drained.complete();
                }
              }),
        );
        controller.add([1, 2, 3]);
        await controller.close();
        await drained.future.timeout(const Duration(seconds: 2));
      });

      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final request = await client.getUrl(
        Uri.parse('http://${server.address.address}:${server.port}/'),
      );
      final response = await request.close();
      await response.drain<void>();
      await drained.future.timeout(const Duration(seconds: 2));
    },
  );
}
