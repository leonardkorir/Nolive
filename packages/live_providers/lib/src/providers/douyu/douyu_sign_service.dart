import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:live_core/live_core.dart';
import 'package:meta/meta.dart';

import '../provider_json.dart';
import '../provider_runtime_support.dart';
import 'douyu_quickjs_signer.dart';
import 'douyu_transport.dart';

typedef DouyuSignExecutor =
    Future<String> Function({
      required String script,
      required String roomId,
      required String deviceId,
      required int timestamp,
    });

class DouyuSignedPlayContext {
  const DouyuSignedPlayContext({
    required this.body,
    required this.deviceId,
    required this.timestamp,
    this.script = '',
  });

  /// Last signed form body (SlotSun always re-signs; may be empty until first sign).
  final String body;
  final String deviceId;
  final int timestamp;

  /// Legacy QuickJS script field; empty when using websec encryption (SlotSun path).
  final String script;
}

abstract class DouyuSignService {
  Map<String, String> buildSearchHeaders();

  Map<String, String> buildRoomHeaders(String roomId);

  /// Headers for `POST getH5PlayV1` (SlotSun: form content-type + browser UA only).
  Map<String, String> buildPlayHeaders(String roomId, {String? deviceId});

  /// Headers for the player when opening the CDN FLV/HLS URL.
  /// SlotSun Douyu: bare URL — empty headers.
  Map<String, String> buildStreamHeaders(String roomId, {String? deviceId});

  /// SlotSun `DouyuUtils.sign(rid, rate:, cdn:)` — full body in one shot, fresh `tt`.
  Future<String> buildSignedPlayBody(
    String roomId, {
    String cdn = '',
    String rate = '-1',
  });

  Future<DouyuSignedPlayContext> buildPlayContext(String roomId);

  String extendPlayBody(
    String baseBody, {
    required String cdn,
    required String rate,
  });
}

/// Generates / validates Douyu `did` values (32-char hex, SlotSun-compatible shape).
class DouyuDeviceId {
  DouyuDeviceId._();

  /// Historical SlotSun fixed id — only for tests / explicit override.
  static const String legacyShared = '10000000000000000000000000001501';

  static final RegExp _validPattern = RegExp(r'^[0-9a-fA-F]{16,64}$');

  /// Process-level cache so multiple provider constructions share one id until
  /// settings persistence lands (and across a single app session).
  static String? _sessionCache;

  static bool isValid(String value) => _validPattern.hasMatch(value.trim());

  /// New per-install id (32 lowercase hex chars).
  static String generate([Random? random]) {
    final r = random ?? Random.secure();
    final buffer = StringBuffer();
    for (var i = 0; i < 32; i += 1) {
      buffer.write(r.nextInt(16).toRadixString(16));
    }
    return buffer.toString();
  }

  /// Prefer valid [candidate], else session cache, else generate.
  ///
  /// Call with the settings-stored value when available so restarts reuse the
  /// same install fingerprint.
  static String resolve(String? candidate, [Random? random]) {
    final trimmed = candidate?.trim() ?? '';
    if (isValid(trimmed)) {
      _sessionCache = trimmed;
      return trimmed;
    }
    return _sessionCache ??= generate(random);
  }

  @visibleForTesting
  static void clearSessionCacheForTest() {
    _sessionCache = null;
  }
}

/// Douyu play signing aligned with SlotSun `DouyuUtils` + `DouyuSite`:
/// - `GET .../websec/getEncryption` + pure MD5 auth
/// - `POST .../getH5PlayV1/{roomId}` with full signed form each time
/// - **per-install** `did` + Windows desktop UA
/// - stream open with **no** custom headers (SlotSun `LivePlayUrl(urls:)` only)
class HttpDouyuSignService implements DouyuSignService {
  factory HttpDouyuSignService({
    required DouyuTransport transport,
    DouyuSignExecutor? signExecutor,
    DouyuQuickJsSigner? signer,
    Random? random,
    String? deviceId,
    void Function()? scheduleSignerWarmUp,
    void Function(String message)? diagnostics,
  }) {
    final ownedSigner = signExecutor == null
        ? signer ?? DouyuQuickJsSigner()
        : null;
    final DouyuSignExecutor resolvedSignExecutor =
        signExecutor ?? ownedSigner!.execute;
    return HttpDouyuSignService._(
      transport: transport,
      signExecutor: resolvedSignExecutor,
      ownedSigner: ownedSigner,
      random: random,
      deviceId: DouyuDeviceId.resolve(deviceId, random),
      diagnostics: diagnostics,
      scheduleSignerWarmUp: scheduleSignerWarmUp,
    );
  }

