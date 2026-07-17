// This file is a part of media_kit
// (https://github.com/media-kit/media-kit).
//
// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
// All rights reserved.
// Use of this source code is governed by MIT license that can be found in the
// LICENSE file.
//
// Nolive Linux H/W patch: Flutter 3.38+ often has no current EGL context on the
// platform thread when VideoOutput is constructed. Upstream then prints
// "EGL display or context is invalid" and falls back to S/W rendering forever.
// This file tries Flutter's current EGL first, then creates an EGL display from
// the GDK X11/Wayland display so H/W OpenGL + VAAPI/NVDEC can still work.
// See LINUX_HW_PATCH.md.

#include "include/media_kit_video/video_output.h"
#include "include/media_kit_video/texture_gl.h"
#include "include/media_kit_video/texture_sw.h"

#include <epoxy/egl.h>
#include <epoxy/glx.h>
#include <gdk/gdkwayland.h>
#include <gdk/gdkx.h>
#include <dlfcn.h>
#include <stdio.h>

// Optional self-test marker (integration tests / SCRATCH probes).
static void video_output_write_hw_marker(const char* mode) {
  const char* path = g_getenv("NOLIVE_VIDEO_OUTPUT_HW_MARKER");
  if (path == NULL || path[0] == '\0') {
    return;
  }
  FILE* f = fopen(path, "w");
  if (f == NULL) {
    return;
  }
  fprintf(f, "%s\n", mode);
  fclose(f);
}

static void video_output_append_hw_diag(const char* line) {
  const char* path = g_getenv("NOLIVE_VIDEO_OUTPUT_HW_DIAG");
  if (path == NULL || path[0] == '\0') {
    return;
  }
  FILE* f = fopen(path, "a");
  if (f == NULL) {
    return;
  }
  fprintf(f, "%s\n", line);
  fclose(f);
}

// libepoxy's egl* wrappers can abort (epoxy_get_proc_address assert) when no
// GL context is current — common on Flutter 3.38+ platform thread. Resolve
// symbols directly from libEGL for context bootstrap.
typedef EGLDisplay (*RealEglGetDisplay)(EGLNativeDisplayType);
typedef EGLDisplay (*RealEglGetPlatformDisplay)(EGLenum, void*, const EGLAttrib*);
typedef EGLBoolean (*RealEglInitialize)(EGLDisplay, EGLint*, EGLint*);
typedef EGLBoolean (*RealEglBindAPI)(EGLenum);
typedef EGLBoolean (*RealEglChooseConfig)(EGLDisplay, const EGLint*, EGLConfig*,
                                          EGLint, EGLint*);
typedef EGLContext (*RealEglCreateContext)(EGLDisplay, EGLConfig, EGLContext,
                                           const EGLint*);
typedef EGLSurface (*RealEglCreatePbufferSurface)(EGLDisplay, EGLConfig,
                                                  const EGLint*);
typedef EGLBoolean (*RealEglMakeCurrent)(EGLDisplay, EGLSurface, EGLSurface,
                                         EGLContext);
typedef EGLint (*RealEglGetError)(void);
typedef void* (*RealEglGetProcAddress)(const char*);
typedef EGLBoolean (*RealEglQueryContext)(EGLDisplay, EGLContext, EGLint,
                                          EGLint*);
typedef EGLDisplay (*RealEglGetCurrentDisplay)(void);
typedef EGLContext (*RealEglGetCurrentContext)(void);
typedef EGLSurface (*RealEglGetCurrentSurface)(EGLint);

struct RealEgl {
  RealEglGetDisplay get_display;
  RealEglGetPlatformDisplay get_platform_display;
  RealEglInitialize initialize;
  RealEglBindAPI bind_api;
  RealEglChooseConfig choose_config;
  RealEglCreateContext create_context;
  RealEglCreatePbufferSurface create_pbuffer;
  RealEglMakeCurrent make_current;
  RealEglGetError get_error;
  RealEglGetProcAddress get_proc_address;
  RealEglQueryContext query_context;
  RealEglGetCurrentDisplay get_current_display;
  RealEglGetCurrentContext get_current_context;
  RealEglGetCurrentSurface get_current_surface;
  gboolean ready;
};

static struct RealEgl g_real_egl = {};

static gboolean video_output_load_real_egl(void) {
  if (g_real_egl.ready) {
    return TRUE;
  }
  void* lib = dlopen("libEGL.so.1", RTLD_NOW | RTLD_GLOBAL);
  if (lib == NULL) {
    lib = dlopen("libEGL.so", RTLD_NOW | RTLD_GLOBAL);
  }
  if (lib == NULL) {
    video_output_append_hw_diag("real_egl: dlopen libEGL failed");
    return FALSE;
  }
#define LOAD(field, symbol)                                              \
  do {                                                                   \
    g_real_egl.field = (typeof(g_real_egl.field))dlsym(lib, symbol);     \
    if (g_real_egl.field == NULL) {                                      \
      video_output_append_hw_diag("real_egl: missing " symbol);          \
      return FALSE;                                                      \
    }                                                                    \
  } while (0)
  LOAD(get_display, "eglGetDisplay");
  LOAD(initialize, "eglInitialize");
  LOAD(bind_api, "eglBindAPI");
  LOAD(choose_config, "eglChooseConfig");
  LOAD(create_context, "eglCreateContext");
  LOAD(create_pbuffer, "eglCreatePbufferSurface");
  LOAD(make_current, "eglMakeCurrent");
  LOAD(get_error, "eglGetError");
  LOAD(get_proc_address, "eglGetProcAddress");
  LOAD(query_context, "eglQueryContext");
  LOAD(get_current_display, "eglGetCurrentDisplay");
  LOAD(get_current_context, "eglGetCurrentContext");
  LOAD(get_current_surface, "eglGetCurrentSurface");
#undef LOAD
  // Optional (EGL 1.5 / EXT_platform_base).
  g_real_egl.get_platform_display =
      (RealEglGetPlatformDisplay)dlsym(lib, "eglGetPlatformDisplay");
  g_real_egl.ready = TRUE;
  video_output_append_hw_diag("real_egl: loaded libEGL.so");
  return TRUE;
}

struct _VideoOutput {
  GObject parent_instance;
  TextureGL* texture_gl;
  EGLDisplay egl_display; /* EGL display for mpv rendering (owned or Flutter). */
  EGLContext egl_context; /* Isolated EGL context (non-shared). */
  EGLSurface egl_surface; /* Pbuffer surface when surfaceless make-current fails. */
  gboolean egl_display_owned; /* TRUE if we eglGetDisplay/eglInitialize ourselves. */
  GdkGLContext* gdk_gl_context; /* Optional GTK GL context (alternative make-current). */
  guint8* pixel_buffer;
  TextureSW* texture_sw;
  GMutex mutex; /* Only used in S/W rendering. */
  mpv_handle* handle;
  mpv_render_context* render_context;
  gint64 width;
  gint64 height;
  VideoOutputConfiguration configuration;
  TextureUpdateCallback texture_update_callback;
  gpointer texture_update_callback_context;
  FlTextureRegistrar* texture_registrar;
  gboolean destroyed;
  /* TRUE: texture_gl registered but mpv OpenGL render not ready yet — complete
   * on first FlTextureGL populate when Flutter has a current GL context (GLX
   * or EGL). Avoids platform-thread "no EGL" and isolated-EGL crash on GLX. */
  gboolean hw_pending;
  /* TRUE: mpv renders in Flutter's GL context (no isolated context / EGLImage). */
  gboolean gl_shared_with_flutter;
  /* TRUE: a S/W texture idle callback is already queued (coalesce updates). */
  gboolean sw_idle_queued;
  /* Monotonic µs of last completed S/W render (pace uploads). */
  gint64 sw_last_render_us;
  /* Effective S/W max height (default 720; env NOLIVE_SW_MAX_HEIGHT). */
  gint64 sw_max_w;
  gint64 sw_max_h;
};

