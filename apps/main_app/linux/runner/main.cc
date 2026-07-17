#include "my_application.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <X11/Xlib.h>
#include <glib.h>

// Shared with my_application.cc — GDK/Flutter reinstall their own X error
// handlers after display connect. We install early, after GTK startup, after
// plugins, and on a recurring timer so GLXBadWindow never reaches the default
// Xlib handler (which calls exit(1)).
static guint nolive_x_handler_timer = 0;

int nolive_x_error_handler(Display* display, XErrorEvent* event) {
  char text[256];
  XGetErrorText(display, event->error_code, text, sizeof(text));

  fprintf(stderr,
          "nolive: X error %s (code=%u major=%u minor=%u serial=%lu) "
          "[ignored]\n",
          text, event->error_code, event->request_code, event->minor_code,
          event->serial);
  // Never abort — multi-window GL (mpv gpu-next) + WebKitGTK headless views
  // produce non-fatal races on the shared process Display.
  return 0;
}

void nolive_install_x_error_handlers(void) {
  XInitThreads();
  XSetErrorHandler(nolive_x_error_handler);
}

static gboolean nolive_reinstall_x_error_handlers_tick(gpointer user_data) {
  (void)user_data;
  XSetErrorHandler(nolive_x_error_handler);
  return G_SOURCE_CONTINUE;
}

void nolive_start_x_error_handler_watchdog(void) {
  nolive_install_x_error_handlers();
  if (nolive_x_handler_timer == 0) {
    // Re-assert every 200ms — Flutter/GDK/WebKit may replace the handler.
    nolive_x_handler_timer =
        g_timeout_add(200, nolive_reinstall_x_error_handlers_tick, nullptr);
  }
}

int main(int argc, char** argv) {
  // media_kit_video H/W path is EGL-based. GTK3 defaults to GLX on many X11
  // dual-GPU hosts, which leaves eglGetCurrent* empty and raw eglMakeCurrent
  // fails with EGL_BAD_ACCESS — permanent S/W rendering + stutter.
  // Force EGL before any GTK/Gdk init (must be process-early).
  if (getenv("GDK_GL") == nullptr) {
    setenv("GDK_GL", "egl", 0);
  }

  // Do NOT force Mesa/NVIDIA glvnd vendor here. Dual-GPU experiments that
  // preferred Mesa isolated EGL produced black video embeds
  // ("Could not create GBM EGL display"). Safe default is S/W texture +
  // auto-copy decode until a dual-GPU H/W path is proven on this host.

  nolive_install_x_error_handlers();

  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
