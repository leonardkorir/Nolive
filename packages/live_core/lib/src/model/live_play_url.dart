import 'model_equality.dart';

class LivePlayUrl {
  const LivePlayUrl({
    required this.url,
    this.headers = const {},
    this.lineLabel,
    this.metadata,
  });

  final String url;
  final Map<String, String> headers;
  final String? lineLabel;
  final Map<String, Object?>? metadata;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is LivePlayUrl &&
            other.url == url &&
            modelMapEquals(other.headers, headers) &&
            other.lineLabel == lineLabel &&
            modelMapEquals(other.metadata, metadata);
  }

  @override
  int get hashCode => Object.hash(
      url, modelMapHash(headers), lineLabel, modelMapHash(metadata));
}