G_DEFINE_TYPE(VideoOutput, video_output, G_TYPE_OBJECT)

static void video_output_dispose(GObject* object) {
  VideoOutput* self = VIDEO_OUTPUT(object);
  self->destroyed = TRUE;

  // Make sure that no more callbacks are invoked from mpv.
  if (self->render_context) {
    mpv_render_context_set_update_callback(self->render_context, NULL, NULL);
  }

  // H/W
  if (self->texture_gl) {
    fl_texture_registrar_unregister_texture(self->texture_registrar,
                                            FL_TEXTURE(self->texture_gl));

    // Save Flutter's current context before cleanup
    EGLDisplay current_display = eglGetCurrentDisplay();
    EGLContext flutter_context = eglGetCurrentContext();
    EGLSurface flutter_draw_surface = eglGetCurrentSurface(EGL_DRAW);
    EGLSurface flutter_read_surface = eglGetCurrentSurface(EGL_READ);

    // Free mpv_render_context with our own isolated EGL context
    if (self->render_context != NULL) {
      if (self->egl_context != EGL_NO_CONTEXT &&
          self->egl_display != EGL_NO_DISPLAY) {
        if (self->egl_surface != EGL_NO_SURFACE) {
          eglMakeCurrent(self->egl_display, self->egl_surface, self->egl_surface,
                         self->egl_context);
        } else {
          eglMakeCurrent(self->egl_display, EGL_NO_SURFACE, EGL_NO_SURFACE,
                         self->egl_context);
        }
      }
      mpv_render_context_free(self->render_context);
      self->render_context = NULL;

      // Restore Flutter's context
      if (flutter_context != EGL_NO_CONTEXT &&
          current_display != EGL_NO_DISPLAY) {
        eglMakeCurrent(current_display, flutter_draw_surface,
                       flutter_read_surface, flutter_context);
      } else if (self->egl_display != EGL_NO_DISPLAY) {
        eglMakeCurrent(self->egl_display, EGL_NO_SURFACE, EGL_NO_SURFACE,
                       EGL_NO_CONTEXT);
      }
    }

    // Clean up EGL resources
    if (self->egl_surface != EGL_NO_SURFACE &&
        self->egl_display != EGL_NO_DISPLAY) {
      eglDestroySurface(self->egl_display, self->egl_surface);
      self->egl_surface = EGL_NO_SURFACE;
    }
    if (self->egl_context != EGL_NO_CONTEXT &&
        self->egl_display != EGL_NO_DISPLAY) {
      eglDestroyContext(self->egl_display, self->egl_context);
      self->egl_context = EGL_NO_CONTEXT;
    }
    if (self->egl_display_owned && self->egl_display != EGL_NO_DISPLAY) {
      eglTerminate(self->egl_display);
      self->egl_display = EGL_NO_DISPLAY;
      self->egl_display_owned = FALSE;
    }
    g_clear_object(&self->gdk_gl_context);

    g_object_unref(self->texture_gl);
  }
  // S/W
  if (self->texture_sw) {
    fl_texture_registrar_unregister_texture(self->texture_registrar,
                                            FL_TEXTURE(self->texture_sw));
    g_free(self->pixel_buffer);
    g_object_unref(self->texture_sw);
    if (self->render_context != NULL) {
      mpv_render_context_free(self->render_context);
      self->render_context = NULL;
    }
  }

  g_mutex_clear(&self->mutex);
  G_OBJECT_CLASS(video_output_parent_class)->dispose(object);
}

static void video_output_class_init(VideoOutputClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = video_output_dispose;
}

static void video_output_init(VideoOutput* self) {
  self->texture_gl = NULL;
  self->egl_display = EGL_NO_DISPLAY;
  self->egl_context = EGL_NO_CONTEXT;
  self->egl_surface = EGL_NO_SURFACE;
  self->egl_display_owned = FALSE;
  self->gdk_gl_context = NULL;
  self->texture_sw = NULL;
  self->pixel_buffer = NULL;
  self->handle = NULL;
  self->render_context = NULL;
  self->width = 0;
  self->height = 0;
  self->configuration = VideoOutputConfiguration{};
  self->texture_update_callback = NULL;
  self->texture_update_callback_context = NULL;
  self->texture_registrar = NULL;
  self->destroyed = FALSE;
  self->hw_pending = FALSE;
  self->gl_shared_with_flutter = FALSE;
  self->sw_idle_queued = FALSE;
  self->sw_last_render_us = 0;
  self->sw_max_w = SW_RENDERING_DEFAULT_MAX_WIDTH;
  self->sw_max_h = SW_RENDERING_DEFAULT_MAX_HEIGHT;
  g_mutex_init(&self->mutex);
}

// Fit |src_w|x|src_h| into max box while preserving aspect (integer-safe).
static void video_output_sw_fit_size(gint64 src_w,
                                     gint64 src_h,
                                     gint64 max_w,
                                     gint64 max_h,
                                     gint64* out_w,
                                     gint64* out_h) {
  if (src_w <= 0 || src_h <= 0) {
    *out_w = 0;
    *out_h = 0;
    return;
  }
  if (src_w <= max_w && src_h <= max_h) {
    *out_w = src_w;
    *out_h = src_h;
    return;
  }
  // Scale by the more constraining dimension.
  if (src_w * max_h > src_h * max_w) {
    *out_w = max_w;
    *out_h = (src_h * max_w) / src_w;
  } else {
    *out_h = max_h;
    *out_w = (src_w * max_h) / src_h;
  }
  if (*out_w < 1) {
    *out_w = 1;
  }
  if (*out_h < 1) {
    *out_h = 1;
  }
}

static void video_output_sw_read_max_from_env(VideoOutput* self) {
  const char* env = g_getenv("NOLIVE_SW_MAX_HEIGHT");
  if (env == NULL || env[0] == '\0') {
    return;
  }
  gint64 h = g_ascii_strtoll(env, NULL, 10);
  if (h < 360) {
    return;
  }
  if (h > SW_RENDERING_MAX_HEIGHT) {
    h = SW_RENDERING_MAX_HEIGHT;
  }
  self->sw_max_h = h;
  self->sw_max_w = (h * 16) / 9;
  if (self->sw_max_w > SW_RENDERING_MAX_WIDTH) {
    self->sw_max_w = SW_RENDERING_MAX_WIDTH;
  }
}

// Make the isolated EGL context current (prefer pbuffer when present).
// Uses real libEGL when loaded (avoids epoxy abort without current context).
// clear_foreign_glx: only during initial bootstrap — clearing on every texture
// frame steals Flutter's GLX current context and hangs the raster thread.
static gboolean video_output_try_make_context_current(VideoOutput* self,
                                                     gboolean clear_foreign_glx);

