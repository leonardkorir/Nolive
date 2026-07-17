# live_hls_proxy

纯 Dart 包：LL-HLS 本地 loopback、Twitch web playback / ad-guard，以及 Chaturbate / Stripchat 相关 runtime-assisted 辅助。

> 历史包 `live_shared` 已移除；原共享基础设施中与 HLS/proxy 相关的能力收敛到本包。应用层 UI 共享组件在 `apps/main_app/lib/src/shared/presentation/`。

## 当前职责

- Chaturbate LL-HLS proxy 与 web room detail loader
- Stripchat LL-HLS proxy 与 mouflon 相关 runtime 支持 / key cache
- Twitch web playback bridge、lifecycle 与 ad-guard proxy
- `HlsProxyPlatformAdapter` 抽象（由 app 提供平台实现）

## 当前导出面（见 `lib/live_hls_proxy.dart`）

- `ChaturbateLlHlsProxy`、`ChaturbateWebRoomDetailLoader`
- `StripchatLlHlsProxy`、`StripchatMouflonRuntimeSupport`、`StripchatMouflonKeyCache`
- `TwitchWebPlaybackBridge`、`TwitchAdGuardProxy`
- `HlsProxyPlatformAdapter`

## 当前边界

- 本包保持 **纯 Dart**（可依赖 `live_core` / `live_providers`），不引入 Flutter UI。
- app 通过 `apps/main_app/lib/src/app/runtime_bridges/` 装配 `AppRuntimeBridges`，并注入平台 adapter（如 `hls_proxy_platform_adapter_impl.dart`）。
- 不要把本包逻辑搬回 `features/room/application` 堆叠，也不要把 WebView UI 写进本包。
