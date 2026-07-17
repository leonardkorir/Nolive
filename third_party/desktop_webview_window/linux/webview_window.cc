//
// Created by boyan on 10/21/21.
//

#include "webview_window.h"
#include <utility>
#include "message_channel_plugin.h"
#include <unordered_map>
#include <string>

#if WEBKIT_MAJOR_VERSION < 2 || \
    (WEBKIT_MAJOR_VERSION == 2 && WEBKIT_MINOR_VERSION < 40)
#define WEBKIT_OLD_USED
#endif

void get_cookies_callback(WebKitCookieManager *manager, GAsyncResult *res,
                          gpointer user_data) {
  CookieData *data = (CookieData *)user_data;
  GError *error = NULL;

  GList *cookies =
      webkit_cookie_manager_get_cookies_finish(manager, res, &error);
  if (error != NULL) {
    g_print("Error getting cookies: %s\n", error->message);
    g_error_free(error);
    data->cookies = NULL;
  } else {
    data->cookies = cookies;
  }

  g_main_loop_quit(data->loop);
}

GList *get_cookies_sync(WebKitWebView *web_view) {
  WebKitCookieManager *cookie_manager;
  GMainLoop *loop;
  CookieData data = {0};

  cookie_manager = webkit_web_context_get_cookie_manager(
      webkit_web_view_get_context(web_view));
  loop = g_main_loop_new(NULL, FALSE);
  data.loop = loop;

  const gchar *uri = webkit_web_view_get_uri(web_view);

  // Start the asynchronous operation
  webkit_cookie_manager_get_cookies(cookie_manager, uri, NULL,
                                    (GAsyncReadyCallback)get_cookies_callback,
                                    &data);

  // Run the main loop until the callback is called
  g_main_loop_run(loop);

  g_main_loop_unref(loop);

  return data.cookies;
}

namespace {

gboolean on_load_failed_with_tls_errors(WebKitWebView *web_view,
                                        char *failing_uri,
                                        GTlsCertificate *certificate,
                                        GTlsCertificateFlags errors,
                                        gpointer user_data) {
  auto *webview = static_cast<WebviewWindow *>(user_data);
  g_critical("on_load_failed_with_tls_errors: %s %p error= %d", failing_uri,
             webview, errors);
  // TODO allow certificate for some certificate ?
  // maybe we can use the pem from
  // https://source.chromium.org/chromium/chromium/src/+/master:net/data/ssl/ev_roots/
  //  webkit_web_context_allow_tls_certificate_for_host(webkit_web_view_get_context(web_view),
  //  certificate, uri->host); webkit_web_view_load_uri(web_view, failing_uri);
  return false;
}

GtkWidget *on_create(WebKitWebView *web_view,
                     WebKitNavigationAction *navigation_action,
                     gpointer user_data) {
  // Deny window.open popups into a new WebView (would need a full secondary
  // window lifecycle). Load the target URI in the current view instead when
  // possible so login redirects (e.g. Douyin) do not open a dead blank tab.
  auto *action = navigation_action;
  if (action != nullptr) {
    auto *request = webkit_navigation_action_get_request(action);
    const char *uri = request != nullptr ? webkit_uri_request_get_uri(request)
                                         : nullptr;
    if (uri != nullptr && uri[0] != '\0') {
      webkit_web_view_load_uri(web_view, uri);
    }
  }
  return nullptr;
}

void on_load_changed(WebKitWebView *web_view, WebKitLoadEvent load_event,
                     gpointer user_data) {
  auto *window = static_cast<WebviewWindow *>(user_data);
  window->OnLoadChanged(load_event);
}

gboolean decide_policy_cb(WebKitWebView *web_view,
                          WebKitPolicyDecision *decision,
                          WebKitPolicyDecisionType type, gpointer user_data) {
  auto *window = static_cast<WebviewWindow *>(user_data);
  return window->DecidePolicy(decision, type);
}

}  // namespace

