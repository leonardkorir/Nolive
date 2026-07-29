import 'dart:convert';
import 'dart:typed_data';

class StripchatMouflonSegmentInfo {
  const StripchatMouflonSegmentInfo({
    required this.key,
    required this.segmentId,
  });

  final String key;
  final String segmentId;
}

class StripchatMatchedMouflonUri {
  const StripchatMatchedMouflonUri({
    required this.prefix,
    required this.encryptedSegment,
    required this.suffix,
  });

  final String prefix;
  final String encryptedSegment;
  final String suffix;

  String rebuild(String decryptedSegment) {
    return '$prefix$decryptedSegment$suffix';
  }
}

String stripchatPadBase64(String value) {
  final remainder = value.length % 4;
  if (remainder == 0) {
    return value;
  }
  return '$value${'=' * (4 - remainder)}';
}

bool stripchatBytesEqual(List<int> a, List<int> b) {
  if (a.length != b.length) {
    return false;
  }
  for (var index = 0; index < a.length; index += 1) {
    if (a[index] != b[index]) {
      return false;
    }
  }
  return true;
}

bool stripchatMp4BytesContainInitialization(Uint8List bytes) {
  // ftyp box at bytes[4..7]: standard MP4 init segment indicator.
  if (bytes.lengthInBytes >= 8) {
    final ftyp = ascii.encode('ftyp');
    if (bytes[4] == ftyp[0] &&
        bytes[5] == ftyp[1] &&
        bytes[6] == ftyp[2] &&
        bytes[7] == ftyp[3]) {
      return true;
    }
  }
  // moov box anywhere: initialization data present.
  return _containsFourByteToken(bytes, ascii.encode('moov'));
}

bool stripchatMp4BytesContainBox(Uint8List bytes, String boxType) {
  if (boxType.length != 4 || bytes.lengthInBytes < 8) {
    return false;
  }
  final expected = ascii.encode(boxType);
  var offset = 0;
  while (offset + 8 <= bytes.lengthInBytes) {
    final size = _readMp4BoxSize(bytes, offset);
    if (size == null || size < 8 || offset + size > bytes.lengthInBytes) {
      return _containsFourByteToken(bytes, expected);
    }
    if (bytes[offset + 4] == expected[0] &&
        bytes[offset + 5] == expected[1] &&
        bytes[offset + 6] == expected[2] &&
        bytes[offset + 7] == expected[3]) {
      return true;
    }
    offset += size;
  }
  return false;
}

bool _containsFourByteToken(Uint8List bytes, List<int> expected) {
  for (var index = 4; index <= bytes.lengthInBytes - 4; index += 1) {
    if (bytes[index] == expected[0] &&
        bytes[index + 1] == expected[1] &&
        bytes[index + 2] == expected[2] &&
        bytes[index + 3] == expected[3]) {
      return true;
    }
  }
  return false;
}

int? _readMp4BoxSize(Uint8List bytes, int offset) {
  if (offset + 4 > bytes.lengthInBytes) {
    return null;
  }
  final size =
      (bytes[offset] << 24) |
      (bytes[offset + 1] << 16) |
      (bytes[offset + 2] << 8) |
      bytes[offset + 3];
  if (size == 1 || size == 0) {
    return null;
  }
  return size;
}

String stripchatReverseString(String value) {
  return value.split('').reversed.join();
}

StripchatMatchedMouflonUri? stripchatMatchMouflonUri(String value) {
  final match = RegExp(
    r'^(.*?_\d+_)(.+?)(_\d+(?:_part\d+)?\.mp4(?:\?.*)?)$',
  ).firstMatch(value);
  if (match == null) {
    return null;
  }
  final prefix = match.group(1) ?? '';
  final encryptedSegment = match.group(2) ?? '';
  final suffix = match.group(3) ?? '';
  if (prefix.isEmpty || encryptedSegment.isEmpty || suffix.isEmpty) {
    return null;
  }
  return StripchatMatchedMouflonUri(
    prefix: prefix,
    encryptedSegment: encryptedSegment,
    suffix: suffix,
  );
}

StripchatMouflonSegmentInfo? stripchatParseMouflonSegmentInfo(String path) {
  final tsMatch = RegExp(r'_(\d{10})(_part\d+)?\.mp4$').firstMatch(path);
  if (tsMatch == null) {
    return null;
  }
  final timestamp = tsMatch.group(1)!;
  final partSuffix = tsMatch.group(2) ?? '';
  final prefix = path.substring(0, tsMatch.start);
  final segMatch = RegExp(r'_(\d+)_([A-Za-z0-9+/=]+)$').firstMatch(prefix);
  if (segMatch == null) {
    return null;
  }
  return StripchatMouflonSegmentInfo(
    key: '${segMatch.group(1)}_${timestamp}_$partSuffix',
    segmentId: segMatch.group(2)!,
  );
}

String? stripchatExtractEncryptedSegmentId(String path) {
  final match = RegExp(r'_(\d{10})(_part\d+)?\.mp4$').firstMatch(path);
  if (match == null) {
    return null;
  }
  final before = path.substring(0, match.start);
  final seg = RegExp(r'_([A-Za-z0-9+/=]+)$').firstMatch(before);
  return seg?.group(1);
}
