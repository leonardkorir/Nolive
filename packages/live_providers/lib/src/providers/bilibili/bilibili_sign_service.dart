import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'bilibili_auth_context.dart';
import 'bilibili_transport.dart';

class BilibiliSignService {
  BilibiliSignService({
    required BilibiliTransport transport,
    required BilibiliAuthContext authContext,
  })  : _transport = transport,
        _authContext = authContext;

  static const String defaultUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36 Edg/126.0.0.0';
  static const String defaultReferer = 'https://live.bilibili.com/';

  static const List<int> _mixinKeyEncTable = [
    46,
    47,
    18,
    2,
    53,
    8,
    23,
    32,
    15,
    50,
    10,
    31,
    58,
    3,
    45,
    35,
    27,
    43,
    5,
    49,
    33,
    9,
    42,
    19,
    29,
    28,
    14,
    39,
    12,
    38,
    41,
    13,
    37,
    48,
    7,
    16,
    24,
    55,
    40,
    61,
    26,
    17,
    0,
    1,
    60,
    51,
    30,
    4,
    22,
    25,
    54,
    21,
    56,
    59,
    6,
    63,
    57,
    62,
    11,
    36,
    20,
    34,
    44,
    52,
  ];

  final BilibiliTransport _transport;
  final BilibiliAuthContext _authContext;

  String get cookie => _authContext.cookie;
  int get userId => _authContext.userId;
  String get buvid3 => _authContext.buvid3;

  Future<Map<String, String>> buildHeaders() async {
    if (_authContext.buvid3.isEmpty) {
      await _loadBuvid();
    }

    final cookie = _authContext.cookie.isEmpty
        ? 'buvid3=${_authContext.buvid3};buvid4=${_authContext.buvid4};'
        : _authContext.cookie.contains('buvid3')
            ? _authContext.cookie
            : '${_authContext.cookie};buvid3=${_authContext.buvid3};buvid4=${_authContext.buvid4};';

    return {
      'user-agent': defaultUserAgent,
      'referer': defaultReferer,
      'cookie': cookie,
    };
  }

  Future<Map<String, String>> signUrl(String url) async {
    final (imgKey, subKey) = await _getWbiKeys();
    final mixinKey = _getMixinKey(imgKey + subKey);
    final currentTime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final queryParameters =
        Map<String, String>.from(Uri.parse(url).queryParameters)
          ..['wts'] = currentTime.toString();

    final filtered = <String, String>{};
    final sortedKeys = queryParameters.keys.toList()..sort();
    for (final key in sortedKeys) {
      final value = queryParameters[key] ?? '';
      filtered[key] = value
          .split('')
          .where((character) => !"!'()*".contains(character))
          .join('');
    }

    final query = filtered.keys
        .map((key) => '$key=${Uri.encodeQueryComponent(filtered[key]!)}')
        .join('&');
    final signature = md5.convert(utf8.encode('$query$mixinKey')).toString();

    return {...queryParameters, 'w_rid': signature};
  }

  Future<void> _loadBuvid() async {
    final response = await _transport.getJson(
      'https://api.bilibili.com/x/frontend/finger/spi',
      headers: {
        'user-agent': defaultUserAgent,
        'referer': defaultReferer,
        'cookie': _authContext.cookie,
      },
    );
    final data =
        (response['data'] as Map?)?.cast<String, dynamic>() ?? const {};
    _authContext.buvid3 = data['b_3']?.toString() ?? '';
    _authContext.buvid4 = data['b_4']?.toString() ?? '';
  }

  Future<String> getAccessId() async {
    if (_authContext.accessId.isNotEmpty) {
      return _authContext.accessId;
    }

    try {
      final response = await _transport.getText(
        'https://live.bilibili.com/lol',
        headers: await buildHeaders(),
      );
      final id = RegExp(r'\"access_id\":\"(.*?)\"')
          .firstMatch(response)
          ?.group(1)
          ?.replaceAll('\\', '');
      _authContext.accessId = id ?? '';
    } catch (_) {
      _authContext.accessId = '';
    }

    return _authContext.accessId;
  }

  Future<(String, String)> _getWbiKeys() async {
    if (_authContext.imgKey.isNotEmpty && _authContext.subKey.isNotEmpty) {
      return (_authContext.imgKey, _authContext.subKey);
    }

    final response = await _transport.getJson(
      'https://api.bilibili.com/x/web-interface/nav',
      headers: await buildHeaders(),
    );
    final data =
        (response['data'] as Map?)?.cast<String, dynamic>() ?? const {};
    final wbiImg =
        (data['wbi_img'] as Map?)?.cast<String, dynamic>() ?? const {};
    final imgUrl = wbiImg['img_url']?.toString() ?? '';
    final subUrl = wbiImg['sub_url']?.toString() ?? '';

    _authContext.imgKey =
        imgUrl.substring(imgUrl.lastIndexOf('/') + 1).split('.').first;
    _authContext.subKey =
        subUrl.substring(subUrl.lastIndexOf('/') + 1).split('.').first;
    return (_authContext.imgKey, _authContext.subKey);
  }

  String _getMixinKey(String origin) {
    return _mixinKeyEncTable
        .fold<String>(
          '',
          (buffer, index) => buffer + origin[index],
        )
        .substring(0, 32);
  }
}
