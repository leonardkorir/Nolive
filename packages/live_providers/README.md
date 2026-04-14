# live_providers

Provider 注册与平台实现层。

## 当前职责

- Provider registry 与 reference catalog
- 当前已接入的平台 provider 实现
- 平台账号 client、Twitch playback bootstrap / manifest 等 provider 侧实现资产

## 当前导出面

- `ProviderRegistry`
- `BilibiliProvider`、`DouyinProvider`、`DouyuProvider`、`HuyaProvider`
- `ChaturbateProvider`、`TwitchProvider`、`YoutubeProvider`
- `BilibiliAccountClient`、`DouyinAccountClient`
- `TwitchPlaybackBootstrap`、`TwitchPlaybackManifest`

## 当前边界

- 本包承载纯 Dart 的 provider 契约实现、映射、解析与注册。
- app-level WebView / runtime-assisted bridge 不在本包，统一归属 `apps/main_app` 的 `app/runtime_bridges`。
