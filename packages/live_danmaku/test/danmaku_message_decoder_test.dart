import 'dart:convert';
import 'dart:typed_data';
import 'package:live_core/live_core.dart';
import 'package:test/test.dart';

// Decoders logic to test parsing of multiple serialization schemes

class JsonDanmakuDecoder {
  static LiveMessage decode(String jsonStr) {
    final parsed = jsonDecode(jsonStr);
    if (parsed is! Map) {
      throw const FormatException('Expected JSON Object');
    }
    final typeStr = parsed['type']?.toString();
    final type = switch (typeStr) {
      'chat' => LiveMessageType.chat,
      'gift' => LiveMessageType.gift,
      'member' => LiveMessageType.member,
      _ => throw FormatException('Unknown message type: $typeStr'),
    };
    return LiveMessage(
      type: type,
      userName: parsed['user']?.toString() ?? '',
      content: parsed['content']?.toString() ?? '',
    );
  }
}

class TextDanmakuDecoder {
  static LiveMessage decode(String text) {
    if (text.isEmpty) {
      throw const FormatException('Empty text message');
    }
    final idx = text.indexOf(':');
    if (idx == -1) {
      throw const FormatException('Delimiter missing');
    }
    return LiveMessage(
      type: LiveMessageType.chat,
      userName: text.substring(0, idx),
      content: text.substring(idx + 1),
    );
  }
}

class ProtoBufDanmakuDecoder {
  // Let's mock a simple protobuf decoder:
  // Field 1 (Varint): Type (1 = Chat, 2 = Gift)
  // Field 2 (Length-delimited): User name
  // Field 3 (Length-delimited): Message content
  static LiveMessage decode(Uint8List bytes) {
    if (bytes.isEmpty) {
      throw const FormatException('Empty protobuf payload');
    }
    var pos = 0;
    LiveMessageType? type;
    String userName = '';
    String content = '';

    while (pos < bytes.length) {
      final tag = bytes[pos++];
      final fieldNum = tag >> 3;
      final wireType = tag & 0x07;

      if (fieldNum == 1 && wireType == 0) {
        // Varint
        if (pos >= bytes.length) {
          throw const FormatException('Truncated varint');
        }
        final val = bytes[pos++];
        type = switch (val) {
          1 => LiveMessageType.chat,
          2 => LiveMessageType.gift,
          _ => throw FormatException('Unsupported protobuf message type: $val'),
        };
      } else if (fieldNum == 2 && wireType == 2) {
        // Length-delimited
        if (pos >= bytes.length) {
          throw const FormatException('Truncated length');
        }
        final len = bytes[pos++];
        if (pos + len > bytes.length) {
          throw const FormatException('Truncated string payload');
        }
        userName = utf8.decode(bytes.sublist(pos, pos + len));
        pos += len;
      } else if (fieldNum == 3 && wireType == 2) {
        // Length-delimited
        if (pos >= bytes.length) {
          throw const FormatException('Truncated length');
        }
        final len = bytes[pos++];
        if (pos + len > bytes.length) {
          throw const FormatException('Truncated string payload');
        }
        content = utf8.decode(bytes.sublist(pos, pos + len));
        pos += len;
      } else {
        // Skip unknown field
        if (wireType == 0) {
          pos++;
        } else if (wireType == 2) {
          if (pos >= bytes.length) {
            throw const FormatException('Truncated length');
          }
          final len = bytes[pos++];
          pos += len;
        } else {
          throw FormatException('Unsupported wire type: $wireType');
        }
      }
    }

    if (type == null) {
      throw const FormatException('Missing required type field');
    }

    return LiveMessage(type: type, userName: userName, content: content);
  }
}

class TarsDanmakuDecoder {
  // Let's mock a simple Tars binary decoder:
  // Tag 1 (INT32): packet length
  // Tag 2 (INT16): message type (1 = Chat, 2 = Gift)
  // Tag 3 (STRING): username
  // Tag 4 (STRING): content
  static LiveMessage decode(Uint8List bytes) {
    if (bytes.length < 4) {
      throw const FormatException('Tars payload too small');
    }
    final view = ByteData.sublistView(bytes);
    final packetLength = view.getInt32(0, Endian.big);
    if (packetLength != bytes.length) {
      throw const FormatException('Tars packet length mismatch');
    }

    var pos = 4;
    LiveMessageType? type;
    String userName = '';
    String content = '';

    while (pos < bytes.length) {
      final head = bytes[pos++];
      final tag = head >> 4;
      final typeId = head & 0x0F;

      if (tag == 2 && typeId == 0) {
        // INT16 (represented as 2 bytes in Tars for simplicity)
        if (pos + 2 > bytes.length) {
          throw const FormatException('Tars INT16 truncated');
        }
        final val = ByteData.sublistView(
          bytes,
          pos,
          pos + 2,
        ).getInt16(0, Endian.big);
        type = switch (val) {
          1 => LiveMessageType.chat,
          2 => LiveMessageType.gift,
          _ => throw FormatException('Unsupported Tars message type: $val'),
        };
        pos += 2;
      } else if (tag == 3 && typeId == 6) {
        // STRING1 (1 byte length)
        if (pos >= bytes.length) {
          throw const FormatException('Tars STRING1 len truncated');
        }
        final len = bytes[pos++];
        if (pos + len > bytes.length) {
          throw const FormatException('Tars STRING1 body truncated');
        }
        userName = utf8.decode(bytes.sublist(pos, pos + len));
        pos += len;
      } else if (tag == 4 && typeId == 6) {
        // STRING1 (1 byte length)
        if (pos >= bytes.length) {
          throw const FormatException('Tars STRING1 len truncated');
        }
        final len = bytes[pos++];
        if (pos + len > bytes.length) {
          throw const FormatException('Tars STRING1 body truncated');
        }
        content = utf8.decode(bytes.sublist(pos, pos + len));
        pos += len;
      } else {
        throw FormatException('Unsupported Tars tag or type: $tag, $typeId');
      }
    }

    if (type == null) {
      throw const FormatException('Tars payload missing type field');
    }

    return LiveMessage(type: type, userName: userName, content: content);
  }
}

