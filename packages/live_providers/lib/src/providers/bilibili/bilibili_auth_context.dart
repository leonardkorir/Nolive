class BilibiliAuthContext {
  BilibiliAuthContext({
    String cookie = '',
    this.userId = 0,
    this.suppressAuthCookieForPublicApis = true,
  }) : cookie = normalizeBilibiliCookie(cookie, userId: userId);

  final String cookie;
  final int userId;

  String buvid3 = '';
  String buvid4 = '';
  String imgKey = '';
  String subKey = '';
  String accessId = '';
  bool suppressAuthCookieForPublicApis;
}

String normalizeBilibiliCookie(
  String cookie, {
  required int userId,
}) {
  final parts = cookie
      .split(';')
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList(growable: true);
  if (userId > 0 && !parts.any((part) => part.startsWith('DedeUserID='))) {
    parts.add('DedeUserID=$userId');
  }
  return parts.join('; ');
}
