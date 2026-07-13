class ProviderId {
  const ProviderId(this.value);

  final String value;

  static const bilibili = ProviderId('bilibili');
  static const chaturbate = ProviderId('chaturbate');
  static const douyu = ProviderId('douyu');
  static const huya = ProviderId('huya');
  static const douyin = ProviderId('douyin');
  static const twitch = ProviderId('twitch');
  static const youtube = ProviderId('youtube');
  static const stripchat = ProviderId('stripchat');

  static final knownValues = {
    bilibili,
    chaturbate,
    douyu,
    huya,
    douyin,
    twitch,
    youtube,
    stripchat,
  };

  factory ProviderId.from(Object? value) {
    if (value is ProviderId) {
      return value;
    }
    final rawValue = value?.toString() ?? '';
    for (final providerId in knownValues) {
      if (providerId.value == rawValue) {
        return providerId;
      }
    }
    return ProviderId(rawValue);
  }

  bool get isEmpty => value.isEmpty;

  bool get isNotEmpty => value.isNotEmpty;

  String toJson() => value;

  @override
  bool operator ==(Object other) {
    return other is ProviderId && other.value == value;
  }

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}
