import 'model_equality.dart';

class LiveCategory {
  const LiveCategory({
    required this.id,
    required this.name,
    this.children = const [],
  });

  final String id;
  final String name;
  final List<LiveSubCategory> children;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is LiveCategory &&
            other.id == id &&
            other.name == name &&
            modelListEquals(other.children, children);
  }

  @override
  int get hashCode => Object.hash(id, name, modelListHash(children));
}

class LiveSubCategory {
  const LiveSubCategory({
    required this.id,
    required this.parentId,
    required this.name,
    this.pic,
  });

  final String id;
  final String parentId;
  final String name;
  final String? pic;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is LiveSubCategory &&
            other.id == id &&
            other.parentId == parentId &&
            other.name == name &&
            other.pic == pic;
  }

  @override
  int get hashCode => Object.hash(id, parentId, name, pic);
}
