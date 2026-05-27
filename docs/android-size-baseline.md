# Android Size Baseline

## Scope

This document records the current Android size baseline and the room-feature governance changes completed in the same maintenance pass.

Date: `2026-04-06 00:29:20 +0800`

## Room Governance Completed

### 1. Feature-scoped room dependencies

`RoomPreviewPage` no longer depends on the full `AppBootstrap` graph at the route boundary.

Introduced:

- `apps/main_app/lib/src/features/room/application/room_preview_dependencies.dart`

Current route entry:

- `apps/main_app/lib/src/app/routing/app_router.dart`

This reduces feature coupling and gives follow-up room refactors a smaller dependency surface.

### 2. Consolidated playback session state

Room playback session and pending bootstrap state are now grouped into:

- `apps/main_app/lib/src/features/room/presentation/room_playback_session_state.dart`

`RoomPreviewPage` keeps the same behavior, but no longer mutates the following fields independently across multiple partials:

- active room detail
- selected quality
- effective quality
- playback source
- play URLs
- playback availability
- pending playback source
- pending playback availability
- pending autoplay

This creates a clearer state boundary for future extraction into a dedicated room session controller or application-layer coordinator.

## Verification

Validated in `apps/main_app`:

```bash
/home/tianfushui/flutter/bin/flutter analyze \
  lib/src/features/room/presentation/room_playback_session_state.dart \
  lib/src/features/room/presentation/room_preview_page.dart \
  lib/src/features/room/presentation/room_preview_page_controls.dart \
  lib/src/features/room/presentation/room_preview_page_player_system.dart \
  test/room_playback_session_state_test.dart \
  test/room_preview_page_test.dart

/home/tianfushui/flutter/bin/flutter test \
  test/room_playback_session_state_test.dart \
  test/room_preview_page_test.dart
```

Result:

- `flutter analyze`: passed
- `flutter test`: passed, `17` tests

## Android Release Size Baseline

### Build command

Executed in `apps/main_app`:

```bash
/home/tianfushui/flutter/bin/flutter build apk --release --analyze-size --target-platform=android-arm64
```

### Generated artifacts

- APK: `apps/main_app/build/app/outputs/flutter-apk/app-release.apk`
- Size analysis JSON: `/home/tianfushui/.flutter-devtools/apk-code-size-analysis_01.json`

### Current baseline

- APK file size on disk: `57 MB`
- Flutter summary compressed APK size: `56 MB`
- Size analysis JSON size: `12 MB`

### Largest contributors from Flutter size summary

- `lib/arm64-v8a`: `21 MB`
- `assets/flutter_assets`: `4 MB`
- `classes.dex`: `3 MB`
- `classes2.dex`: `2 MB`

Largest reported Dart AOT symbol buckets inside the APK summary:

- `package:flutter`: `4 MB`
- `package:nolive_app`: `830 KB`
- `package:live_providers`: `637 KB`
- `package:flutter_localizations`: `279 KB`
- `package:brotli`: `169 KB`
- `package:flutter_inappwebview_platform_interface`: `168 KB`
- `package:media_kit`: `161 KB`
- `package:image`: `126 KB`
- `package:protobuf`: `120 KB`
- `package:fvp`: `65 KB`
- `package:flutter_qjs`: `56 KB`

## Interpretation

This baseline comes from Flutter's `apk --analyze-size` output and is suitable for trend comparison across future changes.

It is **not** the same as final store download size because:

- this artifact is a local APK build
- store delivery can filter ABIs and densities
- the current release process also publishes split APKs and an App Bundle

## Next Reduction Candidates

These are the highest-value places to inspect next, based on current room/player architecture and the size summary:

1. Review whether all packaged player backends and native libraries are required for release builds.
2. Re-check WebView-related dependencies and keep headless WebView initialization strictly lazy.
3. Audit image and bundled asset usage under `flutter_assets`.
4. Run a second baseline with `appbundle --analyze-size` when preparing store release comparisons.
5. Diff future `apk-code-size-analysis_*.json` files in DevTools before and after dependency changes.
