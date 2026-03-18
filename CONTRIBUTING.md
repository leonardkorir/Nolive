# Contributing

感谢你关注 Nolive。

这个仓库当前以 Android 为主要发布目标，欢迎针对稳定性、播放体验、弹幕体验、provider 适配和工程质量提交 issue 或 pull request。

## 开发环境

建议使用以下环境：

- Flutter `3.35+`
- Dart `3.6+`
- Android SDK
- `bash`

本仓库是一个由 `melos` 管理的 monorepo。

## 仓库结构

- `apps/main_app`：主应用
- `packages/live_core`：领域契约
- `packages/live_providers`：平台 provider 实现
- `packages/live_player`：播放器抽象与后端适配
- `packages/live_danmaku`：弹幕相关能力
- `packages/live_storage`：本地存储
- `packages/live_sync`：同步相关模型与协议
- `packages/live_shared`：共享基础设施

## 开始开发

```bash
flutter pub get
flutter pub run melos bootstrap
flutter pub run melos run analyze
flutter pub run melos run test
flutter pub run melos run format
```

公开仓默认不附带私有 provider fixture。依赖本地私有样本的深度回归测试会在缺少样本时自动跳过，不影响常规 `test`。

如果要启动主应用：

```bash
cd apps/main_app
flutter run -d android
```

如果要验证 provider 主链路：

```bash
cd packages/live_providers
dart run tool/smoke_live_providers.dart
```

如果要补充依赖真实远端站点的在线 smoke，请单独执行：

```bash
scripts/build_main_app.sh provider-live-smoke
```

## 提交前要求

- 保持包边界清晰，不要把 provider、播放器、存储逻辑直接揉进页面层。
- 新功能或修复应补充对应测试，至少不要降低现有测试覆盖的有效性。
- 提交前运行 `analyze`、`test`、`format`。
- 依赖真实远端站点的 `provider-live-smoke` 不是 hermetic 校验；仅在合适网络环境下作为补充检查执行。
- 涉及用户可见行为变化时，同步更新 `README.md` 或 `CHANGELOG.md`。
- 大改动建议先开 issue 或先说明设计意图，避免方向性返工。

## 不要提交的内容

以下内容禁止提交到仓库：

- `key.properties`
- `local.properties`
- `*.jks`
- `*.keystore`
- 本地导出的配置或快照 JSON 文件
- 设备日志、测试缓存、构建产物

## Pull Request

提交 PR 时，建议说明以下内容：

- 改动解决了什么问题
- 是否影响播放、弹幕、关注、搜索等主链路
- 是否补了测试
- 是否需要人工验证，验证步骤是什么

## 协作规则

- 协作行为请遵守 `CODE_OF_CONDUCT.md`
- 安全问题请优先阅读 `SECURITY.md`
