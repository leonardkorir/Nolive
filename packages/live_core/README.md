# live_core

核心领域契约与 DTO 中心。

## 当前职责

- Provider capability / descriptor / registration 契约
- 直播房间、房间详情、清晰度、播放地址、分页结果等核心 DTO
- 弹幕消息、平台标识、provider 成熟度等跨包通用模型
- 领域错误与文本规范化基础能力

## 当前导出面

- `LiveProvider`、`ProviderCapability`、`ProviderDescriptor`
- `LiveRoom`、`LiveRoomDetail`、`LivePlayQuality`、`LivePlayUrl`
- `LiveMessage`、`LiveCategory`、`PagedResponse`
- `NoliveException`、`DisplayTextNormalizer`

## 当前边界

- 本包只承载契约、DTO 和极轻量领域基础能力。
- 不放 provider 具体实现、不放 UI 逻辑、不放运行时桥接。
