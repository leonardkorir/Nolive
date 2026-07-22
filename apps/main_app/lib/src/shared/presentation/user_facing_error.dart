/// Maps raw exceptions to short Chinese copy for empty/error cards and snacks.
///
/// Primary UI messages must never be a raw stack or `Exception: ...` dump.
String formatUserFacingError(
  Object? error, {
  String fallback = '加载失败，请稍后重试',
}) {
  if (error == null) {
    return fallback;
  }
  final raw = error.toString().trim();
  if (raw.isEmpty) {
    return fallback;
  }
  final lower = raw.toLowerCase();
  // Chaturbate password rooms return JSON 401 — not a generic auth failure.
  if (lower.contains('requires a password') ||
      lower.contains('room requires a password') ||
      lower.contains('password-protected') ||
      (lower.contains('已加锁') && lower.contains('密码'))) {
    return '该房间已加锁，需要密码才能观看；当前版本暂不支持输入密码。';
  }
  if (_looksLikeNetwork(lower)) {
    return '网络连接失败，请检查网络后重试';
  }
  if (lower.contains('timeout') || lower.contains('timed out')) {
    return '请求超时，请稍后重试';
  }
  if (lower.contains('403') ||
      lower.contains('forbidden') ||
      lower.contains('unauthorized') ||
      lower.contains('401')) {
    return '访问被拒绝，请稍后重试或检查登录状态';
  }
  if (lower.contains('404') || lower.contains('not found')) {
    return '未找到相关内容，请稍后重试';
  }
  if (lower.contains('parse') || lower.contains('format')) {
    return '内容解析失败，请稍后重试';
  }
  // Already short, user-authored Chinese (or simple) messages.
  if (!_looksLikeTechnicalDump(raw) && raw.length <= 80) {
    return raw;
  }
  return fallback;
}

bool _looksLikeNetwork(String lower) {
  return lower.contains('socket') ||
      lower.contains('network') ||
      lower.contains('connection') ||
      lower.contains('failed host') ||
      lower.contains('handshake') ||
      lower.contains('clientexception') ||
      lower.contains('http exception') ||
      lower.contains('connection refused') ||
      lower.contains('connection reset');
}

bool _looksLikeTechnicalDump(String raw) {
  if (raw.contains('\n') || raw.contains('\t')) {
    return true;
  }
  if (raw.length > 120) {
    return true;
  }
  final lower = raw.toLowerCase();
  return lower.contains('exception') ||
      lower.contains('error:') ||
      lower.contains('stack') ||
      lower.startsWith('#0 ') ||
      (raw.contains(' at ') && raw.contains('.dart'));
}
