import 'dart:convert';

extension WellFormedStringExtension on String {
  String toWellFormed() {
    try {
      return utf8.decode(utf8.encode(this), allowMalformed: true);
    } catch (_) {
      return this;
    }
  }
}
