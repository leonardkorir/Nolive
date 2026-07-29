import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:brotli/brotli.dart';
import 'package:fixnum/fixnum.dart' as fixnum;
import 'package:live_core/live_core.dart';

import 'proto/douyin.pb.dart';
import 'tars/codec/tars_input_stream.dart';
import 'tars/huya_danmaku.dart';

abstract class IsolateDanmakuSession extends DanmakuSession {
  final StreamController<LiveMessage> _controller =
      StreamController<LiveMessage>.broadcast();
  final _DanmakuParserWorker _parserWorker = _DanmakuParserWorker();
  Future<void> _parseQueue = Future<void>.value();

  @override
  Stream<LiveMessage> get messages => _controller.stream;

  Future<void> parseInWorker(
    String parserId,
    Uint8List bytes,
    void Function(DanmakuIsolateParseOutput output) onOutput,
  ) {
    final task = _parseQueue.then((_) async {
      final output = await _parserWorker.parse(parserId, bytes);
      if (!_controller.isClosed) {
        onOutput(output);
      }
    });
    _parseQueue = task.catchError((_) {});
    return task;
  }

  void emit(LiveMessage message) {
    if (_controller.isClosed) {
      return;
    }
    _controller.add(message);
  }

  void emitNotice(String content) {
    emit(
      LiveMessage(
        type: LiveMessageType.notice,
        content: content,
        timestamp: DateTime.now(),
      ),
    );
  }

  void emitParsedMessages(DanmakuIsolateParseOutput output) {
    for (final message in output.messages) {
      emit(message);
    }
  }

  Future<void> closeIsolateDanmakuSession() async {
    await _parserWorker.dispose();
    if (!_controller.isClosed) {
      await _controller.close();
    }
  }
}

class DanmakuIsolateParserIds {
  static const String douyin = 'douyin';
  static const String bilibili = 'bilibili';
  static const String huya = 'huya';
}

class DanmakuIsolateCommand {
  const DanmakuIsolateCommand(this.kind, {this.bytes, this.message});

  final String kind;
  final Uint8List? bytes;
  final String? message;
}

class DanmakuIsolateCommands {
  static const String douyinAck = 'douyinAck';
  static const String bilibiliJoinAckOk = 'bilibiliJoinAckOk';
  static const String bilibiliJoinAckFailed = 'bilibiliJoinAckFailed';
  static const String bilibiliAuthorized = 'bilibiliAuthorized';
}

class DanmakuIsolateParseOutput {
  const DanmakuIsolateParseOutput({
    this.messages = const <LiveMessage>[],
    this.commands = const <DanmakuIsolateCommand>[],
  });

  final List<LiveMessage> messages;
  final List<DanmakuIsolateCommand> commands;

  factory DanmakuIsolateParseOutput.fromWire(Map<Object?, Object?> wire) {
    final messages = <LiveMessage>[];
    final rawMessages = wire['messages'];
    if (rawMessages is List) {
      for (final raw in rawMessages) {
        if (raw is Map) {
          messages.add(_messageFromWire(raw.cast<Object?, Object?>()));
        }
      }
    }
    final commands = <DanmakuIsolateCommand>[];
    final rawCommands = wire['commands'];
    if (rawCommands is List) {
      for (final raw in rawCommands) {
        if (raw is Map) {
          final command = raw.cast<Object?, Object?>();
          final bytes = command['bytes'];
          commands.add(
            DanmakuIsolateCommand(
              command['kind']?.toString() ?? '',
              bytes: bytes is Uint8List
                  ? bytes
                  : bytes is List<int>
                  ? Uint8List.fromList(bytes)
                  : null,
              message: command['message']?.toString(),
            ),
          );
        }
      }
    }
    return DanmakuIsolateParseOutput(messages: messages, commands: commands);
  }

