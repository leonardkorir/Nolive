// This file is a part of media_kit
// (https://github.com/media-kit/media-kit).
//
// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
// All rights reserved.
// Use of this source code is governed by MIT license that can be found in the
// LICENSE file.
//
// Nolive: supports isolated EGL mpv rendering with either EGLImage handoff
// (when Flutter is also on EGL) or glReadPixels upload (when Flutter is on
// GLX — dual-GPU X11). Avoids EGLImage across GLX↔EGL which crashes.

#include "include/media_kit_video/texture_gl.h"

#include <epoxy/gl.h>
#include <epoxy/egl.h>
#include <epoxy/glx.h>
#include <gdk/gdk.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// EGLImage extension function pointers
typedef EGLImageKHR (*PFNEGLCREATEIMAGEKHRPROC)(EGLDisplay dpy,
                                                EGLContext ctx,
                                                EGLenum target,
                                                EGLClientBuffer buffer,
                                                const EGLint* attrib_list);
typedef EGLBoolean (*PFNEGLDESTROYIMAGEKHRPROC)(EGLDisplay dpy,
                                                EGLImageKHR image);
typedef void (*PFNGLEGLIMAGETARGETTEXTURE2DOESPROC)(GLenum target,
                                                    GLeglImageOES image);

#ifndef eglCreateImageKHR
static PFNEGLCREATEIMAGEKHRPROC eglCreateImageKHR = NULL;
#endif
#ifndef eglDestroyImageKHR
static PFNEGLDESTROYIMAGEKHRPROC eglDestroyImageKHR = NULL;
#endif
#ifndef glEGLImageTargetTexture2DOES
static PFNGLEGLIMAGETARGETTEXTURE2DOESPROC glEGLImageTargetTexture2DOES = NULL;
#endif

static void init_egl_image_extensions() {
  static gboolean initialized = FALSE;
  if (!initialized) {
    eglCreateImageKHR =
        (PFNEGLCREATEIMAGEKHRPROC)eglGetProcAddress("eglCreateImageKHR");
    eglDestroyImageKHR =
        (PFNEGLDESTROYIMAGEKHRPROC)eglGetProcAddress("eglDestroyImageKHR");
    glEGLImageTargetTexture2DOES =
        (PFNGLEGLIMAGETARGETTEXTURE2DOESPROC)eglGetProcAddress(
            "glEGLImageTargetTexture2DOES");
    initialized = TRUE;
  }
}

struct SavedFlutterGl {
  gboolean is_egl;
  gboolean is_glx;
  EGLDisplay egl_display;
  EGLContext egl_context;
  EGLSurface egl_draw;
  EGLSurface egl_read;
  Display* glx_display;
  GLXContext glx_context;
  GLXDrawable glx_drawable;
};

static SavedFlutterGl texture_gl_save_flutter_gl(void) {
  SavedFlutterGl s{};
  s.egl_display = eglGetCurrentDisplay();
  s.egl_context = eglGetCurrentContext();
  s.egl_draw = eglGetCurrentSurface(EGL_DRAW);
  s.egl_read = eglGetCurrentSurface(EGL_READ);
  if (s.egl_display != EGL_NO_DISPLAY && s.egl_context != EGL_NO_CONTEXT) {
    s.is_egl = TRUE;
    return s;
  }
  s.glx_display = glXGetCurrentDisplay();
  s.glx_context = glXGetCurrentContext();
  s.glx_drawable = glXGetCurrentDrawable();
  if (s.glx_display != NULL && s.glx_context != NULL) {
    s.is_glx = TRUE;
  }
  return s;
}

static void texture_gl_restore_flutter_gl(const SavedFlutterGl* s) {
  if (s == NULL) {
    return;
  }
  if (s->is_egl) {
    eglMakeCurrent(s->egl_display, s->egl_draw, s->egl_read, s->egl_context);
    return;
  }
  if (s->is_glx) {
    glXMakeCurrent(s->glx_display, s->glx_drawable, s->glx_context);
    return;
  }
  // No Flutter GL saved — release only if we somehow hold EGL; do not call
  // gdk_gl_context_clear_current() (destroys Flutter compositor on X11/GLX).
}

static gboolean texture_gl_make_mpv_context_current(VideoOutput* video_output) {
  if (video_output_make_context_current(video_output)) {
    return TRUE;
  }
  g_printerr(
      "media_kit: TextureGL: video_output_make_context_current failed.\n");
  return FALSE;
}

struct _TextureGL {
  FlTextureGL parent_instance;
  guint32 name;          // Flutter's texture name
  guint32 fbo;           // mpv's FBO
  guint32 mpv_texture;   // mpv's color attachment
  EGLImageKHR egl_image; // EGLImage share (EGL↔EGL only)
  guint8* readback;      // CPU staging when Flutter is on GLX
  gsize readback_size;
  guint32 current_width;
  guint32 current_height;
  VideoOutput* video_output;
};

