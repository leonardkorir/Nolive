import 'package:nolive_app/src/app/home/application/home_feature_dependencies.dart';
import 'package:nolive_app/src/features/browse/application/browse_feature_dependencies.dart';
import 'package:nolive_app/src/features/library/application/library_feature_dependencies.dart';

class AppShellDependencies {
  const AppShellDependencies({
    required this.home,
    required this.browse,
    required this.library,
  });

  final HomeFeatureDependencies home;
  final BrowseFeatureDependencies browse;
  final LibraryFeatureDependencies library;
}
