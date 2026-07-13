import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../provider_json.dart';
import '../provider_runtime_support.dart';

abstract class HuyaSignService {
  String get playerUserAgent;

  String buildUrl({required Map<String, Object?> line, required int bitRate});
}

class HttpHuyaSignService implements HuyaSignService {
  static const String defaultPlayerUserAgent = kChromiumDesktopUserAgent;

  final Random _random;
  final ProviderBrowserProfile _browserProfile;

  HttpHuyaSignService({
    Random? random,
    ProviderBrowserProfile browserProfile =
        ProviderBrowserProfile.chromiumDesktop,
  }) : _random = random ?? Random(),
       _browserProfile = browserProfile;

  @override
  String get playerUserAgent => _browserProfile.userAgent;

  @override
  String buildUrl({required Map<String, Object?> line, required int bitRate}) {
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
    final secretHash = md5
        .convert(utf8.encode('$seqId|$ctype|$platformId'))
        .toString();

    final convertedUid = _rotl64(presenterUid);
    final calcUid = isWap ? presenterUid.toString() : convertedUid;
    final fmValue = mapAnti['fm']?.first;
    final wsTime = mapAnti['wsTime']?.first;
    final fs = mapAnti['fs']?.first;
    if (fmValue == null || wsTime == null || fs == null) {
      return antiCode;
    }
    final fm = Uri.decodeComponent(fmValue);
    final secretPrefix = utf8.decode(base64.decode(fm)).split('_').first;
    final secret = '${secretPrefix}_${calcUid}_${stream}_${secretHash}_$wsTime';
    final wsSecret = md5.convert(utf8.encode(secret)).toString();

    final wsTimeValue = int.tryParse(wsTime, radix: 16);
    if (wsTimeValue == null) {
      return antiCode;
    }
    final ct = ((wsTimeValue + _random.nextDouble()) * 1000).toInt();
    final uuid = (((ct % 1e10) + _random.nextDouble()) * 1e3 % 0xffffffff)
        .toInt()
        .toString();
    final antiCodeResult = <String, Object?>{
      'wsSecret': wsSecret,
      'wsTime': wsTime,
      'seqid': seqId,
      'ctype': ctype,
      'ver': '1',
      'fs': fs,
      'fm': fm,
      't': platformId,
    };
    if (isWap) {
      antiCodeResult.addAll({'uid': presenterUid, 'uuid': uuid});
    } else {
      antiCodeResult['u'] = convertedUid;
    }

    return antiCodeResult.entries.map((e) => '${e.key}=${e.value}').join('&');
  }

  String _rotl64(int value) {
    const mask32 = 0xFFFFFFFF;
    final unsigned = BigInt.from(value);
    final low = unsigned & BigInt.from(mask32);
    final rotatedLow = ((low << 8) | (low >> 24)) & BigInt.from(mask32);
    final high = unsigned & ~BigInt.from(mask32);
    return (high | rotatedLow).toString();
  }

  int? _asInt(Object? value) {
    return ProviderJson.asInt(value);
  }
}
