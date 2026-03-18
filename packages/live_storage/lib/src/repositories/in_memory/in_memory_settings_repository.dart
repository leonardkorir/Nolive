import '../settings_repository.dart';

class InMemorySettingsRepository implements SettingsRepository {
  final Map<String, Object?> _values = {};

  @override
  Future<Map<String, Object?>> listAll() async {
    return Map<String, Object?>.unmodifiable(_values);
  }

  @override
  Future<T?> readValue<T>(String key) async {
    final value = _values[key];
    if (value is T) {
      return value;
    }
    return null;
  }

  @override
  Future<void> writeValue<T>(String key, T value) async {
    _values[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    _values.remove(key);
  }

  Map<String, Object?> dump() => Map<String, Object?>.from(_values);
}
