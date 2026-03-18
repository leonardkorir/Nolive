class ProviderId {
  const ProviderId(this.value);

  final String value;

  static const bilibili = ProviderId('bilibili');
  static const chaturbate = ProviderId('chaturbate');
  static const douyu = ProviderId('douyu');
  static const huya = ProviderId('huya');
  static const douyin = ProviderId('douyin');

  static final knownValues = {
    bilibili,
    chaturbate,
    douyu,
    huya,
    douyin,
  };

  @override
  bool operator ==(Object other) {
    return other is ProviderId && other.value == value;
  }

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}
