import 'package:flutter/material.dart';

/// Central theme configuration for the RateMe app
class RateMeTheme {
  /// Get the main theme data for the app based on brightness and primary color
  static ThemeData getTheme(Brightness brightness, Color primaryColor) {
    final isDark = brightness == Brightness.dark;

    // Remove the useless constant and default value comment since it's hardcoded
    const buttonTextColor = Colors.white;

    return ThemeData(
      brightness: brightness,
      colorScheme:
          (isDark ? const ColorScheme.dark() : const ColorScheme.light())
              .copyWith(
        primary: primaryColor,
        secondary: primaryColor,
        onPrimary: buttonTextColor, // Button text color based on preference
        primaryContainer: primaryColor,
        secondaryContainer: primaryColor,
      ),
      // Updated slider theme
      sliderTheme: SliderThemeData(
        activeTrackColor: primaryColor,
        inactiveTrackColor:
            HSLColor.fromColor(primaryColor).withAlpha(0.3).toColor(),
        thumbColor: primaryColor,
        overlayColor: HSLColor.fromColor(primaryColor).withAlpha(0.3).toColor(),
        valueIndicatorColor: primaryColor,
        valueIndicatorTextStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
      // Updated button theme to use configured text color
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: buttonTextColor,
          textStyle: const TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primaryColor,
        foregroundColor: buttonTextColor,
      ),
    );
  }

  /// Default light theme
  static ThemeData get light =>
      getTheme(Brightness.light, const Color(0xFF864AF9));

  /// Default dark theme
  static ThemeData get dark =>
      getTheme(Brightness.dark, const Color(0xFF864AF9));
}
