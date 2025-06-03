#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"
#include <dbus/dbus.h>
#include <string>
#include <map>

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  DBusConnection* dbus_conn;
  guint dbus_name_id;
  guint dbus_object_id;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// MPRIS interface names
const char* MPRIS_MEDIAPLAYER2_INTERFACE = "org.mpris.MediaPlayer2";
const char* MPRIS_PLAYER_INTERFACE = "org.mpris.MediaPlayer2.Player";
const char* MPRIS_OBJECT_PATH = "/org/mpris/MediaPlayer2";

// Media Controls Channel
const char* kMediaControlsChannel = "com.cresca.media_controls";

// Current playback state
bool g_is_playing = false;
std::string g_current_title;
std::string g_current_artist;
std::string g_current_album;
int64_t g_duration = 0;
int64_t g_position = 0;

// Forward declarations
void initialize_mpris(MyApplication* self);
void cleanup_mpris(MyApplication* self);
void update_mpris_metadata(const char* title, const char* artist, const char* album, int64_t duration, int64_t position, bool is_playing);
DBusHandlerResult handle_dbus_message(DBusConnection* conn, DBusMessage* msg, void* user_data);

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // Use a header bar when running in GNOME as this is the common style used
  // by applications and is the setup most users will be using (e.g. Ubuntu
  // desktop).
  // If running on X and not using GNOME then just use a traditional title bar
  // in case the window manager does more exotic layout, e.g. tiling.
  // If running on Wayland assume the header bar will work (may need changing
  // if future cases occur).
  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "Music Player");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "Music Player");
  }

  // Set window properties
  gtk_window_set_default_size(window, 1280, 720);
  gtk_window_set_resizable(window, TRUE);
  gtk_window_set_decorated(window, TRUE);
  gtk_window_set_skip_taskbar_hint(window, FALSE);
  gtk_window_set_skip_pager_hint(window, FALSE);
  gtk_window_set_keep_above(window, FALSE);
  gtk_window_set_keep_below(window, FALSE);
  gtk_window_set_accept_focus(window, TRUE);
  gtk_window_set_focus_on_map(window, TRUE);
  gtk_window_set_urgency_hint(window, FALSE);
  gtk_window_set_gravity(window, GDK_GRAVITY_NORTH_WEST);
  gtk_window_set_position(window, GTK_WIN_POS_CENTER);

  // Enable window state persistence
  gtk_window_set_auto_startup_notification(window, TRUE);
  gtk_window_set_icon_name(window, "music-player");
  gtk_window_set_role(window, "music-player");

  gtk_widget_show(GTK_WIDGET(window));

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Set up media controls channel
  g_autoptr(FlMethodChannel) channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)),
      kMediaControlsChannel,
      FL_METHOD_CODEC(fl_standard_method_codec_new()));

  fl_method_channel_set_method_call_handler(
      channel,
      [](FlMethodChannel* channel, FlMethodCall* method_call, gpointer user_data) {
        const gchar* method = fl_method_call_get_name(method_call);
        FlValue* args = fl_method_call_get_args(method_call);

        if (strcmp(method, "updateMediaControls") == 0) {
          if (fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
            const char* title = fl_value_get_string(fl_value_lookup_string(args, "title"));
            const char* artist = fl_value_get_string(fl_value_lookup_string(args, "artist"));
            const char* album = fl_value_get_string(fl_value_lookup_string(args, "album"));
            int64_t duration = fl_value_get_int(fl_value_lookup_string(args, "duration"));
            int64_t position = fl_value_get_int(fl_value_lookup_string(args, "position"));
            bool is_playing = fl_value_get_bool(fl_value_lookup_string(args, "isPlaying"));

            update_mpris_metadata(title, artist, album, duration, position, is_playing);
            fl_method_call_respond_success(method_call, nullptr);
          } else {
            fl_method_call_respond_error(method_call, "INVALID_ARGUMENTS", "Invalid arguments", nullptr);
          }
        } else if (strcmp(method, "dispose") == 0) {
          cleanup_mpris(MY_APPLICATION(user_data));
          fl_method_call_respond_success(method_call, nullptr);
        } else {
          fl_method_call_respond_not_implemented(method_call);
        }
      },
      self,
      nullptr);

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  gtk_widget_grab_focus(GTK_WIDGET(view));

  // Initialize MPRIS
  initialize_mpris(self);
}

