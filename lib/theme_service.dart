import 'package:flutter/material.dart';
import 'database/database_helper.dart';
import 'logging.dart';
import 'settings_service.dart'; // Add this import
import 'color_utility.dart';

/// A clean, straightforward service to manage application themes
class ThemeService {
  // Store the current theme mode and primary color
  static ThemeMode _themeMode = ThemeMode.system;
  static Color _primaryColor = const Color(0xFF864AF9); // Default purple
  static bool _useDarkButtonText =
      false; // Add this line to store the preference

  // Store listeners that will be notified when the theme changes
  static final List<Function(ThemeMode, Color)> _listeners = [];

  // Access the current theme mode
  static ThemeMode get themeMode => _themeMode;

  // Access the current primary color
  static Color get primaryColor => _primaryColor;

  // Access the dark button text preference
  static bool get useDarkButtonText => _useDarkButtonText; // Add this getter

  // Standard content max width factor - 85% of screen width (matching AppDimensions)
  static const double contentMaxWidthFactor = 0.85;

  // Override getter methods to track when theme is requested
  static ThemeData get lightTheme {
    // Simplify logging, remove the noisy getter logs
    return _buildThemeData(Brightness.light, _primaryColor);
  }

  static ThemeData get darkTheme {
    // Simplify logging, remove the noisy getter logs
    return _buildThemeData(Brightness.dark, _primaryColor);
  }

  /// Initialize the theme service by loading saved settings
  static Future<void> initialize() async {
    Logging.severe('ThemeService: Initializing...');

    // CRITICAL FIX: First make sure we have a valid default color
    _primaryColor = ColorUtility.exactPurple;

    // Set up listener to SettingsService color changes
    SettingsService.addPrimaryColorListener(_handleColorChange);

    await loadThemeSettings();

    // CRITICAL FIX: Sanity check to avoid black colors
    if (_primaryColor.r == 0 && _primaryColor.g == 0 && _primaryColor.b == 0) {
      Logging.severe(
          'ThemeService: EMERGENCY - Detected black color after initialization, forcing purple');
      _primaryColor = ColorUtility.exactPurple;
      // Save the correct color to database
      await _savePrimaryColorToDatabase(_primaryColor);
    }
  }

