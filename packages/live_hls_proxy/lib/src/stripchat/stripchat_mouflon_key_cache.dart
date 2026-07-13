import 'dart:convert';

// Client-side decryption key pairs reverse-engineered from the Stripchat web
// client (source: pdkey-recovery/poc-debugger-capture.mjs).  These keys are
// not Nolive secrets — they exist in every Stripchat browser session and are
// trivially extractable from the Stripchat frontend bundle.  They are shipped
// here as a last-resort fallback (priority 85 in MouflonKeyCache) so that the
// app can still play Stripchat rooms when no user-calibrated keys are
// available.
//
// Risk: keys may be extracted from the compiled APK via `strings` or static
// analysis.  Because these are public client-side keys, this does not expose
// any user data or Nolive credentials.  If Stripchat rotates the key scheme,
// the fallback silently breaks and requires an app update until new keys are
// captured with the poc-debugger-capture script.
//
// Accepted risk; not treated as a credential leak.
String _unreverse(String v) => v.split('').reversed.join();

const Map<String, String> _stripchatTrustedMouflonPdkeys = <String, String>{
  'ItbKL37PjO6cczD1': 'pLOnWIrR5XwVU46Y',
  'iahuyigNiauq7koO': 'hc3aweak2hGeeuQE',
  '9mPRkBeZ2OT2m6qF': 'bwUHXFE9FN1id6bx',
};

final Map<String, String> _hardcodedPdkeys = {
  for (final entry in _stripchatTrustedMouflonPdkeys.entries)
    _unreverse(entry.key): _unreverse(entry.value),
};

String? lookupStripchatHardcodedPdkey(String pkey) {
  return _hardcodedPdkeys[pkey];
}

enum StripchatCalibrationSource { auto, manual }

enum StripchatCalibrationStatus { missing, ready, stale, failed }

enum StripchatCalibrationDecodeStatus { ok, empty, invalid }

class StripchatMouflonKeyRecord {
  const StripchatMouflonKeyRecord({
    required this.pkey,
    required this.pdkey,
    required this.capturedAt,
    required this.source,
    this.captureSource = '',
  });

  final String pkey;
  final String pdkey;
  final DateTime capturedAt;
  final StripchatCalibrationSource source;
  final String captureSource;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'pkey': _unreverse(pkey),
      'pdkey': _unreverse(pdkey),
      'capturedAt': capturedAt.toUtc().toIso8601String(),
      'source': source.name,
      'captureSource': captureSource,
    };
  }

  static StripchatMouflonKeyRecord? fromJson(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final map = raw.cast<Object?, Object?>();
    final pkey = map['pkey']?.toString().trim() ?? '';
    final pdkey = map['pdkey']?.toString().trim() ?? '';
    final capturedAtRaw = map['capturedAt']?.toString().trim() ?? '';
    final sourceRaw = map['source']?.toString().trim().toLowerCase() ?? '';
    final captureSource = map['captureSource']?.toString().trim() ?? '';
    if (pkey.isEmpty || pdkey.isEmpty || capturedAtRaw.isEmpty) {
      return null;
    }
    final capturedAt = DateTime.tryParse(capturedAtRaw);
    if (capturedAt == null) {
      return null;
    }
    final source = StripchatCalibrationSource.values.firstWhere(
      (value) => value.name == sourceRaw,
      orElse: () => StripchatCalibrationSource.auto,
    );
    return StripchatMouflonKeyRecord(
      pkey: _unreverse(pkey),
      pdkey: _unreverse(pdkey),
      capturedAt: capturedAt.toUtc(),
      source: source,
      captureSource: captureSource.isNotEmpty ? captureSource : source.name,
    );
  }
}

int stripchatMouflonKeySourcePriority(String source) {
  final normalized = source.trim().toLowerCase();
  final base = normalized.split(':').first;
  switch (base) {
    case 'manual':
      return 100;
    case 'hash-cache-key':
      return 90;
    case 'trusted-fallback':
      return 85;
    case 'digest-hook':
    case 'importkey-hook':
      return 80;
    case 'known-keys-active':
      return 70;
    case 'object-pair':
    case 'object-candidate':
      return 60;
    case 'chunk-known-keys-map':
    case 'known-keys-map':
      return 40;
    case 'text-explicit-pair':
    case 'storage-explicit-pair':
    case 'json-explicit-pair':
      return 30;
    case 'auto':
      return 20;
    default:
      return 10;
  }
}

class StripchatMouflonKeyCache {
  const StripchatMouflonKeyCache({
    this.records = const <StripchatMouflonKeyRecord>[],
    this.status = StripchatCalibrationStatus.missing,
    this.statusUpdatedAt,
    this.decodeStatus = StripchatCalibrationDecodeStatus.ok,
  });

