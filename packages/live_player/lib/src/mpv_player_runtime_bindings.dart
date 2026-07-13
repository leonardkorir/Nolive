part of 'mpv_player.dart';

extension MpvPlayerRuntimeBindings on MpvPlayer {
  Future<Uint8List?> _captureScreenshotToTempFile(mk.Player player) async {
    final platform = player.platform;
    if (platform is! mk.NativePlayer) {
      return null;
    }
    final directory = await Directory.systemTemp.createTemp(
      'nolive-mpv-screenshot-',
    );
    final file = File(
      '${directory.path}${Platform.pathSeparator}screenshot.png',
    );
    try {
      const attemptCommands = <List<String>>[
        <String>['screenshot-to-file', 'video'],
        <String>['screenshot-to-file'],
      ];
      for (final command in attemptCommands) {
        try {
          await platform.command(<String>[
            command.first,
            file.path,
            ...command.skip(1),
          ]);
        } catch (_) {
          continue;
        }
        final bytes = await waitForScreenshotFileBytes(file);
        if (bytes != null && bytes.isNotEmpty) {
          return bytes;
        }
      }
      return null;
    } finally {
      try {
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {
        // Best-effort cleanup for temporary screenshot files.
      }
      try {
        if (await directory.exists()) {
          await directory.delete(recursive: true);
        }
      } catch (_) {
        // Best-effort cleanup for temporary screenshot directories.
      }
    }
  }

  void _bindPlayer(mk.Player player) {
    _subscriptions.addAll([
      player.stream.playing.listen((playing) {
        if (playing) {
          _logEvent('stream playing=true');
          if (_currentState.status == PlaybackStatus.error) {
            _logEvent(
              'stream playing ignored current-error error=${_currentState.errorMessage ?? '-'}',
            );
            return;
          }
          _emit(_currentState.copyWith(status: PlaybackStatus.playing));
        } else if (_currentState.status == PlaybackStatus.playing) {
          _logEvent('stream playing=false');
          _emit(_currentState.copyWith(status: PlaybackStatus.paused));
        }
      }),
      player.stream.completed.listen((completed) {
        if (completed) {
          _logEvent('stream completed=true');
          _emit(_currentState.copyWith(status: PlaybackStatus.completed));
        }
      }),
      player.stream.position.listen((position) {
        final nextState = _currentState.copyWith(position: position);
        final shouldBroadcast = _shouldBroadcastProgress(
          previous: _lastBroadcastPosition,
          next: position,
          step: MpvPlayer._progressBroadcastStep,
        );
        _emit(nextState, broadcast: shouldBroadcast);
        if (shouldBroadcast) {
          _lastBroadcastPosition = position;
        }
      }),
      player.stream.duration.listen((duration) {
        _emit(_currentState.copyWith(duration: duration));
      }),
      player.stream.volume.listen((volume) {
        _emit(_currentState.copyWith(volume: (volume / 100).clamp(0, 1)));
      }),
      player.stream.buffering.listen((buffering) {
        _logEvent('stream buffering=$buffering');
        _emitDiagnostics(_currentDiagnostics.copyWith(buffering: buffering));
        if (_currentState.status == PlaybackStatus.error) {
          return;
        }
        if (buffering) {
          _emit(_currentState.copyWith(status: PlaybackStatus.buffering));
          return;
        }
        if (_currentState.status == PlaybackStatus.buffering &&
            _currentState.source != null) {
          _emit(_currentState.copyWith(status: PlaybackStatus.ready));
        }
      }),
      player.stream.buffer.listen((buffered) {
        _emitDiagnostics(_currentDiagnostics.copyWith(buffered: buffered));
        final nextState = _currentState.copyWith(buffered: buffered);
        final shouldBroadcast = _shouldBroadcastProgress(
          previous: _lastBroadcastBuffered,
          next: buffered,
          step: MpvPlayer._bufferBroadcastStep,
        );
        _emit(nextState, broadcast: shouldBroadcast);
        if (shouldBroadcast) {
          _lastBroadcastBuffered = buffered;
        }
      }),
      player.stream.error.listen((message) {
        if (message.isEmpty) {
          return;
        }
        if (_shouldIgnoreRuntimeMessage(message)) {
          _logEvent('stream warning ignored=$message');
          return;
        }
        _logEvent('stream error=$message');
        _emitDiagnostics(_currentDiagnostics.copyWith(error: message));
        _emit(
          _currentState.copyWith(
            status: PlaybackStatus.error,
            errorMessage: message,
          ),
        );
      }),
      player.stream.width.listen((width) {
        if ((width ?? 0) > 0) {
          _logEvent('stream width=$width');
        }
        _emitDiagnostics(_currentDiagnostics.copyWith(width: width));
      }),
      player.stream.height.listen((height) {
        if ((height ?? 0) > 0) {
          _logEvent('stream height=$height');
        }
        _emitDiagnostics(_currentDiagnostics.copyWith(height: height));
      }),
      player.stream.videoParams.listen((params) {
        final videoParams = _videoParamsToMap(params);
        if (videoParams.isNotEmpty) {
          _logEvent('stream videoParams ${_formatRuntimeParams(videoParams)}');
        }
        _emitDiagnostics(
          _currentDiagnostics.copyWith(videoParams: videoParams),
        );
      }),
      player.stream.audioParams.listen((params) {
        final audioParams = _audioParamsToMap(params);
        if (audioParams.isNotEmpty) {
          _logEvent('stream audioParams ${_formatRuntimeParams(audioParams)}');
        }
        _emitDiagnostics(
          _currentDiagnostics.copyWith(audioParams: audioParams),
        );
      }),
      if (logEnabled)
        player.stream.log.listen((entry) {
          final message = entry.text.trim();
          if (message.isEmpty) {
            return;
          }
          if (_shouldIgnoreRuntimeMessage(message)) {
            return;
          }
          final normalizedMessage = message.toLowerCase();
          if (normalizedMessage.contains('opening done:')) {
            _lastMpvOpeningDoneAt = DateTime.now();
          }
          if (normalizedMessage.contains(
            'using hardware decoding (mediacodec)',
          )) {
            final readyAt = DateTime.now();
            _lastMediaCodecHardwareDecoderReadyAt = readyAt;
            final completer = _pendingMediaCodecHardwareDecoderReadyCompleter;
            if (completer != null && !completer.isCompleted) {
              completer.complete(readyAt);
            }
            _logEvent('player diagnostics decoder=hardware');
          }
          if (!_emittedMediaCodecDeviceFailureForSource &&
              normalizedMessage.contains('could not create device')) {
            _emittedMediaCodecDeviceFailureForSource = true;
            final failureTimestamp = DateTime.now();
            final failureReason = classifyAndroidMediaCodecDeviceFailureReason(
              lastOpeningDoneAt: _lastMpvOpeningDoneAt,
              failureTimestamp: failureTimestamp,
              reinitThreshold:
                  MpvPlayer._androidMediaCodecReinitClassificationThreshold,
            );
            final openingDoneDelta = _lastMpvOpeningDoneAt == null
                ? null
                : failureTimestamp.difference(_lastMpvOpeningDoneAt!);
            _logEvent(
              'player diagnostics decoder=software '
              'reason=$failureReason'
              '${openingDoneDelta == null ? '' : ' delta=${openingDoneDelta.inMilliseconds}ms'}',
            );
          }
          final nextEntry = '[${entry.level}] ${entry.prefix}: $message';
          _logEvent('mpv $nextEntry');
          final nextLogs = List<String>.from(_recentLogs)..add(nextEntry);
          while (nextLogs.length > 24) {
            nextLogs.removeAt(0);
          }
          _recentLogs
            ..clear()
            ..addAll(nextLogs);
          _emitDiagnostics(
            _currentDiagnostics.copyWith(
              recentLogs: List<String>.unmodifiable(nextLogs),
            ),
          );
        }),
    ]);
  }

  String _formatRuntimeParams(Map<String, String> params) {
    return params.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join(' ');
  }
}
