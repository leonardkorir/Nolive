import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:live_core/live_core.dart';
import 'package:live_providers/live_providers.dart';
import 'package:live_storage/live_storage.dart';

import '../../../shared/application/secure_credential_store.dart';
import 'sensitive_setting_keys.dart';

class CredentialMigrationBundle {
  const CredentialMigrationBundle({
    required this.credentials,
    required this.createdAt,
  });

  final Map<String, String> credentials;
  final DateTime createdAt;
}

class CredentialMigrationBundleCodec {
  const CredentialMigrationBundleCodec._();

  static const String _bundleType = 'nolive_secure_migration';
  static const int currentFormatVersion = 1;
  static const int _pbkdf2Iterations = 120000;
  static const int _saltLength = 16;
  static const int _nonceLength = 12;
  static const int _macLength = 16;

  static final Pbkdf2 _kdf = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: _pbkdf2Iterations,
    bits: 256,
  );

  static final AesGcm _cipher = AesGcm.with256bits();
  static final Random _random = Random.secure();

  static Future<String> encode(
    CredentialMigrationBundle bundle, {
    required String password,
  }) async {
    final normalizedPassword = password.trim();
    if (normalizedPassword.isEmpty) {
      throw const FormatException('迁移口令不能为空。');
    }

    final salt = _randomBytes(_saltLength);
    final nonce = _randomBytes(_nonceLength);
    final secretKey = await _kdf.deriveKeyFromPassword(
      password: normalizedPassword,
      nonce: salt,
    );
    final payload = utf8.encode(
      jsonEncode({
        'credentials': bundle.credentials,
        'created_at': bundle.createdAt.toIso8601String(),
      }),
    );
    final secretBox = await _cipher.encrypt(
      payload,
      secretKey: secretKey,
      nonce: nonce,
    );
    final combinedCipherText = Uint8List.fromList([
      ...secretBox.cipherText,
      ...secretBox.mac.bytes,
    ]);

    return jsonEncode({
      'type': _bundleType,
      'format_version': currentFormatVersion,
      'kdf': 'pbkdf2-sha256',
      'cipher': 'aes-256-gcm',
      'created_at': bundle.createdAt.toIso8601String(),
      'salt': base64Encode(salt),
      'nonce': base64Encode(nonce),
      'ciphertext': base64Encode(combinedCipherText),
    });
  }

  static Future<CredentialMigrationBundle> decode(
    String rawJson, {
    required String password,
  }) async {
    final normalizedPassword = password.trim();
    if (normalizedPassword.isEmpty) {
      throw const FormatException('迁移口令不能为空。');
    }

    final decoded = jsonDecode(rawJson);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('迁移包内容必须是 JSON 对象。');
    }
    if (decoded['type'] != _bundleType) {
      throw const FormatException('不是 Nolive 受控迁移包。');
    }
    final formatVersion = _decodeFormatVersion(decoded['format_version']);
    if (formatVersion != currentFormatVersion) {
      throw FormatException('不支持的迁移包版本：$formatVersion。');
    }
    if (decoded['kdf'] != 'pbkdf2-sha256') {
      throw const FormatException('不支持的迁移包口令派生算法。');
    }
    if (decoded['cipher'] != 'aes-256-gcm') {
      throw const FormatException('不支持的迁移包加密算法。');
    }

    final salt = _decodeBytes(decoded['salt'], fieldName: 'salt');
    final nonce = _decodeBytes(decoded['nonce'], fieldName: 'nonce');
    final combinedCipherText = _decodeBytes(
      decoded['ciphertext'],
      fieldName: 'ciphertext',
    );
    if (combinedCipherText.length <= _macLength) {
      throw const FormatException('迁移包密文无效。');
    }

    final secretKey = await _kdf.deriveKeyFromPassword(
      password: normalizedPassword,
      nonce: salt,
    );
    final secretBox = SecretBox(
      combinedCipherText.sublist(0, combinedCipherText.length - _macLength),
      nonce: nonce,
      mac: Mac(
          combinedCipherText.sublist(combinedCipherText.length - _macLength)),
    );

    try {
      final clearText = await _cipher.decrypt(
        secretBox,
        secretKey: secretKey,
      );
      final payload = jsonDecode(utf8.decode(clearText));
      if (payload is! Map<String, dynamic>) {
        throw const FormatException('迁移包明文结构无效。');
      }
      final rawCredentials = payload['credentials'];
      if (rawCredentials is! Map) {
        throw const FormatException('迁移包缺少 credentials。');
      }
      final createdAt = DateTime.tryParse(
            payload['created_at']?.toString() ?? '',
          ) ??
          DateTime.tryParse(decoded['created_at']?.toString() ?? '') ??
          DateTime.now();
      final credentials = <String, String>{};
      for (final entry in rawCredentials.entries) {
        final key = entry.key.toString();
        if (!SensitiveSettingKeys.isSecureCredentialKey(key)) {
          continue;
        }
        final value = entry.value?.toString().trim() ?? '';
        if (value.isNotEmpty) {
          credentials[key] = value;
        }
      }
      if (credentials.isEmpty) {
        throw const FormatException('迁移包中没有可恢复的敏感凭证。');
      }
      return CredentialMigrationBundle(
        credentials: credentials,
        createdAt: createdAt,
      );
    } on SecretBoxAuthenticationError {
      throw const FormatException('迁移口令错误，或迁移包已损坏。');
    }
  }

  static Uint8List _decodeBytes(
    Object? raw, {
    required String fieldName,
  }) {
    final encoded = raw?.toString().trim() ?? '';
    if (encoded.isEmpty) {
      throw FormatException('迁移包缺少 $fieldName。');
    }
    try {
      return Uint8List.fromList(base64Decode(encoded));
    } on FormatException {
      throw FormatException('迁移包字段 $fieldName 不是有效的 base64。');
    }
  }

  static Uint8List _randomBytes(int length) {
    return Uint8List.fromList(
      List<int>.generate(length, (_) => _random.nextInt(256)),
    );
  }

  static int _decodeFormatVersion(Object? raw) {
    if (raw is int) {
      return raw;
    }
    if (raw is num) {
      return raw.toInt();
    }
    return int.tryParse(raw?.toString() ?? '') ?? 0;
  }
}

