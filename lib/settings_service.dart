import 'package:flutter/material.dart';
import 'database/database_helper.dart';
import 'logging.dart';
import 'theme_service.dart' as ts;

/// Service for managing application settings using SQLite database
class SettingsService {
  static final SettingsService _instance = SettingsService._internal();
  factory SettingsService() => _instance;
  SettingsService._internal();

  // Cache for settings to avoid repeated database calls
  final Map<String, dynamic> _settingsCache = {};

  // Database helper
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  // Has the service been initialized?
  bool _initialized = false;

  // Add a static list of callbacks for theme changes
  static final List<Function(ThemeMode, Color)> _themeListeners = [];

  // Add _lastThemeMode static field
  static ThemeMode _lastThemeMode = ThemeMode.system;

  // Add this method to register a theme change listener
  static void addThemeListener(Function(ThemeMode, Color) listener) {
    _themeListeners.add(listener);
  }

  // Add logging to trace color changes through the SettingsService
  static void notifyThemeChanged(ThemeMode mode, Color color) {
    Logging.severe(
        'SettingsService: notifyThemeChanged called with mode=$mode, color=$color');

    // Update the _lastThemeMode when theme changes
    _lastThemeMode = mode;

    for (final listener in _themeListeners) {
      listener(mode, color);
    }
  }

  // Add a separate notification function JUST for color changes
  static final List<Function(Color)> _colorListeners = [];

  static void addPrimaryColorListener(Function(Color) listener) {
    _colorListeners.add(listener);
  }

  static void notifyPrimaryColorChanged(Color color) {
    Logging.severe(
        'SettingsService: notifyPrimaryColorChanged called with color=$color (HEX: ${color.toHexString().toUpperCase()})');

    for (final listener in _colorListeners) {
      listener(color);
    }

    // Don't notify theme listeners to avoid theme mode changes
    // Only pass the color to theme listeners but keep the existing theme mode
    if (_themeListeners.isNotEmpty) {
      // Get the current theme mode (don't change it)
      final currentThemeMode = _lastThemeMode;
      Logging.severe(
          'SettingsService: Maintaining current theme mode: $currentThemeMode when updating color');

      for (final listener in _themeListeners) {
        listener(currentThemeMode, color);
      }
    }
  }

  // Add a new method to notify only color changes without affecting theme mode
  static void notifyColorChangeOnly(Color color) {
    // Ensure we're working with clean integer RGB values
    final int r = color.r.round();
    final int g = color.g.round();
    final int b = color.b.round();

    // FIX: Check for very small values that should be zero
    // This prevents the FF000101 issue
    final int safeR = r < 3 ? 0 : r;
    final int safeG = g < 3 ? 0 : g;
    final int safeB = b < 3 ? 0 : b;

    // Create a clean color with exact integer RGB values
    final Color safeColor = Color.fromARGB(255, safeR, safeG, safeB);

    // CRITICAL FIX: Ensure we generate the hex string correctly
    final String colorHex =
        '#FF${safeR.toRadixString(16).padLeft(2, '0')}${safeG.toRadixString(16).padLeft(2, '0')}${safeB.toRadixString(16).padLeft(2, '0')}'
            .toUpperCase();

    // EMERGENCY DEBUG: Log the color values clearly to identify what's happening
    Logging.severe(
        'SettingsService: Color change - Raw RGB($r,$g,$b) → Safe RGB($safeR,$safeG,$safeB) → Hex: $colorHex');

    // CRITICAL BUGFIX: Look at the current stack trace to determine if this is a reset operation
    // from _resetColorsToDefault() in settings_page.dart
    bool isColorReset = false;
    try {
      StackTrace currentStack = StackTrace.current;
      String stackString = currentStack.toString();

      // Check if this is coming from _resetColorsToDefault or similar methods
      if (stackString.contains('_resetColorsToDefault') ||
          stackString.contains('resetColors') ||
          stackString.contains('restore')) {
        isColorReset = true;
        Logging.severe('SettingsService: Detected color reset operation');
      }
    } catch (e) {
      Logging.severe('SettingsService: Error checking stack trace: $e');
    }

    // FIXED: If this is a purple reset or the color is purple, always allow it
    final isPurple =
        (r == 134 && g == 74 && b == 249) || colorHex == '#FF864AF9';

    if (isPurple) {
      Logging.severe(
          'SettingsService: Detected purple color - accepting reset');
      _continueWithColorChange(safeColor, colorHex);
      return;
    }

    // CRITICAL BUGFIX: Check for black color and handle specially
    if (colorHex == '#FF000000') {
      // If this is a button text change operation, verify with DB
      bool isFromButtonTextChange = false;

      try {
        StackTrace currentStack = StackTrace.current;
        String stackString = currentStack.toString();

        // Check if this color change is happening during a button text change operation
        if (stackString.contains('notifyButtonTextColorChanged') ||
            stackString.contains('setUseDarkButtonText')) {
          isFromButtonTextChange = true;
          Logging.severe(
              'SettingsService: Detected black color during button text update - will verify');
        }
      } catch (e) {
        Logging.severe('SettingsService: Error checking stack trace: $e');
      }

      // If this is a reset operation or button text change, verify with DB
      if (isColorReset || isFromButtonTextChange) {
        // Get the stored color from DB to make sure we don't override with black
        DatabaseHelper.instance
            .getSetting('primaryColor')
            .then((storedColorHex) {
          if (storedColorHex != null &&
              storedColorHex != '#FF000000' &&
              storedColorHex.isNotEmpty) {
            Logging.severe(
                'SettingsService: Prevented unintended black override! Keeping stored color: $storedColorHex');

            // Parse the color from DB and use that instead of black
            try {
              String hexColor =
                  storedColorHex.substring(1); // Remove the # prefix
              if (hexColor.length == 8) {
                // Force alpha to FF for full opacity
                hexColor = 'FF${hexColor.substring(2)}';
              } else if (hexColor.length == 6) {
                hexColor = 'FF$hexColor';
              }

              final colorValue = int.parse(hexColor, radix: 16);
              final actualColor = Color(colorValue);

              // Update the UI with the correct color from DB
              for (final listener in _colorListeners) {
                listener(actualColor);
              }

              Logging.severe(
                  'SettingsService: Restored DB color instead of using black');
            } catch (e) {
              Logging.severe('SettingsService: Error parsing stored color: $e');
            }
          } else {
            // Black is actually stored in DB or no color found, proceed with black
            _continueWithColorChange(safeColor, colorHex);
          }
        });
        return; // Exit early, we'll handle this asynchronously
      } else {
        // This is a legitimate user request for black color
        Logging.severe(
            'SettingsService: Black color chosen by user - allowing');
        _continueWithColorChange(safeColor, colorHex);
      }
    } else {
      // Non-black color - proceed normally
      _continueWithColorChange(safeColor, colorHex);
    }
  }

