# live_player

播放器抽象层。

当前阶段提供：

- `BasePlayer` 契约与 `PlayerState`
- `SwitchablePlayer` 后端切换入口
- 预览 / 测试环境默认使用模拟 backend
- Android 首发 live runtime 使用 `MpvPlayer` + `media_kit` 真实视频渲染
- Android live runtime 备用后端现已支持 `MdkPlayer` + `fvp` 真实纹理渲染
