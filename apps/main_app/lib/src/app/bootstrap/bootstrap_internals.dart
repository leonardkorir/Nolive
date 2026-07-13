part of 'bootstrap.dart';

bool _decodeBoolSetting(String? raw, {bool fallback = false}) {
  if (raw == null || raw.isEmpty) {
    return fallback;
  }
  switch (raw.trim().toLowerCase()) {
    case 'true':
    case '1':
    case 'yes':
    case 'on':
      return true;
    case 'false':
    case '0':
    case 'no':
    case 'off':
      return false;
    default:
      return fallback;
  }
}

const String _storageFileName = 'nolive_storage.json';
const String _legacyStorageFileName = 'simplelive_storage.json';

Future<File> _resolveStorageFile(Directory directory) async {
  final storageFile = File(
    '${directory.path}${Platform.pathSeparator}$_storageFileName',
  );
  if (await storageFile.exists()) {
    return storageFile;
  }

  final legacyFile = File(
    '${directory.path}${Platform.pathSeparator}$_legacyStorageFileName',
  );
  if (!await legacyFile.exists()) {
    return storageFile;
  }

  try {
    return await legacyFile.rename(storageFile.path);
  } on FileSystemException {
    try {
      await legacyFile.copy(storageFile.path);
    } on FileSystemException {
      if (await storageFile.exists()) {
        await storageFile.delete();
      }
      rethrow;
    }
    await legacyFile.delete();
    return storageFile;
  }
}

PlayerBackend _decodePlayerBackend(String? raw) {
  return PlayerBackend.values.firstWhere(
    (item) => item.name == raw,
    orElse: () => PlayerBackend.mpv,
  );
}

class _BootstrapStateBundle {
  _BootstrapStateBundle()
    : themeMode = ValueNotifier<ThemeMode>(ThemeMode.system),
      layoutPreferences = ValueNotifier<LayoutPreferences>(
        LayoutPreferences.defaults(),
      ),
      providerCatalogRevision = ValueNotifier<int>(0),
      followDataRevision = ValueNotifier<int>(0),
      followWatchlistSnapshot = ValueNotifier<FollowWatchlist?>(null);

  final ValueNotifier<ThemeMode> themeMode;
  final ValueNotifier<LayoutPreferences> layoutPreferences;
  final ValueNotifier<int> providerCatalogRevision;
  final ValueNotifier<int> followDataRevision;
  final ValueNotifier<FollowWatchlist?> followWatchlistSnapshot;
}

class _BootstrapRepositories {
  const _BootstrapRepositories({
    required this.settingsRepository,
    required this.historyRepository,
    required this.followRepository,
    required this.tagRepository,
    required this.settingsSnapshot,
  });

  factory _BootstrapRepositories.inMemory() {
    final settingsRepository = InMemorySettingsRepository();
    return _BootstrapRepositories(
      settingsRepository: settingsRepository,
      historyRepository: InMemoryHistoryRepository(),
      followRepository: InMemoryFollowRepository(),
      tagRepository: InMemoryTagRepository(),
      settingsSnapshot: settingsRepository.dump,
    );
  }

  factory _BootstrapRepositories.persistent(LocalStorageFileStore store) {
    return _BootstrapRepositories(
      settingsRepository: FileSettingsRepository(store),
      historyRepository: FileHistoryRepository(store),
      followRepository: FileFollowRepository(store),
      tagRepository: FileTagRepository(store),
      settingsSnapshot: store.settingsSnapshot,
    );
  }

  final SettingsRepository settingsRepository;
  final HistoryRepository historyRepository;
  final FollowRepository followRepository;
  final TagRepository tagRepository;
  final Map<String, Object?> Function() settingsSnapshot;
}

class _BootstrapSettingReaders {
  const _BootstrapSettingReaders({
    required this.stringSetting,
    required this.intSetting,
  });

  factory _BootstrapSettingReaders.fromSnapshot(
    Map<String, Object?> Function() snapshot, {
    required Map<String, String> Function() secureSnapshot,
  }) {
    return _BootstrapSettingReaders(
      stringSetting: (key) {
        final secureValue = secureSnapshot()[key];
        if (secureValue != null) {
          return secureValue;
        }
        return snapshot()[key]?.toString() ?? '';
      },
      intSetting: (key) {
        final value = snapshot()[key];
        if (value is int) {
          return value;
        }
        if (value is num) {
          return value.toInt();
        }
        return int.tryParse(value?.toString() ?? '') ?? 0;
      },
    );
  }

  final String Function(String key) stringSetting;
  final int Function(String key) intSetting;
}

