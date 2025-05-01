import 'package:flutter/material.dart';
import 'settings_service.dart';
import 'database/database_helper.dart';
import 'logging.dart';
import 'theme_service.dart' as ts;

/// Service responsible for preloading essential application data
class PreloadService {
  static bool _isPreloaded = false;

  // Add a getter to check if preloading is complete
  static bool get isPreloaded => _isPreloaded;

  static Future<void> preloadSettings() async {
    try {
      if (_isPreloaded) {
        return; // Don't reload if already loaded
      }

      Logging.severe('PreloadService: Starting preload of critical settings');

      // Load primary color from database first to avoid UI flash
      final colorString =
          await DatabaseHelper.instance.getSetting('primaryColor');
      if (colorString != null && colorString.isNotEmpty) {
        try {
          if (colorString.startsWith('#')) {
            String hexColor = colorString.substring(1);

            // Ensure we have an 8-digit ARGB hex
            if (hexColor.length == 6) {
              hexColor = 'FF$hexColor';
            } else if (hexColor.length == 8) {
              // Force full opacity
              hexColor = 'FF${hexColor.substring(2)}';
            }

            // Parse the hex string to int and create color
            final colorValue = int.parse(hexColor, radix: 16);
            final Color parsedColor = Color(colorValue);

            // Initialize BOTH services with the same color instance
            SettingsService.initializePrimaryColor(parsedColor);
            ts.ThemeService.setPrimaryColorDirectly(parsedColor);

            Logging.severe(
                'PreloadService: Successfully preloaded primary color: $colorString (RGB: ${parsedColor.r}, ${parsedColor.g}, ${parsedColor.b})');
          }
        } catch (e) {
          Logging.severe('PreloadService: Error parsing color: $e');
        }
      }

      // Preload dark button text setting
      final darkButtonText =
          await DatabaseHelper.instance.getSetting('useDarkButtonText');
      final bool useDarkText = darkButtonText == 'true';
      SettingsService.initializeButtonTextColor(useDarkText);

      // Fix: Use the correct method name in ThemeService
      ts.ThemeService.setUseDarkButtonText(useDarkText);

      _isPreloaded = true;
      Logging.severe('PreloadService: Preload completed');
    } catch (e) {
      Logging.severe('PreloadService: Error during preload', e);
    }
  }
}
