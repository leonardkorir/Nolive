# live_danmaku

弹幕过滤领域包。

## 当前职责

- Dart 实现的弹幕过滤配置
- 批量遮罩与过滤服务
- 面向房间消息流的纯领域过滤能力

## 当前导出面

- `DanmakuFilterConfig`
- `DanmakuFilterService`
- `DanmakuBatchMask`

## 当前边界

- 本包只处理弹幕过滤领域逻辑。
- 不承载 websocket/session 接入，不承载 overlay/UI 渲染。
