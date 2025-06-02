import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:flutter_svg/svg.dart';
import 'package:rateme/features/notifications/global_notifications.dart';
import '../../core/api/api_keys.dart';
import '../../core/utils/color_utility.dart';
import '../../database/api_key_manager.dart';
import '../../database/cleanup_utility.dart';
import '../../database/database_helper.dart';
import '../../database/migration_progress_page.dart';
import '../../database/track_recovery_utility.dart';
import '../../core/services/theme_service.dart' as ts;
import '../../core/services/user_data.dart';
import '../../core/services/logging.dart';
import '../../core/utils/debug_util.dart';
import 'settings_service.dart';
import '../../ui/widgets/skeleton_loading.dart';
import '../../core/services/search_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/utils/version_info.dart';
import 'package:flutter/services.dart'; // Add this for TextInputFormatter
import '../../ui/widgets/platform_match_cleaner.dart';
import '../../core/utils/date_fixer_utility.dart'; // Add this import
import '../../core/utils/album_migration_utility.dart';

class SettingsPage extends StatefulWidget {
  final ThemeMode currentTheme;
  final Function(ThemeMode) onThemeChanged;
  final Color currentPrimaryColor;
  final Function(Color) onPrimaryColorChanged;

  const SettingsPage({
    super.key,
    required this.currentTheme,
    required this.onThemeChanged,
    required this.currentPrimaryColor,
    required this.onPrimaryColorChanged,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late Color pickerColor;
  late Color textColor;
  final defaultColor = const Color(0xFF864AF9);
  final defaultTextColor = Colors.white;
  bool useDarkText = false;
  bool isLoading = true;
  SearchPlatform defaultSearchPlatform = SearchPlatform.itunes;

  // Add refresh indicator key
  final GlobalKey<RefreshIndicatorState> _refreshIndicatorKey =
      GlobalKey<RefreshIndicatorState>();

  // Add default search platform selection
  SearchPlatform _defaultSearchPlatform = SearchPlatform.itunes;

  // Add this field to store the current platform
  SearchPlatform _currentPlatform = SearchPlatform.itunes;

  // Add this variable to track processing state
  final bool _isProcessing = false;

  // Add these at the class level, near the other state variables
  static const Color defaultPurpleColor = Color(0xFF864AF9);
  late Color _primaryColor = defaultPurpleColor;
  late bool _useDarkButtonText = false; // Add this variable declaration

  // Remove the unused _hexController field

  @override
  void initState() {
    super.initState();
    pickerColor = widget.currentPrimaryColor;
    textColor = defaultTextColor;

    // Use cached values if available
    _primaryColor = SettingsService.primaryColor;
    _useDarkButtonText = SettingsService.useDarkButtonText;

    // Subscribe to theme changes
    ts.ThemeService.addGlobalListener(_updateTheme);

    // Still load settings to ensure everything is up to date
    _loadSettings();
    _checkDatabaseSize();
    _loadPreferences();
    // Load saved platform preference
    _loadPlatformPreference();

    // Add a listener for primary color changes
    SettingsService.addPrimaryColorListener(_updatePrimaryColor);

    // Add a global theme listener that will refresh the entire UI when theme changes
    ts.ThemeService.addGlobalListener(_forceRefresh);

    // Add ThemeService listener to update UI when theme changes
    ts.ThemeService.addGlobalListener(_updateThemeState);

    // Log for debugging
    Logging.severe('Refreshing settings page');
    Logging.severe(
        'Current theme mode in settings page: ${ts.ThemeService.themeMode}');
  }

  @override
  void dispose() {
    // Unsubscribe when the page is disposed
    ts.ThemeService.removeGlobalListener(_updateTheme);

    // Remove the listener when the widget is disposed
    SettingsService.removePrimaryColorListener(_updatePrimaryColor);

    // Remove listener when widget is disposed
    ts.ThemeService.removeGlobalListener(_forceRefresh);

    // Remove listener when the widget is disposed
    ts.ThemeService.removeGlobalListener(_updateThemeState);
    super.dispose();
  }

  // This method will be called when the theme changes
  void _updateTheme() {
    if (mounted) {
      setState(() {
        // No need to update _currentColor, just trigger a rebuild
      });
    }
  }

  // Method to update primary color when it changes elsewhere
  void _updatePrimaryColor(Color color) {
    if (mounted) {
      setState(() {
        _primaryColor = color;
      });
    }
  }

  // Force a complete UI refresh when theme changes
  void _forceRefresh() {
    if (mounted) {
      setState(() {
        // This will rebuild the entire widget tree with the new theme
      });
    }
  }

  // Callback for theme changes
  void _updateThemeState() {
    if (mounted) {
      setState(() {
        // This will rebuild the UI when theme changes occur
      });
    }
  }

  Future<void> _loadSettings() async {
    try {
      // Use SettingsService instead of SharedPreferences
      final settingsService = SettingsService();
      await settingsService.initialize();

      if (mounted) {
        // Fix the type issue
        final darkButtonPref = await settingsService
            .getSetting<bool>('useDarkButtonText', defaultValue: false);

        setState(() {
          // Use the result of the Future, not the Future itself
          useDarkText = darkButtonPref ?? false;
          isLoading = false;

          // Fix the other Future usage in a similar way
          final platformIndexFuture = settingsService
              .getSetting<int>('defaultSearchPlatform', defaultValue: 0);
          platformIndexFuture.then((platformIndex) {
            if (mounted &&
                platformIndex != null &&
                platformIndex < SearchPlatform.values.length) {
              setState(() {
                defaultSearchPlatform = SearchPlatform.values[platformIndex];
              });
            }
          });
        });
      }

      // Load primary color with better detection of invalid colors
      final colorString =
          await DatabaseHelper.instance.getSetting('primaryColor');
      Logging.severe('Raw primary color setting: $colorString');

      // Define the default purple for clarity
      final Color defaultPurpleColor = const Color(0xFF864AF9);

      if (colorString != null && colorString.isNotEmpty) {
        try {
          // Parse the color string
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
            final parsedColor = Color(colorValue);

            // We don't need this check anymore since our color picker and saving is working properly
            // Just use the parsed color directly
            setState(() {
              _primaryColor = parsedColor;
            });
            Logging.severe(
                'Loaded color from database: $colorString (RGB: ${parsedColor.r}, ${parsedColor.g}, ${parsedColor.b})');
          } else {
            // Not a hex string, use default
            setState(() {
              _primaryColor = defaultPurpleColor;
            });
          }
        } catch (e) {
          // Error parsing, use default
          Logging.severe('Error parsing color: $e');
          setState(() {
            _primaryColor = defaultPurpleColor;
          });
        }
      } else {
        // No color setting, use default
        setState(() {
          _primaryColor = defaultPurpleColor;
        });

        // Save the default purple
        final String hexR =
            defaultPurpleColor.r.round().toRadixString(16).padLeft(2, '0');
        final String hexG =
            defaultPurpleColor.g.round().toRadixString(16).padLeft(2, '0');
        final String hexB =
            defaultPurpleColor.b.round().toRadixString(16).padLeft(2, '0');
        final String correctHex = '#FF$hexR$hexG$hexB'.toUpperCase();

        await DatabaseHelper.instance.saveSetting('primaryColor', correctHex);
        Logging.severe('Saved default purple: $correctHex');
      }

      // Load dark button text setting
      final darkButtonText =
          await DatabaseHelper.instance.getSetting('useDarkButtonText');
      setState(() {
        _useDarkButtonText = darkButtonText == 'true';
      });
    } catch (e) {
      Logging.severe('Error loading settings: $e');
    }
  }

  Future<void> _loadPreferences() async {
    try {
      // Get database instance
      final settingsService = SettingsService();
      await settingsService.initialize();

      // Load dark button text preference with correct typing
      // Wait for the Future to complete
      final darkButtonTextSetting = await settingsService
          .getSetting<bool>('useDarkButtonText', defaultValue: false);
      bool darkButtonText = darkButtonTextSetting ?? false;

      // Load default search platform with correct typing
      // Wait for the Future to complete
      final platformIndexSetting = await settingsService
          .getSetting<int>('default_search_platform', defaultValue: 0);
      int platformIndex = platformIndexSetting ?? 0;

      if (platformIndex < SearchPlatform.values.length) {
        _defaultSearchPlatform = SearchPlatform.values[platformIndex];
      }

      if (mounted) {
        setState(() {
          useDarkText = darkButtonText;
        });
      }
    } catch (e) {
      Logging.severe('Error loading settings preferences', e);
    }
  }

  Future<void> _checkDatabaseSize() async {
    if (mounted) {
      setState(() {});
    }
  }

  // Modify the _showSnackBar method to safely show snackbars
  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 3),
        ),
      );
    } else {
      // Fallback to just logging if we can't show a snackbar
      Logging.severe('SnackBar message (not shown): $message');
    }
  }

  Future<void> _showClearDatabaseDialog() async {
    return showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        // Renamed to dialogContext to be clear
        return AlertDialog(
          title: const Text('Clear Database'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text('This will delete:'),
              SizedBox(height: 8),
              Text('• All saved albums'),
              Text('• All ratings'),
              Text('• All custom lists'),
              Text('• All settings'),
              SizedBox(height: 16),
              Text(
                'This action cannot be undone!',
                style:
                    TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(), // Use dialogContext here
              child: const Text('Cancel'),
            ),
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: Colors.red,
              ),
              onPressed: () async {
                try {
                  // Close dialog first, using dialogContext to avoid async gap
                  Navigator.of(dialogContext).pop();

                  // Show loading indicator
                  setState(() {
                    isLoading = true;
                  });

                  final db = await DatabaseHelper.instance.database;
                  await db.transaction((txn) async {
                    await txn.delete('albums');
                    await txn.delete('ratings');
                    await txn.delete('custom_lists');
                    await txn.delete('album_lists');
                    await txn.delete('album_order');
                  });

                  // Use if (!mounted) return pattern before using context after async gap
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Database cleared successfully')),
                  );
                } catch (e) {
                  Logging.severe('Error clearing database', e);
                  // Use if (!mounted) return pattern
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error clearing database: $e')),
                  );
                } finally {
                  // Hide loading indicator
                  if (mounted) {
                    setState(() {
                      isLoading = false;
                    });
                  }
                }
              },
              child: const Text('Clear Everything'),
            ),
          ],
        );
      },
    );
  }

  void _showProgressDialog(String title, String message) {
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(message),
            ],
          ),
        );
      },
    );
  }

  String colorToHex(Color color) {
    int rgb = ((color.a * 255).round() << 24) | (color.toARGB32() & 0x00FFFFFF);
    String value = '#${rgb.toRadixString(16).padLeft(6, '0').substring(2)}';
    return value;
  }

  Future<void> _performDatabaseMaintenance() async {
    try {
      // Show the progress dialog
      _showProgressDialog('Database Maintenance', 'Optimizing database...');

      // Get the database instance
      final db = await DatabaseHelper.instance.database;
      final initialSize = await DatabaseHelper.instance.getDatabaseSize();

      // Run integrity check
      final isIntegrityOk =
          await DatabaseHelper.instance.checkDatabaseIntegrity();
      if (!isIntegrityOk) {
        // Safely dismiss dialog and show message
        if (mounted) {
          Navigator.of(context).pop();
          _showSnackBar(
              'Database integrity check failed. Please try emergency reset.');
        }
        return;
      }

      // Vacuum database
      await db.execute('VACUUM');
      await db.execute('ANALYZE');

      // Get final size
      final finalSize = await DatabaseHelper.instance.getDatabaseSize();
      final savedSize = initialSize - finalSize;
      final percentSaved =
          initialSize > 0 ? (savedSize / initialSize * 100) : 0;

      // Build message
      String message = 'Database optimization completed successfully!';
      if (savedSize > 0) {
        message +=
            ' Saved ${(savedSize / 1024).toStringAsFixed(1)}KB (${percentSaved.toStringAsFixed(1)}%).';
      }

      // Check if widget is still mounted before showing results
      if (mounted) {
        // Dismiss the progress dialog
        Navigator.of(context).pop();

        // Show success message
        _showSnackBar(message);
      }
    } catch (e) {
      if (mounted) {
        // Dismiss the progress dialog
        Navigator.of(context).pop();

        // Show error message
        _showSnackBar('Error optimizing database: $e');
      }
    }
  }

  // Add refresh method
  Future<void> _refreshData() async {
    Logging.severe('Refreshing settings page');

    // Set loading state
    setState(() {
      isLoading = true;
    });

    // Reload settings
    await _loadSettings();
    await _checkDatabaseSize();
    await _loadPreferences();

    // Show feedback to user
    if (!mounted) return;
    _showSnackBar('Settings refreshed');

    Logging.severe('Settings refresh complete');
  }

  // Save default search platform using the database
  Future<void> _saveDefaultSearchPlatform(SearchPlatform platform) async {
    try {
      final settingsService = SettingsService();
      await settingsService.saveSetting(
          'default_search_platform', platform.index);

      Logging.severe(
          'Default search platform updated to ${platform.name} (index: ${platform.index})');

      setState(() {
        _defaultSearchPlatform = platform;
      });

      // Notify the app about the default platform change
      GlobalNotifications.defaultSearchPlatformChanged(platform);

      if (mounted) {
        _showSnackBar('Default search platform updated to ${platform.name}');
      }
    } catch (e) {
      Logging.severe('Error saving default search platform', e);
      _showSnackBar('Error setting default platform: $e');
    }
  }

  // Add a method to load platform preference
  Future<void> _loadPlatformPreference() async {
    try {
      final settingsService = SettingsService();
      final platformIndex = await settingsService
          .getSetting<int>('default_search_platform', defaultValue: 0);

      if (platformIndex != null &&
          platformIndex >= 0 &&
          platformIndex < SearchPlatform.values.length) {
        setState(() {
          _currentPlatform = SearchPlatform.values[platformIndex];
        });
      }
      Logging.severe(
          'Loaded default search platform: ${_currentPlatform.name}');
    } catch (e) {
      Logging.severe('Error loading default search platform', e);
    }
  }

  // Helper method to get platform icon - completely rewritten - add bandcamp case
  IconData getPlatformIconForPlatform(SearchPlatform platform) {
    switch (platform) {
      case SearchPlatform.itunes:
        return Icons.album;
      case SearchPlatform.spotify:
        return Icons.album;
      case SearchPlatform.deezer:
        return Icons.album;
      case SearchPlatform.discogs:
        return Icons.album;
      case SearchPlatform.bandcamp:
        return Icons.album;
    }
  }

  // Add the missing _getPlatformIconPath method to _SettingsPageState
  String _getPlatformIconPath(SearchPlatform platform) {
    switch (platform) {
      case SearchPlatform.itunes:
        return 'lib/icons/apple_music.svg';
      case SearchPlatform.spotify:
        return 'lib/icons/spotify.svg';
      case SearchPlatform.deezer:
        return 'lib/icons/deezer.svg';
      case SearchPlatform.discogs:
        return 'lib/icons/discogs.svg';
      case SearchPlatform.bandcamp:
        return 'lib/icons/bandcamp.svg';
    }
  }

  // When displaying SearchPlatform.itunes in dropdowns or lists, make sure it shows as Apple Music
  String _getDisplayNameForPlatform(SearchPlatform platform) {
    switch (platform) {
      case SearchPlatform.itunes:
        return 'Apple Music'; // Changed from "iTunes" to "Apple Music"
      case SearchPlatform.spotify:
        return 'Spotify';
      case SearchPlatform.deezer:
        return 'Deezer';
      case SearchPlatform.discogs:
        return 'Discogs';
      case SearchPlatform.bandcamp:
        return 'Bandcamp';
    }
  }

  Future<void> _migrateToSqliteDatabase() async {
    try {
      // Navigate to migration page and wait for result
      final result = await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => const MigrationProgressPage(),
        ),
      );

      // Early return if not mounted after navigation or if result is not true
      if (!mounted || result != true) return;

      // Show success dialog
      await showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Migration Complete'),
          content: const Text(
            'Your data has been successfully migrated to SQLite database.\n\n'
            'This improves app performance and reliability while ensuring '
            'all your ratings and preferences are safely stored.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Continue'),
            ),
          ],
        ),
      );

      // Check mounted again after dialog
      if (!mounted) return;

      // Show snackbar
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Migration completed successfully!')),
      );
    } catch (e) {
      Logging.severe('Error during migration', e);
    }
  }

  Future<void> _importBackup() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        dialogTitle: 'Select backup file to import',
      );

      if (result == null || result.files.isEmpty) {
        _showSnackBar('No file selected');
        return;
      }

      // Show loading dialog
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          title: Text('Importing...'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Please wait while your backup is being imported...'),
            ],
          ),
        ),
      );

      // Read file
      final file = File(result.files.first.path!);
      final jsonString = await file.readAsString();

      // Import backup
      final success =
          await DatabaseHelper.instance.importBackupFile(jsonString);

      // Dismiss loading dialog
      if (!mounted) return;
      Navigator.pop(context); // Close the loading dialog

      if (success) {
        _showSnackBar('Backup imported successfully');

        // NEW: Force UI refresh by loading settings again
        if (!mounted) return;
        await _loadSettings();

        // NEW: Force theme refresh with the imported primary color
        final db = DatabaseHelper.instance;
        final colorStr = await db.getSetting('primaryColor');
        if (colorStr != null) {
          // Fix: Replace updateColorFromString with setPrimaryColor
          final colorValue = int.tryParse(colorStr);
          if (colorValue != null) {
            await ts.ThemeService.setPrimaryColor(Color(colorValue));

            // Force UI rebuild with setState
            if (mounted) {
              setState(() {
                // This will trigger a rebuild with the new theme
              });
            }
          }
        }
      } else {
        _showSnackBar('Error importing backup');
      }
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('Error importing backup: $e');
    }
  }

  Future<void> _exportBackup() async {
    try {
      final db = DatabaseHelper.instance;

      // Create a modern, SQLite-compatible backup format
      final exportMap = <String, dynamic>{};

      // 1. Export albums with tracks
      final albums = await db.getAllAlbums();
      final List<Map<String, dynamic>> albumsWithTracks = [];

      for (final album in albums) {
        final albumId = album['id'].toString();
        final tracks = await db.getTracksForAlbum(albumId);

        // Create a copy of the album with tracks added
        final albumWithTracks = Map<String, dynamic>.from(album);
        albumWithTracks['tracks'] = tracks;
        albumsWithTracks.add(albumWithTracks);
      }

      exportMap['albums'] = albumsWithTracks;

      // 2. Export ratings
      final ratings = await db.database.then((db) => db.query('ratings'));
      exportMap['ratings'] = ratings;

      // 3. Export custom lists
      final customLists = await db.getAllCustomLists();
      exportMap['custom_lists'] = customLists;

      // 4. Export album order
      final albumOrder = await db.getAlbumOrder();
      exportMap['album_order'] = albumOrder;

      // 5. Export settings
      final settings = await db.database.then((db) => db.query('settings'));
      exportMap['settings'] = settings;

      // Convert to pretty-printed JSON
      final jsonString = const JsonEncoder.withIndent('  ').convert(exportMap);

      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: 'Export Backup As',
        fileName: 'rateme_backup.json',
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (!mounted) return;

      if (savePath == null) {
        _showSnackBar('Export cancelled.');
        return;
      }

      final file = await File(savePath).writeAsString(jsonString);

      if (!mounted) return;
      _showSnackBar('Backup exported to: ${file.path}');
    } catch (e, stack) {
      Logging.severe('Error exporting backup', e, stack);
      if (!mounted) return;
      _showSnackBar('Export failed: $e');
    }
  }

  Future<void> _performEmergencyDatabaseReset() async {
    try {
      _showProgressDialog('Database Reset', 'Resetting database...');

      // Fix: use fixDatabaseLocks
      await DatabaseHelper.instance.fixDatabaseLocks();

      // Always check if widget is still mounted before updating UI
      if (mounted) {
        Navigator.of(context).pop(); // Close the progress dialog
        _showSnackBar('Database reset completed successfully.');
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(); // Close the progress dialog
        _showSnackBar('Database reset failed: $e');
      }
    }
  }

  // Add this method to fix the undefined identifier error
  Future<void> _cleanupDuplicates() async {
    try {
      // Show the progress dialog
      _showProgressDialog(
          'Database Maintenance', 'Cleaning up platform duplicates...');

      // Run the cleanup using CleanupUtility
      await CleanupUtility.cleanupPlatformMatches();

      // If we reach here, the operation completed successfully
      if (mounted) {
        // Dismiss the progress dialog
        Navigator.of(context).pop();

        // Show success message
        _showSnackBar('Platform duplicates cleanup completed successfully');
      }
    } catch (e) {
      // If there was an error
      if (mounted) {
        // Dismiss the progress dialog
        Navigator.of(context).pop();

        // Show error message
        _showSnackBar('Error cleaning up platform duplicates: $e');
      }
    }
  }

  Future<void> _fixBandcampTrackIds() async {
    try {
      // Show the progress dialog
      _showProgressDialog('Bandcamp Update', 'Updating Bandcamp albums...');

      // Run the Bandcamp fix
      await CleanupUtility.fixBandcampTrackIds();

      // If we reach here, the operation completed successfully
      if (mounted) {
        // Dismiss the progress dialog
        Navigator.of(context).pop();

        // Show success message
        _showSnackBar('Bandcamp albums updated successfully');
      }
    } catch (e) {
      // If there was an error
      if (mounted) {
        // Dismiss the progress dialog
        Navigator.of(context).pop();

        // Show error message
        _showSnackBar('Error updating Bandcamp albums: $e');
      }
    }
  }

  void _showColorPickerDialog() {
    // CRITICAL FIX: Get the CURRENT color directly from the widget variable, not the state
    final originalColor = _primaryColor;

    // CRITICAL FIX: Create a fresh, exact copy of the color using integer-based approach
    final int alpha = 255; // Always use full opacity
    // Use r, g, b properties with proper conversion to integers
    final int red = (originalColor.r * 255).round();
    final int green = (originalColor.g * 255).round();
    final int blue = (originalColor.b * 255).round();

    // Create log showing exact values we're starting with
    Logging.severe('COLOR PICKER: Starting with precise values: '
        'RGB integers=($red, $green, $blue), '
        'Float values=(${originalColor.r}, ${originalColor.g}, ${originalColor.b})');

    // Create a new Color object from the integer RGB components
    var dialogColor = Color.fromARGB(alpha, red, green, blue);

    // Get proper hex string using exact integer values
    final String properHex =
        '#FF${red.toRadixString(16).padLeft(2, '0')}${green.toRadixString(16).padLeft(2, '0')}${blue.toRadixString(16).padLeft(2, '0')}'
            .toUpperCase();

    // Log only essential info without the confusing DEBUG prefix
    Logging.severe(
        'COLOR PICKER: Prepared color correctly: RGB($red, $green, $blue) - Hex: $properHex');

    // Use the integer-based values for the hex string
    final String rgbHexPart = "${red.toRadixString(16).padLeft(2, '0')}"
            "${green.toRadixString(16).padLeft(2, '0')}"
            "${blue.toRadixString(16).padLeft(2, '0')}"
        .toUpperCase();

    // Create controller for hex input with the correct RGB part
    final TextEditingController hexController =
        TextEditingController(text: rgbHexPart);

    // Keep only essential logging - JUST ONE LINE IS ENOUGH
    Logging.severe(
        'COLOR PICKER: Opening color picker dialog with hex: #FF$rgbHexPart');

    // We can still keep the raw floating point values debug log
    Logging.severe('COLOR PICKER: Raw floating point values - '
        'red=${originalColor.r}, green=${originalColor.g}, blue=${originalColor.b}');

    if (mounted) {
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                title: const Text('Select Primary Color'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ColorPicker(
                        color: dialogColor,
                        onColorChanged: (Color color) {
                          setDialogState(() {
                            dialogColor = color;
                          });
                          // Update hex input field
                          final r = (color.r * 255).round();
                          final g = (color.g * 255).round();
                          final b = (color.b * 255).round();
                          final hexPart = "${r.toRadixString(16).padLeft(2, '0')}"
                                  "${g.toRadixString(16).padLeft(2, '0')}"
                                  "${b.toRadixString(16).padLeft(2, '0')}"
                              .toUpperCase();
                          hexController.text = hexPart;
                        },
                        width: 40,
                        height: 40,
                        borderRadius: 4,
                        spacing: 5,
                        runSpacing: 5,
                        wheelDiameter: 155,
                        showMaterialName: true,
                        showColorName: true,
                        pickersEnabled: const <ColorPickerType, bool>{
                          ColorPickerType.wheel: true,
                        },
                      ),

                      // Improved custom hex input field with better separation of alpha and RGB
                      const SizedBox(height: 16),
                      const Divider(),
                      const Text("Hex Color Code (RGB):",
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),

                      // Use a Row with two text fields - one disabled for FF, one for RGB
                      Row(
                        children: [
                          SizedBox(
                            width: 50,
                            child: TextField(
                              controller: TextEditingController(text: 'FF'),
                              enabled: false,
                              decoration: InputDecoration(
                                labelText: 'Alpha',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: hexController,
                              decoration: InputDecoration(
                                labelText: 'RGB (RRGGBB)',
                                border: OutlineInputBorder(),
                              ),
                              inputFormatters: [
                                UpperCaseTextFormatter(),
                                FilteringTextInputFormatter.allow(RegExp(r'[0-9A-F]')),
                                LengthLimitingTextInputFormatter(6),
                              ],
                              onChanged: (value) {
                                if (value.length == 6) {
                                  try {
                                    final colorValue = int.parse('FF$value', radix: 16);
                                    final newColor = Color(colorValue);
                                    setDialogState(() {
                                      dialogColor = newColor;
                                    });
                                  } catch (e) {
                                    // Invalid hex, ignore
                                  }
                                }
                              },
                            ),
                          ),
                        ],
                      ),

                      // Add a note about the fixed alpha channel
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text(
                          'Alpha is fixed at FF (fully opaque)',
                          style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                        ),
                      ),

                      // Preview section
                      const SizedBox(height: 16),
                      const Text('Preview:'),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: dialogColor,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Sample Text',
                              style: TextStyle(
                                color: ThemeData.estimateBrightnessForColor(dialogColor) == Brightness.dark
                                    ? Colors.white
                                    : Colors.black,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                actions: <Widget>[
                  TextButton(
                    child: const Text('Cancel'),
                    onPressed: () {
                      // DIAGNOSTICS: Log cancel operation
                      Logging.severe(
                          'COLOR PICKER: Canceled - restoring original color: '
                          'RGB(${originalColor.r}, ${originalColor.g}, ${originalColor.b}) - '
                          'HEX: ${ColorUtility.colorToHex(originalColor)}');

                      // Cancel - restore the original color
                      setState(() {
                        _primaryColor = originalColor;
                      });
                      // Force UI update with original color
                      ts.ThemeService.setPrimaryColorDirectly(originalColor);
                      Navigator.of(context).pop();
                    },
                  ),
                  TextButton(
                    child: const Text('Save'),
                    onPressed: () {
                      // Try to get color from hex input first in case it was manually entered
                      try {
                        if (hexController.text.length == 6) {
                          final colorValue = int.parse('FF${hexController.text}', radix: 16);
                          dialogColor = Color(colorValue);
                        }
                      } catch (e) {
                        Logging.severe('Error parsing hex input: $e');
                      }

                      // CRITICAL FIX: Use the correct float to int conversion here!
                      // The flex_color_picker returns colors with .red/.green/.blue as 0.0-1.0 values
                      // We must multiply by 255 and round for proper integer RGB values
                      final int r = (dialogColor.r * 255).round();
                      final int g = (dialogColor.g * 255).round();
                      final int b = (dialogColor.b * 255).round();

                      // PLATFORM SAFETY: After all calculations, verify we're not using pure black
                      if (r < 3 && g < 3 && b < 3) {
                        Logging.severe(
                            'COLOR PICKER: Black color detected in final values, using default purple');
                        final defaultPurple = ColorUtility.defaultColor;
                        final safeR = (defaultPurple.r * 255).round();
                        final safeG = (defaultPurple.g * 255).round();
                        final safeB = (defaultPurple.b * 255).round();

                        // Use safe values with proper RGB conversion
                        final safeColor =
                            Color.fromARGB(255, safeR, safeG, safeB);
                        setState(() {
                          _primaryColor = safeColor;
                        });
                        ts.ThemeService.setPrimaryColorDirectly(safeColor);

                        // Create hex string for storage
                        final String storageHex =
                            '#FF${safeR.toRadixString(16).padLeft(2, '0')}${safeG.toRadixString(16).padLeft(2, '0')}${safeB.toRadixString(16).padLeft(2, '0')}'.toUpperCase();
                        DatabaseHelper.instance
                            .saveSetting('primaryColor', storageHex);
                        Navigator.of(context).pop();
                        return;
                      }

                      // CRITICAL FIX: Add extra safeguards against very small values
                      final int safeR = r < 3 ? 0 : r;
                      final int safeG = g < 3 ? 0 : g;
                      final int safeB = b < 3 ? 0 : b;

                      // DIAGNOSTICS: Log post-safety check values
                      Logging.severe(
                          'COLOR PICKER: Post-safety check values: RGB($safeR, $safeG, $safeB)');

                      // Use safe values for the color
                      final Color safeColor =
                          Color.fromARGB(255, safeR, safeG, safeB);

                      // DIAGNOSTICS: Log the Color object values
                      Logging.severe('COLOR PICKER: safeColor object values - '
                          'RGB(${safeColor.r}, ${safeColor.g}, ${safeColor.b}) → '
                          'Int(${(safeColor.r * 255).round()}, ${(safeColor.g * 255).round()}, ${(safeColor.b * 255).round()})');

                      // Create hex string with alpha channel - Use proper values!
                      final String storageHex =
                          '#FF${safeR.toRadixString(16).padLeft(2, '0')}'
                          '${safeG.toRadixString(16).padLeft(2, '0')}'
                          '${safeB.toRadixString(16).padLeft(2, '0')}'.toUpperCase();

                      // DIAGNOSTICS: Log the final hex value that will be stored
                      Logging.severe(
                          'COLOR PICKER: Final hex value for storage: $storageHex');

                      // Update state (UI)
                      setState(() {
                        _primaryColor = safeColor;
                      });

                      // Save to database first
                      DatabaseHelper.instance
                          .saveSetting('primaryColor', storageHex);

                      // CRITICAL: Notify ThemeService and SettingsService listeners
                      ts.ThemeService.setPrimaryColorDirectly(safeColor);
                      ts.ThemeService.notifyGlobalListeners();
                      SettingsService.notifyColorChangeOnly(safeColor);

                      // Close dialog
                      Navigator.of(context).pop();
                    },
                  ),
                ],
              );
            },
          );
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Use AnimatedBuilder to ensure theme changes trigger rebuilds
    return AnimatedBuilder(
      animation: ts.ThemeService.instance,
      builder: (context, _) {
        final pageWidth = MediaQuery.of(context).size.width *
            ts.ThemeService.getContentMaxWidthFactor(context);
        final horizontalPadding =
            (MediaQuery.of(context).size.width - pageWidth) / 2;

        // Get the correct icon color based on theme brightness
        final iconColor = Theme.of(context).brightness == Brightness.dark
            ? Colors.white
            : Colors.black;

        // Log current theme mode for debugging
        Logging.severe(
            'Current theme mode in settings page: ${widget.currentTheme}');

        return Scaffold(
          appBar: AppBar(
            centerTitle: false,
            automaticallyImplyLeading: false,
            leadingWidth: horizontalPadding + 48,
            title: Padding(
              padding: const EdgeInsets.only(left: 8.0),
              child: Text(
                'Settings',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white
                      : Colors.black, // Add explicit color for visibility
                ),
              ),
            ),
            leading: Padding(
              padding: EdgeInsets.only(left: horizontalPadding),
              child: IconButton(
                icon: Icon(Icons.arrow_back, color: iconColor),
                padding: const EdgeInsets.all(8.0),
                constraints: const BoxConstraints(),
                iconSize: 24.0,
                splashRadius: 28.0,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ),
          body: _isProcessing
              ? const Center(child: CircularProgressIndicator())
              : Center(
                  child: SizedBox(
                    width: pageWidth,
                    child: isLoading
                        ? _buildSkeletonSettings()
                        : RefreshIndicator(
                            key: _refreshIndicatorKey,
                            onRefresh: _refreshData,
                            child: ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              children: [
                                // Theme Section
                                Card(
                                  margin: const EdgeInsets.all(8),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Padding(
                                        padding: EdgeInsets.all(16),
                                        child: Text(
                                          'Theme',
                                          style: TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      RadioListTile<ThemeMode>(
                                        title: const Text('System'),
                                        value: ThemeMode.system,
                                        groupValue: widget.currentTheme,
                                        onChanged: (ThemeMode? mode) {
                                          if (mode != null) {
                                            widget.onThemeChanged(mode);
                                            setState(() {});
                                          }
                                        },
                                      ),
                                      RadioListTile<ThemeMode>(
                                        title: const Text('Light'),
                                        value: ThemeMode.light,
                                        groupValue: widget.currentTheme,
                                        onChanged: (ThemeMode? mode) {
                                          if (mode != null) {
                                            widget.onThemeChanged(mode);
                                            setState(() {});
                                          }
                                        },
                                      ),
                                      RadioListTile<ThemeMode>(
                                        title: const Text('Dark'),
                                        value: ThemeMode.dark,
                                        groupValue: widget.currentTheme,
                                        onChanged: (ThemeMode? mode) {
                                          if (mode != null) {
                                            widget.onThemeChanged(mode);
                                            setState(() {});
                                          }
                                        },
                                      ),
                                    ],
                                  ),
                                ),

                                // Color Section
                                Card(
                                  margin: const EdgeInsets.all(8),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.all(16),
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            const Text(
                                              'App Colors',
                                              style: TextStyle(
                                                fontSize: 20,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            IconButton(
                                              icon: const Icon(Icons.restore),
                                              tooltip: 'Restore default colors',
                                              onPressed: () async {
                                                // Update UI first, synchronously
                                                setState(() {
                                                  _primaryColor =
                                                      defaultPurpleColor;
                                                  _useDarkButtonText = false;
                                                });

                                                // Call a separate method to handle all async operations
                                                await _resetColorsToDefault();
                                              },
                                            ),
                                          ],
                                        ),
                                      ),
                                      ListTile(
                                        leading: const Icon(Icons.color_lens),
                                        title: const Text('Primary Color'),
                                        subtitle: const Text(
                                            'Change app accent color'),
                                        trailing: Container(
                                          width: 24,
                                          height: 24,
                                          decoration: BoxDecoration(
                                            color: _primaryColor,
                                            shape: BoxShape.circle,
                                            border:
                                                Border.all(color: Colors.grey),
                                          ),
                                        ),
                                        onTap: _showColorPickerDialog,
                                      ),
                                      ListTile(
                                        title: const Text('Button Text Color'),
                                        trailing: Switch(
                                          value: useDarkText,
                                          thumbIcon: WidgetStateProperty
                                              .resolveWith<Icon?>((states) {
                                            return Icon(
                                              useDarkText
                                                  ? Icons.format_color_text
                                                  : Icons.format_color_reset,
                                              size: 16,
                                              color: useDarkText
                                                  ? Colors.black
                                                  : Colors.white,
                                            );
                                          }),
                                          inactiveTrackColor:
                                              HSLColor.fromColor(
                                                      Theme.of(context)
                                                          .colorScheme
                                                          .primary)
                                                  .withAlpha(0.5)
                                                  .toColor(),
                                          activeTrackColor: Theme.of(context)
                                              .colorScheme
                                              .primary,
                                          activeColor: Colors.black, // When active, always black
                                          inactiveThumbColor: Colors.white, // When inactive, always white
                                          onChanged: (bool value) async {
                                            // Update local state immediately for UI feedback
                                            setState(() {
                                              useDarkText = value;
                                              _useDarkButtonText =
                                                  value; // Also update this variable for the preview
                                            });

                                            // Then save to database and notify services
                                            final settingsService =
                                                SettingsService();
                                            await settingsService.saveSetting(
                                                'useDarkButtonText', value);

                                            // Call the notification method to ensure ThemeService is updated
                                            SettingsService
                                                .notifyButtonTextColorChanged(
                                                    value);
                                          },
                                        ),
                                        subtitle: Text(useDarkText
                                            ? 'Dark text'
                                            : 'Light text'),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.all(16),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const Text('Preview:'),
                                            const SizedBox(height: 8),
                                            Container(
                                              padding: const EdgeInsets.all(16),
                                              decoration: BoxDecoration(
                                                color: Theme.of(context)
                                                    .scaffoldBackgroundColor,
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                border: Border.all(
                                                  color: Theme.of(context)
                                                      .dividerColor,
                                                ),
                                              ),
                                              child: Row(
                                                children: [
                                                  Align(
                                                    alignment:
                                                        Alignment.centerLeft,
                                                    child: SizedBox(
                                                      width: 150,
                                                      child: ElevatedButton(
                                                        style: ElevatedButton
                                                            .styleFrom(
                                                          backgroundColor:
                                                              _primaryColor,
                                                          foregroundColor:
                                                              _useDarkButtonText
                                                                  ? Colors.black
                                                                  : Colors
                                                                      .white,
                                                        ),
                                                        onPressed: () {},
                                                        child: const Text(
                                                            'Sample Text'),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                // Search Preferences Section
                                Card(
                                  margin:
                                      const EdgeInsets.symmetric(vertical: 8.0),
                                  child: Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Search Preferences',
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 16),

                                        // Default search platform dropdown
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const Text(
                                                'Default Search Platform:',
                                                style: TextStyle(
                                                    fontWeight:
                                                        FontWeight.bold)),
                                            const SizedBox(height: 8),
                                            DropdownButton<SearchPlatform>(
                                              isExpanded:
                                                  true, // Make dropdown expand to fill width
                                              value: _defaultSearchPlatform,
                                              underline: Container(),
                                              onChanged:
                                                  (SearchPlatform? platform) {
                                                if (platform != null) {
                                                  _saveDefaultSearchPlatform(
                                                      platform);
                                                }
                                              },
                                              items: [
                                                SearchPlatform.itunes,
                                                SearchPlatform.spotify,
                                                SearchPlatform.deezer,
                                                SearchPlatform.discogs,
                                              ].map((platform) {
                                                return DropdownMenuItem<
                                                    SearchPlatform>(
                                                  value: platform,
                                                  child: Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      SvgPicture.asset(
                                                        _getPlatformIconPath(
                                                            platform),
                                                        width: 30,
                                                        height: 30,
                                                        // Fix icon colors for both themes
                                                        colorFilter: ColorFilter.mode(
                                                            Theme.of(context)
                                                                        .brightness ==
                                                                    Brightness
                                                                        .dark
                                                                ? Colors.white
                                                                : Colors.black,
                                                            BlendMode.srcIn),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Text(
                                                          _getDisplayNameForPlatform(
                                                              platform)),
                                                    ],
                                                  ),
                                                );
                                              }).toList(),
                                            ),
                                            const SizedBox(
                                                height:
                                                    8), // Add bottom spacing
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),

                                // API Keys Section
                                _buildApiKeysSection(),

                                // Data Management Section
                                Card(
                                  margin: const EdgeInsets.all(8),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Padding(
                                        padding: EdgeInsets.all(16),
                                        child: Text(
                                          'Data Management',
                                          style: TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      ListTile(
                                        leading:
                                            const Icon(Icons.file_download),
                                        title: const Text('Import Backup'),
                                        subtitle: const Text(
                                            'Restore data from a backup file'),
                                        onTap: _importBackup,
                                      ),
                                      ListTile(
                                        leading: const Icon(Icons.file_upload),
                                        title: const Text('Export Backup'),
                                        subtitle: const Text(
                                            'Save all your data as a backup file'),
                                        onTap: _exportBackup,
                                      ),
                                      const Divider(),
                                      ListTile(
                                        title: const Text(
                                            'Recover Missing Tracks'),
                                        subtitle: const Text(
                                            'Find and fix albums missing track data'),
                                        leading: const Icon(Icons.construction),
                                        onTap: isLoading
                                            ? null
                                            : _runTrackRecovery,
                                      ),
                                    ],
                                  ),
                                ),

                                // Database Management Section
                                Card(
                                  margin: const EdgeInsets.all(8),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Padding(
                                        padding: EdgeInsets.all(16),
                                        child: Text(
                                          'Database Maintenance',
                                          style: TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      // Move the database size display to here (top of the section)
                                      FutureBuilder<int>(
                                        future: UserData.getDatabaseSize(),
                                        builder: (context, snapshot) {
                                          final size = snapshot.data ?? 0;
                                          final sizeText = size > 0
                                              ? '${(size / 1024 / 1024).toStringAsFixed(2)} MB'
                                              : 'Unknown';

                                          return Padding(
                                            padding: const EdgeInsets.all(16.0),
                                            child: Text(
                                              'Current database size: $sizeText',
                                              style: const TextStyle(
                                                fontStyle: FontStyle.italic,
                                                fontSize: 14,
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                      ListTile(
                                        leading: const Icon(Icons
                                            .storage), // Changed to storage icon
                                        title: const Text(
                                            'Migrate to SQLite Database'),
                                        subtitle: const Text(
                                            'Update database and convert albums to new model format'),
                                        onTap: () async {
                                          final shouldMigrate =
                                              await showDialog<bool>(
                                                    context: context,
                                                    builder: (context) =>
                                                        AlertDialog(
                                                      title: const Text(
                                                          'Database Migration'),
                                                      content: const Text(
                                                        'This will migrate your data to the SQLite database and update album models to the latest format. '
                                                        'This step is required for all users upgrading from older versions.\n\n'
                                                        'The app will show a progress indicator during migration.',
                                                      ),
                                                      actions: [
                                                        TextButton(
                                                          onPressed: () =>
                                                              Navigator.of(
                                                                      context)
                                                                  .pop(false),
                                                          child: const Text(
                                                              'Cancel'),
                                                        ),
                                                        ElevatedButton(
                                                          onPressed: () =>
                                                              Navigator.of(
                                                                      context)
                                                                  .pop(true),
                                                          child: const Text(
                                                              'Migrate'),
                                                        ),
                                                      ],
                                                    ),
                                                  ) ??
                                                  false;

                                          if (shouldMigrate) {
                                            _migrateToSqliteDatabase();
                                          }
                                        },
                                      ),
                                      ListTile(
                                        leading: const Icon(Icons.healing),
                                        title: const Text(
                                            'Fix Platform Duplicates'),
                                        subtitle: const Text(
                                            'Clean up duplicate iTunes/Apple Music entries'),
                                        onTap: _cleanupDuplicates,
                                      ),
                                      ListTile(
                                        leading:
                                            const Icon(Icons.rocket_launch),
                                        title: const Text('Optimize Database'),
                                        subtitle: const Text(
                                            'Clean and optimize the database for better performance'),
                                        onTap: _performDatabaseMaintenance,
                                      ),
                                      ListTile(
                                        leading: const Icon(Icons
                                            .update), // or Icons.sync_alt, Icons.upgrade, Icons.format_paint
                                        title: const Text(
                                            'Convert Albums to New Format'),
                                        subtitle: const Text(
                                            'Update album data for compatibility'),
                                        onTap: () async {
                                          final confirmed = await showDialog<bool>(
                                            context: context,
                                            builder: (context) => AlertDialog(
                                              title:
                                                  const Text('Convert Albums?'),
                                              content: const Text(
                                                  'This will update album data to the latest format for compatibility. '
                                                  'This operation is safe but might take some time for large libraries.'),
                                              actions: [
                                                TextButton(
                                                  onPressed: () =>
                                                      Navigator.of(context)
                                                          .pop(false),
                                                  child: const Text('Cancel'),
                                                ),
                                                TextButton(
                                                  onPressed: () =>
                                                      Navigator.of(context)
                                                          .pop(true),
                                                  child: const Text('Convert'),
                                                ),
                                              ],
                                            ),
                                          );

                                          if (confirmed == true) {
                                            setState(() {
                                              isLoading = true;
                                            });

                                            try {
                                              final migratedCount = await AlbumMigrationUtility.migrateAlbumFormats();
                                              if (!mounted) return;
                                              _showAlbumConversionSuccessSnackBar(
                                                  'Successfully converted $migratedCount albums to new format!');
                                            } catch (e) {
                                              Logging.severe('Error converting albums', e);
                                              if (!mounted) return;
                                              _showAlbumConversionErrorSnackBar('Error converting albums: $e');
                                            } finally {
                                              if (mounted) {
                                                setState(() {
                                                  isLoading = false;
                                                });
                                              }
                                            }
                                          }
                                        },
                                      ),
                                      ListTile(
                                        leading: SvgPicture.asset(
                                          'lib/icons/bandcamp.svg',
                                          width: 24,
                                          height: 24,
                                          colorFilter: ColorFilter.mode(
                                            Theme.of(context).brightness ==
                                                    Brightness.dark
                                                ? Colors.white
                                                : Colors.black,
                                            BlendMode.srcIn,
                                          ),
                                        ),
                                        title: const Text(
                                            'Update Bandcamp Albums'),
                                        subtitle: const Text(
                                            'Refresh track data for Bandcamp albums'),
                                        onTap: _fixBandcampTrackIds,
                                      ),
                                      // Add the Fix Album Dates option right after the Bandcamp fix
                                      ListTile(
                                        leading:
                                            const Icon(Icons.calendar_today),
                                        title: const Text(
                                            'Fix Album Release Dates'),
                                        subtitle: const Text(
                                          'Fix missing or incorrect release dates for albums',
                                        ),
                                        onTap: () async {
                                          // Store the BuildContext before async operations
                                          final currentContext = context;

                                          // Store a reference to the ScaffoldMessenger before async gap
                                          final scaffoldMessenger =
                                              ScaffoldMessenger.of(
                                                  currentContext);

                                          final results = await DateFixerUtility
                                              .runWithDialog(
                                            currentContext,
                                            onlyDeezer: true,
                                            onlyMissingDates: true,
                                          );

                                          // Check if still mounted before accessing scaffold messenger
                                          if (mounted) {
                                            scaffoldMessenger.showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                    'Date fixing completed: ${results.fixed} albums fixed, '
                                                    '${results.failed} failed, ${results.skipped} skipped'),
                                                duration:
                                                    const Duration(seconds: 5),
                                              ),
                                            );
                                          }
                                        },
                                      ),
                                      ListTile(
                                        leading: const Icon(Icons
                                            .cleaning_services), // Cleaning icon
                                        title: const Text(
                                            'Clean Platform Matches'),
                                        subtitle: const Text(
                                            'Find and fix incorrect platform links'),
                                        onTap: () {
                                          Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (context) =>
                                                  const PlatformMatchCleanerWidget(),
                                            ),
                                          );
                                        },
                                      ),
                                      ListTile(
                                        leading: Icon(
                                          Icons.warning_amber_rounded,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .error,
                                        ),
                                        title: const Text('Emergency Reset'),
                                        subtitle: const Text(
                                            'Reset database connection if problems occur'),
                                        onTap: _performEmergencyDatabaseReset,
                                      ),
                                      const Divider(height: 32),
                                    ],
                                  ),
                                ),

                                // Debug & Development Section
                                Card(
                                  margin: const EdgeInsets.all(8),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Padding(
                                        padding: EdgeInsets.all(16),
                                        child: Text(
                                          'Debug & Development',
                                          style: TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      // Add About option
                                      ListTile(
                                        leading: const Icon(Icons.info_outline),
                                        title: const Text('About Rate Me!'),
                                        subtitle: const Text(
                                            'View app information and links'),
                                        onTap: () => _showAboutDialog(context),
                                      ),
                                      ListTile(
                                        leading: const Icon(Icons.bug_report),
                                        title: const Text('Show Debug Info'),
                                        subtitle: const Text(
                                            'View technical information'),
                                        onTap: () =>
                                            DebugUtil.showDebugReport(context),
                                      ),
                                      ListTile(
                                        leading: Icon(
                                          Icons.delete_forever,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .error,
                                        ),
                                        title: const Text('Clear Database'),
                                        subtitle: const Text(
                                            'Delete all saved data (cannot be undone)'),
                                        onTap: () => _showClearDatabaseDialog(),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                  ),
                ),
        );
      },
    );
  }

  Widget _buildSkeletonSettings() {
    return ListView(
      children: [
        // Theme section skeleton
        Card(
          margin: const EdgeInsets.all(8),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SkeletonLoading(width: 80, height: 24),
                const SizedBox(height: 16),
                ...List.generate(
                  3,
                  (index) => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8.0),
                    child: SkeletonLoading(height: 40),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Colors section skeleton
        Card(
          margin: const EdgeInsets.all(8),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SkeletonLoading(width: 120, height: 24),
                const SizedBox(height: 16),
                ...List.generate(
                  2,
                  (index) => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        SkeletonLoading(width: 120, height: 20),
                        SkeletonLoading(
                            width: 40, height: 40, borderRadius: 20),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Data Management section skeleton
        Card(
          margin: const EdgeInsets.all(8),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SkeletonLoading(width: 150, height: 24),
                const SizedBox(height: 16),
                ...List.generate(
                  3,
                  (index) => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12.0),
                    child: SkeletonLoading(height: 48),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Database Management section skeleton
        Card(
          margin: const EdgeInsets.all(8),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SkeletonLoading(width: 150, height: 24),
                const SizedBox(height: 16),
                ...List.generate(
                  2,
                  (index) => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12.0),
                    child: SkeletonLoading(height: 48),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Debug & Development section skeleton
        Card(
          margin: const EdgeInsets.all(8),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SkeletonLoading(width: 150, height: 24),
                const SizedBox(height: 16),
                ...List.generate(
                  3,
                  (index) => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12.0),
                    child: SkeletonLoading(height: 48),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // Add this method to show the About dialog
  void _showAboutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('About Rate Me!', textAlign: TextAlign.center),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Text(
              'Rate Me! is an open-source music rating app that helps you track and organize your album listening experience.',
              style: TextStyle(fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            // Use VersionInfo to display version number with the full version string
            Text('Version: ${VersionInfo.fullVersionString}',
                textAlign: TextAlign.center),
            const SizedBox(height: 24),

            // Cleaner sponsor section with a more elegant button - LIGHTER BACKGROUND using shade100
            ElevatedButton.icon(
              onPressed: () async {
                final url = Uri.parse('https://github.com/sponsors/ALi3naTEd0');
                if (await canLaunchUrl(url)) {
                  await launchUrl(url, mode: LaunchMode.externalApplication);
                } else {
                  Logging.severe('Could not launch $url');
                }
              },
              icon: const Icon(Icons.favorite, color: Colors.pink),
              label: const Text('Sponsor This Project',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                foregroundColor: Colors.pink.shade700,
                backgroundColor: Colors
                    .pink.shade100, // Changed to shade100 for better contrast
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),

            const SizedBox(height: 24),
            const Text('Links:',
                style: TextStyle(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Center(
              child: InkWell(
                onTap: () async {
                  // Fixed URL - added /RateMe to repository URL
                  final url = Uri.parse('https://github.com/ALi3naTEd0/RateMe');
                  if (await canLaunchUrl(url)) {
                    await launchUrl(url, mode: LaunchMode.externalApplication);
                  } else {
                    Logging.severe('Could not launch $url');
                  }
                },
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.code, size: 16),
                    SizedBox(width: 8),
                    Text(
                      'GitHub Repository',
                      style: TextStyle(
                        color: Colors.blue,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: InkWell(
                onTap: () async {
                  final url = Uri.parse('https://ali3nated0.github.io/RateMe/');
                  if (await canLaunchUrl(url)) {
                    await launchUrl(url, mode: LaunchMode.externalApplication);
                  } else {
                    Logging.severe('Could not launch $url');
                  }
                },
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.language, size: 16),
                    SizedBox(width: 8),
                    Text(
                      'Visit Website',
                      style: TextStyle(
                        color: Colors.blue,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '© 2025 ALi3naTEd0',
              style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  // Add these helper methods to your class:
  void _showAlbumConversionSuccessSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _showAlbumConversionErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _resetColorsToDefault() async {
    try {
      // Log the start of the reset operation
      Logging.severe('RESET COLORS: Starting color reset to default purple');

      // Create the correct purple color directly
      final Color correctPurpleColor = const Color(0xFF864AF9);
      // Calculate integer RGB values from the Color object
      final int r = (correctPurpleColor.r * 255).round();
      final int g = (correctPurpleColor.g * 255).round();
      final int b = (correctPurpleColor.b * 255).round();

      // First update the UI state for immediate feedback
      setState(() {
        _primaryColor = correctPurpleColor;
        _useDarkButtonText = false;
        useDarkText = false;
      });

      // Create properly formatted hex string with correct values
      final String colorHex =
          '#FF${r.toRadixString(16).padLeft(2, '0')}${g.toRadixString(16).padLeft(2, '0')}${b.toRadixString(16).padLeft(2, '0')}'
              .toUpperCase();

      // CRITICAL FIX: Add extra debugging to verify the actual color values
      Logging.severe(
          'RESET COLORS: Purple color - RGB($r,$g,$b) → Hex: $colorHex');

      // Save directly to database first
      await DatabaseHelper.instance.saveSetting('primaryColor', colorHex);

      // Then reset the button text color to "light" (false)
      await DatabaseHelper.instance.saveSetting('useDarkButtonText', 'false');

      // Ensure ThemeService gets the direct update with a fresh color instance
      // IMPORTANT: Create a completely new color instance with explicit integer values
      final freshPurpleColor = Color.fromARGB(255, r, g, b);

      // Notify UI about the color change with the fresh color instance - directly use the service
      ts.ThemeService.setPrimaryColorDirectly(freshPurpleColor);

      // Only after the ThemeService has been updated, notify SettingsService
      // This changes the order of operations to avoid race conditions
      SettingsService.notifyColorChangeOnly(freshPurpleColor);

      // Notify about button text color change
      SettingsService.notifyButtonTextColorChanged(false);

      // Show confirmation
      if (mounted) {
        _showSnackBar('Restored default colors');
      }

      Logging.severe('RESET COLORS: Color reset completed successfully');
    } catch (e) {
      Logging.severe('Error resetting colors to default: $e');
      if (mounted) {
        _showSnackBar('Error restoring default colors: $e');
      }
    }
  }

  // Add this new section to your settings page build method
  Widget _buildApiKeysSection() {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.vpn_key, size: 22),
                SizedBox(width: 8),
                Text(
                  'API Keys',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Configure API keys for external services',
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).textTheme.bodySmall?.color,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.grey.shade800
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Theme.of(context).dividerColor,
                  width: 0.5,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Rate Me! works with Apple Music and Deezer without requiring any configuration.',
                    style: TextStyle(fontSize: 13),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'To use Spotify or Discogs, you need to provide your own API credentials. Without these keys, features like platform matching will only work with Apple Music and Deezer.',
                    style: TextStyle(fontSize: 13),
                  ),
                  SizedBox(height: 12),
                  Text(
                    'How to set up API keys:',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.only(left: 8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            '1. Register/login at the service\'s developer portal',
                            style: TextStyle(fontSize: 13)),
                        Text('2. Create a new application',
                            style: TextStyle(fontSize: 13)),
                        Text('3. Name your app (e.g., "Rate Me!")',
                            style: TextStyle(fontSize: 13)),
                        Text('4. Copy the provided credentials',
                            style: TextStyle(fontSize: 13)),
                        Text('5. Paste them in the fields below',
                            style: TextStyle(fontSize: 13)),
                      ],
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'The app will guide you to the correct developer websites when you click on each service below.',
                    style: TextStyle(fontSize: 13, fontStyle: FontStyle.italic),
                  ),
                  SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        'Need more info?',
                        style: TextStyle(
                            fontSize: 13, fontStyle: FontStyle.italic),
                      ),
                      SizedBox(width: 4),
                      Material(
                        color: Colors.transparent,
                        shape: CircleBorder(),
                        clipBehavior: Clip.antiAlias,
                        child: IconButton(
                          icon: Icon(
                            Icons.help_outline,
                            size: 20,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          constraints:
                              BoxConstraints(minWidth: 36, minHeight: 36),
                          padding: EdgeInsets.zero,
                          tooltip: 'More information about API keys',
                          onPressed: () => _showApiKeysInfoDialog(context),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            FutureBuilder<String?>(
                future: ApiKeys.spotifyClientId,
                builder: (context, snapshot) {
                  final hasKeys = snapshot.hasData &&
                      snapshot.data != null &&
                      snapshot.data!.isNotEmpty;
                  return ListTile(
                    leading: SvgPicture.asset(
                      'lib/icons/spotify.svg',
                      width: 24,
                      height: 24,
                      colorFilter: ColorFilter.mode(
                        Theme.of(context).brightness == Brightness.dark
                            ? Colors.white
                            : Colors.black,
                        BlendMode.srcIn,
                      ),
                    ),
                    title: Text('Spotify API Keys'),
                    subtitle: Text(
                        hasKeys ? 'Connected' : 'Required for Spotify search'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (hasKeys)
                          Padding(
                            padding: const EdgeInsets.only(right: 8.0),
                            child: Icon(
                              Icons.check_circle,
                              color: Colors.green,
                              size: 18,
                            ),
                          ),
                        Icon(Icons.keyboard_arrow_right),
                      ],
                    ),
                    onTap: () => _showSpotifyApiKeyDialog(),
                  );
                }),
            Divider(),
            FutureBuilder<String?>(
                future: ApiKeys.discogsConsumerKey,
                builder: (context, snapshot) {
                  final hasKeys = snapshot.hasData &&
                      snapshot.data != null &&
                      snapshot.data!.isNotEmpty;
                  return ListTile(
                    leading: SvgPicture.asset(
                      'lib/icons/discogs.svg',
                      width: 24,
                      height: 24,
                      colorFilter: ColorFilter.mode(
                        Theme.of(context).brightness == Brightness.dark
                            ? Colors.white
                            : Colors.black,
                        BlendMode.srcIn,
                      ),
                    ),
                    title: Text('Discogs API Keys'),
                    subtitle: Text(
                        hasKeys ? 'Connected' : 'Required for Discogs search'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (hasKeys)
                          Padding(
                            padding: const EdgeInsets.only(right: 8.0),
                            child: Icon(
                              Icons.check_circle,
                              color: Colors.green,
                              size: 18,
                            ),
                          ),
                        Icon(Icons.keyboard_arrow_right),
                      ],
                    ),
                    onTap: () => _showDiscogsApiKeyDialog(),
                  );
                }),
            Divider(),
          ],
        ),
      ),
    );
  }

  // Update your existing dialogs to refresh UI after saving keys
  Future<void> _showSpotifyApiKeyDialog() async {
    String? clientId = await ApiKeys.spotifyClientId;
    String? clientSecret = await ApiKeys.spotifyClientSecret;

    if (!mounted) return;

    final clientIdController = TextEditingController(text: clientId);
    final clientSecretController = TextEditingController(text: clientSecret);

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Spotify API Keys'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Get your Spotify API keys from the Spotify Developer Dashboard:',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 8),
              InkWell(
                onTap: () =>
                    _launchUrl('https://developer.spotify.com/dashboard/'),
                child: Text(
                  'developer.spotify.com/dashboard',
                  style: TextStyle(
                    color: Colors.blue,
                    decoration: TextDecoration.underline,
                                   ),
                ),
              ),
                                                     const SizedBox(height: 16),
              // Add guidance about the callback URL
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.grey.shade800
                      : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Theme.of(context).dividerColor),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Important setup note:',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'When creating your Spotify app, you need to add this Redirect URI:',
                      style: TextStyle(fontSize: 13),
                    ),
                    SizedBox(height: 8),
                    Container(
                      padding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.grey.shade900
                            : Colors.white,
                        borderRadius: BorderRadius.circular(4),
                        border:
                            Border.all(color: Theme.of(context).dividerColor),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'https://ali3nated0.github.io/RateMe/callback/',
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.copy, size: 16),
                            padding: EdgeInsets.zero,
                            constraints: BoxConstraints(
                              minWidth: 24,
                              minHeight: 24,
                            ),
                            onPressed: () {
                              Clipboard.setData(
                                ClipboardData(
                                  text:
                                      'https://ali3nated0.github.io/RateMe/callback/',
                                ),
                              );
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('URL copied to clipboard'),
                                  duration: Duration(seconds: 1),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Note: This URL is just for registration purposes. The app uses client credentials flow which doesn\'t require a real callback.',
                      style:
                          TextStyle(fontSize: 11, fontStyle: FontStyle.italic),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: clientIdController,
                decoration: InputDecoration(
                  labelText: 'Client ID',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: clientSecretController,
                decoration: InputDecoration(
                  labelText: 'Client Secret',
                  border: OutlineInputBorder(),
                ),
                obscureText: true, // Hide the secret
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final id = clientIdController.text.trim();
              final secret = clientSecretController.text.trim();

              if (id.isEmpty && secret.isEmpty) {
                // Remove keys if both are empty
                await ApiKeyManager.instance.deleteApiKey('spotify');

                if (!mounted) return;

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Spotify API keys removed')),
                );
                Navigator.of(context).pop();
                return;
              }

              if (id.isEmpty || secret.isEmpty) {
                if (!mounted) return;

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content: Text(
                          'Please enter both Client ID and Client Secret')),
                );
                return;
              }

              // Test the credentials
              final isValid = await ApiKeys.testSpotifyCredentials(id, secret);

              if (!mounted) return;

              if (isValid) {
                // Save the valid credentials
                await ApiKeys.saveSpotifyKeys(id, secret);

                if (!mounted) return;

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content: Text('Spotify API keys verified and saved')),
                );
                Navigator.of(context).pop();
              } else {
                if (!mounted) return;

                // Show error but don't dismiss dialog
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                        'Invalid Spotify credentials. Please check and try again.'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: Text('Save'),
          ),
        ],
      ),
    );

    // After saving keys, refresh the state to update status indicators
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _showDiscogsApiKeyDialog() async {
    String? consumerKey = await ApiKeys.discogsConsumerKey;
    String? consumerSecret = await ApiKeys.discogsConsumerSecret;

    if (!mounted) return;

    final consumerKeyController = TextEditingController(text: consumerKey);
    final consumerSecretController =
        TextEditingController(text: consumerSecret);

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (builderContext, setDialogState) => AlertDialog(
          title: Text('Discogs API Keys'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Get your Discogs API keys from your Discogs Developer Settings:',
                  style: TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 8),
                InkWell(
                  onTap: () =>
                      _launchUrl('https://www.discogs.com/settings/developers'),
                  child: Text(
                    'discogs.com/settings/developers',
                    style: TextStyle(
                      color: Colors.blue,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: consumerKeyController,
                  decoration: InputDecoration(
                    labelText: 'Consumer Key',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: consumerSecretController,
                  decoration: InputDecoration(
                    labelText: 'Consumer Secret',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                final key = consumerKeyController.text.trim();
                final secret = consumerSecretController.text.trim();

                if (key.isNotEmpty && secret.isNotEmpty) {
                  await ApiKeys.saveDiscogsKeys(key, secret);

                  if (!mounted) return;

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Discogs API keys saved')),
                  );
                } else if (key.isEmpty && secret.isEmpty) {
                  // Remove keys if both are empty
                  await ApiKeyManager.instance.deleteApiKey('discogs');

                  if (!mounted) return;

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Discogs API keys removed')),
                  );
                } else {
                  if (!mounted) return;

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text(
                            'Please enter both Consumer Key and Consumer Secret')),
                  );
                  return;
                }

                if (!mounted) return;

                Navigator.of(context).pop();
              },
              child: Text('Save'),
            ),
          ],
        ),
      ),
    );

    // After saving keys, refresh the state to update status indicators
    if (mounted) {
      setState(() {});
    }
  }

  void _launchUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      await launchUrl(uri);
    } catch (e) {
      Logging.severe('Error launching URL: $e');
    }
  }

  void _showApiKeysInfoDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('About API Keys', textAlign: TextAlign.center),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Why do I need API keys?',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              SizedBox(height: 8),
              Text(
                'Different music services have different approaches to API access:',
                style: TextStyle(fontSize: 14),
              ),
              SizedBox(height: 12),

              // Apple Music & Deezer
              Text('Apple Music & Deezer:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              Padding(
                padding:
                    const EdgeInsets.only(left: 12.0, top: 4.0, bottom: 8.0),
                child: Text(
                  '• Provide public APIs that don\'t require authentication\n'
                  '• Allow reasonable usage without registration or API keys\n'
                  '• Work out-of-the-box in Rate Me!',
                  style: TextStyle(fontSize: 14),
                ),
              ),

              // Spotify & Discogs
              Text('Spotify & Discogs:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              Padding(
                padding:
                    const EdgeInsets.only(left: 12.0, top: 4.0, bottom: 8.0),
                child: Text(
                  '• Require developer registration\n'
                  '• Need API keys for all operations\n'
                  '• Provide more functionality but require setup',
                  style: TextStyle(fontSize: 14),
                ),
              ),

              Divider(),
              SizedBox(height: 8),
              Text(
                'Setting up keys is simple and free. The app will guide you to the correct developer websites when you click on each service.',
                style: TextStyle(fontSize: 14),
              ),
              SizedBox(height: 16),
              Text(
                'Features like platform matching (finding the same album on different services) work best when you have all services configured.',
                style: TextStyle(fontSize: 14, fontStyle: FontStyle.italic),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Got it'),
          ),
        ],
      ),
    );
  }

  Future<void> _runTrackRecovery() async {
    setState(() {
      isLoading = true;
    });

    // Store context before async operation
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    scaffoldMessenger.showSnackBar(
      const SnackBar(content: Text('Starting track recovery process...')),
    );

    try {
      await TrackRecoveryUtility.runFullRecovery();

      // Check if widget is still mounted before using context
      if (!mounted) return;

      scaffoldMessenger.showSnackBar(
        const SnackBar(content: Text('Track recovery completed!')),
      );
    } catch (e) {
      // Check if widget is still mounted before using context
      if (!mounted) return;

      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('Error recovering tracks: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }
}

// Fix the ColorExtension implementation to use integer value before calling toRadixString
extension ColorExtension on Color {
  String toHex() {
    // Convert to integers first, then to hex string
    final aHex = a.round().toRadixString(16).padLeft(2, '0');
    final rHex = r.round().toRadixString(16).padLeft(2, '0');
    final gHex = g.round().toRadixString(16).padLeft(2, '0');
    final bHex = b.round().toRadixString(16).padLeft(2, '0');

    return '$aHex$rHex$gHex$bHex';
  }
}

// Add this formatter to force uppercase letters for hex input
class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}
