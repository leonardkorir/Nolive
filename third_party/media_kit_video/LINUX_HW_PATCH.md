# Linux H/W rendering patch (Nolive)

Upstream `media_kit_video` 2.0.1 only initializes the OpenGL render path when
Flutter's EGL context is *current* on the platform thread (`eglGetCurrentDisplay`).
On Flutter 3.38+, that context is often not current at `VideoOutput` construction
time, so the plugin silently falls back to S/W rendering
(`EGL display or context is invalid` → `S/W rendering`).

## What this tree does

1. **Flutter EGL path** — same as upstream when a context is already current.
2. **GdkGLContext path** — `gdk_window_create_gl_context` on the `FlView` window;
   used when the realized context also exposes EGL (e.g. `GDK_GL=egl` / Wayland).
3. **Isolated EGL from X11/Wayland** — **opt-in only**
   (`NOLIVE_FORCE_ISOLATED_EGL_VIDEO=1`). On dual-GPU X11 hosts it can init
   then abort with `Could not create GBM EGL display` → **black embed** while
   decode still runs. Default is therefore **S/W texture upload + HW decode**.
4. Frame path must **not** clear Flutter GLX (`glXMakeCurrent(None)` /
   `gdk_gl_context_clear_current`) — that blanks video and UI labels.
4. **libEGL via dlsym** — avoids libepoxy abort when no GL context is current.
5. **Bootstrap-only** `gdk_gl_context_clear_current` before first `eglMakeCurrent`
   (clears foreign GLX that causes `EGL_BAD_ACCESS` / 0x3002).

## HW *decode* vs HW *texture*

Even when VideoOutput uses S/W pixel upload, mpv can still use hardware decode
(`hwdec=auto-copy` → `nvdec-copy` / `vaapi-copy`). That is the shared player
default for all providers on desktop and is the main stutter fix when full GL
interop is unavailable.

## App-side helpers

- `apps/main_app` **must** path-override `media_kit_video` to this directory
  (`pubspec.yaml` + `pubspec_overrides.yaml`). Melos does not manage this override.
- `apps/main_app/linux/runner/main.cc` sets `GDK_GL=egl` early when unset so GTK
  prefers EGL when the driver supports it.
- Self-test markers: `NOLIVE_VIDEO_OUTPUT_HW_MARKER`, `NOLIVE_VIDEO_OUTPUT_HW_DIAG`.

## Files

- `linux/video_output.cc` — multi-path H/W init + diagnostics
- `linux/texture_gl.cc` — pbuffer-aware make-current via `video_output_make_context_current`
