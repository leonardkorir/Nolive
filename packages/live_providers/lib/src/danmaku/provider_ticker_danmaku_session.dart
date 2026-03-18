import 'dart:async';

import 'package:live_core/live_core.dart';

class ProviderTickerDanmakuSession implements DanmakuSession {
  ProviderTickerDanmakuSession({
    required this.providerId,
    required this.detail,
  });

  final String providerId;
  final LiveRoomDetail detail;

  final StreamController<LiveMessage> _controller =
      StreamController<LiveMessage>.broadcast();

  Timer? _timer;
  bool _connected = false;
  int _tick = 0;

  static const List<String> _userNames = [
    '直播观众A',
    '追更用户',
    '老粉丝',
    '移动端用户',
    '弹幕同学',
  ];

  @override
  Stream<LiveMessage> get messages => _controller.stream;

  @override
  Future<void> connect() async {
    if (_connected) {
      return;
    }
    _connected = true;
    _emit(
      LiveMessage(
        type: LiveMessageType.notice,
        content: '${detail.streamerName} 的 $providerId 弹幕已连接',
        timestamp: DateTime.now(),
      ),
    );
    _timer = Timer.periodic(const Duration(milliseconds: 700), (_) {
      _tick += 1;
      _emit(_nextMessage());
    });
  }

  @override
  Future<void> disconnect() async {
    _timer?.cancel();
    _timer = null;
    _connected = false;
    if (!_controller.isClosed) {
      await _controller.close();
    }
  }

  LiveMessage _nextMessage() {
    final timestamp = DateTime.now();
    final userName = _userNames[_tick % _userNames.length];
    if (_tick % 5 == 0) {
      return LiveMessage(
        type: LiveMessageType.online,
        content:
            '当前人气 ${detail.viewerCount ?? 0} · ${detail.areaName ?? '未标注分区'}',
        timestamp: timestamp,
      );
    }
    if (_tick % 7 == 0) {
      return LiveMessage(
        type: LiveMessageType.gift,
        userName: userName,
        content: '送出了一份支持，继续冲！',
        timestamp: timestamp,
      );
    }
    return LiveMessage(
      type: LiveMessageType.chat,
      userName: userName,
      content: _chatLineForTick(_tick),
      timestamp: timestamp,
    );
  }

  String _chatLineForTick(int tick) {
    final lines = [
      '房间页现在切换起来顺手多了。',
      '分类、搜索和播放器的交互统一了。',
      '这个直播间已经能跑完整主链路。',
      '后端切换入口现在更直观了。',
      '弹幕过滤已经生效了。',
    ];
    return lines[tick % lines.length];
  }

  void _emit(LiveMessage message) {
    if (_controller.isClosed) {
      return;
    }
    _controller.add(message);
  }
}
