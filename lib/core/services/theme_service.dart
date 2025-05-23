import 'dart:io';
import 'package:flutter/material.dart';
import '../../database/database_helper.dart';
import 'logging.dart';
import '../../features/settings/settings_service.dart'; // Add this import
import '../utils/color_utility.dart';
import 'dart:io' show Platform;

/// A clean, straightforward service to manage application themes
class ThemeService extends ChangeNotifier {
  static final ThemeService _instance = ThemeService._();

  // Constructor
  ThemeService._();

  // Singleton
  static ThemeService get instance => _instance;

  // Store the current theme mode and primary color
  static ThemeMode _themeMode = ThemeMode.system;
  static Color _primaryColor = const Color(0xFF536DFE); // Use indigo as default
  static bool _useDarkButtonText =
      false; // Add this line to store the preference

  // Preload tracking
  static bool _preloadComplete = false;

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

  // Define this as a static method that takes context
  static double getContentMaxWidthFactor(BuildContext context) {
    // Use 95% width on mobile platforms, 85% on larger screens
    return Platform.isAndroid ||
            Platform.isIOS ||
            MediaQuery.of(context).size.width < 600
        ? 0.95
        : 0.85;
  }

  // For backward compatibility, provide a property that uses a default width factor
  // Rename this to avoid duplicate definition
  static double get defaultContentMaxWidthFactor {
    // For cases where we don't have a context, use the platform size
    return Platform.isAndroid || Platform.isIOS ? 0.95 : 0.85;
  }

  // Override getter methods to track when theme is requested
  static ThemeData get lightTheme {
    // Remove noisy logging here
    return _buildThemeData(Brightness.light, _primaryColor);
  }

  static ThemeData get darkTheme {
    // Remove noisy logging here
    return _buildThemeData(Brightness.dark, _primaryColor);
  }

  /// Initialize the theme service by loading saved settings
  static Future<void> initialize() async {
    // Keep only this critical initialization log
    Logging.severe('ThemeService: Initializing...');

    // Initialize with app's default color (used only if no user preference exists)
    _primaryColor = ColorUtility.defaultColor;

    // Set up listener to SettingsService color changes
    SettingsService.addPrimaryColorListener(_handleColorChange);

    await loadThemeSettings();

    // Safety check for black color - only in extreme cases
    if (_primaryColor.r == 0 && _primaryColor.g == 0 && _primaryColor.b == 0) {
      Logging.severe('ThemeService: Detected black color, using app default');
      _primaryColor = ColorUtility.defaultColor;
      await _savePrimaryColorToDatabase(_primaryColor);
    }
  }

