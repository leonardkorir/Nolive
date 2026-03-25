import 'package:live_core/live_core.dart';
import 'package:live_providers/live_providers.dart';

class ParseRoomInputUseCase {
  const ParseRoomInputUseCase(this.providerRegistry);

  final ProviderRegistry providerRegistry;

  ParseRoomInputResult call({
    required String rawInput,
    ProviderId? fallbackProvider,
  }) {
    final normalized = rawInput.trim();
    if (normalized.isEmpty) {
      return const ParseRoomInputResult.failure('请输入房间号或直播间链接');
    }

    final providerPair = _tryParseProviderPrefix(normalized);
    if (providerPair != null) {
      return _validateAndBuild(
        providerPair.$1,
        _normalizeRoomId(providerPair.$1, providerPair.$2),
        normalized,
      );
    }

    final uri = _tryParseUri(normalized);
    if (uri != null) {
      final parsedFromUrl = _parseFromUri(uri);
      if (parsedFromUrl != null) {
        return _validateAndBuild(
          parsedFromUrl.$1,
          _normalizeRoomId(parsedFromUrl.$1, parsedFromUrl.$2),
          normalized,
        );
      }
      if (uri.host.contains('v.douyin.com')) {
        return const ParseRoomInputResult.failure(
          '暂不支持抖音短链接，请粘贴直播间长链接或直接输入房间号。',
        );
      }
    }

    if (fallbackProvider == null) {
      return const ParseRoomInputResult.failure(
        '未能识别平台，请先选择平台后再输入房间号。',
      );
    }
    return _validateAndBuild(
      fallbackProvider,
      _normalizeRoomId(fallbackProvider, normalized),
      normalized,
    );
  }

  (ProviderId, String)? _tryParseProviderPrefix(String input) {
    final splitIndex = input.indexOf(':');
    if (splitIndex <= 0) {
      return null;
    }
    final providerRaw = input.substring(0, splitIndex).trim().toLowerCase();
    final roomId = input.substring(splitIndex + 1).trim();
    final provider = switch (providerRaw) {
      'bilibili' || 'bili' || 'blive' => ProviderId.bilibili,
      'chaturbate' => ProviderId.chaturbate,
      'douyu' => ProviderId.douyu,
      'huya' => ProviderId.huya,
      'douyin' => ProviderId.douyin,
      'twitch' || 'ttv' => ProviderId.twitch,
      'youtube' || 'yt' => ProviderId.youtube,
      _ => null,
    };
    if (provider == null || roomId.isEmpty) {
      return null;
    }
    return (provider, roomId);
  }

  Uri? _tryParseUri(String input) {
    final maybeUrl = input.startsWith('http://') || input.startsWith('https://')
        ? input
        : input.contains('.') && input.contains('/')
            ? 'https://$input'
            : null;
    if (maybeUrl == null) {
      return null;
    }
    return Uri.tryParse(maybeUrl);
  }

  (ProviderId, String)? _parseFromUri(Uri uri) {
    final host = uri.host.toLowerCase();
    final segments = uri.pathSegments.where((item) => item.isNotEmpty).toList();
    if (host.contains('live.bilibili.com') && segments.isNotEmpty) {
      return (ProviderId.bilibili, segments.first);
    }
    if (host.contains('douyu.com')) {
      final rid = _firstNonEmpty([
        uri.queryParameters['rid'],
        uri.queryParameters['roomId'],
        uri.queryParameters['room_id'],
      ]);
      if (rid != null) {
        return (ProviderId.douyu, rid);
      }
      if (segments.isNotEmpty) {
        return (ProviderId.douyu, segments.first);
      }
    }
    if (host.contains('huya.com') && segments.isNotEmpty) {
      if (segments.length >= 2 && segments.first == 'yy') {
        return (ProviderId.huya, 'yy/${segments[1]}');
      }
      return (ProviderId.huya, segments.first);
    }
    if ((host == 'chaturbate.com' || host == 'www.chaturbate.com') &&
        segments.length == 1 &&
        !_reservedChaturbateSegments.contains(segments.first.toLowerCase())) {
      return (ProviderId.chaturbate, segments.first);
    }
    if ((host == 'live.douyin.com' || host == 'www.douyin.com') &&
        segments.isNotEmpty) {
      return (ProviderId.douyin, segments.last);
    }
    if ((host == 'twitch.tv' ||
            host == 'www.twitch.tv' ||
            host == 'm.twitch.tv') &&
        segments.isNotEmpty) {
      if (segments.length >= 2 && segments.first == 'popout') {
        final roomId = segments[1].trim();
        if (roomId.isNotEmpty &&
            !_reservedTwitchSegments.contains(roomId.toLowerCase())) {
          return (ProviderId.twitch, roomId);
        }
      }
      final roomId = segments.first.trim();
      if (roomId.isNotEmpty &&
          !_reservedTwitchSegments.contains(roomId.toLowerCase())) {
        return (ProviderId.twitch, roomId);
      }
    }
    if (host == 'youtu.be' && segments.isNotEmpty) {
      return (ProviderId.youtube, segments.first);
    }
    if (host == 'youtube.com' ||
        host == 'www.youtube.com' ||
        host == 'm.youtube.com') {
      final videoId = _firstNonEmpty([
        uri.queryParameters['v'],
        segments.length >= 2 && segments.first == 'live' ? segments[1] : null,
      ]);
      if (videoId != null) {
        return (ProviderId.youtube, videoId);
      }
      if (segments.isNotEmpty) {
        if (segments.first.startsWith('@')) {
          return (
            ProviderId.youtube,
            segments.length >= 2 && segments[1] == 'live'
                ? '${segments.first}/live'
                : '${segments.first}/live',
          );
        }
        if (segments.length >= 2 &&
            _youtubeChannelRoots.contains(segments.first)) {
          return (
            ProviderId.youtube,
            segments.length >= 3 && segments[2] == 'live'
                ? '${segments[0]}/${segments[1]}/live'
                : '${segments[0]}/${segments[1]}/live',
          );
        }
      }
    }
    return null;
  }

