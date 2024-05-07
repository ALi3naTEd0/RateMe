import 'package:flutter/material.dart';

class AppTheme {
  static final lightTheme = ThemeData.light().copyWith(
    colorScheme: ThemeData.light().colorScheme.copyWith(
      primary: Color(0xFF864AF9), // Morado claro
      secondary: Color(0xFF5E35B1), // Morado oscuro
    ),
    scaffoldBackgroundColor: Colors.white,
    sliderTheme: SliderThemeData(
      thumbColor: Color(0xFF864AF9), // Morado claro
      activeTrackColor: Color(0xFF864AF9), // Morado claro
      valueIndicatorTextStyle: TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.bold,
      ),
    ),
    toggleableActiveColor: Color(0xFF5E35B1), // Morado oscuro
    switchTheme: SwitchThemeData(
      thumbColor: MaterialStateProperty.all<Color>(Color(0xFF864AF9)), // Morado claro
      trackColor: MaterialStateProperty.all<Color>(Color(0xFF5E35B1).withOpacity(0.5)), // Morado oscuro con opacidad
      overlayColor: MaterialStateProperty.all<Color>(Colors.purple.withOpacity(0.12)), // Overlay morado con opacidad
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: MaterialStateProperty.resolveWith<Color>((states) {
          if (states.contains(MaterialState.disabled)) {
            return Colors.grey; // Cambia el color del botón cuando está deshabilitado
          }
          return Color(0xFF864AF9); // Morado claro
        }),
      ),
    ),
  );

  static final darkTheme = ThemeData.dark().copyWith(
    colorScheme: ThemeData.dark().colorScheme.copyWith(
      primary: Color(0xFF5E35B1), // Morado oscuro
      secondary: Color(0xFF864AF9), // Morado claro
    ),
    scaffoldBackgroundColor: Color(0xFF1E1E1E), // Gris oscuro
    sliderTheme: SliderThemeData(
      thumbColor: Color(0xFF5E35B1), // Morado oscuro
      activeTrackColor: Color(0xFF5E35B1), // Morado oscuro
      valueIndicatorTextStyle: TextStyle(
        color: Colors.black,
        fontWeight: FontWeight.bold,
      ),
    ),
    toggleableActiveColor: Color(0xFF864AF9), // Morado claro
    switchTheme: SwitchThemeData(
      thumbColor: MaterialStateProperty.all<Color>(Color(0xFF5E35B1)), // Morado oscuro
      trackColor: MaterialStateProperty.all<Color>(Color(0xFF864AF9).withOpacity(0.5)), // Morado claro con opacidad
      overlayColor: MaterialStateProperty.all<Color>(Colors.purple.withOpacity(0.12)), // Overlay morado con opacidad
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: MaterialStateProperty.resolveWith<Color>((states) {
          if (states.contains(MaterialState.disabled)) {
            return Colors.grey; // Cambia el color del botón cuando está deshabilitado
          }
          return Color(0xFF5E35B1); // Morado oscuro
        }),
      ),
    ),
  );
}
