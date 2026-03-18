class LiveCategory {
  const LiveCategory({
    required this.id,
    required this.name,
    this.children = const [],
  });

  final String id;
  final String name;
  final List<LiveSubCategory> children;
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
}
