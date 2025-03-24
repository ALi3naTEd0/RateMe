import 'package:flutter/material.dart';

/// Utility class for app-wide navigation without BuildContext
class NavigationUtil {
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  /// Navigate to a new screen
  static Future<T?> navigateTo<T>(Widget page) {
    return navigatorKey.currentState!.push<T>(
      MaterialPageRoute(builder: (_) => page),
    );
  }

  /// Replace current screen with a new one
  static Future<T?> replaceTo<T>(Widget page) {
    return navigatorKey.currentState!.pushReplacement<T, void>(
      MaterialPageRoute(builder: (_) => page),
    );
  }

  /// Go back to previous screen
  static void goBack<T>([T? result]) {
    return navigatorKey.currentState!.pop<T>(result);
  }

  /// Go back to first route
  static void goToRoot() {
    return navigatorKey.currentState!.popUntil((route) => route.isFirst);
  }

  /// Provide a consistent AppBar with back button
  static AppBar buildAppBar(String title, {List<Widget>? actions}) {
    return AppBar(
      title: Text(title),
      leading: const IconButton(
        // Only need one const
        icon: Icon(Icons.arrow_back), // Remove unnecessary const
        onPressed: goBack,
      ),
      actions: actions,
    );
  }
}