  /// Handle color changes from SettingsService
  static void _handleColorChange(Color color) {
    // Update our local copy of the color
    Logging.severe('ThemeService: Color updated from SettingsService');

    // CRITICAL BUGFIX: Double-check if this is a reset operation that should be using purple
    bool isResetOperation = false;

    try {
      StackTrace currentStack = StackTrace.current;
      String stackString = currentStack.toString();

      // Check if this call is part of a reset operation
      if (stackString.contains('_resetColorsToDefault') ||
          stackString.contains('resetColors') ||
          stackString.contains('restore')) {
        isResetOperation = true;
        Logging.severe('ThemeService: Detected color reset operation');
      }
    } catch (e) {
      Logging.severe('ThemeService: Error checking stack trace: $e');
    }

    // CRITICAL BUGFIX: If it's a reset operation and the color is black,
    // use purple instead as black is likely unintended
    if (isResetOperation && color.r == 0 && color.g == 0 && color.b == 0) {
      Logging.severe(
          'ThemeService: Avoiding black color during reset, using purple instead');
      _primaryColor = const Color(0xFF864AF9); // Use default purple
      _notifyListeners();
      return;
    }

    // CRITICAL BUGFIX: Check for unintended black color changes
    if (color.r == 0 && color.g == 0 && color.b == 0) {
      // Check call stack to determine if this is a legitimate color change or a side effect
      bool isFromButtonTextChange = false;

      try {
        StackTrace currentStack = StackTrace.current;
        String stackString = currentStack.toString();

        // Check if this color change is happening during a button text change operation
        if (stackString.contains('notifyButtonTextColorChanged') ||
            stackString.contains('setUseDarkButtonText')) {
          isFromButtonTextChange = true;
          Logging.severe(
              'ThemeService: Detected black color change during button text update - will verify');
        }
      } catch (e) {
        Logging.severe('ThemeService: Error checking stack trace: $e');
      }

      // Only verify with database if it's from an unintended source
      if (isFromButtonTextChange) {
        DatabaseHelper.instance.getSetting('primaryColor').then((colorStr) {
          if (colorStr != null &&
              colorStr != '#FF000000' &&
              colorStr.isNotEmpty) {
            Logging.severe(
                'ThemeService: Prevented unintended black override! Using stored color from database: $colorStr');

            try {
              // Parse the color from the database
              String hexColor = colorStr.substring(1); // Remove the # prefix
              if (hexColor.length == 8) {
                // Force alpha to FF for full opacity
                hexColor = 'FF${hexColor.substring(2)}';
              } else if (hexColor.length == 6) {
                hexColor = 'FF$hexColor';
              }

              final colorValue = int.parse(hexColor, radix: 16);
              final safeColor = Color(colorValue);

              // Update to the correct color
              _primaryColor = safeColor;
              Logging.severe(
                  'ThemeService: Corrected color to: ${_colorToHex(safeColor)}');

              // Notify listeners about the corrected color
              _notifyListeners();
            } catch (e) {
              Logging.severe(
                  'ThemeService: Error parsing color from database: $e');
              // Just set purple as fallback
              _primaryColor = const Color(0xFF864AF9);
              _notifyListeners();
            }
          } else {
            // Black color is genuine, use it
            _primaryColor = color;
            _notifyListeners();
          }
        });
      } else {
        // This is a legitimate user request for black color
        Logging.severe('ThemeService: Black color chosen by user - allowing');
        _primaryColor = color;
        _notifyListeners();
      }
    } else {
      // Not a black color, update normally
      _primaryColor = color;
      _notifyListeners();
    }
  }

