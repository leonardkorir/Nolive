import 'package:live_core/live_core.dart';

/// Builds a paste-friendly room failure report for support / self-debug.
String buildRoomErrorDiagnostic({
  required ProviderId providerId,
  required String roomId,
  Object? error,
  StackTrace? stackTrace,
  String? extra,
}) {
  final buffer = StringBuffer()
    ..writeln('直播平台：${providerId.value}')
    ..writeln('房间号：$roomId')
    ..writeln('错误信息：')
    ..writeln(error?.toString() ?? '(无)');
  if (stackTrace != null) {
    buffer
      ..writeln('----------------')
      ..writeln(stackTrace);
  }
  if (extra != null && extra.trim().isNotEmpty) {
    buffer
      ..writeln('----------------')
      ..writeln(extra.trim());
  }
  return buffer.toString();
}
