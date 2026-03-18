# Nolive Release Checklist

## Scope

本清单用于 Android release 前的最终检查。
当前发布范围以 `apps/main_app` 为主。

## Before Bumping Version

- 更新 `apps/main_app/pubspec.yaml` 版本号
- 确认 `CHANGELOG.md` 已同步本次版本说明
- 确认 `scripts/render_release_notes.sh vX.Y.Z` 预览结果只包含当前版本条目
- 确认 `README.md`、`scripts/README.md`、`docs/android-release-guide.md` 与当前发布口径一致
- 确认 `README.md` 中的下载指引仍然指向正确的 GitHub Release 页面和资产说明
- 确认 Android 签名配置已准备好
- 确认没有本地临时调试改动、测试假数据或未清理日志
- 如需在验证结束后恢复干净工作区，确认会执行 `scripts/clean_public_repo_workspace.sh`

## Engineering Gate

执行：

```bash
export PATH="$HOME/.local/share/flutter/bin:$PATH"
scripts/build_main_app.sh verify
scripts/build_main_app.sh provider-live-smoke
scripts/build_main_app.sh android-release-ready
ANDROID_DEVICE_ID=<device-id> scripts/build_main_app.sh android-release-acceptance
ANDROID_DEVICE_ID=<device-id> scripts/run_main_app_android_smoke.sh
scripts/verify_android_release_signing.sh
```

期望结果：

- `scripts/verify_release_metadata.sh` 通过
- `melos run analyze` 通过
- `melos run test` 通过
- 如需补充远端在线验证，`scripts/build_main_app.sh provider-live-smoke` 在维护者网络环境下通过
- split APK 与 AAB 均成功生成
- APK/AAB 签名与配置的 release keystore 一致
- 安装后的 release 应用可以正常冷启动
- 已连接设备 smoke 通过
- release 验收流程结束后，设备上保留的仍是 release 构建
- 执行 `scripts/clean_public_repo_workspace.sh` 后不再残留 `local.properties`、build 产物、Flutter 临时文件和本地工具痕迹目录

说明：

- `verify` 现在只包含 hermetic 校验，不再依赖第三方站点在线状态。
- 仓库默认不附带私有 provider fixture；对应深度回归测试会在缺少样本时自动跳过。
- `scripts/run_main_app_android_smoke.sh` 会临时部署 integration test 所需测试壳；如果工作区已有 release APK，脚本结束后会自动恢复 release 并重新做一次启动校验。
- 完成上述检查后，如需恢复干净工作区，记得执行一次 `scripts/clean_public_repo_workspace.sh`。

## Manual Android Checks

- 应用名显示为 `Nolive`
- package id 为 `app.nolive.mobile`
- 首页、关注页、房间页主链路正常
- 搜索、打开房间、切换画质、切换线路、切换播放器后端正常
- 弹幕显示与屏蔽词逻辑正常
- 关注、历史、标签在重启后仍然正确
- 本地快照导入、导出、重置逻辑正常
- 中文界面在真实 Android 设备上显示正常，无明显缺字、裁切或排版异常

## Artifact Check

- `apps/main_app/build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk`
- `apps/main_app/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`
- `apps/main_app/build/app/outputs/flutter-apk/app-x86_64-release.apk`
- `apps/main_app/build/app/outputs/bundle/release/app-release.aab`

## CI / Signing

- GitHub Actions workflow: `.github/workflows/android-release.yml`
- Local signing template: `apps/main_app/android/key.properties.example`
- Release guide: `docs/android-release-guide.md`
- 当前发布流程必需 secrets：`ANDROID_KEY_PROPERTIES`、`ANDROID_KEYSTORE_BASE64`
- 仅在改用拆分字段方案时才需要：`ANDROID_KEY_ALIAS`、`ANDROID_KEY_PASSWORD`、`ANDROID_STORE_PASSWORD`
- GitHub Release 文案预览命令：`scripts/render_release_notes.sh vX.Y.Z`

## Repository Settings

- 当前仓库 `main` 尚未启用 branch protection / ruleset
- 建议至少为 `main` 禁止 force push 与删除分支
- 如果后续切换到 PR 合并流，建议要求状态检查 `android-release / verify-and-build-android` 通过