class _BootstrapAccountClients {
  const _BootstrapAccountClients({
    required this.bilibili,
    required this.douyin,
  });

  final BilibiliAccountClient bilibili;
  final DouyinAccountClient douyin;
}

class _BootstrapAssemblyContext {
  const _BootstrapAssemblyContext({
    required this.mode,
    required this.platformCapabilities,
    required this.state,
    required this.repositories,
    required this.settings,
    required this.secureCredentialStore,
    required this.warmUpSecureCredentialStore,
    required this.accountClients,
    required this.disposeResources,
  });

  final AppRuntimeMode mode;
  final AppPlatformCapabilities platformCapabilities;
  final _BootstrapStateBundle state;
  final _BootstrapRepositories repositories;
  final _BootstrapSettingReaders settings;
  final SecureCredentialStore secureCredentialStore;
  final Future<void> Function() warmUpSecureCredentialStore;
  final _BootstrapAccountClients accountClients;
  final Future<void> Function() disposeResources;
}

AppBootstrap _assembleAppBootstrap(_BootstrapAssemblyContext context) {
  final loadProviderAccountSettings = LoadProviderAccountSettingsUseCase(
    context.repositories.settingsRepository,
    context.secureCredentialStore,
  );
  final runtimeBridges = _buildAppRuntimeBridges(
    mode: context.mode,
    platformCapabilities: context.platformCapabilities,
    loadProviderAccountSettings: loadProviderAccountSettings,
    secureCredentialStore: context.secureCredentialStore,
  );
  final providerRegistry = _buildProviderRegistry(
    context,
    runtimeBridges: runtimeBridges,
  );
  final player = _buildPlayer(context);
  final playerRuntime = PlayerRuntimeController(player);
  final snapshotService = RepositorySyncSnapshotService(
    settingsRepository: context.repositories.settingsRepository,
    historyRepository: context.repositories.historyRepository,
    followRepository: context.repositories.followRepository,
    tagRepository: context.repositories.tagRepository,
    shouldIncludeSettingInSnapshot: (key) {
      return !SensitiveSettingKeys.isSnapshotExcludedKey(key);
    },
  );
  final snapshotImportCoordinator = SecureSnapshotImportCoordinator(
    snapshotService: snapshotService,
    secureCredentialStore: context.secureCredentialStore,
    // 局域网/WebDAV 导入写盘后必须通知 UI：否则关注页会沿用旧缓存，
    // 看起来像「没同步」，重启 App 才出现内容。
    onAfterImport: ({
      required bool followDataChanged,
      required bool settingsChanged,
    }) async {
      if (settingsChanged) {
        await syncThemeModeNotifierFromSettings(
          settingsRepository: context.repositories.settingsRepository,
          themeModeNotifier: context.state.themeMode,
        );
        await syncLayoutPreferencesNotifierFromSettings(
          settingsRepository: context.repositories.settingsRepository,
          preferencesNotifier: context.state.layoutPreferences,
        );
        providerRegistry.clearCache();
        context.state.providerCatalogRevision.value += 1;
      }
      if (followDataChanged) {
        context.state.followWatchlistSnapshot.value = null;
        context.state.followDataRevision.value += 1;
      }
    },
  );
  Future<LocalSyncPeerInfo>? localPeerInfoInFlight;

  String generateSecureHexToken({
    required String prefix,
    required int byteCount,
  }) {
    final random = Random.secure();
    final buffer = StringBuffer(prefix);
    for (var index = 0; index < byteCount; index += 1) {
      buffer.write(random.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  String generateLocalSyncDeviceId() {
    return generateSecureHexToken(prefix: 'nolive-', byteCount: 16);
  }

  String generateLocalSyncAccessToken() {
    return generateSecureHexToken(prefix: '', byteCount: 32);
  }

  bool isValidLocalSyncDeviceId(String value) {
    return RegExp(r'^nolive-[0-9a-f]{32}$').hasMatch(value.trim());
  }

  final storedInitialAccessToken = context.settings
      .stringSetting(SensitiveSettingKeys.syncLocalAccessToken)
      .trim();
  final initialLocalSyncAccessToken = storedInitialAccessToken.isNotEmpty
      ? storedInitialAccessToken
      : generateLocalSyncAccessToken();

  Future<String> loadLocalSyncAccessToken() async {
    await context.secureCredentialStore.ensureReady();
    final secureAccessToken = await context.secureCredentialStore.read(
      SensitiveSettingKeys.syncLocalAccessToken,
    );
    final legacyAccessToken = await context.repositories.settingsRepository
        .readValue<String>(SensitiveSettingKeys.syncLocalAccessToken);
    final nextAccessToken = secureAccessToken.trim().isNotEmpty
        ? secureAccessToken.trim()
        : (legacyAccessToken?.trim().isNotEmpty == true
              ? legacyAccessToken!.trim()
              : initialLocalSyncAccessToken);
    await context.secureCredentialStore.write(
      SensitiveSettingKeys.syncLocalAccessToken,
      nextAccessToken,
    );
    if (context.secureCredentialStore.storesSecureValuesSeparately) {
      await context.repositories.settingsRepository.remove(
        SensitiveSettingKeys.syncLocalAccessToken,
      );
    }
    return nextAccessToken;
  }

  Future<LocalSyncPeerInfo> loadLocalPeerInfo() async {
    final storedName = await context.repositories.settingsRepository
        .readValue<String>('sync_local_device_name');
    final storedDeviceId = await context.repositories.settingsRepository
        .readValue<String>(SensitiveSettingKeys.syncLocalDeviceId);
    final displayName = storedName?.trim();
    final normalizedStoredDeviceId = storedDeviceId?.trim() ?? '';
    final nextDeviceId = isValidLocalSyncDeviceId(normalizedStoredDeviceId)
        ? normalizedStoredDeviceId
        : generateLocalSyncDeviceId();
    final nextAccessToken = await loadLocalSyncAccessToken();
    if (normalizedStoredDeviceId != nextDeviceId) {
      await context.repositories.settingsRepository.writeValue(
        SensitiveSettingKeys.syncLocalDeviceId,
        nextDeviceId,
      );
    }
    return LocalSyncPeerInfo(
      displayName: displayName == null || displayName.isEmpty
          ? 'nolive-device'
          : displayName,
      deviceId: nextDeviceId,
      platform: _localSyncPlatformLabel(context.platformCapabilities),
      accessToken: nextAccessToken,
    );
  }

  Future<LocalSyncPeerInfo> readLocalPeerInfo() async {
    final inFlight = localPeerInfoInFlight;
    if (inFlight != null) {
      return inFlight;
    }
    final future = loadLocalPeerInfo();
    localPeerInfoInFlight = future;
    try {
      return await future;
    } finally {
      if (identical(localPeerInfoInFlight, future)) {
        localPeerInfoInFlight = null;
      }
    }
  }

  final localDiscoveryService = UdpLocalDiscoveryService(
    readInfo: readLocalPeerInfo,
  );
  final localSyncServer = HttpLocalSyncServer(
    exportSnapshot: snapshotService.exportSnapshot,
    importSnapshot: snapshotImportCoordinator.importSnapshot,
    exportCategory: snapshotService.exportCategory,
    importCategory: snapshotImportCoordinator.importCategory,
    rollbackCategory: snapshotImportCoordinator.restoreCategoryBackup,
    readInfo: readLocalPeerInfo,
    accessTokenResolver: loadLocalSyncAccessToken,
  );
  final localSyncClient = HttpLocalSyncClient();

  final loadLayoutPreferences = LoadLayoutPreferencesUseCase(
    context.repositories.settingsRepository,
  );
  final updateLayoutPreferences = UpdateLayoutPreferencesUseCase(
    settingsRepository: context.repositories.settingsRepository,
    preferencesNotifier: context.state.layoutPreferences,
  );
  final listAvailableProviders = ListAvailableProvidersUseCase(
    providerRegistry,
    context.state.layoutPreferences,
  );
  final listLibrarySnapshot = ListLibrarySnapshotUseCase(
    historyRepository: context.repositories.historyRepository,
    followRepository: context.repositories.followRepository,
    tagRepository: context.repositories.tagRepository,
  );
  final loadSyncSnapshot = LoadSyncSnapshotUseCase(snapshotService);
  final updateProviderAccountSettings = UpdateProviderAccountSettingsUseCase(
    context.repositories.settingsRepository,
    context.secureCredentialStore,
    providerRegistry: providerRegistry,
    providerCatalogRevision: context.state.providerCatalogRevision,
  );
  final loadFollowPreferences = LoadFollowPreferencesUseCase(
    context.repositories.settingsRepository,
  );
  final updateFollowPreferences = UpdateFollowPreferencesUseCase(
    context.repositories.settingsRepository,
  );
  final loadHistoryPreferences = LoadHistoryPreferencesUseCase(
    context.repositories.settingsRepository,
  );
  final updateHistoryPreferences = UpdateHistoryPreferencesUseCase(
    context.repositories.settingsRepository,
  );
  final listProviderDescriptors = ListProviderDescriptorsUseCase(
    providerRegistry,
  );
  final findProviderDescriptorById = FindProviderDescriptorByIdUseCase(
    providerRegistry,
  );
  final listFollowRecords = ListFollowRecordsUseCase(
    context.repositories.followRepository,
  );

  final llhlsProxyRegistry = LlhlsProxyRegistry(
    chaturbateProxy: runtimeBridges.chaturbateLlHlsProxy,
    stripchatProxy: runtimeBridges.stripchatLlHlsProxy,
    twitchProxy: runtimeBridges.twitchAdGuardProxy,
    releaseRuntimeWebPressure: () async {
      await runtimeBridges.twitchWebPlaybackBridge?.releasePressure(
        reason: 'room left',
      );
      final youtubeSolver = runtimeBridges.youtubeNSigSolver;
      if (youtubeSolver is YouTubeWebViewNSigSolver) {
        await youtubeSolver.releasePressure(reason: 'room left');
      }
    },
  );

  return AppBootstrap(
    mode: context.mode,
    warmUpSecureCredentialStore: context.warmUpSecureCredentialStore,
    themeMode: context.state.themeMode,
    layoutPreferences: context.state.layoutPreferences,
    providerCatalogRevision: context.state.providerCatalogRevision,
    followDataRevision: context.state.followDataRevision,
    followWatchlistSnapshot: context.state.followWatchlistSnapshot,
    providerRegistry: providerRegistry,
    playerRuntime: playerRuntime,
    llhlsProxyRegistry: llhlsProxyRegistry,
    settingsRepository: context.repositories.settingsRepository,
    historyRepository: context.repositories.historyRepository,
    followRepository: context.repositories.followRepository,
    tagRepository: context.repositories.tagRepository,
    listProviderDescriptors: listProviderDescriptors,
    findProviderDescriptorById: findProviderDescriptorById,
    listFollowRecords: listFollowRecords,
    listAvailableProviders: listAvailableProviders,
    loadLayoutPreferences: loadLayoutPreferences,
    updateLayoutPreferences: updateLayoutPreferences,
    loadReferenceRoomPreview: LoadReferenceRoomPreviewUseCase(providerRegistry),
    loadHomeDashboard: LoadHomeDashboardUseCase(
      listAvailableProviders: listAvailableProviders,
      listLibrarySnapshot: listLibrarySnapshot,
      loadSyncSnapshot: loadSyncSnapshot,
    ),
    loadProviderHighlights: LoadProviderHighlightsUseCase(
      registry: providerRegistry,
      listAvailableProviders: listAvailableProviders,
    ),
    loadProviderRecommendRooms: LoadProviderRecommendRoomsUseCase(
      providerRegistry,
    ),
    loadProviderCategories: LoadProviderCategoriesUseCase(providerRegistry),
    loadFavoriteCategoryTags: LoadFavoriteCategoryTagsUseCase(
      context.repositories.settingsRepository,
    ),
    toggleFavoriteCategoryTag: ToggleFavoriteCategoryTagUseCase(
      context.repositories.settingsRepository,
    ),
    loadCategoryRooms: LoadCategoryRoomsUseCase(providerRegistry),
    loadRoom: LoadRoomUseCase(
      providerRegistry,
      historyRepository: context.repositories.historyRepository,
      roomDetailOverride: runtimeBridges.roomDetailOverride,
      resolveRecordHistoryEnabled: () async {
        final preferences = await loadHistoryPreferences();
        return preferences.recordWatchHistory;
      },
    ),
    openRoomDanmaku: OpenRoomDanmakuUseCase(providerRegistry),
    resolvePlaySource: ResolvePlaySourceUseCase(
      providerRegistry,
      wrapChaturbatePlayUrls: runtimeBridges.chaturbateLlHlsProxy?.wrapPlayUrls,
      wrapStripchatPlayUrls: runtimeBridges.stripchatLlHlsProxy?.wrapPlayUrls,
      wrapTwitchPlayUrls: runtimeBridges.twitchAdGuardProxy?.wrapPlayUrls,
    ),
    searchProviderRooms: SearchProviderRoomsUseCase(providerRegistry),
    listLibrarySnapshot: listLibrarySnapshot,
    loadLibraryDashboard: LoadLibraryDashboardUseCase(
      listLibrarySnapshot: listLibrarySnapshot,
      listTags: ListTagsUseCase(context.repositories.tagRepository),
    ),
    loadFollowWatchlist: LoadFollowWatchlistUseCase(
      followRepository: context.repositories.followRepository,
      registry: providerRegistry,
      roomDetailOverride: runtimeBridges.roomDetailOverride,
    ),
    loadFollowPreferences: loadFollowPreferences,
    updateFollowPreferences: updateFollowPreferences,
    loadHistoryPreferences: loadHistoryPreferences,
    updateHistoryPreferences: updateHistoryPreferences,
    exportFollowListJson: ExportFollowListJsonUseCase(
      context.repositories.followRepository,
    ),
    importFollowListJson: ImportFollowListJsonUseCase(
      followRepository: context.repositories.followRepository,
      tagRepository: context.repositories.tagRepository,
      followWatchlistSnapshot: context.state.followWatchlistSnapshot,
      followDataRevision: context.state.followDataRevision,
    ),
    toggleFollowRoom: ToggleFollowRoomUseCase(
      context.repositories.followRepository,
      followDataRevision: context.state.followDataRevision,
    ),
    isFollowedRoom: IsFollowedRoomUseCase(
      context.repositories.followRepository,
    ),
    listTags: ListTagsUseCase(context.repositories.tagRepository),
    createTag: CreateTagUseCase(context.repositories.tagRepository),
    removeTag: RemoveTagUseCase(
      tagRepository: context.repositories.tagRepository,
      followRepository: context.repositories.followRepository,
    ),
    clearTags: ClearTagsUseCase(
      tagRepository: context.repositories.tagRepository,
      followRepository: context.repositories.followRepository,
    ),
    updateFollowTags: UpdateFollowTagsUseCase(
      followRepository: context.repositories.followRepository,
      tagRepository: context.repositories.tagRepository,
    ),
    removeFollowRoom: RemoveFollowRoomUseCase(
      context.repositories.followRepository,
      followDataRevision: context.state.followDataRevision,
    ),
    removeHistoryRecord: RemoveHistoryRecordUseCase(
      context.repositories.historyRepository,
    ),
    clearHistory: ClearHistoryUseCase(context.repositories.historyRepository),
    loadSyncSnapshot: loadSyncSnapshot,
    loadSyncPreferences: LoadSyncPreferencesUseCase(
      context.repositories.settingsRepository,
      context.secureCredentialStore,
    ),
    updateSyncPreferences: UpdateSyncPreferencesUseCase(
      context.repositories.settingsRepository,
      context.secureCredentialStore,
    ),
    verifyWebDavConnection: const VerifyWebDavConnectionUseCase(),
    uploadWebDavSnapshot: UploadWebDavSnapshotUseCase(snapshotService),
    restoreWebDavSnapshot: RestoreWebDavSnapshotUseCase(
      snapshotImportCoordinator,
    ),
    pushLocalSyncSnapshot: PushLocalSyncSnapshotUseCase(
      snapshotService: snapshotService,
      client: localSyncClient,
      loadSensitiveCredentials: () async {
        await context.secureCredentialStore.ensureReady();
        final all = await context.secureCredentialStore.readAll();
        return <String, String>{
          for (final entry in all.entries)
            if (SensitiveSettingKeys.isTransferableCredentialKey(entry.key) &&
                entry.value.trim().isNotEmpty)
              entry.key: entry.value.trim(),
        };
      },
    ),
    loadProviderAccountSettings: loadProviderAccountSettings,
    updateProviderAccountSettings: updateProviderAccountSettings,
    loadProviderAccountDashboard: LoadProviderAccountDashboardUseCase(
      loadSettings: loadProviderAccountSettings,
      updateSettings: updateProviderAccountSettings,
      bilibiliAccountClient: context.accountClients.bilibili,
      douyinAccountClient: context.accountClients.douyin,
    ),
    createBilibiliQrLoginSession: CreateBilibiliQrLoginSessionUseCase(
      context.accountClients.bilibili,
    ),
    pollBilibiliQrLoginSession: PollBilibiliQrLoginSessionUseCase(
      accountClient: context.accountClients.bilibili,
      loadSettings: loadProviderAccountSettings,
      updateSettings: updateProviderAccountSettings,
    ),
    clearProviderAccount: ClearProviderAccountUseCase(
      loadSettings: loadProviderAccountSettings,
      updateSettings: updateProviderAccountSettings,
    ),
    localDiscoveryService: localDiscoveryService,
    localSyncServer: localSyncServer,
    localSyncClient: localSyncClient,
    exportLegacyConfigJson: ExportLegacyConfigJsonUseCase(snapshotService),
    exportSyncSnapshotJson: ExportSyncSnapshotJsonUseCase(snapshotService),
    importSyncSnapshotJson: ImportSyncSnapshotJsonUseCase(
      snapshotService: snapshotService,
      settingsRepository: context.repositories.settingsRepository,
      followRepository: context.repositories.followRepository,
      tagRepository: context.repositories.tagRepository,
      snapshotImportCoordinator: snapshotImportCoordinator,
      themeModeNotifier: context.state.themeMode,
      layoutPreferencesNotifier: context.state.layoutPreferences,
      providerRegistry: providerRegistry,
      providerCatalogRevision: context.state.providerCatalogRevision,
      followWatchlistSnapshot: context.state.followWatchlistSnapshot,
      followDataRevision: context.state.followDataRevision,
    ),
    exportCredentialMigrationBundle: ExportCredentialMigrationBundleUseCase(
      context.secureCredentialStore,
    ),
    importCredentialMigrationBundle: ImportCredentialMigrationBundleUseCase(
      secureCredentialStore: context.secureCredentialStore,
      settingsRepository: context.repositories.settingsRepository,
      providerRegistry: providerRegistry,
      providerCatalogRevision: context.state.providerCatalogRevision,
    ),
    clearSensitiveCredentials: ClearSensitiveCredentialsUseCase(
      secureCredentialStore: context.secureCredentialStore,
      settingsRepository: context.repositories.settingsRepository,
      providerRegistry: providerRegistry,
      providerCatalogRevision: context.state.providerCatalogRevision,
    ),
    resetAppData: ResetAppDataUseCase(
      settingsRepository: context.repositories.settingsRepository,
      historyRepository: context.repositories.historyRepository,
      followRepository: context.repositories.followRepository,
      tagRepository: context.repositories.tagRepository,
      themeModeNotifier: context.state.themeMode,
      layoutPreferencesNotifier: context.state.layoutPreferences,
      providerRegistry: providerRegistry,
      providerCatalogRevision: context.state.providerCatalogRevision,
      followWatchlistSnapshot: context.state.followWatchlistSnapshot,
      followDataRevision: context.state.followDataRevision,
    ),
    updateThemeMode: UpdateThemeModeUseCase(
      settingsRepository: context.repositories.settingsRepository,
      themeModeNotifier: context.state.themeMode,
    ),
    loadBlockedKeywords: LoadBlockedKeywordsUseCase(
      context.repositories.settingsRepository,
    ),
    addBlockedKeyword: AddBlockedKeywordUseCase(
      context.repositories.settingsRepository,
    ),
    removeBlockedKeyword: RemoveBlockedKeywordUseCase(
      context.repositories.settingsRepository,
    ),
    loadDanmakuPreferences: LoadDanmakuPreferencesUseCase(
      context.repositories.settingsRepository,
    ),
    updateDanmakuPreferences: UpdateDanmakuPreferencesUseCase(
      context.repositories.settingsRepository,
    ),
    clearFollows: ClearFollowsUseCase(
      context.repositories.followRepository,
      followWatchlistSnapshot: context.state.followWatchlistSnapshot,
      followDataRevision: context.state.followDataRevision,
    ),
    loadRoomUiPreferences: LoadRoomUiPreferencesUseCase(
      context.repositories.settingsRepository,
    ),
    updateRoomUiPreferences: UpdateRoomUiPreferencesUseCase(
      context.repositories.settingsRepository,
    ),
    loadPlayerPreferences: LoadPlayerPreferencesUseCase(
      context.repositories.settingsRepository,
    ),
    updatePlayerPreferences: UpdatePlayerPreferencesUseCase(
      context.repositories.settingsRepository,
    ),
    applyPlayerPreferencesToRuntime: ApplyPlayerPreferencesToRuntimeUseCase(
      playerRuntime,
      usesSystemMediaVolume: () =>
          context.mode == AppRuntimeMode.live &&
          context.platformCapabilities.isAndroid,
      setSystemMediaVolume: AndroidPlaybackBridge.instance.setMediaVolume,
    ),
    parseRoomInput: ParseRoomInputUseCase(providerRegistry),
    inspectParsedRoom: InspectParsedRoomUseCase(
      providerRegistry,
      roomDetailOverride: runtimeBridges.roomDetailOverride,
    ),
    disposeResources: () async {
      await localDiscoveryService.dispose();
      await localSyncServer.stop();
      await localSyncClient.close(force: true);
      providerRegistry.clearCache();
      await runtimeBridges.dispose();
      await playerRuntime.dispose();
      await context.disposeResources();
    },
  );
}

String _localSyncPlatformLabel(AppPlatformCapabilities platform) {
  if (platform.isAndroid) {
    return 'android-mobile';
  }
  if (platform.isIOS) {
    return 'ios-mobile';
  }
  if (platform.isLinux) {
    return 'desktop-linux';
  }
  if (platform.isMacOS) {
    return 'desktop-macos';
  }
  if (platform.isWindows) {
    return 'desktop-windows';
  }
  return 'unknown';
}

ProviderRegistry _buildProviderRegistry(
  _BootstrapAssemblyContext context, {
  required AppRuntimeBridges runtimeBridges,
}) {
  return switch (context.mode) {
    AppRuntimeMode.preview => ReferenceProviderCatalog.buildPreviewRegistry(),
    AppRuntimeMode.live => ReferenceProviderCatalog.buildLiveRegistry(
      stringSetting: context.settings.stringSetting,
      intSetting: context.settings.intSetting,
      douyinDanmakuSignatureBuilder: context.platformCapabilities.isAndroid
          ? (roomId, userUniqueId) => DouyinDanmakuSignatureService.instance
                .buildSignature(roomId: roomId, userUniqueId: userUniqueId)
          : null,
      twitchPlaybackBootstrapResolver:
          runtimeBridges.twitchWebPlaybackBridge?.call,
      youtubeNSigSolver: runtimeBridges.youtubeNSigSolver,
      chaturbateDiagnostics: (message) {
        AppLog.instance.info(
          'provider/chaturbate',
          message
              .replaceAll(RegExp(r'token=[^&\s]+'), 'token=***')
              .replaceAll(RegExp(r'access_token=[^&\s]+'), 'access_token=***'),
        );
      },
    ),
  };
}

AppRuntimeBridges _buildAppRuntimeBridges({
  required AppRuntimeMode mode,
  required AppPlatformCapabilities platformCapabilities,
  required LoadProviderAccountSettingsUseCase loadProviderAccountSettings,
  required SecureCredentialStore secureCredentialStore,
}) {
  final chaturbateWebRoomDetailLoader = _buildChaturbateRoomDetailLoader(
    mode: mode,
    platformCapabilities: platformCapabilities,
    loadProviderAccountSettings: loadProviderAccountSettings,
  );
  return AppRuntimeBridges(
    chaturbateLlHlsProxy: _buildChaturbateLlHlsProxy(
      mode: mode,
      platformCapabilities: platformCapabilities,
    ),
    stripchatLlHlsProxy: _buildStripchatLlHlsProxy(
      mode: mode,
      platformCapabilities: platformCapabilities,
      loadProviderAccountSettings: loadProviderAccountSettings,
    ),
    roomDetailOverride: chaturbateWebRoomDetailLoader?.call,
    twitchWebPlaybackBridge: _buildTwitchWebPlaybackBridge(
      mode: mode,
      platformCapabilities: platformCapabilities,
      loadProviderAccountSettings: loadProviderAccountSettings,
    ),
    twitchAdGuardProxy: _buildTwitchAdGuardProxy(
      mode: mode,
      platformCapabilities: platformCapabilities,
    ),
    youtubeNSigSolver: _buildYouTubeNSigSolver(
      mode: mode,
      platformCapabilities: platformCapabilities,
    ),
  );
}

BasePlayer _buildPlayer(_BootstrapAssemblyContext context) {
  final initialBackend = _decodePlayerBackend(
    context.settings.stringSetting('player_backend'),
  );
  if (context.mode != AppRuntimeMode.live) {
    return SwitchablePlayer.simulated(initialBackend: initialBackend);
  }
  return SwitchablePlayer(
    initialBackend: initialBackend,
    builders: {
      PlayerBackend.memory: MemoryPlayer.new,
      PlayerBackend.mpv: () {
        final mpvNativeLogEnabled =
            !kReleaseMode &&
            _decodeBoolSetting(
              context.settings.stringSetting('player_mpv_log_enable'),
            );
        return MpvPlayer(
          isAndroid: context.platformCapabilities.isAndroid,
          enableHardwareAcceleration: _decodeBoolSetting(
            context.settings.stringSetting('player_mpv_hardware_acceleration'),
            fallback: true,
          ),
          compatMode: _decodeBoolSetting(
            context.settings.stringSetting('player_mpv_compat_mode'),
          ),
          doubleBufferingEnabled: _decodeBoolSetting(
            context.settings.stringSetting('player_mpv_double_buffering'),
          ),
          customOutputEnabled: _decodeBoolSetting(
            context.settings.stringSetting('player_mpv_custom_output'),
          ),
          videoOutputDriver: context.settings.stringSetting(
            'player_mpv_video_output_driver',
          ),
          audioOutputDriver: context.settings.stringSetting(
            'player_mpv_audio_output_driver',
          ),
          hardwareDecoder: context.settings.stringSetting(
            'player_mpv_hardware_decoder',
          ),
          logEnabled: mpvNativeLogEnabled,
          eventLogger: (message) => AppLog.instance.info('player/mpv', message),
        );
      },
      PlayerBackend.mdk: () => MdkPlayer(
        lowLatency: _decodeBoolSetting(
          context.settings.stringSetting('player_mdk_low_latency'),
          fallback: true,
        ),
        androidTunnel: _decodeBoolSetting(
          context.settings.stringSetting('player_mdk_android_tunnel'),
        ),
        androidPreferHardwareVideoDecoder: _decodeBoolSetting(
          context.settings.stringSetting(
            'player_mdk_android_hardware_video_decoder',
          ),
          fallback: true,
        ),
      ),
    },
  );
}

ChaturbateWebRoomDetailLoader? _buildChaturbateRoomDetailLoader({
  required AppRuntimeMode mode,
  required AppPlatformCapabilities platformCapabilities,
  required LoadProviderAccountSettingsUseCase loadProviderAccountSettings,
}) {
  if (mode != AppRuntimeMode.live) {
    return null;
  }
  if (!platformCapabilities.isMobile) {
    return null;
  }
  return ChaturbateWebRoomDetailLoader(
    platformAdapter: HlsProxyPlatformAdapterImpl(
      platformCapabilities: platformCapabilities,
    ),
    loadCookie: () async {
      final settings = await loadProviderAccountSettings();
      return settings.chaturbateCookie;
    },
  );
}

ChaturbateLlHlsProxy? _buildChaturbateLlHlsProxy({
  required AppRuntimeMode mode,
  required AppPlatformCapabilities platformCapabilities,
}) {
  if (mode != AppRuntimeMode.live) {
    return null;
  }
  if (!platformCapabilities.isMobile) {
    return null;
  }
  return ChaturbateLlHlsProxy(
    platformAdapter: HlsProxyPlatformAdapterImpl(
      platformCapabilities: platformCapabilities,
    ),
  );
}

StripchatLlHlsProxy? _buildStripchatLlHlsProxy({
  required AppRuntimeMode mode,
  required AppPlatformCapabilities platformCapabilities,
  required LoadProviderAccountSettingsUseCase loadProviderAccountSettings,
}) {
  if (mode != AppRuntimeMode.live) {
    return null;
  }
  if (!platformCapabilities.isMobile) {
    return null;
  }
  return StripchatLlHlsProxy(
    enablePdkeyFallback: true,
    platformAdapter: HlsProxyPlatformAdapterImpl(
      platformCapabilities: platformCapabilities,
    ),
    decodedUrlResolver: null,
    warmDecodedUrlBridge: null,
    pdkeyResolver: () async {
      final settings = await loadProviderAccountSettings();
      return settings.stripchatMouflonKeys;
    },
  );
}

TwitchWebPlaybackBridge? _buildTwitchWebPlaybackBridge({
  required AppRuntimeMode mode,
  required AppPlatformCapabilities platformCapabilities,
  required LoadProviderAccountSettingsUseCase loadProviderAccountSettings,
}) {
  if (mode != AppRuntimeMode.live) {
    return null;
  }
  if (!platformCapabilities.isMobile) {
    return null;
  }
  final bridge = TwitchWebPlaybackBridge(
    platformAdapter: HlsProxyPlatformAdapterImpl(
      platformCapabilities: platformCapabilities,
    ),
    loadCookie: () async {
      final settings = await loadProviderAccountSettings();
      return settings.twitchCookie;
    },
    timeout: const Duration(seconds: 6),
    bootstrapScriptTimeout: const Duration(milliseconds: 2500),
  );
  return bridge;
}

TwitchAdGuardProxy? _buildTwitchAdGuardProxy({
  required AppRuntimeMode mode,
  required AppPlatformCapabilities platformCapabilities,
}) {
  if (mode != AppRuntimeMode.live) {
    return null;
  }
  if (!platformCapabilities.isMobile) {
    return null;
  }
  return TwitchAdGuardProxy(
    platformAdapter: HlsProxyPlatformAdapterImpl(
      platformCapabilities: platformCapabilities,
    ),
  );
}

YouTubeNSigSolver? _buildYouTubeNSigSolver({
  required AppRuntimeMode mode,
  required AppPlatformCapabilities platformCapabilities,
}) {
  if (mode != AppRuntimeMode.live) {
    return null;
  }
  if (!_supportsYouTubeNSigWebView(platformCapabilities)) {
    return null;
  }
  return YouTubeWebViewNSigSolver(
    platformAdapter: HlsProxyPlatformAdapterImpl(
      platformCapabilities: platformCapabilities,
    ),
  );
}

bool _supportsYouTubeNSigWebView(AppPlatformCapabilities platformCapabilities) {
  return platformCapabilities.isMobile ||
      platformCapabilities.isMacOS ||
      platformCapabilities.isWindows;
}