  // Helper method to continue with color change notification and persistence
  static void _continueWithColorChange(Color safeColor, String colorHex) {
    // EMERGENCY DEBUG: Add explicit log of the exact color hex being saved to database
    Logging.severe(
        'SettingsService: SAVING COLOR TO DATABASE: $colorHex, RGB: ${safeColor.r.round()}, ${safeColor.g.round()}, ${safeColor.b.round()}');

    // Notify color listeners with the safe color
    for (final listener in _colorListeners) {
      listener(safeColor);
    }

    // Save to database to ensure persistence - use the safe hex value
    // This should match exactly what's being written to the database
    DatabaseHelper.instance.saveSetting('primaryColor', colorHex).then((_) {
      // Verify what was written by reading it back from the database
      DatabaseHelper.instance.getSetting('primaryColor').then((savedColor) {
        Logging.severe('SettingsService: Verified saved color: $savedColor');
      });
    });
  }

  // Add method to remove listeners when widgets are disposed
  static void removePrimaryColorListener(Function(Color) listener) {
    _colorListeners.remove(listener);
  }

  // Add a method to notify about button text color changes
  static void notifyButtonTextColorChanged(bool useDarkText) {
    Logging.severe(
        'SettingsService: notifyButtonTextColorChanged called with useDarkText=$useDarkText');

    // Save to database to ensure persistence
    DatabaseHelper.instance
        .saveSetting('useDarkButtonText', useDarkText.toString());

    // CRITICAL FIX: Load the current primary color from the database before updating ThemeService
    // This prevents the color from being reset to black
    DatabaseHelper.instance.getSetting('primaryColor').then((colorStr) {
      // Only call ThemeService after we have the current color to ensure it's preserved
      Logging.severe(
          'SettingsService: Preserving current color: $colorStr when updating button text');

      // Update ThemeService without triggering color change
      ts.ThemeService.setUseDarkButtonText(useDarkText, notifyListeners: false);
    });
  }

  /// Initialize the settings service
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      // Ensure database is ready
      await DatabaseHelper.initialize();

      // Add clear logging about using database for settings
      Logging.severe('==== SETTINGS SERVICE: USING SQLITE DATABASE ====');

      // Load initial settings
      await _loadInitialSettings();