  static LiveMessage _messageFromWire(Map<Object?, Object?> wire) {
    final typeName = wire['type']?.toString() ?? LiveMessageType.notice.name;
    final type = LiveMessageType.values.firstWhere(
      (candidate) => candidate.name == typeName,
      orElse: () => LiveMessageType.notice,
    );
    return LiveMessage(
      type: type,
      content: wire['content']?.toString() ?? '',
      userName: wire['userName']?.toString(),
      timestamp: DateTime.now(),
      payload: wire['payload'],
    );
  }
}

class _DanmakuParserWorker {
  Isolate? _isolate;
  ReceivePort? _receivePort;
  SendPort? _workerPort;
  Future<SendPort>? _startup;
  Completer<SendPort>? _startupCompleter;
  final Map<int, Completer<DanmakuIsolateParseOutput>> _pending =
      <int, Completer<DanmakuIsolateParseOutput>>{};
  int _nextRequestId = 0;
  bool _disposed = false;
  bool _workerCounted = false;

  Future<DanmakuIsolateParseOutput> parse(
    String parserId,
    Uint8List bytes,
  ) async {
    if (_disposed) {
      throw StateError('Danmaku parser worker has been disposed.');
    }
    final port = await _ensureStarted();
    final requestId = _nextRequestId++;
    final completer = Completer<DanmakuIsolateParseOutput>();
    _pending[requestId] = completer;
    port.send(<Object?>[
      _DanmakuParserProtocol.parse,
      requestId,
      parserId,
      bytes,
    ]);
    return completer.future;
  }

  Future<void> dispose() async {
    _disposed = true;
    _workerPort?.send(<Object?>[_DanmakuParserProtocol.dispose]);
    _receivePort?.close();
    _isolate?.kill(priority: Isolate.immediate);
    _markWorkerStopped();
    _isolate = null;
    _receivePort = null;
    _workerPort = null;
    _startup = null;
    _startupCompleter = null;
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(
          StateError('Danmaku parser worker has been disposed.'),
        );
      }
    }
    _pending.clear();
  }

  void _markWorkerStopped() {
    if (!_workerCounted) {
      return;
    }
    _workerCounted = false;
    NfrIsolateTelemetry.markStopped(
      'danmaku-parser-worker',
      detail: 'pending=${_pending.length}',
    );
  }

  Future<SendPort> _ensureStarted() {
    final existingPort = _workerPort;
    if (existingPort != null) {
      return Future<SendPort>.value(existingPort);
    }
    final existingStartup = _startup;
    if (existingStartup != null) {
      return existingStartup;
    }
    final receivePort = ReceivePort();
    _receivePort = receivePort;
    receivePort.listen(_handleMessage);
    final completer = Completer<SendPort>();
    _startupCompleter = completer;
    _startup = completer.future;
    _workerCounted = true;
    NfrIsolateTelemetry.markStarted('danmaku-parser-worker');
    Isolate.spawn(
      _runDanmakuParserWorker,
      receivePort.sendPort,
      debugName: 'danmaku-parser-worker',
    ).then(
      (isolate) {
        _isolate = isolate;
      },
      onError: (Object error, StackTrace stackTrace) {
        _startup = null;
        _startupCompleter = null;
        _workerCounted = false;
        NfrIsolateTelemetry.markFailed('danmaku-parser-worker', error);
        receivePort.close();
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      },
    );
    return completer.future;
  }

  void _handleMessage(Object? message) {
    if (message is! List<Object?> || message.isEmpty) {
      return;
    }
    final type = message[0];
    if (type == _DanmakuParserProtocol.ready &&
        message.length >= 2 &&
        message[1] is SendPort) {
      final port = message[1] as SendPort;
      _workerPort = port;
      NfrIsolateTelemetry.markReady(
        'danmaku-parser-worker',
        detail: 'pending=${_pending.length}',
      );
      final completer = _startupCompleter;
      _startupCompleter = null;
      _startup = null;
      if (completer != null && !completer.isCompleted) {
        completer.complete(port);
      }
      return;
    }
    if (type != _DanmakuParserProtocol.result ||
        message.length < 4 ||
        message[1] is! int ||
        message[2] is! bool) {
      return;
    }
    final requestId = message[1] as int;
    final completer = _pending.remove(requestId);
    if (completer == null || completer.isCompleted) {
      return;
    }
    if (message[2] as bool) {
      final payload = message[3];
      if (payload is Map) {
        completer.complete(
          DanmakuIsolateParseOutput.fromWire(payload.cast<Object?, Object?>()),
        );
      } else {
        completer.complete(const DanmakuIsolateParseOutput());
      }
    } else {
      completer.completeError(
        StateError(message[3]?.toString() ?? 'parse failed'),
      );
    }
  }
}