gboolean video_output_make_context_current(VideoOutput* self) {
  if (self != NULL && self->gl_shared_with_flutter) {
    // Flutter already made its GL context current for FlTextureGL::populate.
    return TRUE;
  }
  return video_output_try_make_context_current(self, FALSE);
}

static gboolean video_output_try_make_context_current(
    VideoOutput* self,
    gboolean clear_foreign_glx) {
  // Prefer GdkGLContext when we bootstrapped via GTK (works on raster/platform).
  if (self->gdk_gl_context != NULL) {
    gdk_gl_context_make_current(self->gdk_gl_context);
    // Refresh EGL handles from the now-current context for mpv/epoxy.
    if (video_output_load_real_egl()) {
      self->egl_display = g_real_egl.get_current_display();
      self->egl_context = g_real_egl.get_current_context();
      self->egl_surface = g_real_egl.get_current_surface(EGL_DRAW);
    } else {
      self->egl_display = eglGetCurrentDisplay();
      self->egl_context = eglGetCurrentContext();
      self->egl_surface = eglGetCurrentSurface(EGL_DRAW);
    }
    if (self->egl_display != EGL_NO_DISPLAY &&
        self->egl_context != EGL_NO_CONTEXT) {
      return TRUE;
    }
    video_output_append_hw_diag(
        "make_current: GdkGLContext make_current but no EGL current");
  }
  if (self->egl_display == EGL_NO_DISPLAY || self->egl_context == EGL_NO_CONTEXT) {
    video_output_append_hw_diag("make_current: no display/context");
    return FALSE;
  }
  const gboolean use_real = video_output_load_real_egl();
  // Prefer releasing only *our* previous EGL current. Never clear Flutter's
  // GLX current (glXMakeCurrent(None) / gdk_gl_context_clear_current) — that
  // blanks the embed texture and UI on dual-GPU X11 hosts.
  if (clear_foreign_glx && use_real && self->egl_display != EGL_NO_DISPLAY) {
    g_real_egl.make_current(self->egl_display, EGL_NO_SURFACE, EGL_NO_SURFACE,
                            EGL_NO_CONTEXT);
  }
  auto make_current = [&](EGLSurface draw, EGLSurface read) -> EGLBoolean {
    if (use_real) {
      return g_real_egl.make_current(self->egl_display, draw, read,
                                     self->egl_context);
    }
    return eglMakeCurrent(self->egl_display, draw, read, self->egl_context);
  };
  auto get_error = [&]() -> EGLint {
    return use_real ? g_real_egl.get_error() : eglGetError();
  };

  // Prefer existing pbuffer — NVIDIA often rejects surfaceless first.
  if (self->egl_surface != EGL_NO_SURFACE) {
    if (make_current(self->egl_surface, self->egl_surface)) {
      return TRUE;
    }
    char buf[128];
    snprintf(buf, sizeof(buf),
             "make_current: pbuffer failed eglError=0x%x", get_error());
    video_output_append_hw_diag(buf);
  }
  if (make_current(EGL_NO_SURFACE, EGL_NO_SURFACE)) {
    return TRUE;
  }
  {
    char buf[128];
    snprintf(buf, sizeof(buf),
             "make_current: surfaceless failed eglError=0x%x", get_error());
    video_output_append_hw_diag(buf);
  }
  // Create a 1x1 pbuffer if we do not already have one.
  if (self->egl_surface == EGL_NO_SURFACE) {
    EGLConfig config = NULL;
    EGLint num = 0;
    EGLint cfg_attribs[] = {
        EGL_SURFACE_TYPE, EGL_PBUFFER_BIT,
        EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT,
        EGL_RED_SIZE, 8,
        EGL_GREEN_SIZE, 8,
        EGL_BLUE_SIZE, 8,
        EGL_ALPHA_SIZE, 8,
        EGL_NONE,
    };
    EGLBoolean ok_cfg =
        use_real ? g_real_egl.choose_config(self->egl_display, cfg_attribs,
                                            &config, 1, &num)
                 : eglChooseConfig(self->egl_display, cfg_attribs, &config, 1,
                                   &num);
    if (ok_cfg && num > 0) {
      EGLint pbuf_attribs[] = {EGL_WIDTH, 1, EGL_HEIGHT, 1, EGL_NONE};
      self->egl_surface =
          use_real ? g_real_egl.create_pbuffer(self->egl_display, config,
                                               pbuf_attribs)
                   : eglCreatePbufferSurface(self->egl_display, config,
                                             pbuf_attribs);
    }
  }
  if (self->egl_surface == EGL_NO_SURFACE) {
    g_printerr(
        "media_kit: VideoOutput: surfaceless eglMakeCurrent failed and no "
        "pbuffer (eglError=0x%x).\n",
        get_error());
    video_output_append_hw_diag("make_current: no pbuffer available");
    return FALSE;
  }
  if (!make_current(self->egl_surface, self->egl_surface)) {
    EGLint err = get_error();
    g_printerr(
        "media_kit: VideoOutput: pbuffer eglMakeCurrent failed (eglError=0x%x).\n",
        err);
    char buf[160];
    snprintf(buf, sizeof(buf),
             "make_current: final pbuffer failed eglError=0x%x "
             "display=%p context=%p surface=%p",
             err, (void*)self->egl_display, (void*)self->egl_context,
             (void*)self->egl_surface);
    video_output_append_hw_diag(buf);
    return FALSE;
  }
  return TRUE;
}

// Resolve GL entry points: prefer real EGL, then epoxy eglGetProcAddress
// (works for both EGL and GLX once a context is current).
static void* video_output_get_gl_proc(void*, const char* name) {
  if (g_real_egl.ready && g_real_egl.get_proc_address != NULL) {
    void* p = g_real_egl.get_proc_address(name);
    if (p != NULL) {
      return p;
    }
  }
  void* p = (void*)eglGetProcAddress(name);
  if (p != NULL) {
    return p;
  }
#if defined(GLX_VERSION_1_4) || defined(GLX_ARB_get_proc_address)
  p = (void*)glXGetProcAddressARB((const GLubyte*)name);
#endif
  return p;
}

