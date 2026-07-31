# Nolive

Nolive 是一个基于 Flutter 的直播聚合客户端，以 Android 为主发布目标，并提供 **Linux 桌面完整对等**（含国际站 bridge / 网页登录）。统一提供多平台直播间浏览、搜索、关注、播放和弹幕体验。

## 下载与安装

- 最新 Android 发布页：<https://github.com/leonardkorir/Nolive/releases/latest>
- 如果你是大多数近年的 Android 真机，优先下载 `app-arm64-v8a-release.apk`
- 较老的 32 位设备可尝试 `app-armeabi-v7a-release.apk`
- `app-x86_64-release.apk` 主要用于 x86_64 Android 模拟器
- **Linux 桌面**：源码构建 release bundle（见下方「Linux 桌面」）

## 当前状态

- 当前正式发布目标是 Android。
- 正式发布主目标仍是 Android（mobile first）；**Linux 桌面**在依赖齐备时可构建与 Android 主路径同能力的桌面端（平板 UI + 播放 + 国际站 WebView bridge / 登录）。
- 当前对外发布口径为多平台直播聚合客户端。
- 主应用版本见 `apps/main_app/pubspec.yaml`（当前 `0.3.10+13`）；对外版本变化见 [`CHANGELOG.md`](CHANGELOG.md) 与 GitHub Releases。

## 功能概览

- 首页、发现、搜索、关注、我的五段式主流程
- 直播间详情、清晰度 / 线路切换、播放器后端切换、自适应 Auto 画质（可设置）
- 视频弹幕 overlay、弹幕过滤和显示设置
- 关注、历史、标签和本地持久化
- WebDAV 备份、本地快照、局域网发现与分类同步
- 受控迁移包：单独迁移账号 Cookie 与 WebDAV 密码；局域网同步可在用户显式开关下附带凭证
- Android 启动画面、应用图标、PiP 与发布脚本

## 数据与同步边界

- 平台 Cookie、WebDAV 密码属于敏感凭证，默认不进入常规 snapshot、WebDAV 备份或**未开启凭证开关**的局域网同步 payload。
- 日常 snapshot 用于同步普通设置、屏蔽词、历史、关注和标签，不等于“整机克隆”。
- 跨设备迁移敏感凭证时，优先使用设置页中的「受控迁移包」（口令加密）；局域网同步的凭证附带为显式 opt-in。
- `AppBootstrap` 是 composition root；feature 页面通过 feature-scoped dependencies 获取能力，不直接依赖完整 bootstrap。

## 仓库结构

- `apps/main_app`：主应用工程
- `packages/live_core`：核心领域模型与契约
- `packages/live_providers`：各直播平台 provider 实现
- `packages/live_player`：播放器抽象与后端适配
- `packages/live_danmaku`：弹幕领域能力
- `packages/live_storage`：本地存储与持久化
- `packages/live_sync`：同步协议与数据模型
- `packages/live_hls_proxy`：LL-HLS / Twitch 等 runtime-assisted 纯 Dart 辅助（本地 loopback 等）
- `scripts/`：构建、安装、校验和 smoke 脚本

## 环境要求

- Flutter `3.38+`
- Dart `3.10+`
- Android SDK 和可用设备或模拟器
- `bash`，用于执行仓库提供的脚本

## 本地开发

```bash
flutter pub get
flutter pub run melos bootstrap
flutter pub run melos run analyze
flutter pub run melos run test
flutter pub run melos run format
```

仓库默认不附带私有 provider 夹具；部分依赖本地样本的深度回归测试会在缺少样本时自动跳过，不会阻塞 `melos run test`。

如果要运行主应用：

```bash
cd apps/main_app
flutter run -d android
```

### Linux 桌面

系统依赖与构建命令见下方；完整桌面验收以本机构建结果为准。

```bash
# 系统依赖（Debian/Ubuntu 示例）
sudo apt-get install -y clang cmake ninja-build pkg-config \
  libgtk-3-dev libsecret-1-dev libjsoncpp-dev libwebkit2gtk-4.1-dev libmpv-dev mpv

# 构建 release bundle
scripts/build_main_app.sh linux
# 运行
apps/main_app/build/linux/x64/release/bundle/nolive
```

**完整可用条件摘要**：

