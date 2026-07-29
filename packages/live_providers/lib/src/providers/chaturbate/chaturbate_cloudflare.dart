/// Stable marker in [ProviderParseException.message] for a Cloudflare
/// interstitial, so callers can branch on it without matching prose.
///
/// Mirrors the `kChaturbatePasswordRequiredMarker` convention.
const String kChaturbateCloudflareChallengeMarker =
    'received a cloudflare challenge page';

/// Whether [error] is Chaturbate's Cloudflare interstitial rejection.
bool isChaturbateCloudflareChallengeError(Object? error) {
  if (error == null) {
    return false;
  }
  return error.toString().toLowerCase().contains(
    kChaturbateCloudflareChallengeMarker,
  );
}