// Create mpv OpenGL render context. Caller must have a current GL context
// (or isolated EGL ready via try_make_context_current).
// register_texture: create+register TextureGL if not already present.
static gboolean video_output_create_mpv_gl_render(VideoOutput* self,
                                                  gboolean need_make_current,
                                                  gboolean register_texture) {
  if (need_make_current &&
      !video_output_try_make_context_current(self, TRUE)) {
    video_output_append_hw_diag("create_mpv_gl: make_current failed");
    return FALSE;
  }
  if (register_texture && self->texture_gl == NULL) {
    self->texture_gl = texture_gl_new(self);
    if (!fl_texture_registrar_register_texture(self->texture_registrar,
                                               FL_TEXTURE(self->texture_gl))) {
      g_printerr("media_kit: VideoOutput: Failed to register texture.\n");
      video_output_append_hw_diag("create_mpv_gl: register_texture failed");
      return FALSE;
    }
  }
  if (self->render_context != NULL) {
    return TRUE;
  }
  mpv_opengl_init_params gl_init_params{
      video_output_get_gl_proc,
      NULL,
  };
  mpv_render_param params[] = {
      {MPV_RENDER_PARAM_API_TYPE, (void*)MPV_RENDER_API_TYPE_OPENGL},
      {MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, (void*)&gl_init_params},
      {MPV_RENDER_PARAM_INVALID, (void*)0},
      {MPV_RENDER_PARAM_INVALID, (void*)0},
  };
  GdkDisplay* display = gdk_display_get_default();
  if (display != NULL && GDK_IS_WAYLAND_DISPLAY(display)) {
    params[2].type = MPV_RENDER_PARAM_WL_DISPLAY;
    params[2].data = gdk_wayland_display_get_wl_display(display);
  } else if (display != NULL && GDK_IS_X11_DISPLAY(display)) {
    params[2].type = MPV_RENDER_PARAM_X11_DISPLAY;
    params[2].data = gdk_x11_display_get_xdisplay(display);
  }
  if (mpv_render_context_create(&self->render_context, self->handle, params) !=
      0) {
    g_printerr("media_kit: VideoOutput: Failed to create mpv_render_context.\n");
    video_output_append_hw_diag("create_mpv_gl: mpv_render_context_create failed");
    return FALSE;
  }
  mpv_render_context_set_update_callback(
      self->render_context,
      [](void* data) {
        VideoOutput* self = (VideoOutput*)data;
        if (self->destroyed) {
          return;
        }
        // Marshal to GTK main/raster-friendly idle — mpv may call from its
        // own thread; direct registrar calls with foreign EGL current hang.
        g_idle_add(
            [](gpointer d) -> gboolean {
              VideoOutput* self = VIDEO_OUTPUT(d);
              if (!self->destroyed && self->texture_gl != NULL) {
                fl_texture_registrar_mark_texture_frame_available(
                    self->texture_registrar, FL_TEXTURE(self->texture_gl));
              }
              return FALSE;
            },
            self);
      },
      self);
  // Release only *our* EGL context. Never call gdk_gl_context_clear_current()
  // here — that can tear down Flutter's compositor GLX/EGL and blank UI text.
  if (g_real_egl.ready && self->egl_display != EGL_NO_DISPLAY) {
    g_real_egl.make_current(self->egl_display, EGL_NO_SURFACE, EGL_NO_SURFACE,
                            EGL_NO_CONTEXT);
  } else if (self->egl_display != EGL_NO_DISPLAY) {
    eglMakeCurrent(self->egl_display, EGL_NO_SURFACE, EGL_NO_SURFACE,
                   EGL_NO_CONTEXT);
  }
  return TRUE;
}

gboolean video_output_uses_shared_gl(VideoOutput* self) {
  return self != NULL && self->gl_shared_with_flutter;
}

// Called from FlTextureGL::populate when Flutter has a current GL context
// (GLX or EGL). Completes deferred H/W setup using that same context so we
// never need EGLImage interop across GLX↔EGL.
gboolean video_output_ensure_render_context(VideoOutput* self) {
  if (self == NULL || self->destroyed) {
    return FALSE;
  }
  if (self->render_context != NULL && !self->hw_pending) {
    return TRUE;
  }
  if (!self->hw_pending && self->render_context == NULL) {
    return FALSE;
  }
  video_output_append_hw_diag("deferred: ensure_render_context on raster thread");
  (void)video_output_load_real_egl();
  // Snapshot Flutter's current context if it is EGL-based.
  EGLDisplay cur_d =
      g_real_egl.ready ? g_real_egl.get_current_display() : eglGetCurrentDisplay();
  EGLContext cur_c =
      g_real_egl.ready ? g_real_egl.get_current_context() : eglGetCurrentContext();
  if (cur_d != EGL_NO_DISPLAY && cur_c != EGL_NO_CONTEXT) {
    self->egl_display = cur_d;
    self->egl_context = cur_c;
    self->egl_surface =
        g_real_egl.ready ? g_real_egl.get_current_surface(EGL_DRAW)
                         : eglGetCurrentSurface(EGL_DRAW);
    self->egl_display_owned = FALSE;
  }
  // Share Flutter's context (GLX or EGL): no isolated context switch.
  self->gl_shared_with_flutter = TRUE;
  if (!video_output_create_mpv_gl_render(self, /*need_make_current=*/FALSE,
                                         /*register_texture=*/FALSE)) {
    self->gl_shared_with_flutter = FALSE;
    video_output_append_hw_diag("deferred: mpv_render create failed");
    return FALSE;
  }
  self->hw_pending = FALSE;
  g_printerr(
      "media_kit: VideoOutput: H/W rendering with Flutter-shared GL context "
      "(deferred raster).\n");
  video_output_write_hw_marker("flutter-raster");
  video_output_append_hw_diag("deferred: success flutter-raster");
  return TRUE;
}

// Path 1: Flutter platform thread already has a current EGL context (ideal).
static gboolean video_output_init_hw_from_flutter_egl(VideoOutput* self) {
  (void)video_output_load_real_egl();
  EGLDisplay flutter_display =
      g_real_egl.ready ? g_real_egl.get_current_display()
                       : eglGetCurrentDisplay();
  EGLContext flutter_context =
      g_real_egl.ready ? g_real_egl.get_current_context()
                       : eglGetCurrentContext();
  EGLSurface flutter_draw_surface =
      g_real_egl.ready ? g_real_egl.get_current_surface(EGL_DRAW)
                       : eglGetCurrentSurface(EGL_DRAW);
  EGLSurface flutter_read_surface =
      g_real_egl.ready ? g_real_egl.get_current_surface(EGL_READ)
                       : eglGetCurrentSurface(EGL_READ);
  if (flutter_display == EGL_NO_DISPLAY || flutter_context == EGL_NO_CONTEXT) {
    video_output_append_hw_diag(
        "flutter-egl: no current display/context");
    return FALSE;
  }
  self->egl_display = flutter_display;
  self->egl_display_owned = FALSE;
  if (g_real_egl.ready) {
    g_real_egl.bind_api(EGL_OPENGL_ES_API);
  } else {
    eglBindAPI(EGL_OPENGL_ES_API);
  }
  EGLConfig config = NULL;
  EGLint config_id = 0;
  EGLint num_configs = 0;
  EGLBoolean qok =
      g_real_egl.ready
          ? g_real_egl.query_context(self->egl_display, flutter_context,
                                     EGL_CONFIG_ID, &config_id)
          : eglQueryContext(self->egl_display, flutter_context, EGL_CONFIG_ID,
                            &config_id);
  if (!qok) {
    g_printerr(
        "media_kit: VideoOutput: Failed to query Flutter's EGL config ID.\n");
    return FALSE;
  }
  EGLint config_attribs[] = {EGL_CONFIG_ID, config_id, EGL_NONE};
  EGLBoolean cok =
      g_real_egl.ready
          ? g_real_egl.choose_config(self->egl_display, config_attribs, &config,
                                     1, &num_configs)
          : eglChooseConfig(self->egl_display, config_attribs, &config, 1,
                            &num_configs);
  if (!cok || num_configs <= 0) {
    g_printerr(
        "media_kit: VideoOutput: Failed to get Flutter's EGL config by ID.\n");
    return FALSE;
  }
  EGLint context_attribs[] = {EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE};
  self->egl_context =
      g_real_egl.ready
          ? g_real_egl.create_context(self->egl_display, config, EGL_NO_CONTEXT,
                                      context_attribs)
          : eglCreateContext(self->egl_display, config, EGL_NO_CONTEXT,
                             context_attribs);
  if (self->egl_context == EGL_NO_CONTEXT) {
    EGLint err = g_real_egl.ready ? g_real_egl.get_error() : eglGetError();
    g_printerr(
        "media_kit: VideoOutput: Failed to create isolated EGL context from "
        "Flutter display (eglError=0x%x).\n",
        err);
    return FALSE;
  }
  gboolean ok = video_output_create_mpv_gl_render(self, /*need_make_current=*/TRUE,
                                                   /*register_texture=*/TRUE);
  // Restore Flutter's context.
  if (g_real_egl.ready) {
    g_real_egl.make_current(flutter_display, flutter_draw_surface,
                            flutter_read_surface, flutter_context);
  } else {
    eglMakeCurrent(flutter_display, flutter_draw_surface, flutter_read_surface,
                   flutter_context);
  }
  if (ok) {
    // g_printerr: Flutter test runners often drop g_print on stdout.
    g_printerr(
        "media_kit: VideoOutput: H/W rendering with isolated EGL context "
        "(flutter-display).\n");
    video_output_write_hw_marker("flutter-display");
  }
  return ok;
}

