class SensitiveSettingKeys {
  const SensitiveSettingKeys._();

  static const String accountBilibiliCookie = 'account_bilibili_cookie';
  static const String accountChaturbateCookie = 'account_chaturbate_cookie';
  static const String accountDouyinCookie = 'account_douyin_cookie';
  static const String accountStripchatCookie = 'account_stripchat_cookie';
  static const String accountStripchatMouflonKeys =
      'account_stripchat_mouflon_keys';
  static const String accountTwitchCookie = 'account_twitch_cookie';
  static const String accountYouTubeCookie = 'account_youtube_cookie';
  static const String syncWebDavPassword = 'sync_webdav_password';
  static const String syncLocalDeviceId = 'sync_local_device_id';
  static const String syncLocalAccessToken = 'sync_local_access_token';
  static const String syncLocalPeerAccessToken = 'sync_local_peer_access_token';

  static const Set<String> secureCredentialKeys = <String>{
    accountBilibiliCookie,
    accountChaturbateCookie,
    accountDouyinCookie,
    accountStripchatCookie,
    accountStripchatMouflonKeys,
    accountTwitchCookie,
    accountYouTubeCookie,
    syncWebDavPassword,
    syncLocalAccessToken,
    syncLocalPeerAccessToken,
  };

  static const Set<String> snapshotExcludedKeys = <String>{
    ...secureCredentialKeys,
    syncLocalDeviceId,
  };

  static bool isSecureCredentialKey(String key) {
    return secureCredentialKeys.contains(key);
  }

  static bool isSnapshotExcludedKey(String key) {
    return snapshotExcludedKeys.contains(key);
  }
}