      _initialized = true;
      Logging.severe(
          'Settings service initialized with ${_settingsCache.length} settings from database');
    } catch (e, stack) {
      Logging.severe('Failed to initialize settings service', e, stack);
    }
  }

  /// Load initial settings from database
  Future<void> _loadInitialSettings() async {
    try {
      // Define settings to preload
      final settingsToLoad = [
        'themeMode',
        'primaryColor',
        'useDarkButtonText',
        'showWelcomeScreen',
        'defaultPlatform',
        'enableAnalytics',
        'enableCrashReporting',
        'lastSyncDate',
        'useCompactUI',
      ];

      Logging.severe('Loading ${settingsToLoad.length} settings from database');

      int settingsFoundCount = 0;

      for (final key in settingsToLoad) {
        // Load setting from database
        final value = await _dbHelper.getSetting(key);

        if (value != null) {
          _settingsCache[key] = value;
          settingsFoundCount++;
          Logging.severe('Loaded setting from database: $key = $value');
        } else {
          Logging.severe(
              'Setting not found in database: $key - using default value');
        }
      }

      Logging.severe(
          'Database settings loaded: Found $settingsFoundCount out of ${settingsToLoad.length} settings');
    } catch (e, stack) {
      Logging.severe('Error loading initial settings', e, stack);
    }
  }

  /// Get a setting value with type conversion
  Future<T?> getSetting<T>(String key, {T? defaultValue}) async {
    try {
      // Check cache first
      if (_settingsCache.containsKey(key)) {
        return _convertValue<T>(_settingsCache[key]);
      }

      // Get from database
      final value = await _dbHelper.getSetting(key);

      if (value != null) {
        _settingsCache[key] = value;
        return _convertValue<T>(value);
      }

      return defaultValue;
    } catch (e, stack) {
      Logging.severe('Error getting setting $key', e, stack);
      return defaultValue;
    }
  }

  /// Save a setting value
  Future<bool> saveSetting<T>(String key, T value) async {
    try {
      // Convert value to string
      final stringValue = value.toString();

      // Save to database
      await _dbHelper.saveSetting(key, stringValue);

      // Update cache
      _settingsCache[key] = stringValue;

      Logging.severe('Setting saved: $key = $value');
      return true;
    } catch (e, stack) {
      Logging.severe('Error saving setting $key', e, stack);
      return false;
    }
  }

  /// Remove a setting
  Future<bool> removeSetting(String key) async {
    try {
      // Remove from database
      final db = await _dbHelper.database;
      await db.delete(
        'settings',
        where: 'key = ?',
        whereArgs: [key],
      );

      // Remove from cache
      _settingsCache.remove(key);

      Logging.severe('Setting removed: $key');
      return true;
    } catch (e, stack) {
      Logging.severe('Error removing setting $key', e, stack);
      return false;
    }
  }

  // Keep the convenience methods for specific settings

  /// Get theme mode setting
  Future<ThemeMode> getThemeMode() async {
    final value = await getSetting<String>('themeMode', defaultValue: 'system');
    switch (value) {
      case 'dark':
        return ThemeMode.dark;
      case 'light':
        return ThemeMode.light;
      default:
        return ThemeMode.system;
    }
  }

  /// Save theme mode setting
  Future<void> saveThemeMode(ThemeMode mode) async {
    String value;
    switch (mode) {
      case ThemeMode.dark:
        value = 'dark';
        break;
      case ThemeMode.light:
        value = 'light';
        break;
      case ThemeMode.system:
        value = 'system';
        break;
    }
    await saveSetting('themeMode', value);
  }

  /// Get primary color setting
  Future<Color> getPrimaryColor() async {
    // Fix the non-nullable int error by adding null coalescing operator
    final value =
        await getSetting<int>('primaryColor', defaultValue: 0xFF6200EE);
    return Color(
        value ?? 0xFF6200EE); // Fix: Add null check to handle nullable int
  }

  /// Save primary color setting
  Future<void> savePrimaryColor(Color color) async {
    // Fix: Use toARGB32() instead of deprecated value property
    await saveSetting('primaryColor', color.toARGB32());
  }

  /// Get dark button text setting
  Future<bool> getUseDarkButtonText() async {
    // Fix: Add null check for non-nullable return type
    return await getSetting<bool>('useDarkButtonText', defaultValue: false) ??
        false;
  }

  /// Save dark button text setting
  Future<void> saveUseDarkButtonText(bool value) async {
    await saveSetting('useDarkButtonText', value);
    notifyButtonTextColorChanged(value); // Add this line to notify ThemeService
  }

  /// Helper method to convert string values to their appropriate types
  T? _convertValue<T>(dynamic value) {
    if (value == null) return null;

    try {
      if (T == String) {
        return value.toString() as T;
      } else if (T == int) {
        return int.parse(value.toString()) as T;
      } else if (T == double) {
        return double.parse(value.toString()) as T;
      } else if (T == bool) {
        final boolValue = value.toString().toLowerCase();
        return (boolValue == 'true' || boolValue == '1') as T;
      } else {
        return value as T;
      }
    } catch (e) {
      Logging.severe('Error converting value $value to type $T: $e');
      return null;
    }
  }
}

// Fix the toHexString extension method to correctly format hex values
extension ColorToHex on Color {
  String toHexString() {
    // Only use integer rounding at core color serialization points
    final int r = this.r.round();
    final int g = this.g.round();
    final int b = this.b.round();

    // FIX: Check for very small values that should be zero
    final int safeR = r < 3 ? 0 : r;
    final int safeG = g < 3 ? 0 : g;
    final int safeB = b < 3 ? 0 : b;

    return '#${safeR.toRadixString(16).padLeft(2, '0')}${safeG.toRadixString(16).padLeft(2, '0')}${safeB.toRadixString(16).padLeft(2, '0')}'
        .toUpperCase();
  }
}
