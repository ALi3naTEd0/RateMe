import 'package:flutter/material.dart';
import '../services/logging.dart';
import 'dart:io' show Platform;

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
    // Guard against empty string
    if (hexString.isEmpty) {
      Logging.severe('COLOR UTILITY: Empty hex string received');
      return defaultColor;
    }

    // Basic validation - should be in format #FFRRGGBB or FFRRGGBB
    String normalizedHex = hexString;

    // Remove # if present
    if (normalizedHex.startsWith('#')) {
      normalizedHex = normalizedHex.substring(1);
    }

    // Add alpha if needed
    if (normalizedHex.length == 6) {
      normalizedHex = 'FF$normalizedHex';
    }

    Color resultColor;

    // CRITICAL FIX: Manual parsing of the hex components
    try {
      if (normalizedHex.length == 8) {
        // Parse each component separately
        final int a = int.parse(normalizedHex.substring(0, 2), radix: 16);
        final int r = int.parse(normalizedHex.substring(2, 4), radix: 16);
        final int g = int.parse(normalizedHex.substring(4, 6), radix: 16);
        final int b = int.parse(normalizedHex.substring(6, 8), radix: 16);

        // PLATFORM-SPECIFIC FIX: If on Android and this is pure black (#FF000000),
        // use "safe black" (#FF010101) instead which appears virtually identical
        if (Platform.isAndroid && r == 0 && g == 0 && b == 0) {
          Logging.severe(
              'COLOR UTILITY: Converting pure black to safe black on Android');
          resultColor = safeBlack;
        } else {
          resultColor = Color.fromARGB(a, r, g, b);
        }
      } else {
        // Fallback for invalid formats
        throw FormatException('Invalid hex color format');
      }
    } catch (e) {
      Logging.severe('COLOR UTILITY: Error with component parsing: $e');

      // Fallback to original method only if component parsing fails
      try {
        final int value = int.parse(normalizedHex, radix: 16);
        resultColor = Color(value);

        // PLATFORM-SPECIFIC FIX: If on Android and this is pure black (#FF000000),
        // use "safe black" (#FF010101) instead which appears virtually identical
        // Fix: Replace deprecated .value with individual component checks
        if (Platform.isAndroid &&
            resultColor.r == 0 &&
            resultColor.g == 0 &&
            resultColor.b == 0 &&
            resultColor.a == 255) {
          Logging.severe(
              'COLOR UTILITY: Converting pure black to safe black on Android (fallback)');
          resultColor = safeBlack;
        }
      } catch (e) {
        Logging.severe(
            'COLOR UTILITY: Critical parsing error for $hexString: $e');
        return defaultColor;
      }
    }

    return resultColor;
  }

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

    // Format with proper padding and uppercase for consistency
    return '#FF${r.toRadixString(16).padLeft(2, '0')}${g.toRadixString(16).padLeft(2, '0')}${b.toRadixString(16).padLeft(2, '0')}'
        .toUpperCase();
  }

  /// Convert Color to hex string (with alpha)
  static String colorToHexString(Color color) {
    // Replace deprecated color.value with component-based approach
    final int a = color.a.round();
    final int r = color.r.round();
    final int g = color.g.round();
    final int b = color.b.round();
    final int argb = (a << 24) | (r << 16) | (g << 8) | b;
    return '#${argb.toRadixString(16).padLeft(8, '0').toUpperCase()}';
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
