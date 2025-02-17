#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif
#ifdef GDK_WINDOWING_WAYLAND
#include <gdk/gdkwayland.h>
#endif

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Function to detect display backend and set environment variables
static void set_display_backend() {
  // Sistema y accesibilidad
  g_setenv("GTK_IM_MODULE", "gtk-im-context-simple", TRUE);
  g_setenv("XMODIFIERS", "@im=none", TRUE);
  
  // Configuración específica de GTK
  g_setenv("GTK_CSD", "0", TRUE);
  g_setenv("GTK_THEME", "Adwaita:light", TRUE);
  
  // Configuración de cursor
  g_setenv("XCURSOR_THEME", "Adwaita", TRUE);
  g_setenv("XCURSOR_PATH", "/usr/share/icons", TRUE);
}

// Function to configure and show the main application window
static void configure_and_show_window(GtkApplication* application, MyApplication* self) {
  GtkWindow* window = GTK_WINDOW(gtk_application_window_new(application));
  GtkSettings* settings = gtk_settings_get_default();

  if (settings != NULL) {
    g_object_set(G_OBJECT(settings),
                "gtk-theme-name", "Adwaita",
                "gtk-cursor-theme-name", "Adwaita",
                NULL);
  }

  // Configure window before realization
  gtk_window_set_title(window, "Rate Me!");
  gtk_window_set_default_size(window, 1280, 720);
  gtk_window_set_position(window, GTK_WIN_POS_CENTER);
  gtk_window_set_resizable(window, TRUE);

  // Create project and view
  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Register plugins
  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  // Make window visible first
  gtk_widget_show(GTK_WIDGET(window));
  
  // Then show and focus view
  gtk_widget_show(GTK_WIDGET(view));
  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  set_display_backend();
  configure_and_show_window(GTK_APPLICATION(application), self);
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
  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
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

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID,
                                     "flags", G_APPLICATION_NON_UNIQUE,
                                     nullptr));
}