// Path 2a: GTK3 GdkGLContext on FlView's GdkWindow — same display stack as
// Flutter; make_current works without raw EGL BAD_ACCESS on dual-GPU hosts.
static gboolean video_output_init_hw_from_gdk_gl_context(VideoOutput* self,
                                                        FlView* view) {
  if (view == NULL) {
    video_output_append_hw_diag("gdk_gl: FlView is NULL");
    return FALSE;
  }
  GtkWidget* widget = GTK_WIDGET(view);
  GdkWindow* window = gtk_widget_get_window(widget);
  if (window == NULL) {
    GtkWidget* top = gtk_widget_get_toplevel(widget);
    if (top != NULL && gtk_widget_is_toplevel(top)) {
      window = gtk_widget_get_window(top);
    }
  }
  if (window == NULL) {
    video_output_append_hw_diag("gdk_gl: no GdkWindow for FlView");
    return FALSE;
  }
  GError* error = NULL;
  GdkGLContext* gl_context = gdk_window_create_gl_context(window, &error);
  if (gl_context == NULL) {
    char buf[160];
    snprintf(buf, sizeof(buf), "gdk_gl: create failed: %s",
             error != NULL ? error->message : "unknown");
    video_output_append_hw_diag(buf);
    if (error != NULL) {
      g_error_free(error);
    }
    return FALSE;
  }
  // Prefer desktop GL 3.2+; some X11 hosts reject <3.2 (see Gdk-WARNING in logs).
  gdk_gl_context_set_required_version(gl_context, 3, 2);
  gdk_gl_context_set_use_es(gl_context, FALSE);
  if (!gdk_gl_context_realize(gl_context, &error)) {
    char buf[160];
    snprintf(buf, sizeof(buf), "gdk_gl: realize GL3.2 failed: %s; retry ES",
             error != NULL ? error->message : "unknown");
    video_output_append_hw_diag(buf);
    if (error != NULL) {
      g_error_free(error);
      error = NULL;
    }
    g_object_unref(gl_context);
    gl_context = gdk_window_create_gl_context(window, &error);
    if (gl_context == NULL) {
      snprintf(buf, sizeof(buf), "gdk_gl: recreate failed: %s",
               error != NULL ? error->message : "unknown");
      video_output_append_hw_diag(buf);
      if (error != NULL) {
        g_error_free(error);
      }
      return FALSE;
    }
    // GLES often maps to EGL under GDK_GL=egl — better for mpv texture path.
    gdk_gl_context_set_required_version(gl_context, 3, 0);
    gdk_gl_context_set_use_es(gl_context, TRUE);
    if (!gdk_gl_context_realize(gl_context, &error)) {
      snprintf(buf, sizeof(buf), "gdk_gl: realize ES failed: %s",
               error != NULL ? error->message : "unknown");
      video_output_append_hw_diag(buf);
      if (error != NULL) {
        g_error_free(error);
      }
      g_object_unref(gl_context);
      return FALSE;
    }
  }
  self->gdk_gl_context = gl_context;
  gdk_gl_context_make_current(gl_context);
  (void)video_output_load_real_egl();
  self->egl_display =
      g_real_egl.ready ? g_real_egl.get_current_display() : eglGetCurrentDisplay();
  self->egl_context =
      g_real_egl.ready ? g_real_egl.get_current_context() : eglGetCurrentContext();
  self->egl_surface =
      g_real_egl.ready ? g_real_egl.get_current_surface(EGL_DRAW)
                       : eglGetCurrentSurface(EGL_DRAW);
  self->egl_display_owned = FALSE;
  if (self->egl_display == EGL_NO_DISPLAY ||
      self->egl_context == EGL_NO_CONTEXT) {
    // Gdk realized with GLX (default on many X11 hosts). media_kit's texture
    // path needs EGLImage; without EGL current we cannot complete H/W here.
    // Hint operators / our runner to set GDK_GL=egl before GTK init.
    video_output_append_hw_diag(
        "gdk_gl: realized but eglGetCurrent* returned none "
        "(likely GLX backend — set GDK_GL=egl before GTK init)");
    g_clear_object(&self->gdk_gl_context);
    return FALSE;
  }
  char buf[128];
  snprintf(buf, sizeof(buf),
           "gdk_gl: current display=%p context=%p surface=%p",
           (void*)self->egl_display, (void*)self->egl_context,
           (void*)self->egl_surface);
  video_output_append_hw_diag(buf);
  // Reuse the Gdk/EGL context as the mpv context (make_current via GDK).
  if (!video_output_create_mpv_gl_render(self, /*need_make_current=*/TRUE,
                                         /*register_texture=*/TRUE)) {
    video_output_append_hw_diag("gdk_gl: create_mpv_gl_render failed");
    g_clear_object(&self->gdk_gl_context);
    self->egl_display = EGL_NO_DISPLAY;
    self->egl_context = EGL_NO_CONTEXT;
    self->egl_surface = EGL_NO_SURFACE;
    return FALSE;
  }
  g_printerr(
      "media_kit: VideoOutput: H/W rendering with GdkGLContext "
      "(gdk-gl-context).\n");
  video_output_write_hw_marker("gdk-gl-context");
  return TRUE;
}