WebviewWindow::WebviewWindow(FlMethodChannel *method_channel, int64_t window_id,
                             std::function<void()> on_close_callback,
                             const std::string &title, int width, int height,
                             int title_bar_height)
    : method_channel_(method_channel),
      window_id_(window_id),
      on_close_callback_(std::move(on_close_callback)),
      default_user_agent_() {
  g_object_ref(method_channel_);

  window_ = gtk_window_new(GTK_WINDOW_TOPLEVEL);
  g_signal_connect(G_OBJECT(window_), "destroy",
                   G_CALLBACK(+[](GtkWidget *, gpointer arg) {
                     auto *window = static_cast<WebviewWindow *>(arg);
                     // Drop widget pointers before deferred map erase so no
                     // later method channel call touches a destroyed GTK tree.
                     window->window_ = nullptr;
                     window->webview_ = nullptr;
                     window->box_ = nullptr;
                     auto *args = fl_value_new_map();
                     fl_value_set(args, fl_value_new_string("id"),
                                  fl_value_new_int(window->window_id_));
                     fl_method_channel_invoke_method(
                         FL_METHOD_CHANNEL(window->method_channel_),
                         "onWindowClose", args, nullptr, nullptr, nullptr);
                     // Defer erase/delete of WebviewWindow until after the
                     // destroy signal stack unwinds (avoids UAF / SIGSEGV).
                     if (window->on_close_callback_) {
                       auto *cb =
                           new std::function<void()>(window->on_close_callback_);
                       window->on_close_callback_ = nullptr;
                       g_idle_add(
                           [](gpointer data) -> gboolean {
                             auto *fn =
                                 static_cast<std::function<void()> *>(data);
                             (*fn)();
                             delete fn;
                             return G_SOURCE_REMOVE;
                           },
                           cb);
                     }
                   }),
                   this);
  gtk_window_set_title(GTK_WINDOW(window_), title.c_str());
  gtk_window_set_default_size(GTK_WINDOW(window_), width, height);
  gtk_window_set_position(GTK_WINDOW(window_), GTK_WIN_POS_CENTER);

  box_ = GTK_BOX(gtk_box_new(GTK_ORIENTATION_VERTICAL, 0));
  gtk_container_add(GTK_CONTAINER(window_), GTK_WIDGET(box_));

  // Use a plain GTK title bar instead of a nested FlView ("web_view_title_bar"
  // second Flutter engine). A second engine inside the host process freezes /
  // SIGABRTs on heavy sites (Douyin login) and when closing windows.
  if (title_bar_height > 0) {
    GtkWidget *header = gtk_header_bar_new();
    gtk_header_bar_set_title(GTK_HEADER_BAR(header), title.c_str());
    gtk_header_bar_set_show_close_button(GTK_HEADER_BAR(header), TRUE);
    gtk_window_set_titlebar(GTK_WINDOW(window_), header);
  }

  // initial web_view
  webview_ = webkit_web_view_new();
  g_signal_connect(G_OBJECT(webview_), "load-failed-with-tls-errors",
                   G_CALLBACK(on_load_failed_with_tls_errors), this);
  g_signal_connect(G_OBJECT(webview_), "create", G_CALLBACK(on_create), this);
  g_signal_connect(G_OBJECT(webview_), "load-changed",
                   G_CALLBACK(on_load_changed), this);
  g_signal_connect(G_OBJECT(webview_), "decide-policy",
                   G_CALLBACK(decide_policy_cb), this);

  auto settings = webkit_web_view_get_settings(WEBKIT_WEB_VIEW(webview_));
  webkit_settings_set_javascript_can_open_windows_automatically(settings, true);
  webkit_settings_set_enable_javascript(settings, true);
  webkit_settings_set_enable_developer_extras(settings, false);
  webkit_settings_set_enable_page_cache(settings, true);
  webkit_settings_set_enable_smooth_scrolling(settings, true);
  webkit_settings_set_enable_mediasource(settings, true);
  webkit_settings_set_enable_media_stream(settings, true);
  webkit_settings_set_enable_webaudio(settings, true);
  webkit_settings_set_enable_webgl(settings, true);
  // Prefer a modern desktop Chrome UA so sites like Douyin/live.douyin.com do
  // not serve empty mobile shells or challenge pages that look blank.
  webkit_settings_set_user_agent(
      settings,
      "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) "
      "Chrome/122.0.0.0 Safari/537.36");
  default_user_agent_ = webkit_settings_get_user_agent(settings);
  gtk_box_pack_end(box_, webview_, true, true, 0);

  gtk_widget_show_all(GTK_WIDGET(window_));
  gtk_widget_grab_focus(GTK_WIDGET(webview_));
}

