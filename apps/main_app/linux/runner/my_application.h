#ifndef FLUTTER_MY_APPLICATION_H_
#define FLUTTER_MY_APPLICATION_H_

#include <gtk/gtk.h>

G_DECLARE_FINAL_TYPE(MyApplication,
                     my_application,
                     MY,
                     APPLICATION,
                     GtkApplication)

/**
 * my_application_new:
 *
 * Creates a new Flutter-based application.
 *
 * Returns: a new #MyApplication.
 */
MyApplication* my_application_new();

// Install process-wide X11 error handlers that do not abort on GLXBadWindow.
// Called early in main and again after GTK/GDK display setup.
void nolive_install_x_error_handlers(void);

// Keep re-installing the non-fatal handler (GDK/Flutter/WebKit overwrite it).
void nolive_start_x_error_handler_watchdog(void);

#endif  // FLUTTER_MY_APPLICATION_H_
