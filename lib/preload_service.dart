import 'package:flutter/material.dart';
import 'database/database_helper.dart';
import 'logging.dart';

/// A service specifically for preloading critical app settings before UI rendering
class PreloadService {
  // Prevent multiple preload operations
  static bool _preloadComplete = false;

  // Cached values
  static Color? _cachedPrimaryColor;
  static bool? _cachedUseDarkButtonText;
  static ThemeMode? _cachedThemeMode;

  // Access the preloaded values
  static Color get primaryColor =>
      _cachedPrimaryColor ?? const Color(0xFF864AF9);

  static bool get useDarkButtonText => _cachedUseDarkButtonText ?? false;

  static ThemeMode get themeMode => _cachedThemeMode ?? ThemeMode.system;

  /// Preload critical settings to avoid UI flashes
  static Future<void> preloadEssentialSettings() async {
    if (_preloadComplete) return;

    Logging.severe('PreloadService: Starting preload of essential settings');

    try {
      // 1. Load primary color
      await _preloadPrimaryColor();

      // 2. Load button text preference
      await _preloadButtonTextPreference();

      // 3. Load theme mode
      await _preloadThemeMode();

      _preloadComplete = true;
      Logging.severe('PreloadService: Preload complete');
    } catch (e) {
      Logging.severe('PreloadService: Error during preload: $e');
      // Set defaults if preload fails
      _cachedPrimaryColor = const Color(0xFF864AF9);
      _cachedUseDarkButtonText = false;
      _cachedThemeMode = ThemeMode.system;
    }
  }

  static Future<void> _preloadPrimaryColor() async {
    try {
      final colorString =
          await DatabaseHelper.instance.getSetting('primaryColor');

      if (colorString != null && colorString.isNotEmpty) {
        if (colorString.startsWith('#')) {
          String hexColor = colorString.substring(1);

          // Ensure we have an 8-digit ARGB hex
          if (hexColor.length == 6) {
            hexColor = 'FF$hexColor';
          } else if (hexColor.length == 8) {
            // Force full opacity
            hexColor = 'FF${hexColor.substring(2)}';
          }

          final colorValue = int.parse(hexColor, radix: 16);
          _cachedPrimaryColor = Color(colorValue);
          Logging.severe('PreloadService: Loaded primary color: $colorString');
        }
      } else {
        _cachedPrimaryColor = const Color(0xFF864AF9); // Default purple
      }
    } catch (e) {
      Logging.severe('PreloadService: Error preloading color: $e');
      _cachedPrimaryColor = const Color(0xFF864AF9); // Default purple
    }
  }

  static Future<void> _preloadButtonTextPreference() async {
    try {
      final darkButtonText =
          await DatabaseHelper.instance.getSetting('useDarkButtonText');
      _cachedUseDarkButtonText = darkButtonText == 'true';
    } catch (e) {
      Logging.severe(
          'PreloadService: Error preloading button text preference: $e');
      _cachedUseDarkButtonText = false;
    }
  }

  static Future<void> _preloadThemeMode() async {
    try {
      final themeStr = await DatabaseHelper.instance.getSetting('themeMode');
      ThemeMode mode = ThemeMode.system;

      if (themeStr != null && themeStr.isNotEmpty) {
        if (themeStr == 'ThemeMode.dark' ||
            themeStr == '2' ||
            themeStr == 'dark') {
          mode = ThemeMode.dark;
        } else if (themeStr == 'ThemeMode.light' ||
            themeStr == '1' ||
            themeStr == 'light') {
          mode = ThemeMode.light;
        }
      }

      _cachedThemeMode = mode;
    } catch (e) {
      Logging.severe('PreloadService: Error preloading theme mode: $e');
      _cachedThemeMode = ThemeMode.system;
    }
  }

  /// Check if preload is complete
  static bool isPreloadComplete() {
    return _preloadComplete;
  }
}