  HttpDouyuSignService._({
    required DouyuTransport transport,
    required DouyuSignExecutor signExecutor,
    required DouyuQuickJsSigner? ownedSigner,
    required String deviceId,
    Random? random,
    void Function()? scheduleSignerWarmUp,
    void Function(String message)? diagnostics,
  }) : _transport = transport,
       _signExecutor = signExecutor,
       _ownedSigner = ownedSigner,
       _deviceId = deviceId,
       _diagnostics = diagnostics {
    // [random] retained for API compatibility with existing call sites.
    scheduleSignerWarmUp?.call();
  }

  /// SlotSun / browser-aligned UA (also used on Android).
  static const String defaultUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36 Edg/114.0.1823.43';

  /// Legacy SlotSun fixed id kept for test fixtures that assert shape only.
  @visibleForTesting
  static const String kDefaultDeviceId = DouyuDeviceId.legacyShared;

  static const String _searchReferer = 'https://www.douyu.com/search/';
  static const String _encryptionApi =
      'https://www.douyu.com/wgapi/livenc/liveweb/websec/getEncryption';
  static const Duration _encryptionCacheTtl = Duration(hours: 20);

  final DouyuTransport _transport;
  final DouyuSignExecutor _signExecutor;
  final DouyuQuickJsSigner? _ownedSigner;
  final String _deviceId;
  final void Function(String message)? _diagnostics;

  Map<String, dynamic>? _encKey;
  int _encKeyExpireAtSeconds = 0;
  Future<void>? _encKeyLoad;

  /// Per-install device id used for websec / cookies / legacy sign.
  String get deviceId => _deviceId;

  @override
  Map<String, String> buildSearchHeaders() {
    return {
      'user-agent': defaultUserAgent,
      'referer': _searchReferer,
      'cookie': 'dy_did=$_deviceId;acf_did=$_deviceId',
    };
  }

  @override
  Map<String, String> buildRoomHeaders(String roomId) {
    // SlotSun betard headers.
    return {
      'user-agent': defaultUserAgent,
      'referer': 'https://www.douyu.com/$roomId',
    };
  }

  @override
  Map<String, String> buildPlayHeaders(String roomId, {String? deviceId}) {
    // SlotSun getH5PlayV1 headers (no cookie / no referer).
    return {
      'user-agent': defaultUserAgent,
      'content-type': 'application/x-www-form-urlencoded',
      'accept':
          'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'accept-language': 'zh-CN,zh;q=0.8,en-US;q=0.5,en;q=0.3',
    };
  }

  @override
  Map<String, String> buildStreamHeaders(String roomId, {String? deviceId}) {
    // SlotSun: LivePlayUrl(urls: urls) — no httpHeaders for Douyu FLV.
    return const {};
  }

  @override
  Future<String> buildSignedPlayBody(
    String roomId, {
    String cdn = '',
    String rate = '-1',
  }) async {
    final timestamp = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    try {
      return await _buildWebsecPlayBody(
        roomId: roomId,
        timestamp: timestamp,
        cdn: cdn,
        rate: rate,
      );
    } catch (error, stackTrace) {
      reportProviderDiagnostic(
        providerId: ProviderId.douyu,
        scope: 'douyu.sign.websec',
        message: 'websec encryption failed; falling back to legacy homeH5Enc',
        error: error,
        stackTrace: stackTrace,
        diagnostics: _diagnostics,
      );
      final legacy = await _buildLegacyPlayContext(
        roomId,
        timestamp: timestamp,
      );
      return extendPlayBody(legacy.body, cdn: cdn, rate: rate);
    }
  }