WebviewWindow::~WebviewWindow() {
  if (webview_ != nullptr) {
    WebKitUserContentManager *manager = webkit_web_view_get_user_content_manager(WEBKIT_WEB_VIEW(webview_));
    for (auto &entry : js_channel_handler_ids_) {
      g_signal_handler_disconnect(manager, entry.second);
    }
    js_channel_handler_ids_.clear();
  }
  // If Close() was never called, destroy the still-alive window without
  // re-entering the deferred erase (callback already cleared).
  if (window_ != nullptr) {
    on_close_callback_ = nullptr;
    gtk_widget_destroy(window_);
    window_ = nullptr;
    webview_ = nullptr;
    box_ = nullptr;
  }
  g_object_unref(method_channel_);
  printf("~WebviewWindow\n");
}

void WebviewWindow::Navigate(const char *url) {
  if (webview_ == nullptr) {
    return;
  }
  webkit_web_view_load_uri(WEBKIT_WEB_VIEW(webview_), url);
}

void WebviewWindow::RunJavaScriptWhenContentReady(const char *java_script) {
  if (webview_ == nullptr) {
    return;
  }
  auto *manager =
      webkit_web_view_get_user_content_manager(WEBKIT_WEB_VIEW(webview_));
  webkit_user_content_manager_add_script(
      manager,
      webkit_user_script_new(java_script, WEBKIT_USER_CONTENT_INJECT_TOP_FRAME,
                             WEBKIT_USER_SCRIPT_INJECT_AT_DOCUMENT_START,
                             nullptr, nullptr));
}

void WebviewWindow::SetApplicationNameForUserAgent(
    const std::string &app_name) {
  if (webview_ == nullptr) {
    return;
  }
  auto *setting = webkit_web_view_get_settings(WEBKIT_WEB_VIEW(webview_));
  webkit_settings_set_user_agent(setting,
                                 (default_user_agent_ + app_name).c_str());
}

void WebviewWindow::Close() {
  if (window_ == nullptr) {
    return;
  }
  // gtk_widget_destroy is idempotent-safe with our destroy handler nulling
  // window_. Prefer destroy over gtk_window_close so the WM close path and
  // method-channel close path both tear down cleanly.
  GtkWidget *widget = window_;
  gtk_widget_destroy(widget);
}

