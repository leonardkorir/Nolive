# Scripts

本目录存放 Nolive 的工作区初始化、Android 构建、签名校验和真机验证脚本。

当前发布基线以 Android 为主。

依赖 Flutter/Dart 的仓库脚本会自动探测常见 SDK 位置，包括 `FLUTTER_ROOT`、`$HOME/flutter`、`$HOME/.local/share/flutter`，以及 `apps/main_app` 生成的 `flutter_export_environment.sh`。

## 快速开始

```bash
flutter pub get
flutter pub run melos bootstrap
flutter pub run melos run analyze
flutter pub run melos run test
flutter pub run melos run format
```

仓库默认不附带私有 provider fixture。依赖本地私有样本的深度回归测试会在缺少样本时自动跳过。

常用构建命令：

```bash
scripts/build_main_app.sh verify
scripts/build_main_app.sh provider-live-smoke
scripts/build_main_app.sh android-release-ready
scripts/render_release_notes.sh vX.Y.Z
scripts/build_main_app.sh android-mobile-release
scripts/clean_public_repo_workspace.sh
scripts/install_main_app_android.sh
scripts/manage_main_app_android_capture.sh start
scripts/run_main_app_android_smoke.sh
```

## 脚本说明

- `scripts/bootstrap_main_app_platforms.sh`
  重新生成 `apps/main_app` 的 Flutter 平台模板目录。

- `scripts/build_main_app.sh`
  统一的主构建入口。

  常用 target：

  - `verify`：执行 release metadata 检查、静态分析和测试。
  - `verify-release-metadata`：仅校验版本、manifest 和发布文档元数据。
  - `provider-live-smoke`：执行依赖真实远端站点的 provider 在线 smoke；该检查非 hermetic，适合作为补充验证。
  - `android-apk`：构建 Android release APK。
  - `android-apk-split`：按 ABI 构建 split APK。
  - `android-appbundle`：构建 Android App Bundle。
  - `android-mobile-release`：构建首发所需的 split APK 和 AAB。
  - `android-release-ready`：执行 verify 并生成带真实签名的 release 构建。
  - `android-release-acceptance`：执行 release 构建、安装、启动校验和真机 smoke。
  - `android-release-launch-check`：仅校验安装后的 release app 能正常启动。
  - `android-connected-smoke`：仅执行已连接设备 smoke。

- `scripts/create_main_app_android_signing.sh`
  生成本地 Android release keystore 和 `key.properties`。

- `scripts/clean_public_repo_workspace.sh`
  清理 `flutter pub get`、`melos bootstrap`、测试和构建后产生的本地缓存、临时文件、build 产物、`local.properties` 以及本地工具痕迹目录。
  如果你希望在本地验证后恢复为干净的源码状态，建议执行一次。

- `scripts/install_main_app_android.sh`
  按设备 ABI 安装 split APK 到已连接 Android 设备。

- `scripts/manage_main_app_android_capture.sh`
  管理 Android 真机持续采集。
  支持 `start`、`stop`、`status`、`pull`、`pull-app-logs` 五个子命令。
  其中 `start/stop/status/pull` 面向设备侧 `logcat + dumpsys meminfo/top` 持续采集，会写入 `/sdcard/Download/nolive-logs/`；
  `pull-app-logs` 单独拉取 app 自己持续落盘的 `/sdcard/Android/data/app.nolive.mobile/files/logs/`，不依赖 active capture session。
  拉取结果会直接平铺到本地 `app-logs/`，不再额外嵌套一层 `logs/` 目录。

- `scripts/extract_main_app_persisted_log_window.sh`
  从拉下来的 app 持久化日志里提取安装时间之后的窗口日志。
  会递归扫描 `nolive-mobile-YYYY-MM-DD.log` 和 `nolive-mobile-YYYY-MM-DD-01.log` 这类轮转分段，避免漏掉 8MB 轮转后的新日志。
  生成窗口文件时会自动排除已有的 `*-post-install-window.log`，并去掉完全重复的记录，避免重复执行提取时把旧窗口输出再读回去。

- `scripts/run_main_app_android_smoke.sh`
  在已连接 Android 设备或模拟器上执行主链路 smoke。
  如果工作区里已存在 release APK，脚本会在 smoke 结束后自动把 release 重新装回设备并做一次启动校验。

- `scripts/verify_android_release_signing.sh`
  校验 APK 或 AAB 是否由非 debug 的 release keystore 签名。

- `scripts/verify_main_app_android_launch.sh`
  校验已安装 Android release 应用可以正常冷启动并进入前台。

- `scripts/verify_release_metadata.sh`
  校验 `pubspec`、Android manifest、`CHANGELOG.md`、`README.md`、`scripts/README.md` 与发布文档之间的版本和发布说明一致性。

- `scripts/render_release_notes.sh`
  从 `CHANGELOG.md` 中提取指定版本的条目，用于 GitHub Release 文案预览或自动发布。

## 相关文档

- `docs/android-release-guide.md`
- `docs/release-checklist.md`

## 说明

- `key.properties`、`local.properties`、`*.jks`、`*.keystore` 都属于本地敏感材料，不应提交到仓库。
- 如果只是本地开发，一般先跑 `verify`；如需补充远端在线校验，再跑 `provider-live-smoke`；如果是发布候选，再跑 `android-release-ready` 或 `android-release-acceptance`。
- 如果你希望在所有本地验证结束后恢复为不含缓存和构建产物的源码状态，建议执行 `scripts/clean_public_repo_workspace.sh`。
- 发布前可先用 `scripts/render_release_notes.sh vX.Y.Z` 预览 GitHub Release 文案，确认只包含当前版本条目。