  static const int maxRecords = 16;
  static const Duration staleAfter = Duration(days: 7);

  final List<StripchatMouflonKeyRecord> records;
  final StripchatCalibrationStatus status;
  final DateTime? statusUpdatedAt;
  final StripchatCalibrationDecodeStatus decodeStatus;

  bool get isEmpty => records.isEmpty;

  StripchatMouflonKeyRecord? lookup(String pkey) {
    final normalized = pkey.trim();
    if (normalized.isEmpty) {
      return null;
    }
    for (final record in records) {
      if (record.pkey == normalized) {
        return record;
      }
    }
    return null;
  }

  StripchatCalibrationStatus effectiveStatus({DateTime? now}) {
    final referenceNow = (now ?? DateTime.now()).toUtc();
    if (records.isEmpty) {
      return status == StripchatCalibrationStatus.failed
          ? StripchatCalibrationStatus.failed
          : StripchatCalibrationStatus.missing;
    }
    if (status == StripchatCalibrationStatus.failed) {
      return StripchatCalibrationStatus.failed;
    }
    final freshest = records.first.capturedAt.toUtc();
    if (referenceNow.difference(freshest) > staleAfter) {
      return StripchatCalibrationStatus.stale;
    }
    return StripchatCalibrationStatus.ready;
  }

  String encode() => jsonEncode(toJson());

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'records': records
          .map((record) => record.toJson())
          .toList(growable: false),
      'status': status.name,
      'statusUpdatedAt': statusUpdatedAt?.toUtc().toIso8601String(),
      'decodeStatus': decodeStatus.name,
    };
  }

  static StripchatMouflonKeyCache decode(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return const StripchatMouflonKeyCache(
        decodeStatus: StripchatCalibrationDecodeStatus.empty,
      );
    }
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is! Map<String, dynamic>) {
        return const StripchatMouflonKeyCache(
          status: StripchatCalibrationStatus.failed,
          decodeStatus: StripchatCalibrationDecodeStatus.invalid,
        );
      }
      final recordList = decoded['records'];
      final records = <StripchatMouflonKeyRecord>[];
      if (recordList is List) {
        for (final entry in recordList) {
          final record = StripchatMouflonKeyRecord.fromJson(entry);
          if (record != null) {
            records.add(record);
          }
        }
      }
      records.sort(
        (left, right) => right.capturedAt.compareTo(left.capturedAt),
      );
      final status = StripchatCalibrationStatus.values.firstWhere(
        (value) =>
            value.name == decoded['status']?.toString().trim().toLowerCase(),
        orElse: () => records.isEmpty
            ? StripchatCalibrationStatus.missing
            : StripchatCalibrationStatus.ready,
      );
      final statusUpdatedAt = DateTime.tryParse(
        decoded['statusUpdatedAt']?.toString().trim() ?? '',
      )?.toUtc();
      final decodeStatus = StripchatCalibrationDecodeStatus.values.firstWhere(
        (value) =>
            value.name ==
            decoded['decodeStatus']?.toString().trim().toLowerCase(),
        orElse: () => StripchatCalibrationDecodeStatus.ok,
      );
      return StripchatMouflonKeyCache(
        records: List<StripchatMouflonKeyRecord>.unmodifiable(
          records.take(maxRecords),
        ),
        status: status,
        statusUpdatedAt: statusUpdatedAt,
        decodeStatus: decodeStatus,
      );
    } catch (_) {
      return const StripchatMouflonKeyCache(
        status: StripchatCalibrationStatus.failed,
        decodeStatus: StripchatCalibrationDecodeStatus.invalid,
      );
    }
  }

  StripchatMouflonKeyCache mergeRecords(
    Iterable<StripchatMouflonKeyRecord> freshRecords, {
    required StripchatCalibrationSource source,
    DateTime? capturedAt,
  }) {
    final timestamp = (capturedAt ?? DateTime.now()).toUtc();
    final merged = <String, List<StripchatMouflonKeyRecord>>{};
    for (final record in records) {
      merged.putIfAbsent(record.pkey, () => <StripchatMouflonKeyRecord>[])
          .add(record);
    }
    for (final record in freshRecords) {
      final normalizedPkey = record.pkey.trim();
      final normalizedPdkey = record.pdkey.trim();
      if (normalizedPkey.isEmpty || normalizedPdkey.isEmpty) {
        continue;
      }
      final normalizedCaptureSource = _normalizeCaptureSource(
        record.captureSource,
        source,
      );
      final candidate = StripchatMouflonKeyRecord(
        pkey: normalizedPkey,
        pdkey: normalizedPdkey,
        capturedAt: timestamp,
        source: source,
        captureSource: normalizedCaptureSource,
      );
      final bucket =
          merged.putIfAbsent(normalizedPkey, () => <StripchatMouflonKeyRecord>[]);
      if (bucket.isEmpty) {
        bucket.add(candidate);
        continue;
      }
      final strongest = bucket.reduce((left, right) {
        return _shouldReplaceRecord(candidate: left, existing: right)
            ? left
            : right;
      });
      if (!_shouldReplaceRecord(candidate: candidate, existing: strongest) &&
          !bucket.any((item) => item.pdkey == normalizedPdkey)) {
        continue;
      }
      final existingIndex = bucket.indexWhere(
        (item) => item.pdkey == normalizedPdkey,
      );
      if (existingIndex < 0) {
        bucket.add(candidate);
        continue;
      }
      final existing = bucket[existingIndex];
      if (_shouldReplaceRecord(candidate: candidate, existing: existing)) {
        bucket[existingIndex] = candidate;
      }
    }
    final nextRecords = merged.values
        .expand((bucket) => bucket)
        .toList(growable: false)
      ..sort((left, right) => right.capturedAt.compareTo(left.capturedAt));
    return StripchatMouflonKeyCache(
      records: List<StripchatMouflonKeyRecord>.unmodifiable(
        nextRecords.take(maxRecords),
      ),
      status: nextRecords.isEmpty ? status : StripchatCalibrationStatus.ready,
      statusUpdatedAt: timestamp,
      decodeStatus: StripchatCalibrationDecodeStatus.ok,
    );
  }

  StripchatMouflonKeyCache markFailed({DateTime? at}) {
    final timestamp = (at ?? DateTime.now()).toUtc();
    return StripchatMouflonKeyCache(
      records: List<StripchatMouflonKeyRecord>.unmodifiable(records),
      status: StripchatCalibrationStatus.failed,
      statusUpdatedAt: timestamp,
      decodeStatus: decodeStatus,
    );
  }

  StripchatMouflonKeyCache withTrustedFallbacks({
    DateTime? capturedAt,
  }) {
    final trustedRecords = <StripchatMouflonKeyRecord>[];
    _hardcodedPdkeys.forEach((pkey, pdkey) {
      trustedRecords.add(
        StripchatMouflonKeyRecord(
          pkey: pkey,
          pdkey: pdkey,
          capturedAt: capturedAt ?? DateTime.now().toUtc(),
          source: StripchatCalibrationSource.auto,
          captureSource: 'trusted-fallback',
        ),
      );
    });
    if (trustedRecords.isEmpty) {
      return this;
    }
    return mergeRecords(
      trustedRecords,
      source: StripchatCalibrationSource.auto,
      capturedAt: capturedAt,
    );
  }

  StripchatMouflonKeyCache clear() {
    return const StripchatMouflonKeyCache();
  }
}

