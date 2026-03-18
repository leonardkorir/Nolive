# Android Release Guide

## Scope

`Nolive` 当前发布目标以 **Android mobile first** 为主。
本文档只说明 Android release 的构建、签名、验收和 GitHub 发布流程。

## Baseline

- Flutter: `3.35+` stable
- Dart: `3.6+`
- Java: `17`
- Android minSdk: `23`
- Release artifacts: split APK + App Bundle

## Local Signing

将 `apps/main_app/android/key.properties.example` 复制为 `apps/main_app/android/key.properties`。

如果你还没有 release keystore，可以执行：

```bash
scripts/create_main_app_android_signing.sh
```

`key.properties` 示例：

```properties
keyAlias=your-key-alias
keyPassword=your-key-password
storePassword=your-store-password
storeFile=../keystore/nolive-release.jks
```

说明：

- `scripts/build_main_app.sh android-mobile-release` 在本地缺少正式签名时可以继续跑构建。
- `scripts/build_main_app.sh android-release-ready` 要求真实签名材料，并拒绝 `debug.keystore` 或 `androiddebugkey`。
- 构建完成后，可使用 `scripts/verify_android_release_signing.sh` 校验 APK 和 AAB 的签名是否正确。
- 仓库默认不附带私有 provider fixture；依赖这些样本的深度 provider 回归测试会在缺少样本时自动跳过。
- `verify`、`provider-live-smoke` 和 release 构建会产生本地缓存、`local.properties` 与 build 目录；如果你想在验证完成后恢复干净工作区，可运行 `scripts/clean_public_repo_workspace.sh`。

不要提交以下文件：

- `apps/main_app/android/key.properties`
- `apps/main_app/android/keystore/nolive-release.jks`

## CI Secrets

`.github/workflows/android-release.yml` 支持以下签名输入方式之一：

- `ANDROID_KEY_PROPERTIES` + `ANDROID_KEYSTORE_BASE64`
- `ANDROID_KEYSTORE_BASE64` + `ANDROID_KEY_ALIAS` + `ANDROID_KEY_PASSWORD` + `ANDROID_STORE_PASSWORD`

工作流会在运行时写入 `key.properties` 并解码 keystore，不要求这些文件进入仓库。

当前仓库已经采用 `ANDROID_KEY_PROPERTIES` + `ANDROID_KEYSTORE_BASE64` 这组配置。
如果你继续沿用这种方式，后续不需要再新增其他 Android 签名 secrets。
只有在你想改用拆分字段方式时，才需要额外配置：

- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`
- `ANDROID_STORE_PASSWORD`

## Recommended Commands

基础质量门：

```bash
export PATH="$HOME/.local/share/flutter/bin:$PATH"
scripts/build_main_app.sh verify
```

可选远端 provider 在线 smoke：

```bash
scripts/build_main_app.sh provider-live-smoke
```

本地 release 构建：

```bash
scripts/build_main_app.sh android-mobile-release
```

正式签名 release 构建：

```bash
scripts/build_main_app.sh android-release-ready
scripts/verify_android_release_signing.sh
```

连接真机或模拟器后的最终验收：

```bash
ANDROID_DEVICE_ID=<device-id> scripts/build_main_app.sh android-release-acceptance
```

如果你需要清理验证后生成的本地文件，建议在所有验证完成后再执行：

```bash
scripts/clean_public_repo_workspace.sh
```

## Artifact Outputs

- `apps/main_app/build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk`
- `apps/main_app/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`
- `apps/main_app/build/app/outputs/flutter-apk/app-x86_64-release.apk`
- `apps/main_app/build/app/outputs/bundle/release/app-release.aab`

## Version and Release Notes

- version source: `apps/main_app/pubspec.yaml`
- release notes source: `CHANGELOG.md`
- release notes preview: `scripts/render_release_notes.sh vX.Y.Z`
- release checklist: `docs/release-checklist.md`

## CI Workflow

GitHub Actions workflow: `.github/workflows/android-release.yml`

默认流程：

- `scripts/build_main_app.sh verify`
- 如需额外在线检查，再执行 `scripts/build_main_app.sh provider-live-smoke`
- 根据是否提供签名材料执行 `android-mobile-release` 或 `android-release-ready`
- 上传 split APK 与 AAB
- 在 tag 为 `v*` 且签名材料齐全时，根据 `CHANGELOG.md` 中对应版本条目发布 GitHub Release 资源

## Maintainer Release Flow

建议维护者按以下顺序继续发布后续版本：

1. 更新 `apps/main_app/pubspec.yaml` 版本号。
2. 更新 `CHANGELOG.md` 中对应版本条目。
3. 运行 `scripts/build_main_app.sh verify`。
4. 按需要运行 `scripts/build_main_app.sh provider-live-smoke`。
5. 准备好签名材料后运行 `scripts/build_main_app.sh android-release-ready`。
6. 如需真机最终验收，运行 `ANDROID_DEVICE_ID=<device-id> scripts/build_main_app.sh android-release-acceptance`。
7. 运行 `scripts/render_release_notes.sh vX.Y.Z`，确认 GitHub Release 文案只包含当前版本。
8. 确认 `git status` 干净、`README.md` 的下载指引仍然正确。
9. 推送 `main`。
10. 创建并推送 tag：`git tag -a vX.Y.Z -m "Release vX.Y.Z"` 与 `git push origin vX.Y.Z`。
11. 等待 GitHub Actions 完成，并确认 Release 页面已上传 3 个 APK 与 1 个 AAB。

## Recommended GitHub Settings

当前这条发布工作流已经显式声明 `contents: write`，因此不需要再额外为 Release 发布配置仓库级 PAT secret。

推荐你额外检查以下仓库设置：

- `Settings > Actions > General` 保持 Actions 已启用。
- `Settings > Actions > General > Workflow permissions` 保持默认只读也可以，因为工作流里已单独声明写权限。
- `Settings > Rules` 或 `Settings > Branches` 为 `main` 增加轻量保护，至少禁止 force push 和删除分支。
- 如果你准备改成 PR 合并流程，再为 `main` 增加必过检查：`android-release / verify-and-build-android`。
- 如果你仍然主要采用单维护者直推流程，不建议强制要求 PR review，否则会把自己的发布流程也锁死。

## Device Acceptance Focus

建议至少在一台真实 Android 设备上完成以下检查：

- 安装、冷启动和前后台切换正常
- `scripts/run_main_app_android_smoke.sh` 能通过；如果工作区已有 release APK，脚本结束后设备上应恢复为 release 构建
- 首页、关注页、房间页主链路正常
- 播放、切线、切画质、切播放器后端正常
- 弹幕显示、关注、历史、标签和本地快照正常
- 中文界面文本在常用 Android 设备上显示正常，无明显缺字、错位或裁切
