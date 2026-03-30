part of 'room_preview_page.dart';

extension _RoomPreviewPagePlayerSystemExtension on _RoomPreviewPageState {
  void _schedulePlaybackBootstrap({
    required PlaybackSource? playbackSource,
    required bool hasPlayback,
    required bool autoPlay,
  }) {
    if (_pendingPlaybackAvailable == hasPlayback &&
        _pendingPlaybackAutoPlay == autoPlay &&
        _samePlaybackSource(_pendingPlaybackSource, playbackSource)) {
      return;
    }
    _pendingPlaybackAvailable = hasPlayback;
    _pendingPlaybackAutoPlay = autoPlay;
    _pendingPlaybackSource = playbackSource;
    if (_playbackBootstrapScheduled) {
      return;
    }
    _playbackBootstrapScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _playbackBootstrapScheduled = false;
      if (!mounted) {
        return;
      }
      final targetAvailable = _pendingPlaybackAvailable;
      final targetAutoPlay = _pendingPlaybackAutoPlay;
      final targetSource = _pendingPlaybackSource;
      final player = widget.bootstrap.player;
      final currentSource = player.currentState.source;
      final isInitialTwitchBootstrap =
          widget.providerId == ProviderId.twitch && currentSource == null;

      if (!targetAvailable || targetSource == null) {
        final status = player.currentState.status;
        if (player.currentState.source != null ||
            status == PlaybackStatus.playing ||
            status == PlaybackStatus.ready ||
            status == PlaybackStatus.buffering ||
            status == PlaybackStatus.paused) {
          _roomTrace('playback bootstrap stop current=${status.name}');
          await player.stop();
        }
        return;
      }

      if (isInitialTwitchBootstrap) {
        _roomTrace('twitch initial bootstrap wait-surface');
        await WidgetsBinding.instance.endOfFrame;
        await Future<void>.delayed(const Duration(milliseconds: 220));
        if (!mounted) {
          return;
        }
        if (_pendingPlaybackAvailable != targetAvailable ||
            _pendingPlaybackAutoPlay != targetAutoPlay ||
            !_samePlaybackSource(_pendingPlaybackSource, targetSource)) {
          _schedulePlaybackBootstrap(
            playbackSource: _pendingPlaybackSource,
            hasPlayback: _pendingPlaybackAvailable,
            autoPlay: _pendingPlaybackAutoPlay,
          );
          return;
        }
      }

      if (!_samePlaybackSource(currentSource, targetSource)) {
        _roomTrace(
          'playback bootstrap setSource '
          '${_summarizePlaybackSource(targetSource)}',
        );
        await player.setSource(targetSource);
        if (widget.providerId == ProviderId.twitch) {
          await Future<void>.delayed(
            isInitialTwitchBootstrap
                ? const Duration(milliseconds: 220)
                : const Duration(milliseconds: 120),
          );
        }
      }
      if (targetAutoPlay &&
          player.currentState.status != PlaybackStatus.playing) {
        _roomTrace(
          'playback bootstrap play source=${_summarizePlaybackSource(targetSource)}',
        );
        await player.play();
      }

      if (_pendingPlaybackAvailable != targetAvailable ||
          _pendingPlaybackAutoPlay != targetAutoPlay ||
          !_samePlaybackSource(_pendingPlaybackSource, targetSource)) {
        _schedulePlaybackBootstrap(
          playbackSource: _pendingPlaybackSource,
          hasPlayback: _pendingPlaybackAvailable,
          autoPlay: _pendingPlaybackAutoPlay,
        );
      }
    });
  }

  void _scheduleTwitchPlaybackRecovery({
    required LoadedRoomSnapshot snapshot,
    required PlaybackSource? playbackSource,
    required List<LivePlayUrl> playUrls,
    required List<LivePlayQuality> qualities,
    required LivePlayQuality selectedQuality,
  }) {
    if (widget.providerId != ProviderId.twitch || playbackSource == null) {
      return;
    }
    final sourceKey = playbackSource.url.toString();
    if (_twitchRecoverySourceKey == sourceKey) {
      return;
    }
    _twitchRecoverySourceKey = sourceKey;
    final token = ++_twitchRecoveryToken;
    final delay = resolveTwitchRecoveryDelay(
      currentQuality: _selectedQuality ?? selectedQuality,
      recoveryAttempts: _twitchRecoveryAttempts,
    );
    Future<void>.delayed(delay, () async {
      if (!mounted || token != _twitchRecoveryToken) {
        return;
      }
      final currentState = widget.bootstrap.player.currentState;
      if (!_samePlaybackSource(currentState.source, playbackSource)) {
        return;
      }
      final currentQuality = _selectedQuality ?? selectedQuality;
      final promotionQuality = _twitchStartupPromotionQuality;
      if (promotionQuality != null && currentQuality.id == 'auto') {
        if (shouldPromoteTwitchPlaybackQuality(currentState)) {
          _roomTrace(
            'twitch startup promotion '
            'pos=${currentState.position.inMilliseconds}ms '
            'buffer=${currentState.buffered.inMilliseconds}ms '
            'switch-quality=${promotionQuality.id}/${promotionQuality.label}',
          );
          _twitchRecoveryAttempts = 0;
          _twitchStartupPromotionQuality = null;
          await _switchQuality(
            snapshot,
            promotionQuality,
            resetTwitchRecoveryAttempts: false,
          );
          return;
        }
        if (shouldAttemptTwitchPlaybackRecovery(currentState) &&
            _twitchRecoveryAttempts == 1) {
          _twitchRecoveryAttempts = 2;
          _roomTrace(
            'twitch startup promotion refresh '
            'pos=${currentState.position.inMilliseconds}ms '
            'buffer=${currentState.buffered.inMilliseconds}ms '
            'quality=${currentQuality.id}/${currentQuality.label}',
          );
          await _refreshPlaybackSource(
            snapshot,
            currentQuality,
            twitchStartupPromotionQuality: promotionQuality,
            resetTwitchRecoveryAttempts: false,
          );
          return;
        }
        if (shouldAttemptTwitchPlaybackRecovery(currentState) &&
            _twitchRecoveryAttempts >= 2) {
          _roomTrace(
            'twitch startup promotion recovery '
            'pos=${currentState.position.inMilliseconds}ms '
            'buffer=${currentState.buffered.inMilliseconds}ms '
            'switch-quality=${promotionQuality.id}/${promotionQuality.label}',
          );
          _twitchStartupPromotionQuality = null;
          _twitchRecoveryAttempts = 0;
          await _switchQuality(
            snapshot,
            promotionQuality,
            resetTwitchRecoveryAttempts: false,
          );
          return;
        }
        if (_twitchRecoveryAttempts == 0) {
          _twitchRecoveryAttempts = 1;
        }
        _roomTrace(
          'twitch startup promotion wait '
          'pos=${currentState.position.inMilliseconds}ms '
          'buffer=${currentState.buffered.inMilliseconds}ms '
          'target=${promotionQuality.id}/${promotionQuality.label}',
        );
        _twitchRecoverySourceKey = null;
        _scheduleTwitchPlaybackRecovery(
          snapshot: snapshot,
          playbackSource: playbackSource,
          playUrls: playUrls,
          qualities: qualities,
          selectedQuality: currentQuality,
        );
        return;
      }
      final fixedRecovery = resolveTwitchFixedRecoveryDecision(
        state: currentState,
        recoveryAttempts: _twitchRecoveryAttempts,
        playbackSource: playbackSource,
        playUrls: playUrls,
      );
      switch (fixedRecovery.action) {
        case TwitchFixedRecoveryAction.none:
          return;
        case TwitchFixedRecoveryAction.switchLine:
          _twitchRecoveryAttempts = 1;
          final recoveryLine = fixedRecovery.recoveryLine;
          if (recoveryLine == null) {
            return;
          }
          _roomTrace(
            'twitch startup recovery '
            'pos=${currentState.position.inMilliseconds}ms '
            'buffer=${currentState.buffered.inMilliseconds}ms '
            'switch-line=${recoveryLine.lineLabel ?? '-'} '
            'playerType=${recoveryLine.metadata?['playerType'] ?? '-'}',
          );
          await _switchLine(
            recoveryLine,
            resetTwitchRecoveryAttempts: false,
          );
          return;
        case TwitchFixedRecoveryAction.refreshCurrentLine:
          _twitchRecoveryAttempts = 2;
          _roomTrace(
            'twitch startup recovery '
            'pos=${currentState.position.inMilliseconds}ms '
            'buffer=${currentState.buffered.inMilliseconds}ms '
            'action=refresh-current-line '
            'quality=${currentQuality.id}/${currentQuality.label}',
          );
          await _refreshPlaybackSource(
            snapshot,
            currentQuality,
            resetTwitchRecoveryAttempts: false,
            preferredPlaybackSource: playbackSource,
            currentPlayUrls: playUrls,
          );
          return;
        case TwitchFixedRecoveryAction.stop:
          _roomTrace(
            'twitch startup recovery '
            'pos=${currentState.position.inMilliseconds}ms '
            'buffer=${currentState.buffered.inMilliseconds}ms '
            'action=stop-after-line-refresh',
          );
          return;
      }
    });
  }

  bool _samePlaybackSource(PlaybackSource? left, PlaybackSource? right) {
    if (left == null || right == null) {
      return left == right;
    }
    return left.url == right.url &&
        mapEquals(left.headers, right.headers) &&
        _sameExternalMedia(left.externalAudio, right.externalAudio);
  }

  bool _sameExternalMedia(
    PlaybackExternalMedia? left,
    PlaybackExternalMedia? right,
  ) {
    if (left == null || right == null) {
      return left == right;
    }
    return left.url == right.url && mapEquals(left.headers, right.headers);
  }

  void _resolveFullscreenBootstrap({
    required bool roomLoaded,
    required bool playbackAvailable,
  }) {
    if (!_fullscreenBootstrapPending || _isFullscreen) {
      return;
    }
    if (!roomLoaded) {
      return;
    }
    if (!playbackAvailable) {
      if (_fullscreenBootstrapScheduled) {
        return;
      }
      _fullscreenBootstrapScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _fullscreenBootstrapScheduled = false;
        if (!mounted || !_fullscreenBootstrapPending) {
          return;
        }
        _cancelPendingFullscreenBootstrap(scheduleInlineChrome: true);
      });
      return;
    }
    if (_fullscreenBootstrapScheduled) {
      return;
    }
    _fullscreenBootstrapScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _fullscreenBootstrapScheduled = false;
      if (!mounted || !_fullscreenBootstrapPending || _isFullscreen) {
        return;
      }
      _updateViewState(() {
        _fullscreenBootstrapPending = false;
        _isFullscreen = true;
        _showInlinePlayerChrome = false;
        _showFullscreenChrome = true;
        _showFullscreenFollowDrawer = false;
      });
      _clearGestureTip();
      _scheduleFullscreenChromeAutoHide();
      await _applyFullscreenSystemUi();
    });
  }

  void _cancelPendingFullscreenBootstrap({
    required bool scheduleInlineChrome,
  }) {
    if (!_fullscreenBootstrapPending && !_fullscreenBootstrapScheduled) {
      return;
    }
    _fullscreenBootstrapScheduled = false;
    _updateViewState(() {
      _fullscreenBootstrapPending = false;
      _showInlinePlayerChrome = true;
      _showFullscreenChrome = true;
      _showFullscreenFollowDrawer = false;
    });
    _clearGestureTip();
    unawaited(_restoreSystemUi());
    if (scheduleInlineChrome) {
      _scheduleInlineChromeAutoHide();
    }
  }

  void _showGestureTip(String text) {
    _gestureTipTimer?.cancel();
    _fullscreenChromeTimer?.cancel();
    _updateViewState(() {
      _gestureTipText = text;
      if (_isFullscreen) {
        _showFullscreenChrome = true;
      }
    });
    _gestureTipTimer = Timer(const Duration(milliseconds: 900), () {
      if (!mounted) {
        return;
      }
      _updateViewState(() {
        _gestureTipText = null;
      });
      if (_isFullscreen && _showFullscreenChrome) {
        _scheduleFullscreenChromeAutoHide();
      }
    });
  }

  void _clearGestureTip() {
    _gestureTipTimer?.cancel();
    _gestureTipTimer = null;
    if (_gestureTipText == null) {
      return;
    }
    _updateViewState(() {
      _gestureTipText = null;
    });
    if (_isFullscreen && _showFullscreenChrome) {
      _scheduleFullscreenChromeAutoHide();
    }
  }

  Future<void> _applyOverlayStyle({required bool darkBackground}) async {
    final style = (darkBackground
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark)
        .copyWith(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
    );
    SystemChrome.setSystemUIOverlayStyle(style);
  }

  Future<void> _applyFullscreenSystemUi() async {
    await _applyOverlayStyle(darkBackground: true);
    if (Platform.isAndroid) {
      await AndroidPlaybackBridge.instance.enableSensorLandscape();
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
  }

  Future<void> _enterFullscreen() async {
    if (_isFullscreen) {
      return;
    }
    if (_desktopMiniWindowActive) {
      await _exitDesktopMiniWindow();
    }
    _inlineChromeTimer?.cancel();
    _updateViewState(() {
      _isFullscreen = true;
      _showInlinePlayerChrome = false;
      _showFullscreenChrome = true;
      _showFullscreenFollowDrawer = false;
    });
    _clearGestureTip();
    _scheduleFullscreenChromeAutoHide();
    await _applyFullscreenSystemUi();
  }

  Future<void> _exitFullscreen() async {
    if (!_isFullscreen) {
      return;
    }
    _fullscreenChromeTimer?.cancel();
    _updateViewState(() {
      _isFullscreen = false;
      _showInlinePlayerChrome = true;
      _showFullscreenChrome = true;
      _lockFullscreenControls = false;
      _showFullscreenFollowDrawer = false;
    });
    _clearGestureTip();
    _scheduleInlineChromeAutoHide();
    await _restoreSystemUi();
  }

  Future<void> _restoreSystemUi() async {
    if (Platform.isAndroid) {
      await AndroidPlaybackBridge.instance.lockPortrait();
    } else {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
    }
    await _applyOverlayStyle(darkBackground: _darkThemeActive);
    if (Platform.isAndroid) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  Future<void> _setScreenAwake(bool enabled) async {
    if (!Platform.isAndroid && !_supportsDesktopMiniWindow) {
      return;
    }
    try {
      await WakelockPlus.toggle(enable: enabled);
    } catch (_) {}
  }

  Future<void> _primeAndroidPlaybackState() async {
    if (!Platform.isAndroid) {
      return;
    }
    _pipStatusSubscription ??= _floating.pipStatusStream.listen((status) {
      if (status == PiPStatus.enabled) {
        _enteringPictureInPicture = false;
        if (!mounted) {
          return;
        }
        _updateViewState(() {
          _showInlinePlayerChrome = false;
          _showFullscreenChrome = false;
          _showFullscreenFollowDrawer = false;
        });
        _clearGestureTip();
        return;
      }
      if (status == PiPStatus.disabled) {
        _enteringPictureInPicture = false;
        if (!mounted || !_restoreDanmakuAfterPip) {
          return;
        }
        _updateViewState(() {
          _showDanmakuOverlay = _danmakuVisibleBeforePip;
          _restoreDanmakuAfterPip = false;
        });
      }
    });
    final pipSupported = await _floating.isPipAvailable;
    final mediaVolume = await AndroidPlaybackBridge.instance.getMediaVolume();
    if (!mounted) {
      return;
    }
    _updateViewState(() {
      _pipSupported = pipSupported;
      if (mediaVolume != null) {
        _volume = mediaVolume;
      }
    });
  }

  void _scheduleFullscreenChromeAutoHide() {
    _fullscreenChromeTimer?.cancel();
    if (!_isFullscreen ||
        _lockFullscreenControls ||
        _showFullscreenFollowDrawer ||
        _enteringPictureInPicture ||
        _gestureTipText != null) {
      return;
    }
    _fullscreenChromeTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted ||
          !_isFullscreen ||
          _lockFullscreenControls ||
          _showFullscreenFollowDrawer ||
          _enteringPictureInPicture ||
          _gestureTipText != null) {
        return;
      }
      _updateViewState(() {
        _showFullscreenChrome = false;
      });
    });
  }

  void _scheduleInlineChromeAutoHide() {
    _inlineChromeTimer?.cancel();
    if (_isFullscreen || !_showInlinePlayerChrome) {
      return;
    }
    _inlineChromeTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted || _isFullscreen || !_showInlinePlayerChrome) {
        return;
      }
      _updateViewState(() {
        _showInlinePlayerChrome = false;
      });
    });
  }

  void _toggleInlinePlayerChrome() {
    if (_isFullscreen) {
      return;
    }
    _inlineChromeTimer?.cancel();
    _updateViewState(() {
      _showInlinePlayerChrome = !_showInlinePlayerChrome;
    });
    if (_showInlinePlayerChrome) {
      _scheduleInlineChromeAutoHide();
    }
  }

  void _showInlinePlayerChromeTemporarily() {
    if (_isFullscreen) {
      return;
    }
    _inlineChromeTimer?.cancel();
    if (mounted) {
      _updateViewState(() {
        _showInlinePlayerChrome = true;
      });
    }
    _scheduleInlineChromeAutoHide();
  }

  Future<void> _toggleDesktopMiniWindow() async {
    if (!_supportsDesktopMiniWindow) {
      return;
    }
    try {
      if (_desktopMiniWindowActive) {
        await _exitDesktopMiniWindow();
      } else {
        await _enterDesktopMiniWindow();
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('桌面小窗切换失败：$error')),
      );
    }
  }

  Future<void> _enterDesktopMiniWindow() async {
    if (!_supportsDesktopMiniWindow || _desktopMiniWindowActive) {
      return;
    }
    if (_isFullscreen) {
      await _exitFullscreen();
    }
    _desktopWindowBoundsBeforeMini ??= await windowManager.getBounds();
    _desktopWindowWasAlwaysOnTop ??= await windowManager.isAlwaysOnTop();
    _desktopWindowWasResizable ??= await windowManager.isResizable();
    final currentBounds = _desktopWindowBoundsBeforeMini!;
    final width = currentBounds.width.clamp(360.0, 420.0);
    final height = width / (16 / 9);
    final left =
        currentBounds.left + math.max(0.0, currentBounds.width - width);
    final top = currentBounds.top + 24;
    await windowManager.setAlwaysOnTop(true);
    await windowManager.setResizable(false);
    await windowManager.setBounds(
      Rect.fromLTWH(left, top, width, height),
      animate: true,
    );
    if (!mounted) {
      return;
    }
    _updateViewState(() {
      _desktopMiniWindowActive = true;
      _showInlinePlayerChrome = true;
    });
    _scheduleInlineChromeAutoHide();
  }

  Future<void> _exitDesktopMiniWindow() async {
    if (!_supportsDesktopMiniWindow) {
      return;
    }
    final bounds = _desktopWindowBoundsBeforeMini;
    final alwaysOnTop = _desktopWindowWasAlwaysOnTop ?? false;
    final resizable = _desktopWindowWasResizable ?? true;
    await windowManager.setAlwaysOnTop(alwaysOnTop);
    await windowManager.setResizable(resizable);
    if (bounds != null) {
      await windowManager.setBounds(bounds, animate: true);
    }
    _desktopWindowBoundsBeforeMini = null;
    _desktopWindowWasAlwaysOnTop = null;
    _desktopWindowWasResizable = null;
    if (!mounted) {
      return;
    }
    _updateViewState(() {
      _desktopMiniWindowActive = false;
      _showInlinePlayerChrome = true;
    });
    _scheduleInlineChromeAutoHide();
  }

  Future<void> _enterPictureInPicture() async {
    if (!Platform.isAndroid) {
      return;
    }
    final pipAvailable = _pipSupported || await _floating.isPipAvailable;
    if (!pipAvailable) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前设备不支持画中画播放')),
      );
      return;
    }
    _inlineChromeTimer?.cancel();
    _fullscreenChromeTimer?.cancel();
    _danmakuVisibleBeforePip = _showDanmakuOverlay;
    final shouldRestoreDanmaku = _pipHideDanmakuEnabled && _showDanmakuOverlay;
    _enteringPictureInPicture = true;
    if (mounted) {
      _updateViewState(() {
        _showInlinePlayerChrome = false;
        _showFullscreenChrome = false;
        _showFullscreenFollowDrawer = false;
        if (shouldRestoreDanmaku) {
          _showDanmakuOverlay = false;
          _restoreDanmakuAfterPip = true;
        }
      });
      _clearGestureTip();
    } else if (shouldRestoreDanmaku) {
      _restoreDanmakuAfterPip = true;
    }
    PiPStatus status;
    try {
      status = await _floating.enable(
        ImmediatePiP(
          aspectRatio: _pictureInPictureAspectRatio(),
        ),
      );
    } catch (_) {
      status = await _floating.enable(const ImmediatePiP());
    }
    if (status != PiPStatus.enabled && mounted) {
      _restoreAfterFailedPictureInPicture();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('进入画中画失败，请稍后重试')),
      );
      return;
    }
    if (status != PiPStatus.enabled) {
      _restoreAfterFailedPictureInPicture();
    }
  }

  Future<void> _handleVerticalDragStart(DragStartDetails details) async {
    if (!Platform.isAndroid || !_isFullscreen || _lockFullscreenControls) {
      return;
    }
    _gestureTracking = true;
    _gestureAdjustingBrightness =
        details.globalPosition.dx < MediaQuery.sizeOf(context).width / 2;
    _gestureStartY = details.globalPosition.dy;
    final mediaVolume = await AndroidPlaybackBridge.instance.getMediaVolume();
    _gestureStartVolume = mediaVolume ?? _volume;
    try {
      _gestureStartBrightness = await _screenBrightness.application;
    } catch (_) {
      _gestureStartBrightness = 0.5;
    }
  }

  Future<void> _handleVerticalDragUpdate(DragUpdateDetails details) async {
    if (!_gestureTracking || !Platform.isAndroid || _lockFullscreenControls) {
      return;
    }
    final height = MediaQuery.sizeOf(context).height * 0.55;
    final delta = (_gestureStartY - details.globalPosition.dy) / height;
    if (_gestureAdjustingBrightness) {
      final brightness = (_gestureStartBrightness + delta).clamp(0.0, 1.0);
      try {
        await _screenBrightness.setApplicationScreenBrightness(brightness);
      } catch (_) {}
      if (!mounted) {
        return;
      }
      _showGestureTip('亮度 ${(brightness * 100).round()}%');
      return;
    }
    final nextVolume = (_gestureStartVolume + delta).clamp(0.0, 1.0);
    await AndroidPlaybackBridge.instance.setMediaVolume(nextVolume);
    if (!mounted) {
      return;
    }
    _updateViewState(() {
      _volume = nextVolume;
    });
    _showGestureTip('音量 ${(nextVolume * 100).round()}%');
  }

  Future<void> _handleVerticalDragEnd(DragEndDetails details) async {
    if (!_gestureTracking) {
      return;
    }
    _gestureTracking = false;
    if (_isFullscreen && _showFullscreenChrome) {
      _scheduleFullscreenChromeAutoHide();
    }
  }
}
