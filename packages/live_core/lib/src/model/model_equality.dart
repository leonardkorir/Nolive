bool modelListEquals<T>(List<T> left, List<T> right) {
  if (identical(left, right)) {
    return true;
  }
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index += 1) {
    if (!modelValueEquals(left[index], right[index])) {
      return false;
    }
  }
  return true;
}

bool modelMapEquals(Map<Object?, Object?>? left, Map<Object?, Object?>? right) {
  if (identical(left, right)) {
    return true;
  }
  if (left == null || right == null || left.length != right.length) {
    return false;
  }
  for (final key in left.keys) {
    if (!right.containsKey(key) || !modelValueEquals(left[key], right[key])) {
      return false;
    }
  }
  return true;
}

bool modelValueEquals(Object? left, Object? right) {
  if (identical(left, right)) {
    return true;
  }
  if (left is List && right is List) {
    return modelListEquals(left, right);
  }
  if (left is Map && right is Map) {
    return modelMapEquals(
      left.cast<Object?, Object?>(),
      right.cast<Object?, Object?>(),
    );
  }
  return left == right;
}

int modelListHash(List<Object?> values) {
  return Object.hashAll(values.map(modelValueHash));
}

int modelMapHash(Map<Object?, Object?>? value) {
  if (value == null) {
    return 0;
  }
  return Object.hash(
    value.length,
    Object.hashAllUnordered(
      value.entries.map(
        (entry) =>
            Object.hash(modelValueHash(entry.key), modelValueHash(entry.value)),
      ),
    ),
  );
}

int modelValueHash(Object? value) {
  if (value is List) {
    return modelListHash(value.cast<Object?>());
  }
  if (value is Map) {
    return modelMapHash(value.cast<Object?, Object?>());
  }
  return value.hashCode;
}
