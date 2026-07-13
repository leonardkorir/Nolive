abstract final class ProviderJson {
  static Map<String, dynamic> asMap(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.cast<String, dynamic>();
    }
    return const <String, dynamic>{};
  }

  static List<dynamic> asList(Object? value) {
    if (value is List) {
      return value;
    }
    return const <dynamic>[];
  }

  static int? asInt(Object? value, {bool allowNum = false, bool trim = false}) {
    if (value is int) {
      return value;
    }
    if (allowNum && value is num) {
      return value.toInt();
    }
    final raw = value?.toString() ?? '';
    return int.tryParse(trim ? raw.trim() : raw);
  }

  static int? asLocalizedCountInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.round();
    }
    final raw = value?.toString().trim() ?? '';
    if (raw.isEmpty) {
      return null;
    }
    final normalized = raw.replaceAll(',', '');
    final match = RegExp(
      r'^([0-9]+(?:\.[0-9]+)?)([万亿]?)$',
    ).firstMatch(normalized);
    if (match != null) {
      final number = double.tryParse(match.group(1) ?? '');
      if (number == null) {
        return null;
      }
      final unit = match.group(2);
      final multiplier = switch (unit) {
        '万' => 10000,
        '亿' => 100000000,
        _ => 1,
      };
      return (number * multiplier).round();
    }
    return int.tryParse(normalized);
  }
}