class ExportCredentialMigrationBundleUseCase {
  const ExportCredentialMigrationBundleUseCase(this.secureCredentialStore);

  final SecureCredentialStore secureCredentialStore;

  Future<String> call({
    required String password,
  }) async {
    final credentials = await secureCredentialStore.readAll();
    final exportable = <String, String>{
      for (final entry in credentials.entries)
        if (SensitiveSettingKeys.isSecureCredentialKey(entry.key) &&
            entry.value.trim().isNotEmpty)
          entry.key: entry.value.trim(),
    };
    if (exportable.isEmpty) {
      throw const FormatException('当前没有可迁移的敏感凭证。');
    }
    return CredentialMigrationBundleCodec.encode(
      CredentialMigrationBundle(
        credentials: exportable,
        createdAt: DateTime.now(),
      ),
      password: password,
    );
  }
}

class ImportCredentialMigrationBundleUseCase {
  const ImportCredentialMigrationBundleUseCase({
    required this.secureCredentialStore,
    required this.settingsRepository,
    this.providerRegistry,
    this.providerCatalogRevision,
  });

  final SecureCredentialStore secureCredentialStore;
  final SettingsRepository settingsRepository;
  final ProviderRegistry? providerRegistry;
  final ValueNotifier<int>? providerCatalogRevision;

  Future<CredentialMigrationBundle> call(
    String rawJson, {
    required String password,
  }) async {
    final bundle = await CredentialMigrationBundleCodec.decode(
      rawJson,
      password: password,
    );
    await secureCredentialStore.writeAll(bundle.credentials);
    for (final key in bundle.credentials.keys) {
      await settingsRepository.remove(key);
    }
    _invalidateProviderCaches();
    return bundle;
  }

  void _invalidateProviderCaches() {
    providerRegistry?.invalidate(ProviderId.bilibili);
    providerRegistry?.invalidate(ProviderId.chaturbate);
    providerRegistry?.invalidate(ProviderId.douyin);
    providerRegistry?.invalidate(ProviderId.twitch);
    providerRegistry?.invalidate(ProviderId.youtube);
    if (providerCatalogRevision != null) {
      providerCatalogRevision!.value += 1;
    }
  }
}

class ClearSensitiveCredentialsUseCase {
  const ClearSensitiveCredentialsUseCase({
    required this.secureCredentialStore,
    required this.settingsRepository,
    this.providerRegistry,
    this.providerCatalogRevision,
  });

  final SecureCredentialStore secureCredentialStore;
  final SettingsRepository settingsRepository;
  final ProviderRegistry? providerRegistry;
  final ValueNotifier<int>? providerCatalogRevision;

  Future<void> call() async {
    await secureCredentialStore.deleteAll(
      SensitiveSettingKeys.secureCredentialKeys,
    );
    for (final key in SensitiveSettingKeys.secureCredentialKeys) {
      await settingsRepository.remove(key);
    }
    providerRegistry?.invalidate(ProviderId.bilibili);
    providerRegistry?.invalidate(ProviderId.chaturbate);
    providerRegistry?.invalidate(ProviderId.douyin);
    providerRegistry?.invalidate(ProviderId.twitch);
    providerRegistry?.invalidate(ProviderId.youtube);
    if (providerCatalogRevision != null) {
      providerCatalogRevision!.value += 1;
    }
  }
}