  /// Preload essential theme settings before UI rendering
  /// This is key to preventing the "flash of default color" issue
  static Future<void> preloadEssentialSettings() async {
    if (_preloadComplete) return;

    Logging.severe('ThemeService: Preloading essential settings');

    try {
      // Load primary color directly from database
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

            final colorValue = int.parse(hexColor, radix: 16);
            _primaryColor = Color(colorValue);
            Logging.severe(
                'ThemeService: Preloaded primary color: $colorString');
          }
        } catch (e) {
          Logging.severe('ThemeService: Error parsing preloaded color: $e');
          _primaryColor = ColorUtility.defaultColor;
        }
      }

      // Load theme mode
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

      _themeMode = mode;

      // Load dark button text setting
      final darkButtonText =
          await DatabaseHelper.instance.getSetting('useDarkButtonText');
      _useDarkButtonText = darkButtonText == 'true';

      _preloadComplete = true;
      Logging.severe('ThemeService: Preload complete');
    } catch (e) {
      Logging.severe('ThemeService: Error during preload: $e');
      // Use defaults if preload fails
    }
  }

  /// Check if preload is complete
  static bool isPreloadComplete() {
    return _preloadComplete;
  }

  /// Handle color changes from SettingsService
  static void _handleColorChange(Color color) {
    // Almost completely eliminate logging from this method
    // It's called frequently and generates a lot of noise

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
        // Only log truly critical operations
        Logging.severe('ThemeService: Detected color reset operation');
      }
    } catch (e) {
      // No logging for minor errors
    }

    // CRITICAL BUGFIX: If it's a reset operation and the color is black,
    // use default color instead as black is likely unintended
    if (isResetOperation && color.r == 0 && color.g == 0 && color.b == 0) {
      Logging.severe(
          'ThemeService: Avoiding black color during reset, using default color');
      _primaryColor = ColorUtility.defaultColor;
      _notifyListeners();
      return;
    }

    // The rest of the method with no logging
    if (color.r == 0 && color.g == 0 && color.b == 0) {
      bool isFromButtonTextChange = false;

      try {
        StackTrace currentStack = StackTrace.current;
        String stackString = currentStack.toString();

        if (stackString.contains('notifyButtonTextColorChanged') ||
            stackString.contains('setUseDarkButtonText')) {
          isFromButtonTextChange = true;
        }
      } catch (e) {
        // No logging
      }

      if (isFromButtonTextChange) {
        DatabaseHelper.instance.getSetting('primaryColor').then((colorStr) {
          if (colorStr != null &&
              colorStr != '#FF000000' &&
              colorStr.isNotEmpty) {
            // Only log when we're actually preventing an issue
            Logging.severe(
                'ThemeService: Prevented unintended black override!');

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
              _notifyListeners();
            } catch (e) {
              // Only log actual errors
              Logging.severe(
                  'ThemeService: Error parsing color from database: $e');
              _primaryColor = ColorUtility.defaultColor;
              _notifyListeners();
            }
          } else {
            _primaryColor = color;
            _notifyListeners();
          }
        });
      } else {
        _primaryColor = color;
        _notifyListeners();
      }
    } else {
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
        // Minimal log - only the final theme mode
        Logging.severe('ThemeService: Using theme mode: $mode');
      }

      // Load primary color directly from database without modifications
      final colorStr = await DatabaseHelper.instance.getSetting('primaryColor');
      Color color =
          ColorUtility.defaultColor; // Default only if no setting exists

      if (colorStr != null && colorStr.isNotEmpty) {
        try {
          // Use our fixed hexToColor method to parse the color string exactly as stored
          color = ColorUtility.hexToColor(colorStr);
        } catch (e) {
          // Only log the error but keep using the user's chosen color if possible
          Logging.severe('ThemeService: Error parsing color string: $e');
        }
      } else {
        await DatabaseHelper.instance
            .saveSetting('primaryColor', ColorUtility.defaultColorHex);
      }

      // Update the theme with the loaded/default settings
      _themeMode = mode;
      _primaryColor = color;

      // Load dark button text preference from database
      final darkButtonText =
          await DatabaseHelper.instance.getSetting('useDarkButtonText');
      if (darkButtonText != null) {
        _useDarkButtonText = darkButtonText == 'true';
      }

      // Single log at completion
    } catch (e, stack) {
      // Only log errors
      Logging.severe('ThemeService: Error loading theme settings', e, stack);
    }
  }

  // Helper method to save the primary color to database with proper formatting
  static Future<void> _savePrimaryColorToDatabase(Color color) async {
    final hexString = ColorUtility.colorToHex(color);
    await DatabaseHelper.instance.saveSetting('primaryColor', hexString);
    // No logging for routine database operations
  }

  /// Update the theme mode and save to database
  static Future<void> setThemeMode(ThemeMode mode) async {
    try {
      final db = DatabaseHelper.instance;
      // Store as a plain string without the 'ThemeMode.' prefix
      String modeStr;
      switch (mode) {
        case ThemeMode.system:
          modeStr = 'system';
          break;
        case ThemeMode.light:
          modeStr = 'light';
          break;
        case ThemeMode.dark:
          modeStr = 'dark';
          break;
      }
      await db.saveSetting('themeMode', modeStr);
      _themeMode = mode;

      // Notify listeners
      instance.notifyListeners();

      Logging.severe('Theme mode set to $modeStr');
    } catch (e, stack) {
      Logging.severe('Error setting theme mode', e, stack);
    }
  }

  /// Update the primary color and save to database
  static Future<void> setPrimaryColor(Color color) async {
    // CRITICAL FIX: Prevent saving pure black on Android
    if (Platform.isAndroid &&
        color.r == 0 &&
        color.g == 0 &&
        color.b == 0 &&
        color.a == 255) {
      Logging.severe(
          'ThemeService: Preventing pure black on Android, using safe black instead');
      color = ColorUtility.safeBlack; // Use safe black from ColorUtility
    }

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
    final hexString = ColorUtility.colorToHex(safeColor);

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
    // CRITICAL: Add black color rejection
    bool isBlack = color.r == 0 && color.g == 0 && color.b == 0;

    if (isBlack) {
      Logging.severe(
          'CRITICAL ERROR: Attempt to set BLACK color directly. Backtrace:');
      Logging.severe(StackTrace.current.toString());

      // Reject black color for primary color
      // Check the database for the current value
      DatabaseHelper.instance.getSetting('primaryColor').then((colorStr) {
        if (colorStr != null &&
            colorStr != '#FF000000' &&
            colorStr.isNotEmpty) {
          Logging.severe(
              'Avoiding black color by using database value: $colorStr');
          try {
            // Try to use the database value instead
            final dbColor = ColorUtility.hexToColor(colorStr);
            _primaryColor = dbColor;
            _notifyListeners();
          } catch (e) {
            // Fall back to default color
            Logging.severe(
                'Error parsing database color, using default purple');
            _primaryColor = ColorUtility.defaultColor;
            _notifyListeners();
          }
        } else {
          // No valid color in database, use default purple
          Logging.severe('No valid color in database, using default purple');
          _primaryColor = ColorUtility.defaultColor;
          _notifyListeners();
        }
      });
      return;
    }

    // Update the internal value with the non-black color
    _primaryColor = color;
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

    // Only log user preference changes, not internal state updates

    // Only notify listeners if the flag is set to true
    if (notifyListeners) {
      _notifyListeners();
    }
  }

  /// Update the primary color from an imported value
  static Future<void> updatePrimaryColorFromImport(String colorValue) async {
    try {
      Logging.severe(
          'ThemeService: Updating primary color from import: $colorValue');

      // Parse the color string to a Color object
      Color? parsedColor;

      if (colorValue.startsWith('#')) {
        // Handle hex format like #RRGGBB or #AARRGGBB
        String hexColor = colorValue.replaceFirst('#', '');

        if (hexColor.length == 6) {
          hexColor = 'FF$hexColor'; // Add alpha if not present
        }

        if (hexColor.length == 8) {
          parsedColor = Color(int.parse('0x$hexColor'));
        }
      }

      // If we couldn't parse it or it's not valid, just return
      if (parsedColor == null) {
        Logging.severe(
            'ThemeService: Could not parse color value: $colorValue');
        return;
      }

      // Update the database directly
      final db = DatabaseHelper.instance;
      await db.saveSetting('primaryColor', colorValue);

      // Update the in-memory color right away
      _primaryColor = parsedColor;

      // Notify global listeners (which notify _MyAppState)
      for (final listener in _listeners) {
        listener(_themeMode, _primaryColor);
      }

      // Also notify instance listeners for AnimatedBuilder
      instance.notifyListeners();

      // Also notify ChangeNotifier listeners on the instance
      instance._updateState();

      // Add additional notification to ensure Settings page updates
      notifyGlobalListeners();

      Logging.severe(
          'ThemeService: Primary color updated to $colorValue and applied immediately');
    } catch (e, stack) {
      Logging.severe(
          'ThemeService: Error updating primary color from import', e, stack);
    }
  }

  /// Additional method to ensure all global listeners are notified
  static void notifyGlobalListeners() {
    // This ensures that _themeListener in _MyAppState gets called
    for (final listener in _listeners) {
      listener(_themeMode, _primaryColor);
    }

    // This ensures that AnimatedBuilder widgets get rebuilt
    instance.notifyListeners();
  }

  // Make sure the instance._updateState method exists and works properly
  void _updateState() {
    // This method should trigger a rebuild of any widgets using this as a ChangeNotifier
    notifyListeners();
    // Explicitly log this to trace the notification flow
    Logging.severe('ThemeService instance notified listeners of state change');
  }

  /// Update the theme mode from an imported value
  static Future<void> updateThemeModeFromImport(String modeValue) async {
    try {
      Logging.severe(
          'ThemeService: Updating theme mode from import: $modeValue');

      // Parse the theme mode string
      ThemeMode parsedMode = ThemeMode.system;

      // Handle the value with or without the ThemeMode. prefix
      String normalizedValue =
          modeValue.replaceAll('ThemeMode.', '').toLowerCase();

      switch (normalizedValue) {
        case 'dark':
          parsedMode = ThemeMode.dark;
          break;
        case 'light':
          parsedMode = ThemeMode.light;
          break;
        case 'system':
          parsedMode = ThemeMode.system;
          break;
        default:
          Logging.severe(
              'ThemeService: Unknown theme mode value: $modeValue, using system');
          parsedMode = ThemeMode.system;
      }

      // Update the database
      final db = DatabaseHelper.instance;
      await db.saveSetting('themeMode', 'ThemeMode.$normalizedValue');

      // Update in-memory value
      _themeMode = parsedMode;

      // Notify listeners
      if (_listeners.isNotEmpty) {
        for (final listener in _listeners) {
          listener(_themeMode, _primaryColor);
        }
        Logging.severe(
            'ThemeService: Notified ${_listeners.length} listeners of theme mode change');
      }

      // Also notify instance listeners to trigger UI rebuilds
      instance.notifyListeners();

      Logging.severe(
          'ThemeService: Theme mode updated to $parsedMode and applied immediately');
    } catch (e, stack) {
      Logging.severe(
          'ThemeService: Error updating theme mode from import', e, stack);
    }
  }

  // Make sure this method is properly implemented to load themes from the database
  static Future<void> loadSettings() async {
    try {
      final db = DatabaseHelper.instance;

      // Load theme mode with better parsing
      final themeModeValue = await db.getSetting('themeMode');
      if (themeModeValue != null) {
        // Support both formats: with or without 'ThemeMode.' prefix
        final modeStr =
            themeModeValue.replaceAll('ThemeMode.', '').toLowerCase();
        switch (modeStr) {
          case 'dark':
            _themeMode = ThemeMode.dark;
            break;
          case 'light':
            _themeMode = ThemeMode.light;
            break;
          default:
            _themeMode = ThemeMode.system;
            break;
        }
        Logging.severe('Loaded theme mode: $_themeMode');
      }

      // Load primary color
      final primaryColorValue = await db.getSetting('primaryColor');
      if (primaryColorValue != null && primaryColorValue.startsWith('#')) {
        final parsedColor = ColorUtility.hexToColor(primaryColorValue);
        _primaryColor = parsedColor;
        Logging.severe('Loaded primary color: $primaryColorValue');
      }

      // Load dark button text flag
      final useDarkButtonTextValue = await db.getSetting('useDarkButtonText');
      if (useDarkButtonTextValue != null) {
        _useDarkButtonText = useDarkButtonTextValue.toLowerCase() == 'true';
        Logging.severe('Loaded use dark button text: $_useDarkButtonText');
      }

      // Notify listeners that settings have been loaded
      instance.notifyListeners();
    } catch (e, stack) {
      Logging.severe('Error loading theme settings', e, stack);
    }
  }

  // Change the name of the duplicate initialize method to avoid conflict
  // New name: initializeSettings() instead of initialize()
  static Future<void> initializeSettings() async {
    try {
      await loadSettings();
      Logging.severe(
          'ThemeService initialized with primaryColor: ${_primaryColor.toString()}');
    } catch (e, stack) {
      Logging.severe('Error initializing ThemeService', e, stack);
    }
  }

  /// Add a theme listener to the theme change events
  static void addThemeListener(VoidCallback listener) {
    // If _listeners is static final, we need to initialize it differently
    // Assuming _listeners is declared as: static final List<Function(ThemeMode, Color)> _listeners = [];

    // Convert VoidCallback to Function(ThemeMode, Color) with a wrapper
    // No null check needed if _listeners is a non-nullable final field
    _listeners.add((mode, color) => listener());
  }

  /// Remove a theme listener from the theme change events
  static void removeThemeListener(VoidCallback listener) {
    // No null check needed if _listeners is a non-nullable final field
    // Instead, we can just directly access the list methods
    _listeners.removeWhere((fn) => fn.toString() == listener.toString());
  }

  // Static convenience wrapper methods for adding/removing listeners - renamed to avoid conflict
  static void addGlobalListener(VoidCallback listener) {
    instance.addListener(listener);
  }

  static void removeGlobalListener(VoidCallback listener) {
    instance.removeListener(listener);
  }

  /// Notify all listeners of theme changes
  static void _notifyListeners() {
    // No logging for this very frequent operation
    for (var listener in _listeners) {
      listener(_themeMode, _primaryColor);
    }
  }

  /// Build the theme data based on brightness and primary color
  static ThemeData _buildThemeData(Brightness brightness, Color primaryColor) {
    // No logging at all in theme building - this happens constantly
    final isDark = brightness == Brightness.dark;

    // Color for dark theme background - stronger grey, almost black
    final darkBackgroundColor =
        Color.fromRGBO(18, 18, 18, 1.0); // Use RGBA format
    final darkSurfaceColor = Color.fromRGBO(30, 30, 30, 1.0); // Use RGBA format

    // Remove excessive color logging during theme building

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