  /// Load theme settings from the database
  static Future<void> loadThemeSettings() async {
    try {
      // Load theme mode from database
      final themeStr = await DatabaseHelper.instance.getSetting('themeMode');
      ThemeMode mode = ThemeMode.system;

      // Enhanced theme mode parsing to better handle all possible value formats
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
        Logging.severe('ThemeService: Using theme mode: $mode');
      }

      // Load primary color with simpler, more direct approach
      final colorStr = await DatabaseHelper.instance.getSetting('primaryColor');
      Logging.severe('ThemeService: Raw color from database: $colorStr');

      // Default to purple
      Color color = ColorUtility.defaultPurple;

      // If we have a value from the database, parse it
      if (colorStr != null && colorStr.isNotEmpty) {
        try {
          color = ColorUtility.hexToColor(colorStr);
          Logging.severe(
              'ThemeService: Loaded color: ${ColorUtility.colorToHex(color)}');
        } catch (e) {
          Logging.severe(
              'ThemeService: Error parsing color, using default: $e');
          // Save the default to fix any parsing issues
          await _savePrimaryColorToDatabase(ColorUtility.defaultPurple);
        }
      } else {
        // No color setting found, save the default
        Logging.severe(
            'ThemeService: No color setting found, setting default purple');
        await DatabaseHelper.instance
            .saveSetting('primaryColor', ColorUtility.defaultPurpleHex);
      }

      // Load dark button text preference from database
      final darkButtonText =
          await DatabaseHelper.instance.getSetting('useDarkButtonText');
      if (darkButtonText != null) {
        _useDarkButtonText = darkButtonText == 'true';
        Logging.severe(
            'ThemeService: Using dark button text: $_useDarkButtonText');
      }

      // Update the theme with loaded settings
      _themeMode = mode;
      _primaryColor = color;

      Logging.severe('ThemeService: Initialization complete');
    } catch (e, stack) {
      Logging.severe('ThemeService: Error loading theme settings', e, stack);
    }
  }

  // Helper method to save the primary color to database with proper formatting
  static Future<void> _savePrimaryColorToDatabase(Color color) async {
    final hexString = ColorUtility.colorToHex(color);
    await DatabaseHelper.instance.saveSetting('primaryColor', hexString);
    Logging.severe('ThemeService: Saved color to database: $hexString');
  }

  /// Update the theme mode and save to database
  static Future<void> setThemeMode(ThemeMode mode) async {
    // First update the internal value so it's immediately available
    _themeMode = mode;

    // Save to database
    final modeStr = mode.toString();
    await DatabaseHelper.instance.saveSetting('themeMode', modeStr);

    Logging.severe('ThemeService: Theme mode set to $mode');

    // Notify listeners
    _notifyListeners();
  }

  /// Update the primary color and save to database
  static Future<void> setPrimaryColor(Color color) async {
    // Ensure we're working with integer RGB values at storage boundaries only
    final int r = color.r.round();
    final int g = color.g.round();
    final int b = color.b.round();

    // FIX: Check for very small values that should be zero
    final int safeR = r < 3 ? 0 : r;
    final int safeG = g < 3 ? 0 : g;
    final int safeB = b < 3 ? 0 : b;

    // Create a clean color with exact integer RGB values
    final Color safeColor = Color.fromARGB(255, safeR, safeG, safeB);

    // Important: Update our local copy first
    _primaryColor = safeColor;

    // Create a hex string for storage (with FF for alpha)
    final hexString = _colorToHex(safeColor);

    // Log with cleaner format
    Logging.severe(
        'ThemeService: Setting color to $hexString (RGB: $safeR, $safeG, $safeB)');

    // Save to database
    await DatabaseHelper.instance.saveSetting('primaryColor', hexString);

    // Notify listeners about the change
    _notifyListeners();

    // Also notify SettingsService about the change to keep them in sync
    SettingsService.notifyColorChangeOnly(safeColor);
  }

  /// Update the primary color directly without complex checks
  /// This is used only when we're 100% sure we want to set this exact color
  static void setPrimaryColorDirectly(Color color) {
    // Update the internal value
    _primaryColor = color;

    // Log the direct change for debugging
    Logging.severe(
        'ThemeService: Directly setting color to: ${_colorToHex(color)} (RGB: ${color.r}, ${color.g}, ${color.b})');

    // Notify listeners about the change
    _notifyListeners();
  }

  /// Set whether to use dark text on buttons
  static Future<void> setUseDarkButtonText(bool useDark,
      {bool notifyListeners = true}) async {
    // Update the local value
    _useDarkButtonText = useDark;

    // Save to database
    await DatabaseHelper.instance
        .saveSetting('useDarkButtonText', useDark.toString());

    Logging.severe(
        'ThemeService: Button text color set to ${useDark ? "dark" : "light"}');

    // Only notify listeners if the flag is set to true
    if (notifyListeners) {
      _notifyListeners();
    } else {
      Logging.severe(
          'ThemeService: Skipping listener notification for button text change');
    }
  }

  /// Add a listener to be notified when the theme changes
  static void addListener(Function(ThemeMode, Color) listener) {
    _listeners.add(listener);
  }

  /// Remove a listener
  static void removeListener(Function(ThemeMode, Color) listener) {
    _listeners.remove(listener);
  }

  /// Notify all listeners of theme changes
  static void _notifyListeners() {
    Logging.severe('ThemeService: Notifying listeners of theme/color change');
    for (var listener in _listeners) {
      listener(_themeMode, _primaryColor);
    }
  }

  /// Build the theme data based on brightness and primary color
  static ThemeData _buildThemeData(Brightness brightness, Color primaryColor) {
    // Simplify logging - only log when actually building themes
    final isDark = brightness == Brightness.dark;

    // Color for dark theme background - stronger grey, almost black
    final darkBackgroundColor =
        Color.fromRGBO(18, 18, 18, 1.0); // Use RGBA format
    final darkSurfaceColor = Color.fromRGBO(30, 30, 30, 1.0); // Use RGBA format

    // MODIFIED: Add filtering for dark theme background logs to avoid confusion
    // Only log color if it's not the dark theme background/near-black values
    final int r = primaryColor.r.round();
    final int g = primaryColor.g.round();
    final int b = primaryColor.b.round();
    final String colorHex = _colorToHex(primaryColor);

    // Filter out confusing logs: Skip logging when in dark mode AND color is near-black
    bool isNearBlack = (r <= 1 && g <= 1 && b <= 1);

    if (!isDark || !isNearBlack) {
      // Only log when NOT in dark mode with near-black colors
      Logging.severe(
          'ThemeService: Building theme with color: $colorHex (RGB: $r, $g, $b)');
    } else {
      // This is just the dark theme using darkBackgroundColor/darkSurfaceColor
      Logging.severe('ThemeService: Building dark theme (background colors)');
    }

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      primaryColor: primaryColor,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: primaryColor,
        onPrimary: _getContrastingColor(primaryColor),
        secondary: primaryColor,
        onSecondary: _getContrastingColor(primaryColor),
        error: Colors.red.shade800,
        onError: Colors.white,
        // Replace deprecated 'background' with 'surface'
        surface: isDark ? darkSurfaceColor : Colors.white,
        onSurface: isDark ? Colors.white : Colors.black,
        // For Material 3, use surfaceTint instead of 'background'
        surfaceTint: isDark ? darkBackgroundColor : Colors.white,
      ),
      appBarTheme: AppBarTheme(
        // Make app bar transparent with no elevation
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor:
            isDark ? Colors.white : _getContrastingColor(primaryColor),
        centerTitle: false,
        // Add this to remove the app bar shadow
        shadowColor: Colors.transparent,
      ),
      // Use a transparent scaffold background color that picks up the colorScheme.background
      scaffoldBackgroundColor: isDark ? darkBackgroundColor : Colors.white,
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primaryColor,
        foregroundColor: _getContrastingColor(primaryColor),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: _useDarkButtonText
              ? Colors.black
              : _getContrastingColor(primaryColor),
          textStyle: const TextStyle(
            fontWeight: FontWeight.bold, // Make button text bold
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: _useDarkButtonText
              ? Colors.black
              : _getContrastingColor(primaryColor),
          textStyle: const TextStyle(
            fontWeight: FontWeight.bold, // Make button text bold
          ),
        ),
      ),
      // Add slider theme to respect the button text color preference
      sliderTheme: SliderThemeData(
        activeTrackColor: primaryColor,
        // Replace deprecated withOpacity with withAlpha
        inactiveTrackColor: primaryColor.withAlpha(76), // ~0.3 opacity = 76/255
        thumbColor: primaryColor,
        // Replace deprecated withOpacity with withAlpha
        overlayColor: primaryColor.withAlpha(76), // ~0.3 opacity = 76/255
        valueIndicatorColor: primaryColor,
        valueIndicatorTextStyle: TextStyle(
          color: _useDarkButtonText ? Colors.black : Colors.white,
        ),
      ),
    );
  }

  // Helper method to convert Color to hex string for consistent logging
  static String _colorToHex(Color color) {
    return ColorUtility.colorToHex(color);
  }

  /// Helper function to determine if white or black text should be used on a background color
  static Color _getContrastingColor(Color backgroundColor) {
    // Calculate luminance (brightness) of the color
    final double luminance = (0.299 * backgroundColor.r +
            0.587 * backgroundColor.g +
            0.114 * backgroundColor.b) /
        255;

    // Use white text on dark backgrounds, black text on light backgrounds
    return luminance > 0.5 ? Colors.black : Colors.white;
  }
}