void main() {
  group('Danmaku Message Decoder tests', () {
    group('JSON Decoder Group', () {
      test('successfully decodes valid json message', () {
        final raw = '{"type": "chat", "user": "Bob", "content": "Hello!"}';
        final msg = JsonDanmakuDecoder.decode(raw);
        expect(msg.type, LiveMessageType.chat);
        expect(msg.userName, 'Bob');
        expect(msg.content, 'Hello!');
      });

      test('throws FormatException on malformed json or missing field', () {
        expect(
          () => JsonDanmakuDecoder.decode('{invalid json}'),
          throwsFormatException,
        );
        expect(
          () => JsonDanmakuDecoder.decode('{"type": "unknown"}'),
          throwsFormatException,
        );
      });
    });

    group('Text Decoder Group', () {
      test('successfully decodes plain text message', () {
        final raw = 'System:Welcome back!';
        final msg = TextDanmakuDecoder.decode(raw);
        expect(msg.type, LiveMessageType.chat);
        expect(msg.userName, 'System');
        expect(msg.content, 'Welcome back!');
      });

      test('throws FormatException on invalid text formats', () {
        expect(() => TextDanmakuDecoder.decode(''), throwsFormatException);
        expect(
          () => TextDanmakuDecoder.decode('NoDelimiterHere'),
          throwsFormatException,
        );
      });
    });

    group('ProtoBuf Decoder Group', () {
      test('successfully decodes valid protobuf payload', () {
        final userNameBytes = utf8.encode('Charlie');
        final contentBytes = utf8.encode('PB works');
        final builder = BytesBuilder()
          ..addByte((1 << 3) | 0) // Tag 1 (type varint)
          ..addByte(1) // Value 1 (chat)
          ..addByte((2 << 3) | 2) // Tag 2 (username length-delimited)
          ..addByte(userNameBytes.length)
          ..add(userNameBytes)
          ..addByte((3 << 3) | 2) // Tag 3 (content length-delimited)
          ..addByte(contentBytes.length)
          ..add(contentBytes);

        final msg = ProtoBufDanmakuDecoder.decode(builder.toBytes());
        expect(msg.type, LiveMessageType.chat);
        expect(msg.userName, 'Charlie');
        expect(msg.content, 'PB works');
      });

      test(
        'throws FormatException on corrupted/truncated protobuf payload',
        () {
          expect(
            () => ProtoBufDanmakuDecoder.decode(Uint8List(0)),
            throwsFormatException,
          );
          expect(
            () => ProtoBufDanmakuDecoder.decode(
              Uint8List.fromList([1 << 3 | 0]),
            ), // tag but no value
            throwsFormatException,
          );
        },
      );
    });

    group('Tars Decoder Group', () {
      test('successfully decodes valid Tars packet', () {
        final userNameBytes = utf8.encode('David');
        final contentBytes = utf8.encode('Tars parsed');

        final payloadBuilder = BytesBuilder()
          ..addByte((2 << 4) | 0) // Tag 2, Type 0 (INT16)
          ..add([0, 1]) // Value 1 (chat)
          ..addByte((3 << 4) | 6) // Tag 3, Type 6 (STRING1)
          ..addByte(userNameBytes.length)
          ..add(userNameBytes)
          ..addByte((4 << 4) | 6) // Tag 4, Type 6 (STRING1)
          ..addByte(contentBytes.length)
          ..add(contentBytes);

        final payload = payloadBuilder.toBytes();
        final totalLen = 4 + payload.length;

        final packet = BytesBuilder();
        final lenBytes = ByteData(4)..setInt32(0, totalLen, Endian.big);
        packet.add(lenBytes.buffer.asUint8List());
        packet.add(payload);

        final msg = TarsDanmakuDecoder.decode(packet.toBytes());
        expect(msg.type, LiveMessageType.chat);
        expect(msg.userName, 'David');
        expect(msg.content, 'Tars parsed');
      });

      test(
        'throws FormatException on truncated Tars packet or mismatch length',
        () {
          expect(
            () => TarsDanmakuDecoder.decode(Uint8List(2)),
            throwsFormatException,
          );
          expect(
            () => TarsDanmakuDecoder.decode(
              Uint8List.fromList([0, 0, 0, 10, 1, 2, 3]),
            ),
            throwsFormatException,
          );
        },
      );
    });
  });
}
