import 'package:live_storage/live_storage.dart';

/// Shared settings readers for Load*Preferences use cases (ponytail F05).
extension SettingsPreferenceReaders on SettingsRepository {
  Future<bool> readBool(String key, {required bool fallback}) async {
    return await readValue<bool>(key) ?? fallback;
  }

  Future<double> readClampedDouble(
    String key, {
    required double min,
    required double max,
    required double fallback,
  }) async {
    final value = await readValue<double>(key);
    return (value ?? fallback).clamp(min, max).toDouble();
  }

  Future<int> readClampedInt(
    String key, {
    required int min,
    required int max,
    required int fallback,
  }) async {
    final value = await readValue<int>(key);
    return (value ?? fallback).clamp(min, max);
  }
}
