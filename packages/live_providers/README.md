# live_providers

Provider 注册与平台实现层。

## 当前职责

- Provider registry 与 reference catalog
- 当前已接入的平台 provider 实现（纯 Dart）
- 平台账号 client、Twitch playback bootstrap / manifest 等 provider 侧实现资产
- 部分平台弹幕 session 的 Dart 实现

## 当前已接入平台

| Provider | 说明 |
| --- | --- |
| `BilibiliProvider` | 国内平台 |
| `DouyinProvider` | 国内平台 |
| `DouyuProvider` | 国内平台 |
| `HuyaProvider` | 国内平台 |
| `ChaturbateProvider` | 国际平台；LL-HLS / web 辅助见 `live_hls_proxy` |
| `TwitchProvider` | 国际平台；web playback / ad-guard 见 `live_hls_proxy` |
| `YoutubeProvider` | 国际平台；nsig 等求解可经 app `runtime_bridges` |
| `StripchatProvider` | 国际平台；LL-HLS / mouflon 辅助见 `live_hls_proxy` 与 app settings store |

实现存在不等于产品对外逐项承诺；发布口径以根 `README.md` / `CHANGELOG` 为准。

## 当前导出面

- `ProviderRegistry`
- 上述各 `*Provider`
- `BilibiliAccountClient`、`DouyinAccountClient`
- `TwitchPlaybackBootstrap`、`TwitchPlaybackManifest` 等 Twitch 侧资产
- `ReferenceProviderCatalog` 等注册辅助

## 当前边界

- 本包承载纯 Dart 的 provider 契约实现、映射、解析与注册。
- app-level WebView、平台通道、以及需 loopback 的 runtime-assisted 能力不在本包长期堆积：
  - 可纯 Dart 的 proxy / bridge → `packages/live_hls_proxy`
  - 需 Flutter/WebView 装配 → `apps/main_app` 的 `app/runtime_bridges`
- 测试中依赖本地 HAR/HTML 夹具的用例在缺少样本时可跳过；见 `FixtureLoader.skipReason` 与 fixture skip 契约测试。
