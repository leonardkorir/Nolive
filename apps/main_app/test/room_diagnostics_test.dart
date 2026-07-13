import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:nolive_app/src/shared/application/room_diagnostics.dart';

void main() {
  test('buildRoomErrorDiagnostic includes platform room and error', () {
    final report = buildRoomErrorDiagnostic(
      providerId: ProviderId.bilibili,
      roomId: '123',
      error: StateError('boom'),
      stackTrace: StackTrace.current,
      extra: 'line=2',
    );
    expect(report, contains('直播平台：bilibili'));
    expect(report, contains('房间号：123'));
    expect(report, contains('boom'));
    expect(report, contains('line=2'));
  });
}