G_DEFINE_TYPE(TextureGL, texture_gl, fl_texture_gl_get_type())

static void texture_gl_init(TextureGL* self) {
  self->name = 0;
  self->fbo = 0;
  self->mpv_texture = 0;
  self->egl_image = EGL_NO_IMAGE_KHR;
  self->readback = NULL;
  self->readback_size = 0;
  self->current_width = 1;
  self->current_height = 1;
  self->video_output = NULL;
}

static void texture_gl_dispose(GObject* object) {
  TextureGL* self = TEXTURE_GL(object);
  VideoOutput* video_output = self->video_output;

  SavedFlutterGl saved = texture_gl_save_flutter_gl();

  if (self->name != 0 && self->name != self->mpv_texture) {
    glDeleteTextures(1, &self->name);
    self->name = 0;
  }

  if (self->egl_image != EGL_NO_IMAGE_KHR && video_output != NULL) {
    EGLDisplay egl_display = video_output_get_egl_display(video_output);
    if (egl_display != EGL_NO_DISPLAY && eglDestroyImageKHR != NULL) {
      eglDestroyImageKHR(egl_display, self->egl_image);
    }
    self->egl_image = EGL_NO_IMAGE_KHR;
  }

  if (video_output != NULL &&
      texture_gl_make_mpv_context_current(video_output)) {
    if (self->mpv_texture != 0) {
      glDeleteTextures(1, &self->mpv_texture);
      self->mpv_texture = 0;
    }
    if (self->fbo != 0) {
      glDeleteFramebuffers(1, &self->fbo);
      self->fbo = 0;
    }
  }

  g_free(self->readback);
  self->readback = NULL;
  self->readback_size = 0;
  self->current_width = 1;
  self->current_height = 1;
  self->video_output = NULL;

  texture_gl_restore_flutter_gl(&saved);
  G_OBJECT_CLASS(texture_gl_parent_class)->dispose(object);
}

static void texture_gl_class_init(TextureGLClass* klass) {
  FL_TEXTURE_GL_CLASS(klass)->populate = texture_gl_populate_texture;
  G_OBJECT_CLASS(klass)->dispose = texture_gl_dispose;
}

TextureGL* texture_gl_new(VideoOutput* video_output) {
  init_egl_image_extensions();
  TextureGL* self = TEXTURE_GL(g_object_new(texture_gl_get_type(), NULL));
  self->video_output = video_output;
  return self;
}

static gboolean texture_gl_ensure_readback(TextureGL* self,
                                           gint32 width,
                                           gint32 height) {
  gsize need = (gsize)width * (gsize)height * 4u;
  if (need == 0) {
    return FALSE;
  }
  if (self->readback != NULL && self->readback_size >= need) {
    return TRUE;
  }
  g_free(self->readback);
  self->readback = (guint8*)g_malloc(need);
  self->readback_size = need;
  return self->readback != NULL;
}

