import 'package:flutter/material.dart';

/// Central theme configuration for the RateMe app
class RateMeTheme {
  /// Get the main theme data for the app based on brightness
  static ThemeData getTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    
    return ThemeData(
      brightness: brightness,
      colorScheme: (isDark ? const ColorScheme.dark() : const ColorScheme.light()).copyWith(
        primary: isDark ? const Color(0xFF5E35B1) : const Color(0xFF864AF9),
        secondary: isDark ? const Color(0xFF864AF9) : const Color(0xFF5E35B1),
      ),
      // Component-specific themes
      sliderTheme: _getSliderTheme(isDark),
      // Other component themes can be added here
    );
  }
  
  /// Default light theme
  static ThemeData get light => getTheme(Brightness.light);
  
  /// Default dark theme
  static ThemeData get dark => getTheme(Brightness.dark);
  
  /// Get slider theme based on dark mode setting
  static SliderThemeData _getSliderTheme(bool isDark) {
    return SliderThemeData(
      thumbColor: isDark ? const Color(0xFF5E35B1) : const Color(0xFF864AF9),
      activeTrackColor: isDark ? const Color(0xFF5E35B1) : const Color(0xFF864AF9),
      // En modo oscuro, mantenemos el indicador de color en un tono púrpura que contraste bien
      valueIndicatorColor: isDark ? const Color(0xFF5E35B1) : Colors.white,
      valueIndicatorTextStyle: const TextStyle(
        color: Colors.white, // Siempre texto blanco para máximo contraste
        fontWeight: FontWeight.bold,
      ),
    );
  }
  
  /// Extension method to get slider theme when full ThemeData isn't needed
  static SliderThemeData getSliderTheme(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return _getSliderTheme(isDark);
  }
}