class _DanmakuParserProtocol {
  static const String ready = 'ready';
  static const String parse = 'parse';
  static const String result = 'result';
  static const String dispose = 'dispose';
}

void _runDanmakuParserWorker(SendPort hostPort) {
  final commandPort = ReceivePort();
  hostPort.send(<Object?>[_DanmakuParserProtocol.ready, commandPort.sendPort]);
  commandPort.listen((message) {
    if (message is! List<Object?> || message.isEmpty) {
      return;
    }
    if (message[0] == _DanmakuParserProtocol.dispose) {
      commandPort.close();
      return;
    }
    if (message.length < 4 ||
        message[0] != _DanmakuParserProtocol.parse ||
        message[1] is! int ||
        message[2] is! String) {
      return;
    }
    final requestId = message[1] as int;
    try {
      final bytes = _wireBytes(message[3]);
      final output = switch (message[2] as String) {
        DanmakuIsolateParserIds.douyin => _parseDouyin(bytes),
        DanmakuIsolateParserIds.bilibili => _parseBilibili(bytes),
        DanmakuIsolateParserIds.huya => _parseHuya(bytes),
        _ => const <Object?, Object?>{},
      };
      hostPort.send(<Object?>[
        _DanmakuParserProtocol.result,
        requestId,
        true,
        output,
      ]);
    } catch (error) {
      hostPort.send(<Object?>[
        _DanmakuParserProtocol.result,
        requestId,
        false,
        error.toString(),
      ]);
    }
  });
}

Uint8List _wireBytes(Object? raw) {
  if (raw is Uint8List) {
    return raw;
  }
  if (raw is List<int>) {
    return Uint8List.fromList(raw);
  }
  return Uint8List(0);
}

Map<Object?, Object?> _parseDouyin(Uint8List bytes) {
  try {
    final frame = PushFrame.fromBuffer(bytes);
    final payload = gzip.decode(frame.payload);
    final response = Response.fromBuffer(payload);
    final commands = <Map<Object?, Object?>>[];
    if (response.needAck) {
      final ackFrame = PushFrame()
        ..payloadType = 'ack'
        ..logId = fixnum.Int64(frame.logId.toInt())
        ..payload = utf8.encode(response.internalExt);
      commands.add(<Object?, Object?>{
        'kind': DanmakuIsolateCommands.douyinAck,
        'bytes': Uint8List.fromList(ackFrame.writeToBuffer()),
      });
    }
    final messages = <Map<Object?, Object?>>[];
    for (final message in response.messagesList) {
      switch (message.method) {
        case 'WebcastChatMessage':
          final chat = ChatMessage.fromBuffer(message.payload);
          if (chat.content.isNotEmpty) {
            messages.add(
              _messageWire(
                LiveMessageType.chat,
                chat.content,
                userName: chat.user.nickName,
              ),
            );
          }
        case 'WebcastRoomUserSeqMessage':
          final online = RoomUserSeqMessage.fromBuffer(message.payload);
          messages.add(
            _messageWire(
              LiveMessageType.online,
              '当前人气 ${online.totalUser}',
              payload: online.totalUser,
            ),
          );
      }
    }
    return <Object?, Object?>{'messages': messages, 'commands': commands};
  } catch (error) {
    return <Object?, Object?>{
      'messages': <Map<Object?, Object?>>[
        _messageWire(LiveMessageType.notice, '抖音弹幕解析失败：$error'),
      ],
    };
  }
}

