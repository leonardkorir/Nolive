part of 'bootstrap.dart';

bool _decodeBoolSetting(String? raw, {bool fallback = false}) {
  if (raw == null || raw.isEmpty) {
    return fallback;
  }
  return raw.toLowerCase() == 'true';
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
    await legacyFile.copy(storageFile.path);
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
    Map<String, Object?> Function() snapshot,
  ) {
    return _BootstrapSettingReaders(
      stringSetting: (key) => snapshot()[key]?.toString() ?? '',
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
    required this.state,
    required this.repositories,
    required this.settings,
    required this.accountClients,
  });

  final AppRuntimeMode mode;
  final _BootstrapStateBundle state;
  final _BootstrapRepositories repositories;
  final _BootstrapSettingReaders settings;
  final _BootstrapAccountClients accountClients;
}

AppBootstrap _assembleAppBootstrap(_BootstrapAssemblyContext context) {
  final loadProviderAccountSettings = LoadProviderAccountSettingsUseCase(
    context.repositories.settingsRepository,
  );
  final twitchAdGuardProxy = _buildTwitchAdGuardProxy(mode: context.mode);
  final twitchWebPlaybackBridge = _buildTwitchWebPlaybackBridge(
    mode: context.mode,
    loadProviderAccountSettings: loadProviderAccountSettings,
  );
  final providerRegistry = _buildProviderRegistry(
    context,
    twitchWebPlaybackBridge: twitchWebPlaybackBridge,
  );
  final player = _buildPlayer(context);
  final snapshotService = RepositorySyncSnapshotService(
    settingsRepository: context.repositories.settingsRepository,
    historyRepository: context.repositories.historyRepository,
    followRepository: context.repositories.followRepository,
    tagRepository: context.repositories.tagRepository,
  );
  final localDiscoveryService = ManualLocalDiscoveryService();
  final localSyncServer = HttpLocalSyncServer(
    exportSnapshot: snapshotService.exportSnapshot,
    importSnapshot: snapshotService.importSnapshot,
    readInfo: () async {
      final storedName = await context.repositories.settingsRepository
          .readValue<String>('sync_local_device_name');
      final deviceName = storedName?.trim();
      return LocalSyncPeerInfo(
        displayName: deviceName == null || deviceName.isEmpty
            ? 'nolive-device'
            : deviceName,
      );
    },
  );
  final localSyncClient = HttpLocalSyncClient();

  final loadLayoutPreferences =
      LoadLayoutPreferencesUseCase(context.repositories.settingsRepository);
  final updateLayoutPreferences = UpdateLayoutPreferencesUseCase(
    settingsRepository: context.repositories.settingsRepository,
    preferencesNotifier: context.state.layoutPreferences,
  );
  final listAvailableProviders = ListAvailableProvidersUseCase(
    providerRegistry,
    context.state.layoutPreferences,
    stringSetting: context.settings.stringSetting,
  );
  final listLibrarySnapshot = ListLibrarySnapshotUseCase(
    historyRepository: context.repositories.historyRepository,
    followRepository: context.repositories.followRepository,
    tagRepository: context.repositories.tagRepository,
  );
  final loadSyncSnapshot = LoadSyncSnapshotUseCase(snapshotService);
  final updateProviderAccountSettings = UpdateProviderAccountSettingsUseCase(
    context.repositories.settingsRepository,
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
  final chaturbateWebRoomDetailLoader = _buildChaturbateRoomDetailLoader(
    mode: context.mode,
    loadProviderAccountSettings: loadProviderAccountSettings,
  );

  return AppBootstrap(
    mode: context.mode,
    themeMode: context.state.themeMode,
    layoutPreferences: context.state.layoutPreferences,
    providerCatalogRevision: context.state.providerCatalogRevision,
    followDataRevision: context.state.followDataRevision,
    followWatchlistSnapshot: context.state.followWatchlistSnapshot,
    providerRegistry: providerRegistry,
    player: player,
    settingsRepository: context.repositories.settingsRepository,
    historyRepository: context.repositories.historyRepository,
    followRepository: context.repositories.followRepository,
    tagRepository: context.repositories.tagRepository,
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
    loadProviderRecommendRooms:
        LoadProviderRecommendRoomsUseCase(providerRegistry),
    loadProviderCategories: LoadProviderCategoriesUseCase(providerRegistry),
    loadCategoryRooms: LoadCategoryRoomsUseCase(providerRegistry),
    loadRoom: LoadRoomUseCase(
      providerRegistry,
      historyRepository: context.repositories.historyRepository,
      loadRoomDetailOverride: chaturbateWebRoomDetailLoader?.call,
      resolveRecordHistoryEnabled: () async {
        final preferences = await loadHistoryPreferences();
        return preferences.recordWatchHistory;
      },
    ),
    openRoomDanmaku: OpenRoomDanmakuUseCase(providerRegistry),
    resolvePlaySource: ResolvePlaySourceUseCase(
      providerRegistry,
      twitchAdGuardProxy: twitchAdGuardProxy,
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
      loadRoomDetailOverride: chaturbateWebRoomDetailLoader?.call,
    ),
    loadFollowPreferences: loadFollowPreferences,
    updateFollowPreferences: updateFollowPreferences,
    loadHistoryPreferences: loadHistoryPreferences,
    updateHistoryPreferences: updateHistoryPreferences,
    exportFollowListJson:
        ExportFollowListJsonUseCase(context.repositories.followRepository),
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
    isFollowedRoom:
        IsFollowedRoomUseCase(context.repositories.followRepository),
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
    removeHistoryRecord:
        RemoveHistoryRecordUseCase(context.repositories.historyRepository),
    clearHistory: ClearHistoryUseCase(context.repositories.historyRepository),
    loadSyncSnapshot: loadSyncSnapshot,
    loadSyncPreferences:
        LoadSyncPreferencesUseCase(context.repositories.settingsRepository),
    updateSyncPreferences:
        UpdateSyncPreferencesUseCase(context.repositories.settingsRepository),
    verifyWebDavConnection: const VerifyWebDavConnectionUseCase(),
    uploadWebDavSnapshot: UploadWebDavSnapshotUseCase(snapshotService),
    restoreWebDavSnapshot: RestoreWebDavSnapshotUseCase(snapshotService),
    pushLocalSyncSnapshot: PushLocalSyncSnapshotUseCase(
      snapshotService: snapshotService,
      client: localSyncClient,
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
    exportLegacyConfigJson: ExportLegacyConfigJsonUseCase(
      settingsRepository: context.repositories.settingsRepository,
      historyRepository: context.repositories.historyRepository,
      followRepository: context.repositories.followRepository,
      tagRepository: context.repositories.tagRepository,
    ),
    exportSyncSnapshotJson: ExportSyncSnapshotJsonUseCase(snapshotService),
    importSyncSnapshotJson: ImportSyncSnapshotJsonUseCase(
      snapshotService: snapshotService,
      settingsRepository: context.repositories.settingsRepository,
      followRepository: context.repositories.followRepository,
      tagRepository: context.repositories.tagRepository,
      themeModeNotifier: context.state.themeMode,
      layoutPreferencesNotifier: context.state.layoutPreferences,
      providerRegistry: providerRegistry,
      providerCatalogRevision: context.state.providerCatalogRevision,
      followWatchlistSnapshot: context.state.followWatchlistSnapshot,
      followDataRevision: context.state.followDataRevision,
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
    loadBlockedKeywords:
        LoadBlockedKeywordsUseCase(context.repositories.settingsRepository),
    addBlockedKeyword:
        AddBlockedKeywordUseCase(context.repositories.settingsRepository),
    removeBlockedKeyword:
        RemoveBlockedKeywordUseCase(context.repositories.settingsRepository),
    loadDanmakuPreferences:
        LoadDanmakuPreferencesUseCase(context.repositories.settingsRepository),
    updateDanmakuPreferences: UpdateDanmakuPreferencesUseCase(
        context.repositories.settingsRepository),
    clearFollows: ClearFollowsUseCase(
      context.repositories.followRepository,
      followWatchlistSnapshot: context.state.followWatchlistSnapshot,
      followDataRevision: context.state.followDataRevision,
    ),
    loadRoomUiPreferences:
        LoadRoomUiPreferencesUseCase(context.repositories.settingsRepository),
    updateRoomUiPreferences:
        UpdateRoomUiPreferencesUseCase(context.repositories.settingsRepository),
    loadPlayerPreferences:
        LoadPlayerPreferencesUseCase(context.repositories.settingsRepository),
    updatePlayerPreferences:
        UpdatePlayerPreferencesUseCase(context.repositories.settingsRepository),
    parseRoomInput: ParseRoomInputUseCase(providerRegistry),
    inspectParsedRoom: InspectParsedRoomUseCase(
      providerRegistry,
      loadProviderAccountSettings: loadProviderAccountSettings,
      requireChaturbateCookiePreflight: context.mode == AppRuntimeMode.live,
      loadRoomDetailOverride: chaturbateWebRoomDetailLoader?.call,
    ),
  );
}

ProviderRegistry _buildProviderRegistry(
  _BootstrapAssemblyContext context, {
  TwitchWebPlaybackBridge? twitchWebPlaybackBridge,
}) {
  return switch (context.mode) {
    AppRuntimeMode.preview => ReferenceProviderCatalog.buildPreviewRegistry(),
    AppRuntimeMode.live => ReferenceProviderCatalog.buildLiveRegistry(
        stringSetting: context.settings.stringSetting,
        intSetting: context.settings.intSetting,
        douyinDanmakuSignatureBuilder: Platform.isAndroid
            ? (roomId, userUniqueId) =>
                DouyinDanmakuSignatureService.instance.buildSignature(
                  roomId: roomId,
                  userUniqueId: userUniqueId,
                )
            : null,
        twitchPlaybackBootstrapResolver: twitchWebPlaybackBridge?.call,
      ),
  };
}

BasePlayer _buildPlayer(_BootstrapAssemblyContext context) {
  final initialBackend = _decodePlayerBackend(
    context.settings.stringSetting('player_backend'),
  );
  if (context.mode != AppRuntimeMode.live) {
    return SwitchablePlayer(initialBackend: initialBackend);
  }
  return SwitchablePlayer(
    initialBackend: initialBackend,
    builders: {
      PlayerBackend.memory: MemoryPlayer.new,
      PlayerBackend.mpv: () => MpvPlayer(
            enableHardwareAcceleration: _decodeBoolSetting(
              context.settings.stringSetting(
                'player_mpv_hardware_acceleration',
              ),
              fallback: true,
            ),
            compatMode: _decodeBoolSetting(
              context.settings.stringSetting('player_mpv_compat_mode'),
            ),
          ),
      PlayerBackend.mdk: () => MdkPlayer(
            lowLatency: _decodeBoolSetting(
              context.settings.stringSetting('player_mdk_low_latency'),
              fallback: true,
            ),
            androidTunnel: _decodeBoolSetting(
              context.settings.stringSetting('player_mdk_android_tunnel'),
            ),
          ),
    },
  );
}

ChaturbateWebRoomDetailLoader? _buildChaturbateRoomDetailLoader({
  required AppRuntimeMode mode,
  required LoadProviderAccountSettingsUseCase loadProviderAccountSettings,
}) {
  if (mode != AppRuntimeMode.live) {
    return null;
  }
  if (!Platform.isAndroid && !Platform.isIOS) {
    return null;
  }
  return ChaturbateWebRoomDetailLoader(
    loadProviderAccountSettings: loadProviderAccountSettings,
  );
}

TwitchWebPlaybackBridge? _buildTwitchWebPlaybackBridge({
  required AppRuntimeMode mode,
  required LoadProviderAccountSettingsUseCase loadProviderAccountSettings,
}) {
  if (mode != AppRuntimeMode.live) {
    return null;
  }
  if (!Platform.isAndroid && !Platform.isIOS) {
    return null;
  }
  final bridge = TwitchWebPlaybackBridge(
    loadProviderAccountSettings: loadProviderAccountSettings,
    timeout: const Duration(seconds: 6),
    bootstrapScriptTimeout: const Duration(milliseconds: 2500),
  );
  unawaited(bridge.warmUp());
  return bridge;
}

TwitchAdGuardProxy? _buildTwitchAdGuardProxy({
  required AppRuntimeMode mode,
}) {
  if (mode != AppRuntimeMode.live) {
    return null;
  }
  if (!Platform.isAndroid && !Platform.isIOS) {
    return null;
  }
  return TwitchAdGuardProxy();
}
