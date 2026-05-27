import 'model_equality.dart';

class PagedResponse<T> {
  const PagedResponse({
    required this.items,
    required this.hasMore,
    this.page = 1,
  });

  final List<T> items;
  final bool hasMore;
  final int page;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is PagedResponse<T> &&
            modelListEquals(other.items, items) &&
            other.hasMore == hasMore &&
            other.page == page;
  }

  @override
  int get hashCode => Object.hash(modelListHash(items), hasMore, page);
}