void WebviewWindow::OnLoadChanged(WebKitLoadEvent load_event) {
  if (webview_ == nullptr) {
    return;
  }
  // notify history changed event.
  {
    auto can_go_back = webkit_web_view_can_go_back(WEBKIT_WEB_VIEW(webview_));
    auto can_go_forward =
        webkit_web_view_can_go_forward(WEBKIT_WEB_VIEW(webview_));
    auto *args = fl_value_new_map();
    fl_value_set(args, fl_value_new_string("id"), fl_value_new_int(window_id_));
    fl_value_set(args, fl_value_new_string("canGoBack"),
                 fl_value_new_bool(can_go_back));
    fl_value_set(args, fl_value_new_string("canGoForward"),
                 fl_value_new_bool(can_go_forward));
    fl_method_channel_invoke_method(FL_METHOD_CHANNEL(method_channel_),
                                    "onHistoryChanged", args, nullptr, nullptr,
                                    nullptr);
  }

  // notify load start/finished event.
  switch (load_event) {
    case WEBKIT_LOAD_STARTED: {
      auto *args = fl_value_new_map();
      fl_value_set(args, fl_value_new_string("id"),
                   fl_value_new_int(window_id_));
      fl_method_channel_invoke_method(FL_METHOD_CHANNEL(method_channel_),
                                      "onNavigationStarted", args, nullptr,
                                      nullptr, nullptr);
      break;
    }
    case WEBKIT_LOAD_FINISHED: {
      auto *args = fl_value_new_map();
      fl_value_set(args, fl_value_new_string("id"),
                   fl_value_new_int(window_id_));
      fl_method_channel_invoke_method(FL_METHOD_CHANNEL(method_channel_),
                                      "onNavigationCompleted", args, nullptr,
                                      nullptr, nullptr);
      break;
    }
    default:
      break;
  }
}

void WebviewWindow::GoForward() {
  if (webview_ == nullptr) {
    return;
  }
  webkit_web_view_go_forward(WEBKIT_WEB_VIEW(webview_));
}

void WebviewWindow::GoBack() {
  if (webview_ == nullptr) {
    return;
  }
  webkit_web_view_go_back(WEBKIT_WEB_VIEW(webview_));
}

void WebviewWindow::Reload() {
  if (webview_ == nullptr) {
    return;
  }
  webkit_web_view_reload(WEBKIT_WEB_VIEW(webview_));
}

void WebviewWindow::StopLoading() {
  if (webview_ == nullptr) {
    return;
  }
  webkit_web_view_stop_loading(WEBKIT_WEB_VIEW(webview_));
}

FlValue *WebviewWindow::GetAllCookies() {
  if (webview_ == nullptr) {
    return fl_value_new_list();
  }
  GList *cookies = get_cookies_sync(WEBKIT_WEB_VIEW(webview_));

  g_autoptr(FlValue) fl_cookie_list = fl_value_new_list();

  FlValue* cookie_list = fl_value_ref(fl_cookie_list);

  for (GList *l = cookies; l; l = l->next) {
    SoupCookie *cookie = (SoupCookie *)l->data;
    g_autoptr(FlValue) cookie_map = fl_value_new_map();

    fl_value_set_string_take(cookie_map, "name",
                             fl_value_new_string(soup_cookie_get_name(cookie)));
    fl_value_set_string_take(
        cookie_map, "value",
        fl_value_new_string(soup_cookie_get_value(cookie)));
    fl_value_set_string_take(
        cookie_map, "domain",
        fl_value_new_string(soup_cookie_get_domain(cookie)));
    fl_value_set_string_take(cookie_map, "path",
                             fl_value_new_string(soup_cookie_get_path(cookie)));

    gdouble expires = g_date_time_get_seconds(soup_cookie_get_expires(cookie));

    if (expires >= 0) {
      fl_value_set_string_take(cookie_map, "expires",
                               fl_value_new_float(expires));
    } else {
      fl_value_set_string_take(cookie_map, "expires", fl_value_new_null());
    }

    fl_value_set_string_take(
        cookie_map, "httpOnly",
        fl_value_new_bool(soup_cookie_get_http_only(cookie)));
    fl_value_set_string_take(cookie_map, "secure",
                             fl_value_new_bool(soup_cookie_get_secure(cookie)));
    fl_value_set_string_take(cookie_map, "sessionOnly",
                             fl_value_new_bool(false));

    fl_value_append(cookie_list, cookie_map);
    soup_cookie_free(cookie);
  }

  g_free(cookies);

  return cookie_list;
}

