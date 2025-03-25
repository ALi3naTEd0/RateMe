import 'package:flutter/material.dart';

/// Central theme configuration for the RateMe app
class RateMeTheme {
  /// Get the main theme data for the app based on brightness and primary color
  static ThemeData getTheme(Brightness brightness, Color primaryColor) {
    final isDark = brightness == Brightness.dark;

    // Remove the useless constant and default value comment since it's hardcoded
    const buttonTextColor = Colors.white;

    // Define icon colors based on theme
    final iconColor = isDark ? Colors.white : Colors.grey.shade900;

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
      // Add icon theme configuration
      iconTheme: IconThemeData(
        color: iconColor,
        size: 24.0,
      ),
      // Define platform icon theme separately
      extensions: [
        PlatformIconTheme(
          color: iconColor,
          selectedColor: primaryColor,
          disabledColor: isDark ? Colors.white38 : Colors.black38,
        ),
      ],
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

// Add a custom theme extension for platform icons
class PlatformIconTheme extends ThemeExtension<PlatformIconTheme> {
  final Color color;
  final Color selectedColor;
  final Color disabledColor;

  const PlatformIconTheme({
    required this.color,
    required this.selectedColor,
    required this.disabledColor,
  });

  @override
  PlatformIconTheme copyWith({
    Color? color,
    Color? selectedColor,
    Color? disabledColor,
  }) {
    return PlatformIconTheme(
      color: color ?? this.color,
      selectedColor: selectedColor ?? this.selectedColor,
      disabledColor: disabledColor ?? this.disabledColor,
    );
  }

  @override
  ThemeExtension<PlatformIconTheme> lerp(
    ThemeExtension<PlatformIconTheme>? other,
    double t,
  ) {
    if (other is! PlatformIconTheme) return this;
    return PlatformIconTheme(
      color: Color.lerp(color, other.color, t)!,
      selectedColor: Color.lerp(selectedColor, other.selectedColor, t)!,
      disabledColor: Color.lerp(disabledColor, other.disabledColor, t)!,
    );
  }
}
