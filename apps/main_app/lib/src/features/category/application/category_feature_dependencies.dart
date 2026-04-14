import 'package:nolive_app/src/features/search/application/search_feature_dependencies.dart';

import 'load_category_rooms_use_case.dart';
import 'load_provider_categories_use_case.dart';
import 'manage_favorite_category_tags_use_case.dart';

class CategoryFeatureDependencies {
  const CategoryFeatureDependencies({
    required this.loadProviderCategories,
    required this.loadFavoriteCategoryTags,
    required this.toggleFavoriteCategoryTag,
    required this.loadCategoryRooms,
    required this.searchDependencies,
  });

  final LoadProviderCategoriesUseCase loadProviderCategories;
  final LoadFavoriteCategoryTagsUseCase loadFavoriteCategoryTags;
  final ToggleFavoriteCategoryTagUseCase toggleFavoriteCategoryTag;
  final LoadCategoryRoomsUseCase loadCategoryRooms;
  final SearchFeatureDependencies searchDependencies;
}
