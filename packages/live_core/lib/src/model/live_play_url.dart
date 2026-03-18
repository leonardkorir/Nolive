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
}