Map<Object?, Object?> _parseBilibili(Uint8List bytes) {
  final messages = <Map<Object?, Object?>>[];
  final commands = <Map<Object?, Object?>>[];
  late void Function(Uint8List packetBytes) parsePackets;

  void parseJsonMessage(String text) {
    final decoded = jsonDecode(text);
    if (decoded is! Map) {
      return;
    }
    final obj = decoded.cast<String, dynamic>();
    final cmd = obj['cmd']?.toString() ?? '';
    if (cmd.contains('DANMU_MSG')) {
      final info = obj['info'];
      if (info is List && info.length > 2) {
        final content = decodeHtmlEntities(info[1]?.toString() ?? '');
        final userName = (info[2] is List && (info[2] as List).length > 1)
            ? info[2][1]?.toString()
            : null;
        if (content.isNotEmpty) {
          messages.add(
            _messageWire(LiveMessageType.chat, content, userName: userName),
          );
        }
      }
      return;
    }
    if (cmd == 'SUPER_CHAT_MESSAGE') {
      final data = obj['data'];
      if (data is Map) {
        messages.add(
          _messageWire(
            LiveMessageType.superChat,
            data['message']?.toString() ?? '醒目留言',
            userName: data['user_info'] is Map
                ? (data['user_info'] as Map)['uname']?.toString()
                : null,
            payload: data.cast<Object?, Object?>(),
          ),
        );
      }
      return;
    }
    if (cmd == 'SEND_GIFT') {
      final data = obj['data'];
      if (data is Map) {
        messages.add(
          _messageWire(
            LiveMessageType.gift,
            '送出了 ${data['giftName']?.toString() ?? '礼物'}',
            userName: data['uname']?.toString(),
            payload: data.cast<Object?, Object?>(),
          ),
        );
      }
      return;
    }
    if (cmd == 'INTERACT_WORD' || cmd == 'ENTRY_EFFECT') {
      final data = obj['data'];
      final userName = data is Map ? data['uname']?.toString() : null;
      messages.add(
        _messageWire(
          LiveMessageType.member,
          '${userName ?? '用户'} 进入了直播间',
          userName: userName,
          payload: data is Map ? data.cast<Object?, Object?>() : data,
        ),
      );
      return;
    }
    if (cmd == 'NOTICE_MSG') {
      final data = obj['msg_common']?.toString() ?? obj['msg_self']?.toString();
      if (data != null && data.isNotEmpty) {
        messages.add(_messageWire(LiveMessageType.notice, data));
      }
    }
  }

  void parsePacket(Uint8List packet) {
    final protocolVersion = _readBilibiliInt(packet, 6, 2);
    final operation = _readBilibiliInt(packet, 8, 4);
    final body = packet.sublist(16);
    if (operation == 8) {
      final failureMessage = _parseBilibiliJoinAckFailure(body);
      commands.add(<Object?, Object?>{
        'kind': failureMessage == null
            ? DanmakuIsolateCommands.bilibiliJoinAckOk
            : DanmakuIsolateCommands.bilibiliJoinAckFailed,
        if (failureMessage != null) 'message': failureMessage,
      });
      return;
    }
    if (operation == 3 && body.length >= 4) {
      commands.add(<Object?, Object?>{
        'kind': DanmakuIsolateCommands.bilibiliAuthorized,
      });
      messages.add(
        _messageWire(
          LiveMessageType.online,
          '当前人气 ${_readBilibiliInt(body, 0, 4)}',
        ),
      );
      return;
    }
    if (operation != 5) {
      return;
    }
    commands.add(<Object?, Object?>{
      'kind': DanmakuIsolateCommands.bilibiliAuthorized,
    });
    if (protocolVersion == 2) {
      final decoded = _decodeCompressedBilibiliBody(body, zlib.decoder);
      if (decoded != null) {
        parsePackets(decoded);
      }
      return;
    }
    if (protocolVersion == 3) {
      final decoded = _decodeCompressedBilibiliBody(body, brotli.decoder);
      if (decoded != null) {
        parsePackets(decoded);
      }
      return;
    }
    final text = utf8.decode(body, allowMalformed: true);
    final groups = text
        .split(RegExp(r'[\x00-\x1f]+', unicode: true, multiLine: true))
        .where((item) => item.length > 2 && item.trim().startsWith('{'));
    for (final item in groups) {
      try {
        parseJsonMessage(item);
      } catch (_) {}
    }
  }

  parsePackets = (Uint8List packetBytes) {
    var offset = 0;
    while (offset + 16 <= packetBytes.length) {
      final packetLength = _readBilibiliInt(packetBytes, offset, 4);
      if (packetLength <= 0 || offset + packetLength > packetBytes.length) {
        break;
      }
      parsePacket(packetBytes.sublist(offset, offset + packetLength));
      offset += packetLength;
    }
  };

  parsePackets(bytes);
  return <Object?, Object?>{'messages': messages, 'commands': commands};
}