namespace {

struct PolicyDecisionAsyncData {
  FlMethodChannel *channel;
  WebKitPolicyDecision *decision;
};

void on_url_request_policy_response(GObject * /*source*/, GAsyncResult *result,
                                    gpointer user_data) {
  auto *data = static_cast<PolicyDecisionAsyncData *>(user_data);
  g_autoptr(GError) error = nullptr;
  g_autoptr(FlMethodResponse) response =
      fl_method_channel_invoke_method_finish(data->channel, result, &error);

  bool allow = true;
  if (error != nullptr) {
    g_warning("onUrlRequested failed: %s", error->message);
  } else if (FL_IS_METHOD_SUCCESS_RESPONSE(response)) {
    FlValue *result_value = fl_method_success_response_get_result(
        FL_METHOD_SUCCESS_RESPONSE(response));
    if (result_value != nullptr &&
        fl_value_get_type(result_value) == FL_VALUE_TYPE_BOOL) {
      // Dart OnUrlRequestCallback: true = allow, false = block.
      allow = fl_value_get_bool(result_value);
    }
  }

  if (allow) {
    webkit_policy_decision_use(data->decision);
  } else {
    webkit_policy_decision_ignore(data->decision);
  }
  g_object_unref(data->decision);
  delete data;
}

const char *policy_decision_uri(WebKitPolicyDecision *decision,
                                WebKitPolicyDecisionType type) {
  if (type == WEBKIT_POLICY_DECISION_TYPE_NAVIGATION_ACTION) {
    auto *navigation_decision = WEBKIT_NAVIGATION_POLICY_DECISION(decision);
    auto *navigation_action =
        webkit_navigation_policy_decision_get_navigation_action(
            navigation_decision);
    auto *request = webkit_navigation_action_get_request(navigation_action);
    return webkit_uri_request_get_uri(request);
  }
  if (type == WEBKIT_POLICY_DECISION_TYPE_RESPONSE) {
    auto *response_decision = WEBKIT_RESPONSE_POLICY_DECISION(decision);
    auto *request =
        webkit_response_policy_decision_get_request(response_decision);
    return webkit_uri_request_get_uri(request);
  }
  return nullptr;
}

}  // namespace

gboolean WebviewWindow::DecidePolicy(WebKitPolicyDecision *decision,
                                     WebKitPolicyDecisionType type) {
  // Only gate top-level navigations through Dart. Intercepting RESPONSE for
  // every CSS/JS/XHR/image freezes heavy sites (Douyin login blank page) —
  // method channel cannot keep up and policy decisions pile up indefinitely.
  // Headless bridges that need resource blocking should do it in JS or via
  // navigation-level callbacks.
  if (type != WEBKIT_POLICY_DECISION_TYPE_NAVIGATION_ACTION) {
    return false;
  }

  const char *uri = policy_decision_uri(decision, type);
  if (uri == nullptr) {
    return false;
  }

  auto *args = fl_value_new_map();
  fl_value_set(args, fl_value_new_string("id"), fl_value_new_int(window_id_));
  fl_value_set(args, fl_value_new_string("url"), fl_value_new_string(uri));

  auto *async_data = new PolicyDecisionAsyncData{
      FL_METHOD_CHANNEL(method_channel_),
      // Keep decision alive until Dart responds.
      WEBKIT_POLICY_DECISION(g_object_ref(decision)),
  };

  fl_method_channel_invoke_method(FL_METHOD_CHANNEL(method_channel_),
                                  "onUrlRequested", args, nullptr,
                                  on_url_request_policy_response, async_data);
  // TRUE: we own the decision; use/ignore will be called in the async callback.
  return true;
}

