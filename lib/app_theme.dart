import 'package:flutter/material.dart';

class AppTheme {
  static final lightTheme = ThemeData.light().copyWith(
    colorScheme: ThemeData.light().colorScheme.copyWith(
      primary: Color(0xFF864AF9), // Light purple
      secondary: Color(0xFF5E35B1), // Dark purple
    ),
    scaffoldBackgroundColor: Colors.white,
    sliderTheme: SliderThemeData(
      thumbColor: Color(0xFF864AF9), // Light purple
      activeTrackColor: Color(0xFF864AF9), // Light purple
      valueIndicatorTextStyle: TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.bold,
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: MaterialStateProperty.all<Color>(Color(0xFF864AF9)), // Light purple
      trackColor: MaterialStateProperty.all<Color>(Color(0xFF5E35B1).withOpacity(0.5)), // Dark purple with opacity
      overlayColor: MaterialStateProperty.all<Color>(Colors.purple.withOpacity(0.12)), // Purple overlay with opacity
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: MaterialStateProperty.resolveWith<Color>((states) {
          if (states.contains(MaterialState.disabled)) {
            return Colors.grey; // Change button color when disabled
          }
          return Color(0xFF864AF9); // Light purple
        }),
      ),
    ),
  );

  static final darkTheme = ThemeData.dark().copyWith(
    colorScheme: ThemeData.dark().colorScheme.copyWith(
      primary: Color(0xFF5E35B1), // Dark purple
      secondary: Color(0xFF864AF9), // Light purple
    ),
    scaffoldBackgroundColor: Color(0xFF1E1E1E), // Dark grey
    sliderTheme: SliderThemeData(
      thumbColor: Color(0xFF5E35B1), // Dark purple
      activeTrackColor: Color(0xFF5E35B1), // Dark purple
      valueIndicatorTextStyle: TextStyle(
        color: Colors.black,
        fontWeight: FontWeight.bold,
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: MaterialStateProperty.all<Color>(Color(0xFF5E35B1)), // Dark purple
      trackColor: MaterialStateProperty.all<Color>(Color(0xFF864AF9).withOpacity(0.5)), // Light purple with opacity
      overlayColor: MaterialStateProperty.all<Color>(Colors.purple.withOpacity(0.12)), // Purple overlay with opacity
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: MaterialStateProperty.resolveWith<Color>((states) {
          if (states.contains(MaterialState.disabled)) {
            return Colors.grey; // Change button color when disabled
          }
          return Color(0xFF5E35B1); // Dark purple
        }),
      ),
    ),
  );
}