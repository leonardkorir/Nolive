import 'dart:collection';

import 'model_equality.dart';

class LivePlayQuality {
  LivePlayQuality({
    required this.id,
    required this.label,
    this.isDefault = false,
    this.sortOrder = 0,
    Map<String, Object?>? metadata,
  }) : metadata = metadata == null
           ? null
           : UnmodifiableMapView<String, Object?>(
               Map<String, Object?>.fromEntries(
                 metadata.entries.map(
                   (entry) => MapEntry(
                     entry.key,
                     _immutableMetadataValue(entry.value),
                   ),
                 ),
               ),
             );

  final String id;
  final String label;
  final bool isDefault;
  final int sortOrder;
  final Map<String, Object?>? metadata;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is LivePlayQuality &&
            other.id == id &&
            other.label == label &&
            other.isDefault == isDefault &&
            other.sortOrder == sortOrder &&
            modelMapEquals(other.metadata, metadata);
  }

  @override
  int get hashCode =>
      Object.hash(id, label, isDefault, sortOrder, modelMapHash(metadata));
}

Object? _immutableMetadataValue(Object? value) {
  if (value is Map) {
    return UnmodifiableMapView<Object?, Object?>(
      Map<Object?, Object?>.fromEntries(
        value.entries.map(
          (entry) => MapEntry(entry.key, _immutableMetadataValue(entry.value)),
        ),
      ),
    );
  }
  if (value is List) {
    return List<Object?>.unmodifiable(value.map(_immutableMetadataValue));
  }
  if (value is Set) {
    return Set<Object?>.unmodifiable(value.map(_immutableMetadataValue));
  }
  return value;
}
