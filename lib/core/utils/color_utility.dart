import 'package:flutter/material.dart';

/// Comprehensive utility class for color operations in the app
class ColorUtility {
  // Default app color - ONLY used when database has no color setting
  static const Color defaultColor = Color(0xFF864AF9); // Default purple
  static const String defaultColorHex = '#FF864AF9';

  // "Safe black" is a very dark grey that looks like black but avoids Android UI issues
  static const Color safeBlack = Color(0xFF010101);
  static const String safeBlackHex = '#FF010101';

  /// Convert a hex string to Color - CRITICAL METHOD THAT MUST WORK CORRECTLY
  static Color hexToColor(String hexString) {
    String hex = hexString.replaceAll('#', '');
    if (hex.length == 6) {
      hex = 'FF$hex'; // Add alpha if missing
    }
    return Color(int.parse(hex, radix: 16));
  }

  /// Convert a Color to RGB string format
  static String colorToRgbString(Color color) {
    final int r = color.r.round();
    final int g = color.g.round();
    final int b = color.b.round();
    return 'RGB: $r, $g, $b';
  }

  /// Convert a Color to hex string with proper formatting
  static String colorToHex(Color color) {
    return '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';
  }

  /// Convert Color to hex string (with alpha)
  static String colorToHexString(Color color) {
    return '#${color.toARGB32().toRadixString(16).padLeft(8, '0')}';
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
    final double luminance = (0.299 * backgroundColor.r +
            0.587 * backgroundColor.g +
            0.114 * backgroundColor.b) /
        255;
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