void initialize_mpris(MyApplication* self) {
  DBusError error;
  dbus_error_init(&error);

  // Connect to the session bus
  self->dbus_conn = dbus_bus_get(DBUS_BUS_SESSION, &error);
  if (dbus_error_is_set(&error)) {
    g_warning("Failed to connect to session bus: %s", error.message);
    dbus_error_free(&error);
    return;
  }

  // Request a name on the bus
  int ret = dbus_bus_request_name(self->dbus_conn,
                                "org.mpris.MediaPlayer2.Cresca",
                                DBUS_NAME_FLAG_REPLACE_EXISTING,
                                &error);
  if (ret != DBUS_REQUEST_NAME_REPLY_PRIMARY_OWNER) {
    g_warning("Failed to request name: %s", error.message);
    dbus_error_free(&error);
    return;
  }

  // Register object path
  DBusObjectPathVTable vtable = {
    nullptr,
    handle_dbus_message,
    nullptr,
    nullptr,
    nullptr,
    nullptr
  };

  self->dbus_object_id = dbus_connection_register_object_path(
      self->dbus_conn,
      MPRIS_OBJECT_PATH,
      &vtable,
      self);

  if (self->dbus_object_id == 0) {
    g_warning("Failed to register object path");
    return;
  }
}

void cleanup_mpris(MyApplication* self) {
  if (self->dbus_conn) {
    if (self->dbus_object_id != 0) {
      dbus_connection_unregister_object_path(self->dbus_conn, MPRIS_OBJECT_PATH);
    }
    dbus_connection_unref(self->dbus_conn);
    self->dbus_conn = nullptr;
  }
}

void update_mpris_metadata(const char* title, const char* artist, const char* album, int64_t duration, int64_t position, bool is_playing) {
  g_current_title = title;
  g_current_artist = artist;
  g_current_album = album;
  g_duration = duration;
  g_position = position;
  g_is_playing = is_playing;
}

DBusHandlerResult handle_dbus_message(DBusConnection* conn, DBusMessage* msg, void* user_data) {
  const char* interface = dbus_message_get_interface(msg);
  const char* method = dbus_message_get_member(msg);
  DBusMessage* reply = nullptr;

  if (strcmp(interface, MPRIS_PLAYER_INTERFACE) == 0) {
    if (strcmp(method, "Play") == 0) {
      // Handle play command
      reply = dbus_message_new_method_return(msg);
    } else if (strcmp(method, "Pause") == 0) {
      // Handle pause command
      reply = dbus_message_new_method_return(msg);
    } else if (strcmp(method, "Next") == 0) {
      // Handle next command
      reply = dbus_message_new_method_return(msg);
    } else if (strcmp(method, "Previous") == 0) {
      // Handle previous command
      reply = dbus_message_new_method_return(msg);
    } else if (strcmp(method, "Stop") == 0) {
      // Handle stop command
      reply = dbus_message_new_method_return(msg);
    }
  }

  if (reply) {
    dbus_connection_send(conn, reply, nullptr);
    dbus_message_unref(reply);
    return DBUS_HANDLER_RESULT_HANDLED;
  }

  return DBUS_HANDLER_RESULT_NOT_YET_HANDLED;
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application, gchar*** arguments, int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
     g_warning("Failed to register: %s", error->message);
     *exit_status = 1;
     return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  cleanup_mpris(self);
  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line = my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {
  self->dbus_conn = nullptr;
  self->dbus_name_id = 0;
  self->dbus_object_id = 0;
}

MyApplication* my_application_new() {
  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID,
                                     "flags", G_APPLICATION_NON_UNIQUE,
                                     nullptr));
}