// Dual-GPU hosts: ensure Mesa is preferred before first eglGetDisplay when
// both NVIDIA and Mesa glvnd vendors exist (matches Flutter GLX on Intel iGPU).
static void video_output_prefer_mesa_egl_vendor_if_dual_gpu(void) {
  if (g_getenv("__EGL_VENDOR_LIBRARY_FILENAMES") != NULL) {
    return;
  }
  const char* prefer = g_getenv("NOLIVE_EGL_VENDOR");
  if (prefer != NULL && (prefer[0] == 'n' || prefer[0] == 'N')) {
    return;
  }
  if (g_file_test("/usr/share/glvnd/egl_vendor.d/10_nvidia.json",
                  G_FILE_TEST_EXISTS) &&
      g_file_test("/usr/share/glvnd/egl_vendor.d/50_mesa.json",
                  G_FILE_TEST_EXISTS)) {
    // May be too late if libEGL already bound a vendor; main.cc sets this
    // process-early. Still attempt here for tests / alternate entrypoints.
    setenv("__EGL_VENDOR_LIBRARY_FILENAMES",
           "/usr/share/glvnd/egl_vendor.d/50_mesa.json", 1);
    video_output_append_hw_diag(
        "egl: dual-vendor host → prefer Mesa (50_mesa.json)");
  }
}

// Path 2b: Flutter 3.38+ — raw EGL from GDK X11/Wayland (fallback if GdkGL fails).
static gboolean video_output_init_hw_from_gdk_display(VideoOutput* self) {
  video_output_prefer_mesa_egl_vendor_if_dual_gpu();
  if (!video_output_load_real_egl()) {
    video_output_append_hw_diag("gdk: real libEGL unavailable");
    return FALSE;
  }
  GdkDisplay* gdk_display = gdk_display_get_default();
  if (gdk_display == NULL) {
    g_printerr("media_kit: VideoOutput: gdk_display_get_default() is NULL.\n");
    video_output_append_hw_diag("gdk: display NULL");
    return FALSE;
  }
  EGLDisplay egl_display = EGL_NO_DISPLAY;
  if (GDK_IS_X11_DISPLAY(gdk_display)) {
    Display* x11 = gdk_x11_display_get_xdisplay(gdk_display);
#if defined(EGL_PLATFORM_X11_KHR)
    if (g_real_egl.get_platform_display != NULL) {
      egl_display = g_real_egl.get_platform_display(EGL_PLATFORM_X11_KHR, x11,
                                                    NULL);
    }
#endif
    if (egl_display == EGL_NO_DISPLAY) {
      egl_display = g_real_egl.get_display((EGLNativeDisplayType)x11);
    }
    g_printerr("media_kit: VideoOutput: creating EGL display from X11.\n");
    // Log which vendor we got — dual-GPU mismatch is the usual 0x3002 cause.
    if (egl_display != EGL_NO_DISPLAY) {
      // initialize later; vendor string needs initialized display
    }
    video_output_append_hw_diag("gdk: X11 path");
  } else if (GDK_IS_WAYLAND_DISPLAY(gdk_display)) {
    struct wl_display* wl = gdk_wayland_display_get_wl_display(gdk_display);
#if defined(EGL_PLATFORM_WAYLAND_KHR)
    if (g_real_egl.get_platform_display != NULL) {
      egl_display = g_real_egl.get_platform_display(EGL_PLATFORM_WAYLAND_KHR, wl,
                                                    NULL);
    }
#endif
    if (egl_display == EGL_NO_DISPLAY) {
      egl_display = g_real_egl.get_display((EGLNativeDisplayType)wl);
    }
    g_printerr("media_kit: VideoOutput: creating EGL display from Wayland.\n");
    video_output_append_hw_diag("gdk: Wayland path");
  } else {
    g_printerr(
        "media_kit: VideoOutput: unsupported GDK display type for EGL "
        "fallback.\n");
    video_output_append_hw_diag("gdk: unsupported display type");
    return FALSE;
  }
  if (egl_display == EGL_NO_DISPLAY) {
    g_printerr("media_kit: VideoOutput: eglGetDisplay failed.\n");
    video_output_append_hw_diag("gdk: eglGetDisplay failed");
    return FALSE;
  }
  EGLint major = 0, minor = 0;
  if (!g_real_egl.initialize(egl_display, &major, &minor)) {
    g_printerr(
        "media_kit: VideoOutput: eglInitialize failed (eglError=0x%x).\n",
        g_real_egl.get_error());
    video_output_append_hw_diag("gdk: eglInitialize failed");
    return FALSE;
  }
  {
    // Query vendor via epoxy only after init — helps dual-GPU diagnosis.
    const char* vendor = (const char*)eglQueryString(egl_display, EGL_VENDOR);
    char buf[160];
    snprintf(buf, sizeof(buf), "gdk: eglInitialize ok vendor=%s major=%d minor=%d",
             vendor != NULL ? vendor : "?", major, minor);
    video_output_append_hw_diag(buf);
    g_printerr("media_kit: VideoOutput: EGL vendor=%s\n",
               vendor != NULL ? vendor : "?");
  }
  // Same native display as Flutter → same EGLDisplay object. Never terminate it
  // (Flutter still owns the connection); only destroy contexts/surfaces we create.
  self->egl_display = egl_display;
  self->egl_display_owned = FALSE;

  // Try desktop OpenGL first (mpv's usual path on Linux), then GLES2.
  // Isolated GLES contexts often return EGL_BAD_ACCESS (0x3002) on make_current
  // when the process already hosts Flutter's EGL (multi-GPU / epoxy).
  struct {
    EGLenum api;
    EGLint renderable;
    EGLint context_attribs[8];
    const char* label;
  } attempts[] = {
      {EGL_OPENGL_API, EGL_OPENGL_BIT,
       {EGL_CONTEXT_MAJOR_VERSION, 3, EGL_CONTEXT_MINOR_VERSION, 0,
        EGL_CONTEXT_OPENGL_PROFILE_MASK, EGL_CONTEXT_OPENGL_CORE_PROFILE_BIT,
        EGL_NONE},
       "opengl-core3"},
      {EGL_OPENGL_API, EGL_OPENGL_BIT,
       {EGL_CONTEXT_MAJOR_VERSION, 2, EGL_CONTEXT_MINOR_VERSION, 1, EGL_NONE},
       "opengl-2.1"},
      {EGL_OPENGL_ES_API, EGL_OPENGL_ES2_BIT,
       {EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE}, "gles2"},
  };

  gboolean created = FALSE;
  for (size_t i = 0; i < sizeof(attempts) / sizeof(attempts[0]); i++) {
    g_real_egl.bind_api(attempts[i].api);
    EGLint cfg_attribs[] = {
        EGL_SURFACE_TYPE, EGL_PBUFFER_BIT | EGL_WINDOW_BIT,
        EGL_RENDERABLE_TYPE, attempts[i].renderable,
        EGL_RED_SIZE, 8,
        EGL_GREEN_SIZE, 8,
        EGL_BLUE_SIZE, 8,
        EGL_ALPHA_SIZE, 8,
        EGL_NONE,
    };
    EGLConfig config = NULL;
    EGLint num = 0;
    if (!g_real_egl.choose_config(self->egl_display, cfg_attribs, &config, 1,
                                  &num) ||
        num <= 0) {
      char buf[96];
      snprintf(buf, sizeof(buf), "gdk: eglChooseConfig failed (%s)",
               attempts[i].label);
      video_output_append_hw_diag(buf);
      continue;
    }
    self->egl_context = g_real_egl.create_context(
        self->egl_display, config, EGL_NO_CONTEXT, attempts[i].context_attribs);
    if (self->egl_context == EGL_NO_CONTEXT) {
      char buf[96];
      snprintf(buf, sizeof(buf), "gdk: eglCreateContext failed (%s) err=0x%x",
               attempts[i].label, g_real_egl.get_error());
      video_output_append_hw_diag(buf);
      continue;
    }
    EGLint pbuf_attribs[] = {EGL_WIDTH, 16, EGL_HEIGHT, 16, EGL_NONE};
    self->egl_surface =
        g_real_egl.create_pbuffer(self->egl_display, config, pbuf_attribs);
    if (self->egl_surface == EGL_NO_SURFACE) {
      char buf[96];
      snprintf(buf, sizeof(buf),
               "gdk: pbuffer failed (%s) err=0x%x; try surfaceless",
               attempts[i].label, g_real_egl.get_error());
      video_output_append_hw_diag(buf);
    }
    if (video_output_create_mpv_gl_render(self, /*need_make_current=*/TRUE,
                                          /*register_texture=*/TRUE)) {
      char buf[96];
      snprintf(buf, sizeof(buf), "gdk: success with %s", attempts[i].label);
      video_output_append_hw_diag(buf);
      created = TRUE;
      break;
    }
    // Clean partial state before next attempt.
    if (self->render_context != NULL) {
      mpv_render_context_free(self->render_context);
      self->render_context = NULL;
    }
    if (self->texture_gl != NULL) {
      g_object_unref(self->texture_gl);
      self->texture_gl = NULL;
    }
    if (self->egl_surface != EGL_NO_SURFACE) {
      // eglDestroySurface via epoxy is fine once real path failed.
      eglDestroySurface(self->egl_display, self->egl_surface);
      self->egl_surface = EGL_NO_SURFACE;
    }
    if (self->egl_context != EGL_NO_CONTEXT) {
      eglDestroyContext(self->egl_display, self->egl_context);
      self->egl_context = EGL_NO_CONTEXT;
    }
  }
  if (!created) {
    video_output_append_hw_diag("gdk: all GL API attempts failed");
    return FALSE;
  }
  g_printerr(
      "media_kit: VideoOutput: H/W rendering with isolated EGL context "
      "(gdk-display fallback).\n");
  video_output_write_hw_marker("gdk-display");
  return TRUE;
}

