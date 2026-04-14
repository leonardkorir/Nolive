import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:nolive_app/src/features/category/presentation/category_search_support.dart';

void main() {
  const categories = <LiveCategory>[
    LiveCategory(
      id: 'group-1',
      name: '网游',
      children: [
        LiveSubCategory(id: 'lol', parentId: 'group-1', name: '英雄联盟'),
        LiveSubCategory(id: 'valorant', parentId: 'group-1', name: '无畏契约'),
      ],
    ),
    LiveCategory(
      id: 'group-2',
      name: '手游',
      children: [
        LiveSubCategory(id: 'genshin', parentId: 'group-2', name: '原神'),
      ],
    ),
  ];

  List<LiveSubCategory> childrenOf(LiveCategory category) => category.children;

  test('empty query returns every category group', () {
    final result = filterCategoryGroups(
      categories,
      '',
      childrenOf: childrenOf,
    );

    expect(result, hasLength(2));
    expect(result.first.items, hasLength(2));
    expect(result.last.items.single.name, '原神');
  });

  test('matching a group returns all children under that group', () {
    final result = filterCategoryGroups(
      categories,
      '网游',
      childrenOf: childrenOf,
    );

    expect(result, hasLength(1));
    expect(result.single.group.name, '网游');
    expect(result.single.items.map((item) => item.name), ['英雄联盟', '无畏契约']);
    expect(result.single.matchedByGroup, isTrue);
  });

  test('matching a child returns only matched children', () {
    final result = filterCategoryGroups(
      categories,
      '原神',
      childrenOf: childrenOf,
    );

    expect(result, hasLength(1));
    expect(result.single.group.name, '手游');
    expect(result.single.items.map((item) => item.name), ['原神']);
    expect(result.single.matchedByGroup, isFalse);
  });

  test('search matches malformed utf16 category names after normalization', () {
    final malformedCategories = <LiveCategory>[
      LiveCategory(
        id: 'group-1',
        name: '游${String.fromCharCode(0xD800)}戏',
        children: [
          LiveSubCategory(
            id: 'hot',
            parentId: 'group-1',
            name: '热${String.fromCharCode(0xDC00)}门',
          ),
        ],
      ),
    ];

    final result = filterCategoryGroups(
      malformedCategories,
      '热门',
      childrenOf: childrenOf,
    );

    expect(result, hasLength(1));
    expect(result.single.items.single.name, contains('门'));
  });
}
