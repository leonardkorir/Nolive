import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:live_core/live_core.dart';

/// Stable marker in [ProviderParseException.message] for password-gated rooms.
const String kChaturbatePasswordRequiredMarker = 'room requires a password';

/// User-facing copy when Chaturbate refuses open access because of a room lock.
const String kChaturbatePasswordProtectedUserMessage =
    '该房间已加锁，需要密码才能观看；当前版本暂不支持输入密码。';

/// Whether [error] is Chaturbate's password-protected room rejection.
bool isChaturbatePasswordProtectedError(Object? error) {
  if (error == null) {
    return false;
  }
  final text = error.toString().toLowerCase();
  return text.contains(kChaturbatePasswordRequiredMarker) ||
      text.contains('requires a password') ||
      text.contains('password-protected') ||
      text.contains('password protected');
}

/// Whether an HTTP response is CB's password-gated 401/403 JSON (not CF).
bool looksLikeChaturbatePasswordProtectedResponse(http.Response response) {
  final status = response.statusCode;
  if (status != 401 && status != 403) {
    return false;
  }
  final body = response.body.trim();
  if (body.isEmpty) {
    return false;
  }
  final lower = body.toLowerCase();
  if (lower.contains('requires a password') ||
      lower.contains('password required') ||
      lower.contains('password-protected')) {
    return true;
  }
  // {"status":401,"detail":"This room requires a password.","code":"unauthorized"}
  try {
    final decoded = jsonDecode(body);
    if (decoded is! Map) {
      return false;
    }
    final detail = decoded['detail']?.toString().toLowerCase() ?? '';
    return detail.contains('password');
  } catch (_) {
    // Not JSON — not the password API shape.
  }
  return false;
}

/// True when [detail] was synthesized (or annotated) as password-locked.
bool isChaturbatePasswordProtectedDetail(LiveRoomDetail detail) {
  final metadata = detail.metadata;
  if (metadata == null) {
    return false;
  }
  for (final key in const ['passwordProtected', 'hasPassword', 'locked']) {
    final value = metadata[key];
    if (value == true) {
      return true;
    }
    final normalized = value?.toString().trim().toLowerCase() ?? '';
    if (normalized == 'true' || normalized == '1' || normalized == 'yes') {
      return true;
    }
  }
  final status = metadata['roomStatus']?.toString().trim().toLowerCase() ?? '';
  return status == 'password' || status == 'password_protected';
}

/// Minimal [LiveRoomDetail] for a password-gated room (online, no public HLS).
LiveRoomDetail chaturbatePasswordProtectedDetail(String roomId) {
  final normalized = roomId.trim();
  final safeId = normalized.isEmpty ? roomId : normalized;
  return LiveRoomDetail(
    providerId: ProviderId.chaturbate,
    roomId: safeId,
    title: safeId,
    streamerName: normalizeDisplayText(safeId),
    sourceUrl: safeId.isEmpty ? null : 'https://chaturbate.com/$safeId/',
    // Product: password rooms count as offline (未开播), not publicly live.
    // Chip still shows 加锁 via passwordProtected metadata.
    isLive: false,
    metadata: const <String, Object?>{
      'roomStatus': 'password',
      'passwordProtected': true,
      'hasPassword': true,
      'locked': true,
      'playbackUnavailableReason': kChaturbatePasswordProtectedUserMessage,
    },
  );
}
