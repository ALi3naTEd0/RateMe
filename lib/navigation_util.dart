import 'package:flutter/material.dart';

/// Utility class for app-wide navigation without BuildContext
class NavigationUtil {
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  // Standard content max width factor - 85% of screen width (matching AppDimensions)
  static const double contentMaxWidthFactor = 0.85;

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

  /// Provide a consistent AppBar with back button that follows the 85% width pattern
  static AppBar buildAppBar(BuildContext context, String title,
      {List<Widget>? actions}) {
    // Calculate page width and horizontal padding
    final pageWidth = MediaQuery.of(context).size.width * contentMaxWidthFactor;
    final horizontalPadding =
        (MediaQuery.of(context).size.width - pageWidth) / 2;

    return AppBar(
      centerTitle: false,
      automaticallyImplyLeading: false,
      title: Padding(
        padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back),
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              onPressed: goBack,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      actions: actions != null
          ? [
              Padding(
                padding: EdgeInsets.only(right: horizontalPadding),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: actions,
                ),
              )
            ]
          : null,
    );
  }

  /// Center content with 85% width consistent with app design
  static Widget centerWithWidth(BuildContext context, Widget child) {
    final pageWidth = MediaQuery.of(context).size.width * contentMaxWidthFactor;

    return Center(
      child: SizedBox(
        width: pageWidth,
        child: child,
      ),
    );
  }

  /// Get consistent horizontal padding for 85% width
  static EdgeInsets getHorizontalPadding(BuildContext context) {
    final pageWidth = MediaQuery.of(context).size.width * contentMaxWidthFactor;
    final padding = (MediaQuery.of(context).size.width - pageWidth) / 2;

    return EdgeInsets.symmetric(horizontal: padding);
  }

  /// Get the standard width (85% of screen width)
  static double getStandardWidth(BuildContext context) {
    return MediaQuery.of(context).size.width * contentMaxWidthFactor;
  }
}
