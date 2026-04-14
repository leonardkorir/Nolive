import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'room_fullscreen_session_platforms.dart';
import 'room_view_ui_state.dart';

class RoomDesktopMiniWindowContext {
  const RoomDesktopMiniWindowContext({
    required this.desktopWindow,
    required this.readViewUiState,
    required this.updateViewUiState,
    required this.isDisposed,
  });

  final RoomDesktopWindowFacade desktopWindow;
  final RoomViewUiState Function() readViewUiState;
  final void Function(RoomViewUiState Function(RoomViewUiState current))
      updateViewUiState;
  final bool Function() isDisposed;
}

class RoomDesktopMiniWindowCoordinator {
  RoomDesktopMiniWindowCoordinator({required this.context});

  final RoomDesktopMiniWindowContext context;

  Rect? _desktopWindowBoundsBeforeMini;
  bool? _desktopWindowWasAlwaysOnTop;
  bool? _desktopWindowWasResizable;

  Future<void> enterDesktopMiniWindow({
    required Future<void> Function() exitFullscreen,
    required void Function() scheduleInlineChromeAutoHide,
  }) async {
    final viewState = context.readViewUiState();
    if (!context.desktopWindow.isSupported ||
        viewState.desktopMiniWindowActive) {
      return;
    }
    if (viewState.isFullscreen) {
      await exitFullscreen();
    }
    _desktopWindowBoundsBeforeMini ??= await context.desktopWindow.getBounds();
    _desktopWindowWasAlwaysOnTop ??=
        await context.desktopWindow.isAlwaysOnTop();
    _desktopWindowWasResizable ??= await context.desktopWindow.isResizable();
    final currentBounds = _desktopWindowBoundsBeforeMini!;
    final width = currentBounds.width.clamp(360.0, 420.0);
    final height = width / (16 / 9);
    final left =
        currentBounds.left + math.max(0.0, currentBounds.width - width);
    final top = currentBounds.top + 24;
    try {
      await context.desktopWindow.setAlwaysOnTop(true);
      await context.desktopWindow.setResizable(false);
      await context.desktopWindow.setBounds(
        Rect.fromLTWH(left, top, width, height),
        animate: true,
      );
    } catch (_) {
      await _restoreWindowAfterFailedMiniWindowEnter(
        bounds: currentBounds,
        alwaysOnTop: _desktopWindowWasAlwaysOnTop ?? false,
        resizable: _desktopWindowWasResizable ?? true,
      );
      _desktopWindowBoundsBeforeMini = null;
      _desktopWindowWasAlwaysOnTop = null;
      _desktopWindowWasResizable = null;
      rethrow;
    }
    if (context.isDisposed()) {
      return;
    }
    context.updateViewUiState(
      (current) => current.copyWith(
        desktopMiniWindowActive: true,
        showInlinePlayerChrome: true,
      ),
    );
    scheduleInlineChromeAutoHide();
  }

  Future<void> exitDesktopMiniWindow({
    required void Function() scheduleInlineChromeAutoHide,
    bool scheduleInlineChromeAfterExit = true,
  }) async {
    if (!context.desktopWindow.isSupported) {
      return;
    }
    final bounds = _desktopWindowBoundsBeforeMini;
    final alwaysOnTop = _desktopWindowWasAlwaysOnTop ?? false;
    final resizable = _desktopWindowWasResizable ?? true;
    await context.desktopWindow.setAlwaysOnTop(alwaysOnTop);
    await context.desktopWindow.setResizable(resizable);
    if (bounds != null) {
      await context.desktopWindow.setBounds(bounds, animate: true);
    }
    _desktopWindowBoundsBeforeMini = null;
    _desktopWindowWasAlwaysOnTop = null;
    _desktopWindowWasResizable = null;
    if (context.isDisposed()) {
      return;
    }
    context.updateViewUiState(
      (current) => current.copyWith(
        desktopMiniWindowActive: false,
        showInlinePlayerChrome: true,
      ),
    );
    if (scheduleInlineChromeAfterExit) {
      scheduleInlineChromeAutoHide();
    }
  }

  Future<void> _restoreWindowAfterFailedMiniWindowEnter({
    required Rect bounds,
    required bool alwaysOnTop,
    required bool resizable,
  }) async {
    try {
      await context.desktopWindow.setAlwaysOnTop(alwaysOnTop);
    } catch (_) {}
    try {
      await context.desktopWindow.setResizable(resizable);
    } catch (_) {}
    try {
      await context.desktopWindow.setBounds(bounds, animate: false);
    } catch (_) {}
  }
}