VideoOutput* video_output_new(FlTextureRegistrar* texture_registrar,
                              FlView* view,
                              gint64 handle,
                              VideoOutputConfiguration configuration) {
  VideoOutput* self = VIDEO_OUTPUT(g_object_new(video_output_get_type(), NULL));
  self->texture_registrar = texture_registrar;
  self->handle = (mpv_handle*)handle;
  self->width = configuration.width;
  self->height = configuration.height;
  self->configuration = configuration;
  self->egl_display = EGL_NO_DISPLAY;
  self->egl_context = EGL_NO_CONTEXT;
  self->egl_surface = EGL_NO_SURFACE;
  self->egl_display_owned = FALSE;
  self->gdk_gl_context = NULL;
  self->hw_pending = FALSE;
  self->gl_shared_with_flutter = FALSE;
  self->sw_idle_queued = FALSE;
  self->sw_last_render_us = 0;
  self->sw_max_w = SW_RENDERING_DEFAULT_MAX_WIDTH;
  self->sw_max_h = SW_RENDERING_DEFAULT_MAX_HEIGHT;
  video_output_sw_read_max_from_env(self);
#ifndef MPV_RENDER_API_TYPE_SW
  // MPV_RENDER_API_TYPE_SW must be available for S/W rendering.
  if (!self->configuration.enable_hardware_acceleration) {
    g_printerr("media_kit: VideoOutput: S/W rendering is not supported.\n");
  }
  self->configuration.enable_hardware_acceleration = TRUE;
#endif
  // Keep audio clock as VO default (known-good with pulse + libmpv embed).
  // Per-source Dart properties may set display-tempo / framedrop.
  mpv_set_option_string(self->handle, "video-sync", "audio");
  // Causes frame drops with `pulse` audio output. (SlotSun/dart_simple_live#42)
  // mpv_set_option_string(self->handle, "video-timing-offset", "0");

  gboolean hardware_acceleration_supported = FALSE;
  if (self->configuration.enable_hardware_acceleration) {
    // 1) Prefer Flutter's current EGL context when the platform thread has one.
    if (video_output_init_hw_from_flutter_egl(self)) {
      hardware_acceleration_supported = TRUE;
    } else if (video_output_init_hw_from_gdk_gl_context(self, view)) {
      // 2) GTK-owned GL context that exposes EGL (GDK_GL=egl / Wayland).
      hardware_acceleration_supported = TRUE;
    } else {
      // 3) Isolated EGL is opt-in only. On dual-GPU X11 hosts it can report
      // success then abort with "Could not create GBM EGL display" and leave a
      // black embed (decode still runs). Prefer proven S/W texture upload +
      // HW decode (auto-copy/nvdec) unless the user forces isolated EGL.
      const char* force = g_getenv("NOLIVE_FORCE_ISOLATED_EGL_VIDEO");
      if (force != NULL && force[0] == '1' &&
          video_output_init_hw_from_gdk_display(self)) {
        hardware_acceleration_supported = TRUE;
      } else {
        video_output_append_hw_diag(
            "skip isolated EGL (set NOLIVE_FORCE_ISOLATED_EGL_VIDEO=1 to try); "
            "S/W texture + HW decode to protect visible playback");
        g_printerr(
            "media_kit: VideoOutput: H/W OpenGL texture path deferred "
            "(no Flutter/GDK EGL; isolated EGL opt-in only). "
            "Using S/W texture upload; HW decode via auto-copy/nvdec/vaapi.\n");
      }
    }
  }
#ifdef MPV_RENDER_API_TYPE_SW
  if (!hardware_acceleration_supported) {
    g_printerr(
        "media_kit: VideoOutput: S/W rendering (max %ldx%ld). "
        "NOLIVE_SW_MAX_HEIGHT=720 reduces CPU; H/W texture needs "
        "NOLIVE_FORCE_ISOLATED_EGL_VIDEO=1 (may black-screen on dual-GPU).\n",
        (long)self->sw_max_w, (long)self->sw_max_h);
    video_output_write_hw_marker("software");
    // H/W rendering failed. Fallback to S/W rendering.
    self->pixel_buffer = g_new0(guint8, SW_RENDERING_PIXEL_BUFFER_SIZE);
    self->texture_gl = NULL;
    self->texture_sw = texture_sw_new(self);
    if (fl_texture_registrar_register_texture(texture_registrar,
                                              FL_TEXTURE(self->texture_sw))) {
      mpv_render_param params[] = {
          {MPV_RENDER_PARAM_API_TYPE, (void*)MPV_RENDER_API_TYPE_SW},
          {MPV_RENDER_PARAM_INVALID, (void*)0},
      };
      if (mpv_render_context_create(&self->render_context, self->handle,
                                    params) == 0) {
        mpv_render_context_set_update_callback(
            self->render_context,
            [](void* data) {
              // Coalesce only: one idle at a time. Do NOT time-throttle —
              // skipping frames here made domestic playback feel *more* juddery.
              VideoOutput* self = (VideoOutput*)data;
              if (self->destroyed || self->sw_idle_queued) {
                return;
              }
              self->sw_idle_queued = TRUE;
              gdk_threads_add_idle(
                  [](gpointer data) -> gboolean {
                    VideoOutput* self = (VideoOutput*)data;
                    self->sw_idle_queued = FALSE;
                    if (self->destroyed) {
                      return FALSE;
                    }
                    g_mutex_lock(&self->mutex);
                    gint64 width = video_output_get_width(self);
                    gint64 height = video_output_get_height(self);
                    if (width > 0 && height > 0 &&
                        width * height * 4 <=
                            (gint64)SW_RENDERING_PIXEL_BUFFER_SIZE) {
                      gint32 size[]{(gint32)width, (gint32)height};
                      gint32 pitch = 4 * (gint32)width;
                      mpv_render_param params[]{
                          {MPV_RENDER_PARAM_SW_SIZE, size},
                          {MPV_RENDER_PARAM_SW_FORMAT, (void*)"rgb0"},
                          {MPV_RENDER_PARAM_SW_STRIDE, &pitch},
                          {MPV_RENDER_PARAM_SW_POINTER, self->pixel_buffer},
                          {MPV_RENDER_PARAM_INVALID, (void*)0},
                      };
                      mpv_render_context_render(self->render_context, params);
                      fl_texture_registrar_mark_texture_frame_available(
                          self->texture_registrar,
                          FL_TEXTURE(self->texture_sw));
                    }
                    g_mutex_unlock(&self->mutex);
                    return FALSE;
                  },
                  data);
            },
            self);
      }
    }
  }
#endif
  return self;
}

