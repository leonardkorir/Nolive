import 'dart:async';

import 'package:live_core/live_core.dart';

class ProviderUnavailableDanmakuSession implements DanmakuSession {
  ProviderUnavailableDanmakuSession({
    required this.reason,
  });

  final String reason;

  final StreamController<LiveMessage> _controller =
      StreamController<LiveMessage>.broadcast();

  bool _connected = false;

  @override
  Stream<LiveMessage> get messages => _controller.stream;

  @override
  Future<void> connect() async {
    if (_connected) {
      return;
    }
    _connected = true;
    if (reason.trim().isEmpty) {
      return;
    }
    _controller.add(
      LiveMessage(
        type: LiveMessageType.notice,
        userName: 'LiveSysMessage',
        content: reason.trim(),
        timestamp: DateTime.now(),
      ),
    );
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
    if (!_controller.isClosed) {
      await _controller.close();
    }
  }
}
