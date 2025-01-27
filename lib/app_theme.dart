import 'package:flutter/material.dart';

class AppTheme {
  static final lightTheme = ThemeData.light().copyWith(
    colorScheme: const ColorScheme.light().copyWith(
      primary: const Color(0xFF864AF9), // Light purple
      secondary: const Color(0xFF5E35B1), // Dark purple
    ),
    scaffoldBackgroundColor: Colors.white,
    sliderTheme: const SliderThemeData(
      thumbColor: Color(0xFF864AF9), // Light purple
      activeTrackColor: Color(0xFF864AF9), // Light purple
      valueIndicatorTextStyle: TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.bold,
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.all<Color>(const Color(0xFF864AF9)), // Light purple
      trackColor: WidgetStateProperty.all<Color>(const Color(0xFF5E35B1).withOpacity(0.5)), // Dark purple with opacity
      overlayColor: WidgetStateProperty.all<Color>(Colors.purple.withOpacity(0.12)), // Purple overlay with opacity
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith<Color>((states) {
          if (states.contains(WidgetState.disabled)) {
            return Colors.grey; // Change button color when disabled
          }
          return const Color(0xFF864AF9); // Light purple
        }),
      ),
    ),
  );

  static final darkTheme = ThemeData.dark().copyWith(
    colorScheme: const ColorScheme.dark().copyWith(
      primary: const Color(0xFF5E35B1), // Dark purple
      secondary: const Color(0xFF864AF9), // Light purple
    ),
    scaffoldBackgroundColor: const Color(0xFF1E1E1E), // Dark grey
    sliderTheme: const SliderThemeData(
      thumbColor: Color(0xFF5E35B1), // Dark purple
      activeTrackColor: Color(0xFF5E35B1), // Dark purple
      valueIndicatorTextStyle: TextStyle(
        color: Colors.black,
        fontWeight: FontWeight.bold,
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.all<Color>(const Color(0xFF5E35B1)), // Dark purple
      trackColor: WidgetStateProperty.all<Color>(const Color(0xFF864AF9).withOpacity(0.5)), // Light purple with opacity
      overlayColor: WidgetStateProperty.all<Color>(Colors.purple.withOpacity(0.12)), // Purple overlay with opacity
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith<Color>((states) {
          if (states.contains(WidgetState.disabled)) {
            return Colors.grey; // Change button color when disabled
          }
          return const Color(0xFF5E35B1); // Dark purple
        }),
      ),
    ),
  );
}
