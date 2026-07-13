import 'dart:convert';

import 'package:live_core/live_core.dart';

import '../provider_json.dart';

class ChaturbateRoomPageContext {
  const ChaturbateRoomPageContext({
    required this.dossier,
    required this.csrfToken,
    required this.pushServices,
  });

  final Map<String, dynamic> dossier;
  final String csrfToken;
  final List<Map<String, dynamic>> pushServices;

  Map<String, dynamic> get primaryPushService {
    if (pushServices.isEmpty) {
      return const {};
    }
    return pushServices.first;
  }
}

class ChaturbateRoomPageParser {
  const ChaturbateRoomPageParser();

  static final RegExp _initialRoomDossierPattern = RegExp(
    r'window\.initialRoomDossier\s*=\s*"((?:\\.|[^"\\])*)";?',
  );
  static final RegExp _csrfTokenPattern = RegExp(
    r'''["']?csrftoken["']?\s*:\s*["']([^"']+)["']''',
  );
  static final RegExp _csrfMiddlewareInputPattern = RegExp(
    r'''name=["']csrfmiddlewaretoken["'][^>]*value=["']([^"']+)["']'''
    r'''|value=["']([^"']+)["'][^>]*name=["']csrfmiddlewaretoken["']''',
    caseSensitive: false,
  );
  static final RegExp _csrfCookiePattern = RegExp(
    r'(?:^|;\s*)csrftoken=([^;\s]+)',
    caseSensitive: false,
  );
  static final RegExp _pushServicesSingleQuotePattern = RegExp(
    r"push_services:\s*JSON\.parse\('((?:\\.|[^'\\])*)'\)",
    dotAll: true,
  );
  static final RegExp _pushServicesDoubleQuotePattern = RegExp(
    r'push_services:\s*JSON\.parse\("((?:\\.|[^"\\])*)"\)',
    dotAll: true,
  );
  static final RegExp _pushServicesArrayPattern = RegExp(
    r'''["']?push_services["']?\s*:\s*(\[[\s\S]*?\])\s*[,}]''',
    dotAll: true,
  );

  String extractInitialRoomDossierRawValue(String source) {
    final match = _initialRoomDossierPattern.firstMatch(source);
    final rawValue = match?.group(1);
    if (rawValue == null || rawValue.isEmpty) {
      throw ProviderParseException(
        providerId: ProviderId.chaturbate,
        message:
            'Chaturbate room page did not contain window.initialRoomDossier.',
      );
    }
    return rawValue;
  }

  String extractCsrfToken(String source) {
    final token = tryExtractCsrfToken(source);
    if (token != null) {
      return token;
    }
    throw ProviderParseException(
      providerId: ProviderId.chaturbate,
      message: 'Chaturbate room page did not contain csrftoken.',
    );
  }

  String? tryExtractCsrfToken(String source) {
    final match = _csrfTokenPattern.firstMatch(source);
    final fromScript = match?.group(1)?.trim() ?? '';
    if (fromScript.isNotEmpty) {
      return fromScript;
    }
    final inputMatch = _csrfMiddlewareInputPattern.firstMatch(source);
    final fromInput =
        (inputMatch?.group(1) ?? inputMatch?.group(2))?.trim() ?? '';
    if (fromInput.isNotEmpty) {
      return fromInput;
    }
    return tryExtractCsrfTokenFromCookie(source);
  }

  /// Extracts `csrftoken` from a Cookie header / cookie jar string.
  static String? tryExtractCsrfTokenFromCookie(String cookie) {
    final match = _csrfCookiePattern.firstMatch(cookie);
    final token = match?.group(1)?.trim() ?? '';
    if (token.isEmpty) {
      return null;
    }
    try {
      return Uri.decodeComponent(token);
    } catch (_) {
      return token;
    }
  }

  String extractPushServicesRawValue(String source) {
    final rawValue = tryExtractPushServicesRawValue(source);
    if (rawValue != null) {
      return rawValue;
    }
    throw ProviderParseException(
      providerId: ProviderId.chaturbate,
      message: 'Chaturbate room page did not contain push_services.',
    );
  }

  String? tryExtractPushServicesRawValue(String source) {
    final match =
        _pushServicesSingleQuotePattern.firstMatch(source) ??
        _pushServicesDoubleQuotePattern.firstMatch(source) ??
        _pushServicesArrayPattern.firstMatch(source);
    final rawValue = match?.group(1);
    if (rawValue == null || rawValue.isEmpty) {
      return null;
    }
    return rawValue;
  }

  bool hasRealtimeBootstrap(String source) {
    return tryExtractCsrfToken(source) != null &&
        tryExtractPushServicesRawValue(source) != null;
  }

  Map<String, dynamic> decodeInitialRoomDossier(String rawValue) {
    try {
      final unescaped = _decodeEmbeddedJsonString(
        rawValue,
        context: 'initialRoomDossier outer string',
      );
      final decoded = jsonDecode(unescaped);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.cast<String, dynamic>();
      }
      throw const FormatException(
        'initialRoomDossier inner JSON was not an object',
      );
    } catch (error, stackTrace) {
      throw ProviderParseException(
        providerId: ProviderId.chaturbate,
        message: 'Failed to decode Chaturbate initialRoomDossier payload.',
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  List<Map<String, dynamic>> decodePushServices(String rawValue) {
    try {
      final unescaped = _decodeMaybeEmbeddedJsonString(
        rawValue,
        context: 'push_services outer string',
      );
      final decoded = jsonDecode(unescaped);
      if (decoded is! List) {
        throw const FormatException('push_services inner JSON was not a list');
      }
      return decoded
          .map((item) => _asMap(item))
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
    } catch (error, stackTrace) {
      throw ProviderParseException(
        providerId: ProviderId.chaturbate,
        message: 'Failed to decode Chaturbate push_services payload.',
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  Map<String, dynamic> parseInitialRoomDossier(String source) {
    final rawValue = extractInitialRoomDossierRawValue(source);
    return decodeInitialRoomDossier(rawValue);
  }

  ChaturbateRoomPageContext parsePageContext(String source) {
    final pushServicesRawValue = tryExtractPushServicesRawValue(source);
    return ChaturbateRoomPageContext(
      dossier: parseInitialRoomDossier(source),
      csrfToken: tryExtractCsrfToken(source) ?? '',
      pushServices: pushServicesRawValue == null
          ? const []
          : decodePushServices(pushServicesRawValue),
    );
  }

  String _decodeEmbeddedJsonString(String rawValue, {required String context}) {
    final unescaped = jsonDecode('"$rawValue"');
    if (unescaped is! String) {
      throw FormatException('$context did not decode to String');
    }
    return unescaped;
  }

  String _decodeMaybeEmbeddedJsonString(
    String rawValue, {
    required String context,
  }) {
    try {
      return _decodeEmbeddedJsonString(rawValue, context: context);
    } on FormatException {
      return rawValue;
    }
  }

  Map<String, dynamic> _asMap(Object? value) {
    return ProviderJson.asMap(value);
  }
}
