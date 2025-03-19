import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Central theme configuration for the RateMe app
class RateMeTheme {
  /// Get the main theme data for the app based on brightness and primary color
  static ThemeData getTheme(Brightness brightness, Color primaryColor) {
    final isDark = brightness == Brightness.dark;
    
    // Get button text color preference
    final prefs = SharedPreferences.getInstance();
    final useDarkText = false; // Default value
    final buttonTextColor = useDarkText ? Colors.black : Colors.white;
    
    return ThemeData(
      brightness: brightness,
      colorScheme: (isDark ? const ColorScheme.dark() : const ColorScheme.light()).copyWith(
        primary: primaryColor,
        secondary: primaryColor,
        onPrimary: buttonTextColor, // Button text color based on preference
        primaryContainer: primaryColor,
        secondaryContainer: primaryColor,
      ),
      // Updated slider theme
      sliderTheme: SliderThemeData(
        activeTrackColor: primaryColor,
        inactiveTrackColor: primaryColor.withOpacity(0.3),
        thumbColor: primaryColor,
        overlayColor: primaryColor.withOpacity(0.3),
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
  static ThemeData get light => getTheme(Brightness.light, const Color(0xFF864AF9));
  
  /// Default dark theme
  static ThemeData get dark => getTheme(Brightness.dark, const Color(0xFF864AF9));
}