  @override
  Future<DouyuSignedPlayContext> buildPlayContext(String roomId) async {
    final timestamp = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    try {
      // SlotSun quality probe signs with rate=-1, cdn=''.
      final body = await _buildWebsecPlayBody(
        roomId: roomId,
        timestamp: timestamp,
        cdn: '',
        rate: '-1',
      );
      return DouyuSignedPlayContext(
        body: body,
        deviceId: _deviceId,
        timestamp: timestamp,
      );
    } catch (error, stackTrace) {
      reportProviderDiagnostic(
        providerId: ProviderId.douyu,
        scope: 'douyu.sign.websec',
        message: 'websec encryption failed; falling back to legacy homeH5Enc',
        error: error,
        stackTrace: stackTrace,
        diagnostics: _diagnostics,
      );
      return _buildLegacyPlayContext(roomId, timestamp: timestamp);
    }
  }

  @override
  String extendPlayBody(
    String baseBody, {
    required String cdn,
    required String rate,
  }) {
    final normalizedBody = baseBody.trim();
    // Strip trailing origin flags if re-extending a full SlotSun body.
    final withoutOrigin = normalizedBody
        .replaceAll(RegExp(r'&cdn=[^&]*'), '')
        .replaceAll(RegExp(r'&rate=[^&]*'), '')
        .replaceAll(RegExp(r'&hevc=0'), '')
        .replaceAll(RegExp(r'&fa=0'), '')
        .replaceAll(RegExp(r'&ive=0'), '')
        .replaceAll(RegExp(r'&ver=Douyu_new'), '')
        .replaceAll(RegExp(r'&iar=0'), '');
    final prefix = withoutOrigin.isEmpty || withoutOrigin.endsWith('&')
        ? withoutOrigin
        : '$withoutOrigin&';
    // SlotSun: hevc=0&fa=0&ive=0&ver=Douyu_new&iar=0
    return '${prefix}cdn=$cdn&rate=$rate&hevc=0&fa=0&ive=0&ver=Douyu_new&iar=0';
  }

  Future<DouyuSignedPlayContext> _buildLegacyPlayContext(
    String roomId, {
    required int timestamp,
  }) async {
    final response = await _transport.getJson(
      'https://www.douyu.com/swf_api/homeH5Enc',
      queryParameters: {'rids': roomId},
      headers: buildRoomHeaders(roomId),
    );
    final data = _asMap(response['data']);
    final script = data['room$roomId']?.toString() ?? '';
    final deviceId = _deviceId;

    final body = script.isNotEmpty
        ? await _buildLegacySignedBody(
            script: script,
            roomId: roomId,
            deviceId: deviceId,
            timestamp: timestamp,
          )
        : _buildFallbackBody(
            roomId: roomId,
            deviceId: deviceId,
            timestamp: timestamp,
          );

    return DouyuSignedPlayContext(
      body: body,
      deviceId: deviceId,
      timestamp: timestamp,
      script: script,
    );
  }

  /// Exact SlotSun `DouyuUtils.sign` form body.
  Future<String> _buildWebsecPlayBody({
    required String roomId,
    required int timestamp,
    required String cdn,
    required String rate,
  }) async {
    await _ensureEncryptionKey();
    final encKey = _encKey;
    if (encKey == null) {
      throw StateError('Douyu encryption key is unavailable.');
    }

    final randStr = encKey['rand_str']?.toString() ?? '';
    final encTime = _asInt(encKey['enc_time']) ?? 1;
    final isSpecial = _asInt(encKey['is_special']) == 1;
    final salt = isSpecial ? '' : '$roomId$timestamp';
    final key = encKey['key']?.toString() ?? '';
    final encData = encKey['enc_data']?.toString() ?? '';
    if (key.isEmpty || encData.isEmpty) {
      throw StateError('Douyu encryption payload missing key/enc_data.');
    }

    var secret = randStr;
    final rounds = encTime < 1 ? 1 : encTime;
    for (var i = 0; i < rounds; i += 1) {
      secret = md5.convert(utf8.encode('$secret$key')).toString();
    }
    final auth = md5.convert(utf8.encode('$secret$key$salt')).toString();

    // application/x-www-form-urlencoded: percent-encode every value so Base64
    // enc_data containing + / = is not corrupted by form parsers.
    return _formUrlEncoded({
      'enc_data': encData,
      'tt': '$timestamp',
      'did': _deviceId,
      'auth': auth,
      'cdn': cdn,
      'rate': rate,
      'hevc': '0',
      'fa': '0',
      'ive': '0',
      'ver': 'Douyu_new',
      'iar': '0',
    });
  }

