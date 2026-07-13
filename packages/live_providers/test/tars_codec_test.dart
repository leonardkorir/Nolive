import 'dart:typed_data';

import 'package:live_providers/src/danmaku/tars/huya_danmaku.dart';
import 'package:live_providers/src/danmaku/tars/codec/tars_decode_exception.dart';
import 'package:live_providers/src/danmaku/tars/codec/tars_deep_copyable.dart';
import 'package:live_providers/src/danmaku/tars/codec/tars_encode_exception.dart';
import 'package:live_providers/src/danmaku/tars/codec/tars_input_stream.dart';
import 'package:live_providers/src/danmaku/tars/codec/tars_output_stream.dart';
import 'package:test/test.dart';

void main() {
  test('binary reader throws decode exception on truncated reads', () {
    final reader = BinaryReader(Uint8List.fromList([1, 2]));

    expect(() => reader.readInt(4), throwsA(isA<TarsDecodeException>()));
  });

  test('skipToTag propagates decode exceptions for malformed payloads', () {
    final input = TarsInputStream(Uint8List.fromList([6]));

    expect(() => input.skipToTag(1), throwsA(isA<TarsDecodeException>()));
  });

  test('tars decode exception is a recoverable exception', () {
    expect(TarsDecodeException('bad payload'), isA<Exception>());
  });

  test('tars list deep copy accepts empty lists', () {
    expect(listDeepCopy<Object>(const []), isEmpty);
  });

  test('tars readMap rejects empty type template with decode exception', () {
    final input = TarsInputStream(Uint8List.fromList(const []));

    expect(
      () => input.readMap<String, String>(const {}, 0, false),
      throwsA(isA<TarsDecodeException>()),
    );
  });

  test('tars output stream no longer swallows binary writer failures', () {
    final output = TarsOutputStream();
    output.bw = _ThrowingBinaryWriter([]);

    expect(() => output.writeHead(1, 1), throwsA(isA<StateError>()));
  });

  test('tars output stream still rejects oversized tags', () {
    final output = TarsOutputStream();

    expect(() => output.writeHead(1, 300), throwsA(isA<TarsEncodeException>()));
  });

  test('huya sender reads lMid from its dedicated tag', () {
    final output = TarsOutputStream()
      ..writeInt(123, 0)
      ..writeInt(456, 1)
      ..writeString('tester', 2)
      ..writeInt(1, 3);
    final input = TarsInputStream(Uint8List.fromList(output.bw.buffer));
    final sender = HYSender()..readFrom(input);

    expect(sender.uid, 123);
    expect(sender.lMid, 456);
    expect(sender.nickName, 'tester');
    expect(sender.gender, 1);
  });
}

class _ThrowingBinaryWriter extends BinaryWriter {
  _ThrowingBinaryWriter(super.buffer);

  @override
  void writeInt(int value, int len) {
    throw StateError('writer failed');
  }
}
