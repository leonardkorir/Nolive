part of 'room_preview_page.dart';

extension _RoomPreviewPagePlayerSystemExtension on _RoomPreviewPageState {
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

  Future<void> _enterFullscreen() async {
    if (_isFullscreen) {
      return;
    }
    _inlineChromeTimer?.cancel();
    _updateViewState(() {
      _isFullscreen = true;
      _showInlinePlayerChrome = false;
      _showFullscreenChrome = true;
      _gestureTipText = null;
    });
    _scheduleFullscreenChromeAutoHide();
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
      _gestureTipText = null;
    });
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
    if (!Platform.isAndroid) {
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
          _gestureTipText = null;
        });
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
    if (!_isFullscreen || _lockFullscreenControls) {
      return;
    }
    _fullscreenChromeTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted || !_isFullscreen || _lockFullscreenControls) {
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
        _gestureTipText = null;
        if (shouldRestoreDanmaku) {
          _showDanmakuOverlay = false;
          _restoreDanmakuAfterPip = true;
        }
      });
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
      _updateViewState(() {
        _gestureTipText = '亮度 ${(brightness * 100).round()}%';
      });
      return;
    }
    final nextVolume = (_gestureStartVolume + delta).clamp(0.0, 1.0);
    await AndroidPlaybackBridge.instance.setMediaVolume(nextVolume);
    if (!mounted) {
      return;
    }
    _updateViewState(() {
      _volume = nextVolume;
      _gestureTipText = '音量 ${(nextVolume * 100).round()}%';
    });
  }

  Future<void> _handleVerticalDragEnd(DragEndDetails details) async {
    if (!_gestureTracking) {
      return;
    }
    _gestureTracking = false;
    if (!mounted) {
      return;
    }
    _updateViewState(() {
      _gestureTipText = null;
    });
  }
}
