/// Twitch GraphQL operation hashes used for persisted queries.
abstract class TwitchGraphQlHashes {
  /// Operation: SideNav
  /// Origin: Twilight web client side navigation queries.
  static const String sideNav =
      '3d96d9a885e7761ccd4bab5d19f66eb6e1a0005cb94700afa8309676ca3052a5';

  /// Operation: BrowsePage_Popular
  /// Origin: Twilight web client popular browse directory queries.
  static const String browsePopular =
      'fb60a7f9b2fe8f9c9a080f41585bd4564bea9d3030f4d7cb8ab7f9e99b1cee67';

  /// Operation: BrowsePage_AllDirectories
  /// Origin: Twilight web client browsing all categories/directories.
  static const String browseAllDirectories =
      '2f67f71ba89f3c0ed26a141ec00da1defecb2303595f5cda4298169549783d9e';

  /// Operation: DirectoryPage_Game
  /// Origin: Twilight web client browsing game/category directory detail pages.
  static const String directoryPageGame =
      '76cb069d835b8a02914c08dc42c421d0dafda8af5b113a3f19141824b901402f';

  /// Operation: SearchResultsPage_SearchResults
  /// Origin: Twilight web client search functionality.
  static const String search =
      'a7c600111acc4d1b294eafa364600556227939e2ff88505faa73035b57a83b22';

  /// Operation: ChannelShell
  /// Origin: Twilight web client channel shell metadata.
  static const String channelShell =
      'fea4573a7bf2644f5b3f2cbbdcbee0d17312e48d2e55f080589d053aad353f11';

  /// Operation: StreamMetadata
  /// Origin: Twilight web client live stream metadata status queries.
  static const String streamMetadata =
      'ad022ca32220d5523d03a23cbcb5beaa1e0999889c1f8f78f9f2520dafb5cae6';

  /// Operation: UseViewCount
  /// Origin: Twilight web client viewer counts query.
  static const String useViewCount =
      'e28de6b91c2ac736882f4960e7de60ca4a4eeebc06affdc45d6408b19318cef7';

  /// Operation: UseLiveBroadcast
  /// Origin: Twilight web client live broadcast attributes query.
  static const String useLiveBroadcast =
      '0b47cc6d8c182acd2e78b81c8ba5414a5a38057f2089b1bbcfa6046aae248bd2';
}
