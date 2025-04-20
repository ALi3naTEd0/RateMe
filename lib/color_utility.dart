import 'package:flutter/material.dart';

/// Comprehensive utility class for color operations in the app
class ColorUtility {
  // Standard app colors
  static const Color defaultPurple = Color(0xFF864AF9);
  static const Color exactPurple = Color(0xFF864AF9);
  static const String defaultPurpleHex = '#FF864AF9';

  /// Convert a Color to RGB string format
  static String colorToRgbString(Color color) {
    // Always use round() to ensure we get integer values
    final int r = color.r.round();
    final int g = color.g.round();
    final int b = color.b.round();
    return 'RGB: $r, $g, $b';
  }

  /// Convert a Color to hex string with proper formatting
  static String colorToHex(Color color) {
    // Always use round() for component values for consistency
    final int r = color.r.round();
    final int g = color.g.round();
    final int b = color.b.round();

    // Apply safety check for very small values that should be zero
    final int safeR = r < 3 ? 0 : r;
    final int safeG = g < 3 ? 0 : g;
    final int safeB = b < 3 ? 0 : b;

    // Format with proper padding and uppercase for consistency
    return '#FF${safeR.toRadixString(16).padLeft(2, '0')}${safeG.toRadixString(16).padLeft(2, '0')}${safeB.toRadixString(16).padLeft(2, '0')}'
        .toUpperCase();
  }

  /// Convert a hex string to Color with proper error handling
  static Color hexToColor(String hexString) {
    if (hexString.isEmpty) {
      return defaultPurple;
    }

    // Remove # if present
    final String processedHex =
        hexString.startsWith('#') ? hexString.substring(1) : hexString;

    // Handle different hex formats
    String normalizedHex;
    if (processedHex.length == 6) {
      // Add alpha channel if missing
      normalizedHex = 'FF$processedHex';
    } else if (processedHex.length == 8) {
      // Force full opacity for consistency
      normalizedHex = 'FF${processedHex.substring(2)}';
    } else {
      // Invalid format, return default
      return defaultPurple;
    }

    // Parse and return the color
    try {
      final int colorValue = int.parse(normalizedHex, radix: 16);
      return Color(colorValue);
    } catch (e) {
      // Return default on parsing error
      return defaultPurple;
    }
  }

  /// Create a Color from RGB components
  static Color fromRGB(int r, int g, int b) {
    return Color.fromRGBO(r, g, b, 1.0);
  }

  /// Compare two colors by their components
  static bool colorsEqual(Color a, Color b) {
    return a.r == b.r && a.g == b.g && a.b == b.b && a.a == b.a;
  }

  /// Get contrasting text color (black or white) based on background color
  static Color getContrastingColor(Color backgroundColor) {
    // Calculate perceived brightness
    final double luminance = (0.299 * backgroundColor.r +
            0.587 * backgroundColor.g +
            0.114 * backgroundColor.b) /
        255;

    // Return white for dark backgrounds, black for light backgrounds
    return luminance > 0.5 ? Colors.black : Colors.white;
  }

  /// Lightens a color by the given percent
  static Color lighten(Color color, double percent) {
    assert(percent >= 0 && percent <= 1);

    return Color.fromRGBO(
      (color.r + ((255 - color.r) * percent)).round().clamp(0, 255),
      (color.g + ((255 - color.g) * percent)).round().clamp(0, 255),
      (color.b + ((255 - color.b) * percent)).round().clamp(0, 255),
      1.0,
    );
  }

  /// Darkens a color by the given percent
  static Color darken(Color color, double percent) {
    assert(percent >= 0 && percent <= 1);

    return Color.fromRGBO(
      (color.r * (1 - percent)).round().clamp(0, 255),
      (color.g * (1 - percent)).round().clamp(0, 255),
      (color.b * (1 - percent)).round().clamp(0, 255),
      1.0,
    );
  }
}
