part of 'room_preview_page.dart';

extension _RoomPreviewPageControlsExtension on _RoomPreviewPageState {
  void _scheduleCurrentTwitchRecovery({
    required LoadedRoomSnapshot snapshot,
    required PlaybackSource playbackSource,
    required List<LivePlayUrl> playUrls,
    required LivePlayQuality selectedQuality,
  }) {
    _scheduleTwitchPlaybackRecovery(
      snapshot: snapshot,
      playbackSource: playbackSource,
      playUrls: playUrls,
      qualities: snapshot.qualities,
      selectedQuality: selectedQuality,
    );
  }

  Future<ResolvedPlaySource> _resolveTwitchPlaybackRefresh(
    LoadedRoomSnapshot snapshot,
    LivePlayQuality quality,
  ) {
    return widget.bootstrap.resolvePlaySource(
      providerId: snapshot.providerId,
      detail: snapshot.detail,
      quality: quality,
      preferHttps: _forceHttpsEnabled,
    );
  }

  Future<void> _applyResolvedPlaybackSource(
    ResolvedPlaySource resolved, {
    LivePlayQuality? selectedQuality,
    LivePlayQuality? twitchStartupPromotionQuality,
    bool resetTwitchRecoveryAttempts = true,
  }) async {
    if (widget.providerId == ProviderId.twitch) {
      _twitchStartupPromotionQuality = twitchStartupPromotionQuality;
      _twitchRecoveryToken += 1;
      _twitchRecoverySourceKey = null;
      if (resetTwitchRecoveryAttempts) {
        _twitchRecoveryAttempts = 0;
      }
    }
    await widget.bootstrap.player.setSource(resolved.playbackSource);
    if (widget.providerId == ProviderId.twitch) {
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
    if (_autoPlayEnabled) {
      await widget.bootstrap.player.play();
    }
    _updateViewState(() {
      if (selectedQuality != null) {
        _selectedQuality = selectedQuality;
      }
      _effectiveQuality = resolved.effectiveQuality;
      _playbackSource = resolved.playbackSource;
      _playUrls = resolved.playUrls;
      _roomPlaybackAvailable = resolved.playUrls.isNotEmpty;
    });
  }

  Future<void> _switchQuality(
    LoadedRoomSnapshot snapshot,
    LivePlayQuality quality, {
    bool resetTwitchRecoveryAttempts = true,
    LivePlayQuality? twitchStartupPromotionQuality,
  }) async {
    if (!snapshot.hasPlayback) {
      _showPlaybackUnavailableHint(snapshot.playbackUnavailableReason);
      return;
    }
    final resolved = await _resolveTwitchPlaybackRefresh(snapshot, quality);
    _roomTrace(
      'manual switch quality=${quality.id}/${quality.label} '
      'playback=${_summarizePlaybackSource(resolved.playbackSource)}',
    );
    await _applyResolvedPlaybackSource(
      resolved,
      selectedQuality: quality,
      twitchStartupPromotionQuality: twitchStartupPromotionQuality,
      resetTwitchRecoveryAttempts: resetTwitchRecoveryAttempts,
    );
    _scheduleCurrentTwitchRecovery(
      snapshot: snapshot,
      playbackSource: resolved.playbackSource,
      playUrls: resolved.playUrls,
      selectedQuality: quality,
    );
    _showQualityFallbackHint(
      requestedQuality: quality,
      effectiveQuality: resolved.effectiveQuality,
    );
  }

  Future<void> _refreshPlaybackSource(
    LoadedRoomSnapshot snapshot,
    LivePlayQuality quality, {
    LivePlayQuality? twitchStartupPromotionQuality,
    bool resetTwitchRecoveryAttempts = false,
    PlaybackSource? preferredPlaybackSource,
    List<LivePlayUrl>? currentPlayUrls,
  }) async {
    var resolved = await _resolveTwitchPlaybackRefresh(snapshot, quality);
    LivePlayUrl? refreshedLine;
    if (preferredPlaybackSource != null && currentPlayUrls != null) {
      refreshedLine = selectTwitchRefreshLine(
        playbackSource: preferredPlaybackSource,
        currentPlayUrls: currentPlayUrls,
        refreshedPlayUrls: resolved.playUrls,
      );
      if (refreshedLine != null) {
        resolved = ResolvedPlaySource(
          quality: resolved.quality,
          effectiveQuality: resolved.effectiveQuality,
          playUrls: resolved.playUrls,
          playbackSource: playbackSourceFromLivePlayUrl(refreshedLine),
        );
      }
    }
    _roomTrace(
      'refresh playback quality=${quality.id}/${quality.label} '
      'line=${refreshedLine?.lineLabel ?? '-'} '
      'playerType=${refreshedLine?.metadata?['playerType'] ?? '-'} '
      'playback=${_summarizePlaybackSource(resolved.playbackSource)}',
    );
    await _applyResolvedPlaybackSource(
      resolved,
      selectedQuality: quality,
      twitchStartupPromotionQuality: twitchStartupPromotionQuality,
      resetTwitchRecoveryAttempts: resetTwitchRecoveryAttempts,
    );
    _scheduleCurrentTwitchRecovery(
      snapshot: snapshot,
      playbackSource: resolved.playbackSource,
      playUrls: resolved.playUrls,
      selectedQuality: quality,
    );
  }

  Future<void> _switchLine(
    LivePlayUrl playUrl, {
    bool resetTwitchRecoveryAttempts = true,
  }) async {
    final source = playbackSourceFromLivePlayUrl(playUrl);
    _roomTrace(
      'manual switch line=${playUrl.lineLabel ?? '-'} '
      'playerType=${playUrl.metadata?['playerType'] ?? '-'} '
      'playback=${_summarizePlaybackSource(source)}',
    );
    if (widget.providerId == ProviderId.twitch) {
      _twitchStartupPromotionQuality = null;
      _twitchRecoveryToken += 1;
      _twitchRecoverySourceKey = null;
      if (resetTwitchRecoveryAttempts) {
        _twitchRecoveryAttempts = 0;
      }
    }
    await widget.bootstrap.player.setSource(source);
    if (widget.providerId == ProviderId.twitch) {
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
    if (_autoPlayEnabled) {
      await widget.bootstrap.player.play();
    }
    _updateViewState(() {
      _playbackSource = source;
      _roomPlaybackAvailable = true;
    });
    final latestState = _latestLoadedState;
    if (latestState == null) {
      return;
    }
    final selectedQuality =
        _selectedQuality ?? latestState.snapshot.selectedQuality;
    final playUrls =
        _playUrls.isEmpty ? latestState.snapshot.playUrls : _playUrls;
    _scheduleCurrentTwitchRecovery(
      snapshot: latestState.snapshot,
      playbackSource: source,
      playUrls: playUrls,
      selectedQuality: selectedQuality,
    );
  }

  LivePlayQuality _requestedQualityOf(_RoomPageState state) {
    return _selectedQuality ?? state.snapshot.selectedQuality;
  }

  LivePlayQuality _effectiveQualityOf(_RoomPageState state) {
    return _effectiveQuality ??
        state.resolved?.effectiveQuality ??
        _requestedQualityOf(state);
  }

  bool _hasQualityFallback(_RoomPageState state) {
    final requested = _requestedQualityOf(state);
    final effective = _effectiveQualityOf(state);
    return requested.id != effective.id || requested.label != effective.label;
  }

  String _qualityBadgeLabel(_RoomPageState state) {
    final requested = _requestedQualityOf(state);
    final effective = _effectiveQualityOf(state);
    if (!_hasQualityFallback(state)) {
      return effective.label;
    }
    return '${requested.label} · 实际${effective.label}';
  }

  String _lineLabelOf(
      List<LivePlayUrl> playUrls, PlaybackSource playbackSource) {
    if (playUrls.isEmpty) {
      return '线路';
    }
    return playUrls
            .firstWhere(
              (item) => item.url == playbackSource.url.toString(),
              orElse: () => playUrls.first,
            )
            .lineLabel ??
        '线路';
  }

  String _compactQualityLabel(String label) {
    if (label.contains('原画')) {
      return '原画';
    }
    if (label.contains('蓝光')) {
      return '蓝光';
    }
    if (label.contains('超清')) {
      return '超清';
    }
    if (label.contains('高清')) {
      return '高清';
    }
    if (label.contains('流畅') || label.contains('标清')) {
      return '流畅';
    }
    return label.length <= 4 ? label : label.substring(0, 4);
  }

  String _compactLineLabel(String label) {
    if (label.startsWith('线路')) {
      return label;
    }
    return '线路';
  }

  void _showQualityFallbackHint({
    required LivePlayQuality requestedQuality,
    required LivePlayQuality effectiveQuality,
  }) {
    if (!mounted) {
      return;
    }
    if (requestedQuality.id == effectiveQuality.id &&
        requestedQuality.label == effectiveQuality.label) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            '已请求 ${requestedQuality.label}，当前源实际返回 ${effectiveQuality.label}'),
      ),
    );
  }

  void _showPlaybackUnavailableHint(String? reason) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(reason ?? '当前房间暂时没有可用播放地址。'),
      ),
    );
  }

  Future<void> _copyRoomLink(LiveRoomDetail room) async {
    final content = room.sourceUrl?.isNotEmpty == true
        ? room.sourceUrl!
        : (_playbackSource?.url.toString() ?? room.roomId);
    await Clipboard.setData(ClipboardData(text: content));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('直播间链接已复制')),
    );
  }

  Future<void> _shareRoomLink(LiveRoomDetail room) async {
    await _copyRoomLink(room);
  }

  void _showCaptureUnavailableMessage() {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('当前版本暂不支持截图')),
    );
  }

  Future<void> _captureScreenshot() async {
    if (!_supportsPlayerCapture) {
      _showCaptureUnavailableMessage();
      return;
    }
    try {
      final bytes = await widget.bootstrap.player.captureScreenshot();
      if (bytes == null || bytes.isEmpty) {
        throw const FormatException('未获取到图像数据');
      }
      final fileName =
          'nolive-${widget.providerId.value}-${widget.roomId}-${DateTime.now().millisecondsSinceEpoch}.png';
      final savedTarget = await _persistScreenshot(
        bytes: bytes,
        fileName: fileName,
      );
      if (!mounted) {
        return;
      }
      final message = switch (savedTarget) {
        null => '已取消截图保存',
        String path when path == 'gallery' => '已保存截图到系统相册',
        String path => '已保存截图到 $path',
      };
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('截图失败：$error')),
      );
    }
  }

  Future<String?> _persistScreenshot({
    required Uint8List bytes,
    required String fileName,
  }) async {
    if (Platform.isAndroid || Platform.isIOS) {
      final result = await ImageGallerySaverPlus.saveImage(
        bytes,
        name: fileName.replaceAll('.png', ''),
        quality: 100,
      );
      return _resolveGallerySaveResult(result);
    }
    final path = await FilePicker.platform.saveFile(
      dialogTitle: '保存截图',
      fileName: fileName,
      type: FileType.image,
      allowedExtensions: const ['png'],
    );
    if (path == null || path.trim().isEmpty) {
      return null;
    }
    final file = File(path);
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  String _resolveGallerySaveResult(dynamic result) {
    if (result is Map) {
      final normalized = Map<Object?, Object?>.from(result);
      final isSuccess = normalized['isSuccess'] == true ||
          normalized['success'] == true ||
          normalized['ok'] == true;
      if (!isSuccess) {
        throw StateError('系统相册返回保存失败');
      }
      final filePath = normalized['filePath']?.toString().trim();
      if (filePath != null && filePath.isNotEmpty) {
        return filePath;
      }
      return 'gallery';
    }
    if (result == true || result == 1 || result?.toString() == '1') {
      return 'gallery';
    }
    throw StateError('系统相册返回未知结果');
  }

  Future<void> _showPlayerDebugSheet(
    _RoomPageState state,
    PlaybackSource? playbackSource,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: false,
      builder: (context) {
        return StreamBuilder<PlayerDiagnostics>(
          stream: widget.bootstrap.player.diagnostics,
          initialData: widget.bootstrap.player.currentDiagnostics,
          builder: (context, snapshot) {
            final diagnostics =
                snapshot.data ?? widget.bootstrap.player.currentDiagnostics;
            final children = <Widget>[
              const ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('调试面板'),
                subtitle: Text('当前播放器状态、音视频参数与最近日志。'),
              ),
              _MetadataRow(
                label: '播放器内核',
                value: widget.bootstrap.player.backend.name.toUpperCase(),
              ),
              _MetadataRow(
                label: '播放器状态',
                value: widget.bootstrap.player.currentState.status.name,
              ),
              _MetadataRow(
                label: '请求清晰度',
                value: _requestedQualityOf(state).label,
              ),
              _MetadataRow(
                label: '实际清晰度',
                value: _effectiveQualityOf(state).label,
              ),
              _MetadataRow(
                label: '当前线路',
                value: playbackSource?.url.toString() ?? '暂无',
              ),
              _MetadataRow(
                label: '画面尺寸',
                value: diagnostics.width == null
                    ? '未知'
                    : '${diagnostics.width} x ${diagnostics.height ?? '-'}',
              ),
              _MetadataRow(
                label: '缓冲状态',
                value: diagnostics.buffering ? 'buffering' : 'ready',
              ),
              _MetadataRow(
                label: '已缓冲',
                value: '${diagnostics.buffered.inMilliseconds} ms',
              ),
              _MetadataRow(
                label: '画面缩放',
                value: _labelOfScaleMode(_scaleMode),
              ),
              _MetadataRow(
                label: '弹幕频控',
                value: _usingNativeDanmakuBatchMask ? '原生' : 'Dart',
              ),
              _MetadataRow(
                label: '调试日志',
                value: diagnostics.debugLogEnabled ? '已开启' : '未开启',
              ),
              if (diagnostics.error?.isNotEmpty ?? false)
                _MetadataRow(label: '最近错误', value: diagnostics.error!),
            ];

            if (diagnostics.videoParams.isNotEmpty) {
              children.add(
                const Padding(
                  padding: EdgeInsets.only(top: 16, bottom: 8),
                  child: Text('视频参数'),
                ),
              );
              children.addAll(
                diagnostics.videoParams.entries.map(
                  (entry) => _MetadataRow(
                    label: entry.key,
                    value: entry.value,
                  ),
                ),
              );
            }

            if (diagnostics.audioParams.isNotEmpty) {
              children.add(
                const Padding(
                  padding: EdgeInsets.only(top: 16, bottom: 8),
                  child: Text('音频参数'),
                ),
              );
              children.addAll(
                diagnostics.audioParams.entries.map(
                  (entry) => _MetadataRow(
                    label: entry.key,
                    value: entry.value,
                  ),
                ),
              );
            }

            if (diagnostics.recentLogs.isNotEmpty) {
              children.add(
                const Padding(
                  padding: EdgeInsets.only(top: 16, bottom: 8),
                  child: Text('最近日志'),
                ),
              );
              children.add(
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    diagnostics.recentLogs.join('\n'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              );
            }

            return SafeArea(
              child: _buildFlatTileScope(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                  children: children,
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showAutoCloseSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: false,
      builder: (context) {
        return SafeArea(
          child: _buildFlatTileScope(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: const Text('关闭定时关闭'),
                  trailing: _scheduledCloseAt == null
                      ? const Icon(Icons.check_rounded)
                      : null,
                  onTap: () {
                    Navigator.of(context).pop();
                    _setAutoCloseTimer(null);
                  },
                ),
                for (final minutes in const [15, 30, 60, 120])
                  ListTile(
                    title: Text('$minutes 分钟后关闭'),
                    trailing: _scheduledCloseAt != null &&
                            _scheduledCloseAt!
                                    .difference(DateTime.now())
                                    .inMinutes
                                    .clamp(0, minutes) >=
                                minutes - 1
                        ? const Icon(Icons.check_rounded)
                        : null,
                    onTap: () {
                      Navigator.of(context).pop();
                      _setAutoCloseTimer(Duration(minutes: minutes));
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _setAutoCloseTimer(Duration? duration) {
    _autoCloseTimer?.cancel();
    if (duration == null) {
      _updateViewState(() {
        _scheduledCloseAt = null;
      });
      return;
    }
    final scheduled = DateTime.now().add(duration);
    _updateViewState(() {
      _scheduledCloseAt = scheduled;
    });
    _autoCloseTimer = Timer(duration, () async {
      if (!mounted) {
        return;
      }
      await _leaveRoom();
    });
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已设置 ${duration.inMinutes} 分钟后自动关闭')),
    );
  }

  Future<void> _openPlayerSettings() async {
    final navigator = Navigator.of(context);
    if (_isFullscreen) {
      await _exitFullscreen();
      if (!mounted) {
        return;
      }
    }
    await navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => PlayerSettingsPage(bootstrap: widget.bootstrap),
      ),
    );
    if (!mounted) {
      return;
    }
    await _refreshRoom(reloadPlayer: true);
  }

  Future<void> _openDanmakuSettings() async {
    final navigator = Navigator.of(context);
    if (_isFullscreen) {
      await _exitFullscreen();
      if (!mounted) {
        return;
      }
    }
    await navigator.pushNamed(AppRoutes.danmakuSettings);
    if (!mounted) {
      return;
    }
    final blockedKeywords = await widget.bootstrap.loadBlockedKeywords();
    final danmakuPreferences = await widget.bootstrap.loadDanmakuPreferences();
    _updateViewState(() {
      _danmakuPreferences = danmakuPreferences;
      _showDanmakuOverlay = danmakuPreferences.enabledByDefault;
    });
    _replaceDanmakuBatchMask(
      preferNative: danmakuPreferences.nativeBatchMaskEnabled,
    );
    try {
      final state = await _future;
      final session = await widget.bootstrap.openRoomDanmaku(
        providerId: widget.providerId,
        detail: state.snapshot.detail,
      );
      await _bindDanmakuSession(session, blockedKeywords);
    } catch (_) {}
  }

  Widget _buildFlatTileScope({required Widget child}) {
    return ListTileTheme.merge(
      contentPadding: EdgeInsets.zero,
      minLeadingWidth: 24,
      minVerticalPadding: 0,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      child: child,
    );
  }

  Size _pictureInPictureAspectSize() {
    final size = _inlinePlayerViewportSize;
    if (size != null && size.width > 0 && size.height > 0) {
      return size;
    }
    return const Size(16, 9);
  }

  Rational _pictureInPictureAspectRatio() {
    final size = _pictureInPictureAspectSize();
    final width = size.width.round().clamp(1, 4096);
    final height = size.height.round().clamp(1, 4096);
    return Rational(width, height);
  }

  void _restoreAfterFailedPictureInPicture() {
    _enteringPictureInPicture = false;
    if (!mounted || !_restoreDanmakuAfterPip) {
      return;
    }
    _updateViewState(() {
      _showDanmakuOverlay = _danmakuVisibleBeforePip;
      _restoreDanmakuAfterPip = false;
    });
  }

  Future<void> _showQuickActionsSheet() async {
    late final _RoomPageState state;
    try {
      state = await _future;
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('房间尚未准备完成，请稍后再试')),
      );
      return;
    }
    if (!mounted) {
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: false,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (sheetContext) {
        final playbackSource =
            _playbackSource ?? state.resolved?.playbackSource;
        final playUrls =
            _playUrls.isEmpty ? state.snapshot.playUrls : _playUrls;
        final hasPlayback = playbackSource != null && playUrls.isNotEmpty;
        final unavailableReason =
            state.snapshot.playbackUnavailableReason ?? '当前房间暂无可用播放流';
        return SafeArea(
          child: StatefulBuilder(
            builder: (sheetContext, setSheetState) {
              Future<void> refreshSheet() async {
                if (!sheetContext.mounted) {
                  return;
                }
                setSheetState(() {});
              }

              return _buildFlatTileScope(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                  children: [
                    ListTile(
                      key: const Key('room-quick-refresh-button'),
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.refresh),
                      title: const Text('刷新'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () async {
                        Navigator.of(sheetContext).pop();
                        await _refreshRoom(showFeedback: true);
                      },
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.play_circle_outline),
                      title: const Text('切换清晰度'),
                      subtitle: hasPlayback ? null : Text(unavailableReason),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: hasPlayback
                          ? () async {
                              Navigator.of(sheetContext).pop();
                              await _showQualitySheet(state);
                            }
                          : null,
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.switch_video_outlined),
                      title: const Text('切换线路'),
                      subtitle: hasPlayback ? null : Text(unavailableReason),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: hasPlayback
                          ? () async {
                              Navigator.of(sheetContext).pop();
                              await _showLineSheet(playUrls, playbackSource);
                            }
                          : null,
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.aspect_ratio_outlined),
                      title: const Text('画面尺寸'),
                      trailing: Text(_labelOfScaleMode(_scaleMode)),
                      onTap: () async {
                        final modes = PlayerScaleMode.values;
                        final current = _scaleMode;
                        final index = modes.indexOf(current);
                        await _updateScaleMode(
                            modes[(index + 1) % modes.length]);
                        await refreshSheet();
                      },
                    ),
                    if (_pipSupported)
                      ListTile(
                        key: const Key('room-quick-pip-button'),
                        contentPadding: EdgeInsets.zero,
                        leading:
                            const Icon(Icons.picture_in_picture_alt_outlined),
                        title: const Text('小窗播放'),
                        subtitle: hasPlayback ? null : Text(unavailableReason),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: hasPlayback
                            ? () async {
                                Navigator.of(sheetContext).pop();
                                await _enterPictureInPicture();
                              }
                            : null,
                      ),
                    if (_supportsDesktopMiniWindow)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.open_in_new_rounded),
                        title: Text(
                          _desktopMiniWindowActive ? '退出桌面小窗' : '桌面小窗',
                        ),
                        subtitle: hasPlayback ? null : Text(unavailableReason),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: hasPlayback
                            ? () async {
                                Navigator.of(sheetContext).pop();
                                await _toggleDesktopMiniWindow();
                              }
                            : null,
                      ),
                    if (_supportsPlayerCapture)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.camera_alt_outlined),
                        title: const Text('截图'),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () {
                          Navigator.of(sheetContext).pop();
                          unawaited(_captureScreenshot());
                        },
                      ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.timer_outlined),
                      title: const Text('定时关闭'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () async {
                        Navigator.of(sheetContext).pop();
                        await _showAutoCloseSheet();
                      },
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.bug_report_outlined),
                      title: const Text('调试面板'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () async {
                        Navigator.of(sheetContext).pop();
                        await _showPlayerDebugSheet(state, playbackSource);
                      },
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _showQualitySheet(_RoomPageState state) async {
    final selectedQuality = _requestedQualityOf(state);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: false,
      builder: (sheetContext) {
        return SafeArea(
          child: _buildFlatTileScope(
            child: RadioGroup<String>(
              groupValue: selectedQuality.id,
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                final quality = state.snapshot.qualities.firstWhere(
                  (item) => item.id == value,
                  orElse: () => selectedQuality,
                );
                Navigator.of(sheetContext).pop();
                unawaited(_switchQuality(state.snapshot, quality));
              },
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.only(top: 8, bottom: 16),
                children: [
                  const ListTile(
                    title: Text('切换清晰度'),
                    subtitle: Text('若平台实际返回降档流，会在房间头部显示实际清晰度。'),
                  ),
                  for (final quality in state.snapshot.qualities)
                    RadioListTile<String>(
                      value: quality.id,
                      title: Text(quality.label),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showLineSheet(
      List<LivePlayUrl> playUrls, PlaybackSource playbackSource) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: false,
      builder: (sheetContext) {
        return SafeArea(
          child: _buildFlatTileScope(
            child: RadioGroup<String>(
              groupValue: playbackSource.url.toString(),
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                final selectedItem = playUrls.firstWhere(
                  (item) => item.url == value,
                  orElse: () => playUrls.first,
                );
                Navigator.of(sheetContext).pop();
                unawaited(_switchLine(selectedItem));
              },
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.only(top: 8, bottom: 16),
                children: [
                  const ListTile(
                    title: Text('切换线路'),
                    subtitle: Text('优先选择更稳定的线路，必要时手动切到备用线路。'),
                  ),
                  for (final item in playUrls)
                    RadioListTile<String>(
                      value: item.url,
                      title: Text(item.lineLabel ?? '线路'),
                      subtitle: Text(
                        item.url,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