gboolean texture_gl_populate_texture(FlTextureGL* texture,
                                     guint32* target,
                                     guint32* name,
                                     guint32* width,
                                     guint32* height,
                                     GError** error) {
  TextureGL* self = TEXTURE_GL(texture);
  VideoOutput* video_output = self->video_output;

  (void)video_output_ensure_render_context(video_output);
  const gboolean shared = video_output_uses_shared_gl(video_output);
  mpv_render_context* render_context =
      video_output_get_render_context(video_output);

  gint32 required_width = (guint32)video_output_get_width(video_output);
  gint32 required_height = (guint32)video_output_get_height(video_output);

  if (required_width > 0 && required_height > 0 && render_context != NULL) {
    gboolean first_frame =
        self->fbo == 0 || self->mpv_texture == 0 || self->name == 0;
    gboolean resize = self->current_width != (guint32)required_width ||
                      self->current_height != (guint32)required_height;

    SavedFlutterGl flutter_gl = texture_gl_save_flutter_gl();
    const gboolean flutter_on_egl = flutter_gl.is_egl;

    if (!shared) {
      if (!texture_gl_make_mpv_context_current(video_output)) {
        texture_gl_restore_flutter_gl(&flutter_gl);
        return FALSE;
      }
    }

    if (first_frame || resize) {
      if (!first_frame) {
        if (self->mpv_texture != 0) {
          glDeleteTextures(1, &self->mpv_texture);
          self->mpv_texture = 0;
        }
        if (self->fbo != 0) {
          glDeleteFramebuffers(1, &self->fbo);
          self->fbo = 0;
        }
        if (self->egl_image != EGL_NO_IMAGE_KHR) {
          EGLDisplay egl_display = video_output_get_egl_display(video_output);
          if (egl_display != EGL_NO_DISPLAY && eglDestroyImageKHR != NULL) {
            eglDestroyImageKHR(egl_display, self->egl_image);
          }
          self->egl_image = EGL_NO_IMAGE_KHR;
        }
      }

      glGenFramebuffers(1, &self->fbo);
      glBindFramebuffer(GL_FRAMEBUFFER, self->fbo);
      glGenTextures(1, &self->mpv_texture);
      glBindTexture(GL_TEXTURE_2D, self->mpv_texture);
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
      glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, required_width, required_height, 0,
                   GL_RGBA, GL_UNSIGNED_BYTE, NULL);
      glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D,
                             self->mpv_texture, 0);
      glBindFramebuffer(GL_FRAMEBUFFER, 0);
      glBindTexture(GL_TEXTURE_2D, 0);
      glFlush();

      if (shared) {
        if (!first_frame && self->name != 0 && self->name != self->mpv_texture) {
          glDeleteTextures(1, &self->name);
        }
        self->name = self->mpv_texture;
      } else if (flutter_on_egl && eglCreateImageKHR != NULL &&
                 glEGLImageTargetTexture2DOES != NULL) {
        EGLDisplay egl_display = video_output_get_egl_display(video_output);
        EGLContext egl_context = video_output_get_egl_context(video_output);
        EGLint egl_image_attribs[] = {EGL_NONE};
        self->egl_image = eglCreateImageKHR(
            egl_display, egl_context, EGL_GL_TEXTURE_2D_KHR,
            (EGLClientBuffer)(guintptr)self->mpv_texture, egl_image_attribs);
        texture_gl_restore_flutter_gl(&flutter_gl);
        if (!first_frame && self->name != 0 && self->name != self->mpv_texture) {
          glDeleteTextures(1, &self->name);
        }
        glGenTextures(1, &self->name);
        glBindTexture(GL_TEXTURE_2D, self->name);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        if (self->egl_image != EGL_NO_IMAGE_KHR) {
          glEGLImageTargetTexture2DOES(GL_TEXTURE_2D, self->egl_image);
        }
        glBindTexture(GL_TEXTURE_2D, 0);
      } else {
        // Flutter on GLX (or no EGLImage): prepare Flutter-side texture after
        // restore; pixels filled via glReadPixels each frame.
        texture_gl_restore_flutter_gl(&flutter_gl);
        if (!first_frame && self->name != 0 && self->name != self->mpv_texture) {
          glDeleteTextures(1, &self->name);
        }
        glGenTextures(1, &self->name);
        glBindTexture(GL_TEXTURE_2D, self->name);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, required_width, required_height,
                     0, GL_RGBA, GL_UNSIGNED_BYTE, NULL);
        glBindTexture(GL_TEXTURE_2D, 0);
        (void)texture_gl_ensure_readback(self, required_width, required_height);
      }

      self->current_width = (guint32)required_width;
      self->current_height = (guint32)required_height;
      video_output_notify_texture_update(video_output);
    }

    // Render one frame into FBO (isolated EGL or shared).
    if (!shared) {
      flutter_gl = texture_gl_save_flutter_gl();
      if (!texture_gl_make_mpv_context_current(video_output)) {
        texture_gl_restore_flutter_gl(&flutter_gl);
        return FALSE;
      }
    }

    glBindFramebuffer(GL_FRAMEBUFFER, self->fbo);
    mpv_opengl_fbo fbo{(gint32)self->fbo, required_width, required_height, 0};
    int flip_y = 0;
    mpv_render_param params[] = {
        {MPV_RENDER_PARAM_OPENGL_FBO, &fbo},
        {MPV_RENDER_PARAM_FLIP_Y, &flip_y},
        {MPV_RENDER_PARAM_INVALID, NULL},
    };
    mpv_render_context_render(render_context, params);

    const gboolean need_readback =
        !shared && self->egl_image == EGL_NO_IMAGE_KHR && self->readback != NULL;

    if (need_readback) {
      glPixelStorei(GL_PACK_ALIGNMENT, 1);
      glReadPixels(0, 0, required_width, required_height, GL_RGBA,
                   GL_UNSIGNED_BYTE, self->readback);
    }

    glBindFramebuffer(GL_FRAMEBUFFER, 0);
    glFlush();

    if (!shared) {
      texture_gl_restore_flutter_gl(&flutter_gl);
      if (need_readback && self->name != 0) {
        glBindTexture(GL_TEXTURE_2D, self->name);
        glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
        glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, required_width, required_height,
                        GL_RGBA, GL_UNSIGNED_BYTE, self->readback);
        glBindTexture(GL_TEXTURE_2D, 0);
      }
    }
  }

  *target = GL_TEXTURE_2D;
  *name = self->name;
  *width = self->current_width;
  *height = self->current_height;

  if (self->name == 0) {
    glGenTextures(1, &self->name);
    glBindTexture(GL_TEXTURE_2D, self->name);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, 1, 1, 0, GL_RGBA, GL_UNSIGNED_BYTE,
                 NULL);
    glBindTexture(GL_TEXTURE_2D, 0);
    *name = self->name;
    *width = 1;
    *height = 1;
  }

  return TRUE;
}