void WebviewWindow::EvaluateJavaScript(const char *java_script,
                                       FlMethodCall *call) {
  if (webview_ == nullptr) {
    fl_method_call_respond_error(call, "webview closed",
                                 "evaluateJavaScript after close", nullptr,
                                 nullptr);
    return;
  }
#ifdef WEBKIT_OLD_USED
  webkit_web_view_run_javascript(
#else
  webkit_web_view_evaluate_javascript(
#endif
      WEBKIT_WEB_VIEW(webview_), java_script,
#ifndef WEBKIT_OLD_USED
      -1, nullptr, nullptr,
#endif
      nullptr,
      [](GObject *object, GAsyncResult *result, gpointer user_data) {
        auto *call = static_cast<FlMethodCall *>(user_data);
        GError *error = nullptr;
        auto *js_result =
#ifdef WEBKIT_OLD_USED
            webkit_web_view_run_javascript_finish(
#else
            webkit_web_view_evaluate_javascript_finish(
#endif
                WEBKIT_WEB_VIEW(object), result, &error);
        if (!js_result) {
          fl_method_call_respond_error(call, "failed to evaluate javascript.",
                                       error->message, nullptr, nullptr);
          g_error_free(error);
        } else {
          auto *js_value = jsc_value_to_json(
#ifdef WEBKIT_OLD_USED
              webkit_javascript_result_get_js_value
#endif
              (js_result),
              0);
          fl_method_call_respond_success(
              call, js_value ? fl_value_new_string(js_value) : nullptr,
              nullptr);
        }
        g_object_unref(call);
      },
      g_object_ref(call));
}

void WebviewWindow::RegisterJavaScriptChannel(const std::string &name) {
    WebKitUserContentManager *manager =
            webkit_web_view_get_user_content_manager(WEBKIT_WEB_VIEW(webview_));

    webkit_user_content_manager_register_script_message_handler(
            manager, name.c_str());

    struct HandlerData {
        WebviewWindow *self;
        std::string name;
    };

    HandlerData *data = new HandlerData{this, name};
    auto it = js_channel_handler_ids_.find(name);
    if (it != js_channel_handler_ids_.end()) {
        g_signal_handler_disconnect(manager, it->second);
        js_channel_handler_ids_.erase(it);
    }

    gulong handler_id = g_signal_connect_data(
            manager,
            ("script-message-received::" + name).c_str(),
            G_CALLBACK(+[](WebKitUserContentManager *manager,
                           WebKitJavascriptResult *result,
                           gpointer user_data) {
                HandlerData *data = static_cast<HandlerData *>(user_data);
                WebviewWindow *self = data->self;
                const std::string &handler_name = data->name;

                JSCValue *value = webkit_javascript_result_get_js_value(result);

                if (jsc_value_is_string(value)) {
                    gchar *str_value = jsc_value_to_string(value);
                    if (str_value != nullptr) {
                        FlValue *args = fl_value_new_map();
                        fl_value_set_string(args, "name",
                                            fl_value_new_string(handler_name.c_str()));
                        fl_value_set_string(args, "body",
                                            fl_value_new_string(str_value));
                        fl_value_set_string(args, "id",
                                            fl_value_new_int(self->window_id_));

                        fl_method_channel_invoke_method(
                                self->method_channel_,
                                "onJavaScriptMessage",
                                args,
                                nullptr,
                                nullptr,
                                nullptr);

                        g_free(str_value);
                    }
                }
            }),
            data,
            +[](gpointer user_data, GClosure *) {
                delete static_cast<HandlerData *>(user_data);
            },
            static_cast<GConnectFlags>(0));

    js_channel_handler_ids_[name] = handler_id;
}


void WebviewWindow::UnregisterJavaScriptChannel(const std::string &name) {
    WebKitUserContentManager *manager =
            webkit_web_view_get_user_content_manager(WEBKIT_WEB_VIEW(webview_));

    auto it = js_channel_handler_ids_.find(name);
    if (it != js_channel_handler_ids_.end()) {
        g_signal_handler_disconnect(manager, it->second);
        js_channel_handler_ids_.erase(it);
    }

    webkit_user_content_manager_unregister_script_message_handler(
            manager, name.c_str());
}


void WebviewWindow::SetVisibility(bool visible) {
  if (window_ == nullptr) {
    return;
  }
  if (visible) {
    gtk_widget_show(GTK_WIDGET(window_));
  } else {
    gtk_widget_hide(GTK_WIDGET(window_));
  }
}
