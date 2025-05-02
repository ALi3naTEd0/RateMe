import 'package:flutter/material.dart';
import 'logging.dart';
import 'theme_service.dart';
import 'color_utility.dart';
import 'database/database_helper.dart';
import 'dart:io' show Platform;

/// Service to preload essential settings before UI rendering
class PreloadService {
  static bool _isPreloadComplete = false;
  static Color? _cachedPrimaryColor;

  /// Get the cached primary color after preload
  static Color get primaryColor {
    // CRITICAL FIX: Use safe default if no color loaded yet
    return _cachedPrimaryColor ?? ColorUtility.defaultColor;
  }

  /// Check if preload is complete
  static bool get isPreloadComplete => _isPreloadComplete;

  /// Preload essential settings (theme color, etc.) before UI rendering
  static Future<void> preloadEssentialSettings() async {
    if (_isPreloadComplete) return;

    Logging.severe('PRELOAD: Starting essential settings preload');

    try {
      // First, initialize database
      await DatabaseHelper.initialize();

      // Check if there's a saved primary color
      final String? colorStr =
          await DatabaseHelper.instance.getSetting('primaryColor');

      if (colorStr != null && colorStr.isNotEmpty) {
        Logging.severe('PRELOAD: Found color setting: $colorStr');

        // CRITICAL FIX: Check for black and convert if on Android
        if (colorStr == '#FF000000' && Platform.isAndroid) {
          Logging.severe('PRELOAD: Converting black to safe black on Android');
          _cachedPrimaryColor = ColorUtility.safeBlack;
        } else {
          // Parse color from hex string using our utility
          _cachedPrimaryColor = ColorUtility.hexToColor(colorStr);
        }

        Logging.severe(
            'PRELOAD: Cached primary color: ${ColorUtility.colorToRgbString(_cachedPrimaryColor!)}');
      } else {
        Logging.severe('PRELOAD: No color setting found, using default purple');
        _cachedPrimaryColor = ColorUtility.defaultColor;
      }

      // Also initialize ThemeService with our cached color
      await ThemeService.preloadEssentialSettings();
      ThemeService.setPrimaryColorDirectly(_cachedPrimaryColor!);

      _isPreloadComplete = true;
      Logging.severe('PRELOAD: Essential settings preloaded successfully');
    } catch (e, stack) {
      Logging.severe('PRELOAD: Error preloading essential settings', e, stack);
      // If there's an error, use default color
      _cachedPrimaryColor = ColorUtility.defaultColor;
    }
  }

  /// Reset to factory defaults
  static Future<void> resetToDefaults() async {
    Logging.severe('PRELOAD: Resetting to default settings');
    _cachedPrimaryColor = ColorUtility.defaultColor;
    await ThemeService.setPrimaryColor(ColorUtility.defaultColor);
    _isPreloadComplete = false;
  }
}
