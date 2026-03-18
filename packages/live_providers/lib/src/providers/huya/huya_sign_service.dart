import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

abstract class HuyaSignService {
  String buildUrl({
    required Map<String, Object?> line,
    required int bitRate,
  });
}

class HttpHuyaSignService implements HuyaSignService {
  static const String playerUserAgent =
      'HYSDK(Windows,30000002)_APP(pc_exe&7070000&official)_SDK(trans&2.33.0.5678)';

  final Random _random;

  HttpHuyaSignService({Random? random}) : _random = random ?? Random();

  @override
  String buildUrl({
    required Map<String, Object?> line,
    required int bitRate,
  }) {
    final lineUrl = line['line']?.toString() ?? '';
    final streamName = line['streamName']?.toString() ?? '';
    final presenterUid = _asInt(line['presenterUid']) ?? 0;
    final lineType = line['lineType']?.toString() ?? 'flv';
    final antiCode = line['antiCode']?.toString() ?? '';
    final suffix = lineType == 'hls' ? 'm3u8' : 'flv';
    final signedAntiCode = _buildAntiCode(
      stream: streamName,
      presenterUid: presenterUid,
      antiCode: antiCode,
    );
    var url = '$lineUrl/$streamName.$suffix';
    if (signedAntiCode.isNotEmpty) {
      url += '?$signedAntiCode&codec=264';
    }
    if (bitRate > 0) {
      url += signedAntiCode.isEmpty ? '?ratio=$bitRate' : '&ratio=$bitRate';
    }
    return url;
  }

  String _buildAntiCode({
    required String stream,
    required int presenterUid,
    required String antiCode,
  }) {
    final mapAnti = Uri(query: antiCode).queryParametersAll;
    if (!mapAnti.containsKey('fm')) {
      return antiCode;
    }

    final ctype = mapAnti['ctype']?.first ?? 'huya_pc_exe';
    final platformId = int.tryParse(mapAnti['t']?.first ?? '0') ?? 0;
    final isWap = platformId == 103;
    final currentTime = DateTime.now().millisecondsSinceEpoch;
    final seqId = presenterUid + currentTime;
    final secretHash =
        md5.convert(utf8.encode('$seqId|$ctype|$platformId')).toString();

    final convertedUid = _rotl64(presenterUid);
    final calcUid = isWap ? presenterUid : convertedUid;
    final fm = Uri.decodeComponent(mapAnti['fm']!.first);
    final secretPrefix = utf8.decode(base64.decode(fm)).split('_').first;
    final wsTime = mapAnti['wsTime']!.first;
    final secret = '${secretPrefix}_${calcUid}_${stream}_${secretHash}_$wsTime';
    final wsSecret = md5.convert(utf8.encode(secret)).toString();

    final ct =
        ((int.parse(wsTime, radix: 16) + _random.nextDouble()) * 1000).toInt();
    final uuid = (((ct % 1e10) + _random.nextDouble()) * 1e3 % 0xffffffff)
        .toInt()
        .toString();
    final antiCodeResult = <String, Object?>{
      'wsSecret': wsSecret,
      'wsTime': wsTime,
      'seqid': seqId,
      'ctype': ctype,
      'ver': '1',
      'fs': mapAnti['fs']!.first,
      'fm': fm,
      't': platformId,
    };
    if (isWap) {
      antiCodeResult.addAll({
        'uid': presenterUid,
        'uuid': uuid,
      });
    } else {
      antiCodeResult['u'] = convertedUid;
    }

    return antiCodeResult.entries.map((e) => '${e.key}=${e.value}').join('&');
  }

  int _rotl64(int value) {
    final low = value & 0xFFFFFFFF;
    final rotatedLow = ((low << 8) | (low >> 24)) & 0xFFFFFFFF;
    final high = value & ~0xFFFFFFFF;
    return high | rotatedLow;
  }

  int? _asInt(Object? value) {
    if (value is int) {
      return value;
    }
    return int.tryParse(value?.toString() ?? '');
  }
}