Map<Object?, Object?> _parseHuya(Uint8List bytes) {
  try {
    var input = TarsInputStream(bytes);
    final type = input.read(0, 0, false);
    if (type != 7) {
      return const <Object?, Object?>{};
    }
    input = TarsInputStream(input.readBytes(1, false));
    final pushMessage = HYPushMessage()..readFrom(input);
    if (pushMessage.uri == 1400) {
      final message = HYMessage();
      message.readFrom(TarsInputStream(Uint8List.fromList(pushMessage.msg)));
      return <Object?, Object?>{
        'messages': <Map<Object?, Object?>>[
          _messageWire(
            LiveMessageType.chat,
            message.content,
            userName: message.userInfo.nickName,
          ),
        ],
      };
    }
    if (pushMessage.uri == 8006) {
      final onlineStream = TarsInputStream(Uint8List.fromList(pushMessage.msg));
      final online = onlineStream.read(0, 0, false);
      return <Object?, Object?>{
        'messages': <Map<Object?, Object?>>[
          _messageWire(LiveMessageType.online, '当前人气 $online', payload: online),
        ],
      };
    }
    return const <Object?, Object?>{};
  } catch (error) {
    return <Object?, Object?>{
      'messages': <Map<Object?, Object?>>[
        _messageWire(LiveMessageType.notice, '虎牙弹幕解析失败：$error'),
      ],
    };
  }
}

Map<Object?, Object?> _messageWire(
  LiveMessageType type,
  String content, {
  String? userName,
  Object? payload,
}) {
  return <Object?, Object?>{
    'type': type.name,
    'content': content,
    if (userName != null) 'userName': userName,
    if (payload != null) 'payload': payload,
  };
}

Uint8List? _decodeCompressedBilibiliBody(
  Uint8List body,
  Converter<List<int>, List<int>> decoder,
) {
  const maxCompressedBodyBytes = 2 * 1024 * 1024;
  const maxDecodedBodyBytes = 4 * 1024 * 1024;
  if (body.length > maxCompressedBodyBytes) {
    return null;
  }
  try {
    final decoded = decoder.convert(body);
    if (decoded.length > maxDecodedBodyBytes) {
      return null;
    }
    return Uint8List.fromList(decoded);
  } catch (_) {
    return null;
  }
}

String? _parseBilibiliJoinAckFailure(Uint8List body) {
  if (body.isEmpty) {
    return null;
  }
  final raw = utf8.decode(body, allowMalformed: true).trim();
  if (raw.isNotEmpty) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        final code = _toInt(decoded['code']);
        if (code == 0) {
          return null;
        }
        return 'Bilibili 弹幕鉴权失败 code=$code';
      }
    } catch (_) {}
  }
  if (body.length == 4 && _readBilibiliInt(body, 0, 4) == 0) {
    return null;
  }
  return 'Bilibili 弹幕鉴权失败';
}

int _readBilibiliInt(Uint8List bytes, int offset, int length) {
  final data = ByteData.sublistView(bytes, offset, offset + length);
  return switch (length) {
    2 => data.getUint16(0, Endian.big),
    4 => data.getUint32(0, Endian.big),
    _ => 0,
  };
}

int _toInt(Object? value) {
  if (value is int) {
    return value;
  }
  return int.tryParse(value?.toString() ?? '') ?? 0;
}