  static const Set<String> _reservedChaturbateSegments = {
    'api',
    'apps',
    'discover',
    'statsapi',
    'tag',
  };

  static const Set<String> _reservedTwitchSegments = {
    'directory',
    'downloads',
    'jobs',
    'login',
    'messages',
    'p',
    'payments',
    'popout',
    'products',
    'search',
    'settings',
    'signup',
    'store',
    'subscriptions',
    'turbo',
    'videos',
    'wallet',
  };

  static const Set<String> _youtubeChannelRoots = {
    'channel',
    'c',
    'user',
  };

  String _normalizeRoomId(ProviderId providerId, String roomId) {
    final trimmed = roomId.trim().replaceFirst(RegExp(r'^/+'), '');
    if (providerId == ProviderId.huya) {
      if (trimmed.startsWith('yy/')) {
        return trimmed;
      }
      if (RegExp(r'^\d{10,}$').hasMatch(trimmed)) {
        return 'yy/$trimmed';
      }
      return trimmed;
    }
    if (providerId == ProviderId.twitch) {
      return trimmed.toLowerCase();
    }
    return trimmed;
  }

  String? _firstNonEmpty(List<String?> values) {
    for (final value in values) {
      final trimmed = value?.trim() ?? '';
      if (trimmed.isNotEmpty) {
        return trimmed;
      }
    }
    return null;
  }

  ParseRoomInputResult _validateAndBuild(
    ProviderId providerId,
    String roomId,
    String normalizedInput,
  ) {
    final descriptor = providerRegistry.findDescriptor(providerId);
    if (descriptor == null) {
      return ParseRoomInputResult.failure('平台 ${providerId.value} 尚未注册');
    }

    final trimmedRoomId = roomId.trim();
    if (trimmedRoomId.isEmpty) {
      return const ParseRoomInputResult.failure('房间号不能为空');
    }

    final patterns = descriptor.roomIdPatterns;
    final matches = patterns.isEmpty ||
        patterns.any((pattern) => RegExp(pattern).hasMatch(trimmedRoomId));
    if (!matches) {
      return ParseRoomInputResult.failure(
        '${descriptor.displayName} 房间号格式不合法：$trimmedRoomId',
      );
    }

    return ParseRoomInputResult.success(
      ParsedRoomInput(
        providerId: providerId,
        providerName: descriptor.displayName,
        roomId: trimmedRoomId,
        normalizedInput: normalizedInput,
      ),
    );
  }
}

class ParseRoomInputResult {
  const ParseRoomInputResult.success(this.parsedRoom)
      : errorMessage = null,
        isSuccess = true;

  const ParseRoomInputResult.failure(this.errorMessage)
      : parsedRoom = null,
        isSuccess = false;

  final ParsedRoomInput? parsedRoom;
  final String? errorMessage;
  final bool isSuccess;
}

class ParsedRoomInput {
  const ParsedRoomInput({
    required this.providerId,
    required this.providerName,
    required this.roomId,
    required this.normalizedInput,
  });

  final ProviderId providerId;
  final String providerName;
  final String roomId;
  final String normalizedInput;
}