  static String _formUrlEncoded(Map<String, String> fields) {
    return fields.entries
        .map(
          (e) =>
              '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}',
        )
        .join('&');
  }

  bool _isEncryptionKeyFresh(int nowSeconds) {
    if (_encKey == null) {
      return false;
    }
    final serverExpire = _asInt(_encKey?['expire_at']) ?? 0;
    // Non-future expire_at is treated as absent → fall back to local TTL.
    final effectiveExpire =
        serverExpire > nowSeconds ? serverExpire : _encKeyExpireAtSeconds;
    return effectiveExpire > nowSeconds;
  }

  Future<void> _ensureEncryptionKey() async {
    final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (_isEncryptionKeyFresh(nowSeconds)) {
      return;
    }
    // Coalesce concurrent getEncryption GETs (qualities + multi-CDN urls).
    final inflight = _encKeyLoad;
    if (inflight != null) {
      await inflight;
      if (_isEncryptionKeyFresh(
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
      )) {
        return;
      }
    }
    final load = _loadEncryptionKey();
    _encKeyLoad = load;
    try {
      await load;
    } finally {
      if (identical(_encKeyLoad, load)) {
        _encKeyLoad = null;
      }
    }
  }

  Future<void> _loadEncryptionKey() async {
    final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (_isEncryptionKeyFresh(nowSeconds)) {
      return;
    }
    final response = await _transport.getJson(
      _encryptionApi,
      queryParameters: {'did': _deviceId},
      headers: {
        'user-agent': defaultUserAgent,
      },
    );
    final data = _asMap(response['data']);
    if (data.isEmpty) {
      throw StateError('Douyu getEncryption returned empty data.');
    }
    _encKey = data;
    final expireAt = _asInt(data['expire_at']);
    // Always keep a local TTL floor so past/skewed expire_at does not thrash.
    final localFloor = nowSeconds + _encryptionCacheTtl.inSeconds;
    _encKeyExpireAtSeconds =
        expireAt != null && expireAt > nowSeconds ? expireAt : localFloor;
  }

  Future<String> _buildLegacySignedBody({
    required String script,
    required String roomId,
    required String deviceId,
    required int timestamp,
  }) async {
    try {
      return await _signExecutor(
        script: script,
        roomId: roomId,
        deviceId: deviceId,
        timestamp: timestamp,
      );
    } catch (error, stackTrace) {
      reportProviderDiagnostic(
        providerId: ProviderId.douyu,
        scope: 'douyu.sign.legacy',
        message: 'legacy sign executor failed; using fallback body',
        error: error,
        stackTrace: stackTrace,
        diagnostics: _diagnostics,
      );
      return _buildFallbackBody(
        roomId: roomId,
        deviceId: deviceId,
        timestamp: timestamp,
      );
    }
  }

  static String _buildFallbackBody({
    required String roomId,
    required String deviceId,
    required int timestamp,
  }) {
    final signature = md5
        .convert(utf8.encode('$roomId|$deviceId|$timestamp|simplelive-douyu'))
        .toString();
    return 'rid=$roomId&did=$deviceId&tt=$timestamp&sign=$signature';
  }

  static Map<String, dynamic> _asMap(Object? value) {
    return ProviderJson.asMap(value);
  }

  static int? _asInt(Object? value) {
    return ProviderJson.asInt(value);
  }

  void dispose() {
    _ownedSigner?.dispose();
  }

  @visibleForTesting
  void clearEncryptionCacheForTest() {
    _encKey = null;
    _encKeyExpireAtSeconds = 0;
    _encKeyLoad = null;
  }

  /// Inject a past server expire_at while keeping local TTL (unit tests).
  @visibleForTesting
  void seedEncryptionKeyForTest(
    Map<String, dynamic> data, {
    required int localExpireAtSeconds,
  }) {
    _encKey = data;
    _encKeyExpireAtSeconds = localExpireAtSeconds;
  }
}
