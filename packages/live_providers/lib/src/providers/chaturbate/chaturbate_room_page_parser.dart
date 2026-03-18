import 'dart:convert';

import 'package:live_core/live_core.dart';

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
  static final RegExp _csrfTokenPattern = RegExp(r"csrftoken:\s*'([^']+)'");
  static final RegExp _pushServicesPattern = RegExp(
    r"push_services:\s*JSON\.parse\('((?:\\.|[^'\\])*)'\)",
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
    final token = match?.group(1)?.trim() ?? '';
    return token.isEmpty ? null : token;
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
    final match = _pushServicesPattern.firstMatch(source);
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
      final unescaped = _decodeEmbeddedJsonString(
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

  String _decodeEmbeddedJsonString(
    String rawValue, {
    required String context,
  }) {
    final unescaped = jsonDecode('"$rawValue"');
    if (unescaped is! String) {
      throw FormatException('$context did not decode to String');
    }
    return unescaped;
  }

  Map<String, dynamic> _asMap(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.cast<String, dynamic>();
    }
    return const {};
  }
}