void video_output_set_texture_update_callback(
    VideoOutput* self,
    TextureUpdateCallback texture_update_callback,
    gpointer texture_update_callback_context) {
  self->texture_update_callback = texture_update_callback;
  self->texture_update_callback_context = texture_update_callback_context;
  // Notify initial dimensions as (1, 1) if |width| & |height| are 0 i.e.
  // texture & video frame size is based on playing file's resolution. This
  // will make sure that `Texture` widget on Flutter's widget tree is actually
  // mounted & |fl_texture_registrar_mark_texture_frame_available| actually
  // invokes the |TextureGL| or |TextureSW| callbacks. Otherwise it will be a
  // never ending deadlock where no video frames are ever rendered.
  gint64 texture_id = video_output_get_texture_id(self);
  if (self->width == 0 || self->height == 0) {
    self->texture_update_callback(texture_id, 1, 1,
                                  self->texture_update_callback_context);
  } else {
    self->texture_update_callback(texture_id, self->width, self->height,
                                  self->texture_update_callback_context);
  }
}

void video_output_set_size(VideoOutput* self, gint64 width, gint64 height) {
  // Ideally, a mutex should be used here & |video_output_get_width| +
  // |video_output_get_height|. However, that is throwing everything into a
  // deadlock. Flutter itself seems to have some synchronization mechanism in
  // rendering & platform channels AFAIK.

  // H/W
  if (self->texture_gl) {
    self->width = width;
    self->height = height;
  }
  // S/W — aspect-preserving fit into runtime max box.
  if (self->texture_sw) {
    gint64 fw = 0, fh = 0;
    video_output_sw_fit_size(width, height, self->sw_max_w, self->sw_max_h, &fw,
                             &fh);
    self->width = fw;
    self->height = fh;
  }
}

mpv_render_context* video_output_get_render_context(VideoOutput* self) {
  return self->render_context;
}

GdkGLContext* video_output_get_gdk_gl_context(VideoOutput* self) {
  return self->gdk_gl_context;
}

EGLDisplay video_output_get_egl_display(VideoOutput* self) {
  return self->egl_display;
}

EGLContext video_output_get_egl_context(VideoOutput* self) {
  return self->egl_context;
}

EGLSurface video_output_get_egl_surface(VideoOutput* self) {
  return self->egl_surface;
}

guint8* video_output_get_pixel_buffer(VideoOutput* self) {
  return self->pixel_buffer;
}

gint64 video_output_get_width(VideoOutput* self) {
  // Fixed width.
  if (self->width) {
    return self->width;
  }

  // Video resolution dependent width.
  gint64 width = 0;
  gint64 height = 0;

  mpv_node params;
  mpv_get_property(self->handle, "video-out-params", MPV_FORMAT_NODE, &params);

  int64_t dw = 0, dh = 0, rotate = 0;
  if (params.format == MPV_FORMAT_NODE_MAP) {
    for (int32_t i = 0; i < params.u.list->num; i++) {
      char* key = params.u.list->keys[i];
      auto value = params.u.list->values[i];
      if (value.format == MPV_FORMAT_INT64) {
        if (strcmp(key, "dw") == 0) {
          dw = value.u.int64;
        }
        if (strcmp(key, "dh") == 0) {
          dh = value.u.int64;
        }
        if (strcmp(key, "rotate") == 0) {
          rotate = value.u.int64;
        }
      }
    }
    mpv_free_node_contents(&params);
  }

  width = rotate == 0 || rotate == 180 ? dw : dh;
  height = rotate == 0 || rotate == 180 ? dh : dw;

  if (self->texture_sw != NULL) {
    gint64 fw = 0, fh = 0;
    video_output_sw_fit_size(width, height, self->sw_max_w, self->sw_max_h, &fw,
                             &fh);
    return fw;
  }

  return width;
}

gint64 video_output_get_height(VideoOutput* self) {
  // Fixed height.
  if (self->width) {
    return self->height;
  }

  // Video resolution dependent height.
  gint64 width = 0;
  gint64 height = 0;

  mpv_node params;
  mpv_get_property(self->handle, "video-out-params", MPV_FORMAT_NODE, &params);

  int64_t dw = 0, dh = 0, rotate = 0;
  if (params.format == MPV_FORMAT_NODE_MAP) {
    for (int32_t i = 0; i < params.u.list->num; i++) {
      char* key = params.u.list->keys[i];
      auto value = params.u.list->values[i];
      if (value.format == MPV_FORMAT_INT64) {
        if (strcmp(key, "dw") == 0) {
          dw = value.u.int64;
        }
        if (strcmp(key, "dh") == 0) {
          dh = value.u.int64;
        }
        if (strcmp(key, "rotate") == 0) {
          rotate = value.u.int64;
        }
      }
    }
    mpv_free_node_contents(&params);
  }

  width = rotate == 0 || rotate == 180 ? dw : dh;
  height = rotate == 0 || rotate == 180 ? dh : dw;

  if (self->texture_sw != NULL) {
    gint64 fw = 0, fh = 0;
    video_output_sw_fit_size(width, height, self->sw_max_w, self->sw_max_h, &fw,
                             &fh);
    return fh;
  }

  return height;
}

gint64 video_output_get_texture_id(VideoOutput* self) {
  // H/W
  if (self->texture_gl) {
    return (gint64)self->texture_gl;
  }
  // S/W
  if (self->texture_sw) {
    return (gint64)self->texture_sw;
  }
  g_assert_not_reached();
  return -1;
}

void video_output_notify_texture_update(VideoOutput* self) {
  gint64 id = video_output_get_texture_id(self);
  gint64 width = video_output_get_width(self);
  gint64 height = video_output_get_height(self);
  gpointer context = self->texture_update_callback_context;
  if (self->texture_update_callback != NULL) {
    self->texture_update_callback(id, width, height, context);
  }
}
