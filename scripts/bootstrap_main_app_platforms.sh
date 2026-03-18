#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/apps/main_app"

if ! command -v flutter >/dev/null 2>&1; then
  export PATH="$HOME/.local/share/flutter/bin:$PATH"
fi

if ! command -v flutter >/dev/null 2>&1; then
  echo "flutter not found; please install Flutter or export PATH first" >&2
  exit 1
fi

cd "$APP_DIR"
flutter create . --platforms=android,ios,linux,macos,windows --project-name nolive_app --org app.nolive
rm -f test/widget_test.dart

python3 - <<'PY'
from pathlib import Path
updates = {
    'android/app/build.gradle.kts': [('app.nolive.nolive_app', 'app.nolive.mobile')],
    'android/app/src/main/AndroidManifest.xml': [('android:label="nolive_app"', 'android:label="Nolive"')],
    'ios/Runner/Info.plist': [('<string>Nolive App</string>', '<string>Nolive</string>'), ('<string>nolive_app</string>', '<string>Nolive</string>')],
    'ios/Runner.xcodeproj/project.pbxproj': [('app.nolive.noliveApp.RunnerTests', 'app.nolive.mobile.RunnerTests'), ('app.nolive.noliveApp', 'app.nolive.mobile')],
    'macos/Runner.xcodeproj/project.pbxproj': [('app.nolive.noliveApp.RunnerTests', 'app.nolive.mobile.RunnerTests')],
    'macos/Runner/Configs/AppInfo.xcconfig': [('PRODUCT_NAME = nolive_app', 'PRODUCT_NAME = Nolive'), ('PRODUCT_BUNDLE_IDENTIFIER = app.nolive.noliveApp', 'PRODUCT_BUNDLE_IDENTIFIER = app.nolive.mobile')],
    'linux/CMakeLists.txt': [('APPLICATION_ID "app.nolive.nolive_app"', 'APPLICATION_ID "app.nolive.mobile"'), ('BINARY_NAME "nolive_app"', 'BINARY_NAME "nolive"')],
    'linux/runner/my_application.cc': [('"nolive_app"', '"Nolive"')],
    'windows/runner/main.cpp': [('L"nolive_app"', 'L"Nolive"')],
    'windows/runner/Runner.rc': [('"nolive_app"', '"Nolive"'), ('"nolive_app.exe"', '"nolive.exe"')],
}
for relative, replacements in updates.items():
    path = Path(relative)
    text = path.read_text()
    for old, new in replacements:
        text = text.replace(old, new)
    path.write_text(text)
old_path = Path('android/app/src/main/kotlin/app/nolive/nolive_app/MainActivity.kt')
new_path = Path('android/app/src/main/kotlin/app/nolive/mobile/MainActivity.kt')
if old_path.exists():
    new_path.parent.mkdir(parents=True, exist_ok=True)
    new_path.write_text(old_path.read_text().replace('package app.nolive.nolive_app', 'package app.nolive.mobile'))
    old_path.unlink()
PY

echo "main_app platform scaffolding refreshed." 