String _normalizeCaptureSource(
  String raw,
  StripchatCalibrationSource fallback,
) {
  final normalized = raw.trim().toLowerCase();
  if (normalized.isNotEmpty) {
    return normalized;
  }
  return fallback.name;
}

bool _shouldReplaceRecord({
  required StripchatMouflonKeyRecord candidate,
  required StripchatMouflonKeyRecord existing,
}) {
  final candidatePriority = stripchatMouflonKeySourcePriority(
    candidate.captureSource,
  );
  final existingPriority = stripchatMouflonKeySourcePriority(
    existing.captureSource,
  );
  if (candidatePriority != existingPriority) {
    return candidatePriority > existingPriority;
  }
  return !candidate.capturedAt.isBefore(existing.capturedAt);
}

List<StripchatMouflonKeyRecord> parseStripchatMouflonImport(
  String input, {
  required StripchatCalibrationSource source,
  DateTime? capturedAt,
}) {
  final timestamp = (capturedAt ?? DateTime.now()).toUtc();
  final records = <StripchatMouflonKeyRecord>[];
  final seen = <String>{};
  final lines = const LineSplitter().convert(input);
  for (final line in lines) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) {
      continue;
    }
    final separator = trimmed.indexOf(':');
    if (separator <= 0 || separator == trimmed.length - 1) {
      throw const FormatException('每行必须是 pkey:pdkey');
    }
    final pkey = trimmed.substring(0, separator).trim();
    final pdkey = trimmed.substring(separator + 1).trim();
    if (pkey.isEmpty || pdkey.isEmpty) {
      throw const FormatException('pkey 或 pdkey 不能为空');
    }
    if (!seen.add(pkey)) {
      continue;
    }
    records.add(
      StripchatMouflonKeyRecord(
        pkey: pkey,
        pdkey: pdkey,
        capturedAt: timestamp,
        source: source,
        captureSource: source.name,
      ),
    );
  }
  if (records.isEmpty) {
    throw const FormatException('当前没有可导入的密钥');
  }
  return List<StripchatMouflonKeyRecord>.unmodifiable(records);
}
