class HuyaRoomMediaData {
  const HuyaRoomMediaData({
    required this.lines,
    required this.bitRates,
  });

  final List<HuyaStreamLine> lines;
  final List<HuyaBitRate> bitRates;
}

enum HuyaLineType {
  flv,
  hls,
}

class HuyaStreamLine {
  const HuyaStreamLine({
    required this.baseUrl,
    required this.cdnType,
    required this.flvAntiCode,
    required this.hlsAntiCode,
    required this.streamName,
    required this.lineType,
    required this.presenterUid,
  });

  final String baseUrl;
  final String cdnType;
  final String flvAntiCode;
  final String hlsAntiCode;
  final String streamName;
  final HuyaLineType lineType;
  final int presenterUid;

  String get antiCode {
    return lineType == HuyaLineType.hls ? hlsAntiCode : flvAntiCode;
  }

  String get fileExtension {
    return lineType == HuyaLineType.hls ? 'm3u8' : 'flv';
  }
}

class HuyaBitRate {
  const HuyaBitRate({
    required this.name,
    required this.bitRate,
  });

  final String name;
  final int bitRate;
}
