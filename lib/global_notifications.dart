import 'dart:async';
import 'search_service.dart';
import 'logging.dart';
import 'package:flutter/material.dart';

/// Helper class for showing consistent notifications across the app
class GlobalNotifications {
  // Stream controller for search platform changes
  static final StreamController<SearchPlatform> _platformChangeController =
      StreamController<SearchPlatform>.broadcast();

  /// Stream of search platform changes that can be listened to throughout the app
  static Stream<SearchPlatform> get onSearchPlatformChanged =>
      _platformChangeController.stream;

  /// Notify when default search platform changes
  static void defaultSearchPlatformChanged(SearchPlatform platform) {
    Logging.severe('Broadcasting default platform change: ${platform.name}');
    _platformChangeController.add(platform);
  }

  /// Show a notification at the bottom of the screen
  static void showNotification(
    BuildContext context,
    String message, {
    bool isError = false,
    Duration duration = const Duration(seconds: 2),
  }) {
    final snackBar = SnackBar(
      content: Text(message),
      duration: duration,
      backgroundColor: isError
          ? Theme.of(context).colorScheme.error
          : Theme.of(context).colorScheme.primary,
      behavior: SnackBarBehavior.floating,
      // Set width to 85% of the screen width
      width: MediaQuery.of(context).size.width * 0.85,
      // Set margin to center the notification
      margin: const EdgeInsets.only(bottom: 16.0, left: 8.0, right: 8.0),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8.0),
      ),
    );

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(snackBar);
  }

  /// Show a success notification
  static void showSuccess(BuildContext context, String message) {
    showNotification(context, message, isError: false);
  }

  /// Show an error notification
  static void showError(BuildContext context, String message) {
    showNotification(context, message,
        isError: true, duration: const Duration(seconds: 3));
  }

  // List of callbacks for theme changes
  static final List<Function(Color)> _themeListeners = [];

  /// Add a listener for theme changes
  static void addThemeListener(Function(Color) listener) {
    _themeListeners.add(listener);
  }

  /// Notify all listeners of a theme change
  static void notifyThemeChanged(Color color) {
    for (var listener in _themeListeners) {
      listener(color);
    }
  }

  /// Close all streams when app is terminated
  static void dispose() {
    _platformChangeController.close();
  }
}
