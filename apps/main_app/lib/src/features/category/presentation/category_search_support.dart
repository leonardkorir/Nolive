import 'package:live_core/live_core.dart';

class FilteredCategoryGroup {
  const FilteredCategoryGroup({
    required this.group,
    required this.items,
    required this.matchedByGroup,
  });

  final LiveCategory group;
  final List<LiveSubCategory> items;
  final bool matchedByGroup;
}

List<FilteredCategoryGroup> filterCategoryGroups(
  List<LiveCategory> categories,
  String query, {
  required List<LiveSubCategory> Function(LiveCategory category) childrenOf,
}) {
  final normalized = normalizeDisplayText(query).toLowerCase();
  if (normalized.isEmpty) {
    return [
      for (final category in categories)
        FilteredCategoryGroup(
          group: category,
          items: childrenOf(category),
          matchedByGroup: false,
        ),
    ];
  }

  final groups = <FilteredCategoryGroup>[];
  for (final category in categories) {
    final children = childrenOf(category);
    final matchedByGroup = normalizeDisplayText(category.name)
        .toLowerCase()
        .contains(normalized);
    final matchedChildren = matchedByGroup
        ? children
        : children
            .where(
              (item) => normalizeDisplayText(item.name)
                  .toLowerCase()
                  .contains(normalized),
            )
            .toList(growable: false);
    if (matchedChildren.isEmpty) {
      continue;
    }
    groups.add(
      FilteredCategoryGroup(
        group: category,
        items: matchedChildren,
        matchedByGroup: matchedByGroup,
      ),
    );
  }
  return groups;
}
