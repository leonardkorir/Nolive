class TarsDecodeException implements Exception {
  TarsDecodeException(this.message);

  final String message;

  @override
  String toString() {
    return message;
  }
}
