# live_player

播放器抽象与后端实现层。

## 当前职责

- `BasePlayer` 播放器抽象
- MPV / MDK / memory / simulated backend 实现
- backend 切换、播放器状态与 diagnostics 模型
- 启动清晰度策略辅助（如 `startup_quality_policy.dart` 中的网络偏好选择）

## 当前导出面

- `BasePlayer`
- `MpvPlayer`、`MdkPlayer`、`MemoryPlayer`
- `SwitchablePlayer`
- `PlayerState`、`PlayerBackend`、`PlayerDiagnostics`
- 启动画质相关 policy 工具

## 当前边界

- 本包负责播放器能力抽象和具体后端实现。
- 页面和 feature 不应直接操纵原生播放器对象；运行时装配和业务编排留在 app 层。
- 自适应 Auto 档位与平台特化（如 Twitch Auto 策略）主要由 app `features/room` 与 settings 偏好协作，不把站点逻辑塞进后端播放器。

## Android 当前说明

- Android live runtime 当前使用 `MpvPlayer` 与 `MdkPlayer` 两条真实视频渲染链路。
- 预览和测试环境保留 simulated backend。
- `MdkPlayer + fvp` 当前走 Flutter 可用的 `SurfaceProducer / SurfaceTexture` 渲染路径。
