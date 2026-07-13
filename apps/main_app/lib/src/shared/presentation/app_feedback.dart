import 'package:flutter/material.dart';
import 'package:nolive_app/src/shared/presentation/user_facing_error.dart';

/// Single entry for floating SnackBars — always uses [ThemeData.snackBarTheme].
void showAppSnackBar(
  BuildContext context,
  String message, {
  SnackBarAction? action,
  Duration? duration,
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) {
    return;
  }
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Text(message),
      action: action,
      duration: duration ?? const Duration(seconds: 4),
    ),
  );
}

/// Error / failure toast with friendly Chinese copy (no raw Exception dumps).
void showAppErrorSnackBar(
  BuildContext context,
  Object? error, {
  String fallback = '操作失败，请稍后重试',
  String? prefix,
}) {
  final body = formatUserFacingError(error, fallback: fallback);
  final message = prefix == null || prefix.isEmpty ? body : '$prefix$body';
  showAppSnackBar(context, message);
}
