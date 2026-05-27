import '../text/well_formed_string_extension.dart';
import 'model_equality.dart';

enum LiveMessageType {
  chat,
  notice,
  gift,
  member,
  superChat,
  online,
}

class LiveMessage<TPayload extends Object?> {
  const LiveMessage({
    required this.type,
    required String content,
    String? userName,
    this.timestamp,
    this.payload,
  }) : _content = content,
       _userName = userName;

  final LiveMessageType type;
  final String _content;
  final String? _userName;
  final DateTime? timestamp;
  final TPayload? payload;

  String get content => _content.toWellFormed();
  String? get userName => _userName?.toWellFormed();

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is LiveMessage &&
            other.type == type &&
            other.content == content &&
            other.userName == userName &&
            other.timestamp == timestamp &&
            modelValueEquals(other.payload, payload);
  }

  @override
  int get hashCode => Object.hash(
        type,
        content,
        userName,
        timestamp,
        modelValueHash(payload),
      );
}
