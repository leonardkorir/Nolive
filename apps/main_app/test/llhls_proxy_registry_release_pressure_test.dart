import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nolive_app/src/app/bootstrap/llhls_proxy_lifecycle.dart';

void main() {
  test(
    'unregisterSession invokes releaseRuntimeWebPressure for leave-room cleanup',
    () async {
      var released = 0;
      final completer = Completer<void>();
      final registry = LlhlsProxyRegistry(
        chaturbateProxy: null,
        stripchatProxy: null,
        twitchProxy: null,
        releaseRuntimeWebPressure: () async {
          released += 1;
          completer.complete();
        },
      );

      registry.unregisterSession(roomId: 'any-room');
      await completer.future.timeout(const Duration(seconds: 1));
      expect(released, 1);
    },
  );
}