1. 上述系统依赖安装齐全（尤其 **libsecret** 与 **WebKitGTK 4.1**）
2. `scripts/build_main_app.sh linux` 产出 bundle
3. 默认窗口 1280×720 为平板侧栏导航
4. 国内站列表/进房可播；国际站（Twitch / YouTube / Chaturbate / Stripchat）经 WebView bridge 启用
5. 设置页网页登录可保存 Cookie；安全存储可用

如果要快速验证 provider 主链路：

```bash
cd packages/live_providers
dart run tool/smoke_live_providers.dart
```

如果要执行依赖真实远端站点的在线 smoke，可运行：

```bash
scripts/build_main_app.sh provider-live-smoke
```

## Android 构建

常用命令：

```bash
scripts/build_main_app.sh verify
scripts/build_main_app.sh provider-live-smoke
scripts/build_main_app.sh android-release-ready
scripts/install_main_app_android.sh
scripts/run_main_app_android_smoke.sh
```

更多脚本说明见 [`scripts/README.md`](scripts/README.md)。

## Android 发布

如果你是维护者并准备继续发布新版本，建议按以下顺序执行：

1. 更新 `apps/main_app/pubspec.yaml` 与 `CHANGELOG.md`
2. 执行 `scripts/build_main_app.sh verify`
3. 按需要执行 `scripts/build_main_app.sh provider-live-smoke`
4. 准备好 Android 签名材料后执行 `scripts/build_main_app.sh android-release-ready`
5. 如需真机最终验收，执行 `ANDROID_DEVICE_ID=<device-id> scripts/build_main_app.sh android-release-acceptance`
6. 预览 Release 文案：`scripts/render_release_notes.sh vX.Y.Z`
7. 推送 `main`
8. 创建并推送 tag：`vX.Y.Z`
9. 等待 GitHub Actions 自动上传 APK/AAB 到 GitHub Release

详细流程见 [`docs/android-release-guide.md`](docs/android-release-guide.md) 与 [`docs/release-checklist.md`](docs/release-checklist.md)。

## 项目来源与致谢

Nolive 的发布流程和部分功能调研，参考了以下项目与资料：

- [GH4NG/dart_simple_live](https://github.com/GH4NG/dart_simple_live)：参考其 README 组织方式、发布经验和资料整理方式。
- [SlotSun/dart_simple_live](https://github.com/SlotSun/dart_simple_live)：参考其早期 Flutter 直播聚合客户端的公开实践与多平台思路。
- [xiaoyaocz/dart_simple_live](https://github.com/xiaoyaocz/dart_simple_live) 与 [AllLive](https://github.com/xiaoyaocz/AllLive)：作为更早期的公开项目与调研线索来源。

当前仓库是 `Nolive` 的独立维护版本，不是上述仓库的官方发行版，也不与上述仓库维护者构成从属关系。

## 参考及引用

以下资料主要用于直播协议调研、弹幕实现、签名链路分析和公开项目背景了解：

- [AllLive](https://github.com/xiaoyaocz/AllLive)
- [dart_tars_protocol](https://github.com/xiaoyaocz/dart_tars_protocol.git)
- [wbt5/real-url](https://github.com/wbt5/real-url)
- [IsoaSFlus/danmaku](https://github.com/IsoaSFlus/danmaku)
- [TarsCloud/Tars](https://github.com/TarsCloud/Tars)
- [5ime/Tiktok_Signature](https://github.com/5ime/Tiktok_Signature)
- [stream-rec](https://github.com/stream-rec/stream-rec)

## 贡献

欢迎提交 issue 和 pull request。开始之前请先阅读 [`CONTRIBUTING.md`](CONTRIBUTING.md)。

## 文档

- [`CHANGELOG.md`](CHANGELOG.md)：对外版本变化记录
- [`docs/android-release-guide.md`](docs/android-release-guide.md)：Android 构建、签名与发布流程
- [`docs/release-checklist.md`](docs/release-checklist.md)：发布前核对清单
- [`CONTRIBUTING.md`](CONTRIBUTING.md)：开发与提交流程说明

## License

本仓库采用 [MIT License](LICENSE)。

## 说明

- Android 签名文件、`key.properties`、`local.properties` 等敏感材料不会进入版本控制。
- 请在使用本项目时自行遵守目标平台服务条款、当地法律和网络使用规范。
