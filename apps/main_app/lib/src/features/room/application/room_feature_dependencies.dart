import 'package:nolive_app/src/features/room/application/room_preview_dependencies.dart';

/// Feature-scoped room dependency surface used by router and room pages.
///
/// Alias of [RoomPreviewDependencies] so room is wired like settings/sync:
/// pages receive this slice, not the full [AppBootstrap] field surface.
typedef RoomFeatureDependencies = RoomPreviewDependencies;
