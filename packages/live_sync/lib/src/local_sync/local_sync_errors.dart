import 'dart:async';
import 'dart:io';

/// Maps low-level LAN sync failures to short user-facing Chinese messages.
String describeLocalSyncError(Object error) {
  if (error is FormatException) {
    final message = error.message.trim();
    if (message.isEmpty) {
      return '局域网同步参数无效，请检查地址与配对码。';
    }
    return message;
  }
  if (error is HttpException) {
    final message = error.message.toLowerCase();
    if (message.contains('status 401') ||
        message.contains('unauthorized') ||
        message.contains('forbidden') ||
        message.contains('status 403')) {
      return '配对码错误或已失效，请重新扫码或向对方确认配对码。';
    }
    if (message.contains('status 413') ||
        message.contains('payload_too_large') ||
        message.contains('request entity too large')) {
      return '同步数据过大：已尝试拆分传输；若仍失败请改用分类同步。';
    }
    if (message.contains('timed out') || message.contains('timeout')) {
      return '同步超时：数据量可能较大或对方处理较慢。可改用分类同步，并确认对方同步服务已启动。';
    }
    if (message.contains('connection failed') ||
        message.contains('connection refused') ||
        message.contains('failed host lookup')) {
      return '无法连接目标设备：请确认对方已启动同步服务，且地址端口正确。';
    }
    if (message.contains('status 400') || message.contains('invalid_snapshot')) {
      return '同步数据格式无效，请升级双方应用后重试。';
    }
    return '局域网同步失败：${error.message}';
  }
  if (error is SocketException) {
    return '无法连接目标设备：请确认对方已启动同步服务，且地址端口正确。';
  }
  if (error is TimeoutException) {
    return '同步超时：数据量可能较大或对方处理较慢。可改用分类同步，并确认对方同步服务已启动。';
  }
  final text = error.toString();
  if (text.contains('Access token') || text.contains('配对码')) {
    return '请先填写或扫描局域网同步配对码。';
  }
  return '局域网同步失败：$error';
}
