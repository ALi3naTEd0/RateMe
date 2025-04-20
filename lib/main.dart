import 'package:flutter/material.dart';
import 'dart:async';
import 'saved_ratings_page.dart';
import 'logging.dart';
import 'details_page.dart';
import 'search_service.dart';
import 'settings_service.dart';
import 'user_data.dart';
import 'custom_lists_page.dart';
import 'footer.dart';
import 'settings_page.dart';
import 'platform_ui.dart';
import 'database/database_helper.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'global_notifications.dart';
import 'clipboard_detector.dart';
import 'preferences_migration.dart';
import 'database/migration_utility.dart';
import 'database/cleanup_utility.dart';
import 'theme_service.dart' as ts;
import 'color_utility.dart';

void main() async {
  // Ensure Flutter is initialized
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize logging
  Logging.initialize();

  // Initialize the database first
  await DatabaseHelper.initialize();

  // CRITICAL FIX: Check if color is corrupted on startup and fix it
  await _validateAndFixColorIfNeeded();

  // Check if migration is needed
  final migrationCompleted = await MigrationUtility.isMigrationCompleted();
  if (!migrationCompleted) {
    Logging.severe(
        'Database migration not completed. User can run from Settings.');
  }

  // Migrate any remaining preferences
  await PreferencesMigration.migrateRemainingPreferences();

  // Initialize theme service
  await ts.ThemeService.initialize();

  // Log the theme mode after initialization to verify it's correct
  Logging.severe(
      'Initial theme mode after initialization: ${ts.ThemeService.themeMode}');

  // Run the app
  runApp(const MyApp());

  // Log app startup
  Logging.severe('Application started');
}

/// Validate and fix the primary color if it's missing or corrupted
Future<void> _validateAndFixColorIfNeeded() async {
  try {
    // Directly access database for maximum reliability
    final db = await DatabaseHelper.instance.database;

    // Get the raw color value first to diagnose the issue
    final colorRows = await db
        .query('settings', where: 'key = ?', whereArgs: ['primaryColor']);
    final colorStr =
        colorRows.isNotEmpty ? colorRows.first['value'] as String? : null;

    Logging.severe('STARTUP COLOR CHECK: Current color in database: $colorStr');

    // CRITICAL FIX: Better detection for corrupted colors:
    // 1. Delete settings if it's black OR has a corrupted format
    // 2. Force the default purple color with direct SQL to avoid any translation issues
    if (colorStr == null ||
        colorStr.isEmpty ||
        colorStr == '#FF000000' ||
        colorStr == '#FF000001' ||
        colorStr == '#FF010001' ||
        colorStr == '#FF000100' ||
        colorStr == '#FF010100') {
      Logging.severe(
          'STARTUP COLOR CHECK: Detected missing or corrupted color - resetting to default purple');

      // Delete any existing primaryColor setting first to ensure clean state
      await db
          .delete('settings', where: 'key = ?', whereArgs: ['primaryColor']);

      // Insert the correct default purple directly
      await db
          .insert('settings', {'key': 'primaryColor', 'value': '#FF864AF9'});

      // Verify the direct insertion worked
      final verifyRows = await db
          .query('settings', where: 'key = ?', whereArgs: ['primaryColor']);
      final verifiedColor =
          verifyRows.isNotEmpty ? verifyRows.first['value'] as String? : null;

      Logging.severe('STARTUP COLOR CHECK: Reset result: $verifiedColor');
    } else {
      // Even if the color looks valid, verify it can be parsed
      try {
        final color = ColorUtility.hexToColor(colorStr);
        final colorHex = ColorUtility.colorToHex(color);
        Logging.severe('STARTUP COLOR CHECK: Verified valid color: $colorHex');
      } catch (e) {
        Logging.severe(
            'STARTUP COLOR CHECK: Error parsing color, resetting to default: $e');

        // Handle any parsing errors by resetting to default
        await db
            .delete('settings', where: 'key = ?', whereArgs: ['primaryColor']);
        await db
            .insert('settings', {'key': 'primaryColor', 'value': '#FF864AF9'});
      }
    }
  } catch (e) {
    Logging.severe('Error validating color at startup: $e');
  }
}

class MyApp extends StatefulWidget {
  final bool showMigrationPrompt;
  const MyApp({
    super.key,
    this.showMigrationPrompt = false,
  });

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  ThemeMode _themeMode = ThemeMode.system;
  // Set the correct default purple color
  static const Color defaultPurpleColor = Color(0xFF864AF9);
  Color _primaryColor = defaultPurpleColor;
  final TextEditingController searchController = TextEditingController();
  List<Map<String, dynamic>> searchResults = [];
  bool _isLoading = false;
  Timer? _debounce;
  Timer? _clipboardTimer;
  SearchPlatform _selectedSearchPlatform = SearchPlatform.itunes;
  final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();

    // Fix: Set ThemeMode and Color directly from ThemeService right at initState
    _themeMode = ts.ThemeService.themeMode;
    _primaryColor = ts.ThemeService.primaryColor;

    // Add this tracking of changes to the theme mode and color during initialization
    Logging.severe(
        'MAIN: initState - Setting initial ThemeMode to: $_themeMode');
    Logging.severe(
        'MAIN: initState - Setting initial PrimaryColor to: $_primaryColor (${_colorToHex(_primaryColor)})');

    _loadTheme();

    // Add a listener to ensure ThemeService changes are applied
    ts.ThemeService.addListener(_themeListener);

    _loadSettings();
    _startClipboardDetection();
    _loadSearchPlatform();
    _setupGlobalListeners();
    if (widget.showMigrationPrompt) {
      Future.delayed(const Duration(seconds: 2), () {
        _showMigrationPrompt();
      });
    }
    _setupNotificationListener();

    // Register for theme changes
    SettingsService.addThemeListener((mode, color) {
      if (mounted) {
        setState(() {
          _themeMode = mode;
          _primaryColor = color;
        });
      }
    });

    _loadTheme();

    // Set up separate listeners for theme changes vs color changes
    SettingsService.addThemeListener((mode, color) {
      if (mounted) {
        setState(() {
          _themeMode = mode;
          // Also update the color since the API requires it
          _primaryColor = color;
        });
      }
    });

    // Add color-specific listener
    SettingsService.addPrimaryColorListener((color) {
      if (mounted) {
        setState(() {
          _primaryColor = color;
        });
      }
    });

    // Add a listener to ThemeService to update when theme changes
    ts.ThemeService.addListener((mode, color) {
      if (mounted) {
        setState(() {
          _themeMode = mode;
          _primaryColor = color;
        });
        Logging.severe('Theme updated via listener: mode=$mode, color=$color');
      }
    });
  }

  void _setupGlobalListeners() {
    GlobalNotifications.onSearchPlatformChanged.listen((platform) {
      if (_selectedSearchPlatform != platform) {
        Logging.severe('Default search platform changed to: ${platform.name}');
        setState(() {
          _selectedSearchPlatform = platform;
        });
        final currentQuery = searchController.text.trim();
        if (currentQuery.isNotEmpty) {
          Future.delayed(const Duration(milliseconds: 100), () {
            _performSearch(currentQuery);
          });
        }
      }
    });
  }

  Future<void> _loadSettings() async {
    try {
      final db = DatabaseHelper.instance;
      final themeModeStr = await db.getSetting('themeMode');
      ThemeMode mode = ThemeMode.system;
      if (themeModeStr != null) {
        final modeIndex = int.tryParse(themeModeStr);
        if (modeIndex != null && modeIndex < ThemeMode.values.length) {
          mode = ThemeMode.values[modeIndex];
        }
      }
      final colorStr = await db.getSetting('primaryColor');
      Color primaryColor = const Color(0xFF864AF9);
      if (colorStr != null) {
        final colorValue = int.tryParse(colorStr);
        if (colorValue != null) {
          primaryColor = Color(colorValue);
        }
      }
      await _loadSearchPlatform();
      setState(() {
        _themeMode = mode;
        _primaryColor = primaryColor;
      });
    } catch (e) {
      Logging.severe('Error loading settings', e);
    }
  }

  void _updateTheme(ThemeMode mode) {
    ts.ThemeService.setThemeMode(mode);
    setState(() {
      _themeMode = mode;
    });
  }

  void _updatePrimaryColor(Color color) {
    // Set ThemeService color first
    ts.ThemeService.setPrimaryColor(color);

    // Then update the local state variable
    setState(() {
      _primaryColor = color;
    });
  }

  Future<void> _loadSearchPlatform() async {
    try {
      final db = DatabaseHelper.instance;
      final platformStr = await db.getSetting('default_search_platform');
      if (platformStr != null) {
        final platformIndex = int.tryParse(platformStr);
        if (platformIndex != null &&
            platformIndex < SearchPlatform.values.length) {
          if (mounted) {
            setState(() {
              _selectedSearchPlatform = SearchPlatform.values[platformIndex];
            });
            Logging.severe(
                'Loaded default search platform: ${_selectedSearchPlatform.name}');
          }
        }
      }
    } catch (e) {
      Logging.severe('Error loading search platform', e);
    }
  }

  void _updateSearchPlatform(SearchPlatform platform) async {
    try {
      setState(() {
        _selectedSearchPlatform = platform;
      });
      final currentQuery = searchController.text.trim();
      if (currentQuery.isNotEmpty) {
        Future.delayed(const Duration(milliseconds: 100), () {
          _performSearch(currentQuery);
        });
      }
    } catch (e) {
      Logging.severe('Error updating search platform', e);
    }
  }

  Future<void> _performSearch(String query) async {
    if (query.isEmpty) {
      setState(() => searchResults = []);
      ClipboardDetector.reportSearchResult(false);
      return;
    }
    setState(() => _isLoading = true);
    try {
      final results =
          await SearchService.searchAlbum(query, _selectedSearchPlatform);
      if (mounted) {
        setState(() {
          if (results != null && results['results'] != null) {
            searchResults = List<Map<String, dynamic>>.from(results['results']);
            ClipboardDetector.reportSearchResult(searchResults.isNotEmpty);
          } else {
            searchResults = [];
            ClipboardDetector.reportSearchResult(false);
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          searchResults = [];
          _isLoading = false;
        });
        Logging.severe('Error performing search', e);
        ClipboardDetector.reportSearchResult(false);
      }
    }
  }

  void _startClipboardDetection() {
    _clipboardTimer = ClipboardDetector.startClipboardListener(
      onDetected: (text) {
        if (searchController.text.isEmpty &&
            !text.toLowerCase().contains('http')) {
          setState(() {
            searchController.text = text;
            _performSearch(text);
          });
        }
      },
      onUrlDetected: (url, searchQuery) {
        if (searchController.text.isEmpty) {
          setState(() {
            searchController.text = url;
            _performSearch(searchQuery);
          });
        }
      },
      onSnackBarMessage: (message) {
        scaffoldMessengerKey.currentState?.showSnackBar(
          SnackBar(content: Text(message)),
        );
      },
      onSearchCompleted: (success) {
        ClipboardDetector.reportSearchResult(success);
      },
    );
  }

  void _showMigrationPrompt() {
    if (!mounted) return;
    scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: const Text(
            'New database format available. Upgrade your data for better performance!'),
        action: SnackBarAction(
          label: 'Upgrade',
          onPressed: () {
            navigatorKey.currentState?.push(
              MaterialPageRoute(
                builder: (context) => SettingsPage(
                  currentTheme: _themeMode,
                  onThemeChanged: _updateTheme,
                  currentPrimaryColor: _primaryColor,
                  onPrimaryColorChanged: _updatePrimaryColor,
                ),
              ),
            );
          },
        ),
        duration: const Duration(seconds: 10),
      ),
    );
  }

  // Modify the setupNotificationListener method to preserve theme mode
  void _setupNotificationListener() {
    SettingsService.addThemeListener((mode, color) {
      if (mounted) {
        setState(() {
          // Only update theme mode if it's different from current
          // This prevents the color changes from affecting theme mode
          if (mode != _themeMode) {
            _themeMode = mode;
            Logging.severe('Theme mode updated to: $_themeMode');
          }

          // Always update color
          _primaryColor = color;
          Logging.severe('Primary color updated to: $_primaryColor');
        });
      }
    });
  }

  // Modify the _loadTheme method to ensure the opacity is always enforced
  Future<void> _loadTheme() async {
    try {
      final prevMode = _themeMode; // Store previous mode for comparison

      // Update state with ThemeService values
      setState(() {
        _themeMode = ts.ThemeService.themeMode;
        _primaryColor = ts.ThemeService.primaryColor;
        Logging.severe(
            'MAIN: _loadTheme - Loaded PrimaryColor: ${_colorToHex(_primaryColor)}');
      });

      // Log any changes in theme mode
      if (prevMode != _themeMode) {
        Logging.severe('Theme mode changed from $prevMode to $_themeMode');
      } else {
        Logging.severe('Theme mode remains $_themeMode');
      }

      Logging.severe(
          'USING COLOR FOR THEME: $_primaryColor (RGB: ${_primaryColor.r}, ${_primaryColor.g}, ${_primaryColor.b})');
    } catch (e) {
      Logging.severe('Error loading theme: $e');
    }
  }

  @override
  void dispose() {
    _clipboardTimer?.cancel();
    ClipboardDetector.stopClipboardListener();
    searchController.dispose();
    _debounce?.cancel();
    GlobalNotifications.dispose();

    ts.ThemeService.removeListener(_themeListener);

    super.dispose();
  }

  void _themeListener(ThemeMode mode, Color color) {
    if (mounted) {
      setState(() {
        _themeMode = mode;
        _primaryColor = color;
      });
    }
  }

  // Fix the build method to prevent ThemeMode.system override
  @override
  Widget build(BuildContext context) {
    // First, store the current values to ensure they don't change during build
    final currentThemeMode = _themeMode; // IMPORTANT: Make a local copy
    final currentPrimaryColor = _primaryColor; // IMPORTANT: Make a local copy

    final searchWidth = MediaQuery.of(context).size.width * 0.85;
    final sideOffset = (MediaQuery.of(context).size.width - searchWidth) / 2;
    const iconAdjustment = 8.0;

    Logging.severe('MAIN: build - Using ThemeMode: $currentThemeMode');
    Logging.severe(
        'MAIN: build - Using PrimaryColor: ${currentPrimaryColor.r}, ${currentPrimaryColor.g}, ${currentPrimaryColor.b}');
    Logging.severe(
        'MAIN BUILD: Using ThemeService color = ${ts.ThemeService.primaryColor}');

    // Sanity check - if somehow main.dart's state got out of sync with ThemeService
    if (currentThemeMode != ts.ThemeService.themeMode && mounted) {
      // Fix without triggering a build during the current build
      Future.microtask(() {
        if (mounted) {
          setState(() {
            _themeMode = ts.ThemeService.themeMode;
          });
        }
      });
    }

    return MaterialApp(
      navigatorKey: navigatorKey,
      scaffoldMessengerKey: scaffoldMessengerKey,
      title: 'RateMe!',
      debugShowCheckedModeBanner: false,

      // CRITICAL: Use currentThemeMode instead of _themeMode to prevent changes during build
      theme: ts.ThemeService.lightTheme.copyWith(
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          width: MediaQuery.of(context).size.width *
              0.85, // Set to 85% of screen width
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8.0),
          ),
        ),
      ),
      darkTheme: ts.ThemeService.darkTheme.copyWith(
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          width: MediaQuery.of(context).size.width *
              0.85, // Set to 85% of screen width
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8.0),
          ),
        ),
      ),
      themeMode:
          currentThemeMode, // !!! Use the local copy to prevent inconsistency

      home: Builder(builder: (context) {
        // FIXED: Get the correct color for icons based on theme brightness
        final iconColor = Theme.of(context).brightness == Brightness.dark
            ? Colors.white
            : Colors.black;

        return Scaffold(
          appBar: AppBar(
            title: Text(
              'Rate Me!',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 24,
                // Add explicit color based on theme brightness
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white
                    : Colors.black,
              ),
            ),
            centerTitle: true,
            leadingWidth: sideOffset + 80 - iconAdjustment,
            leading: Padding(
              padding: EdgeInsets.only(left: sideOffset - iconAdjustment),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  Expanded(
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                      icon:
                          Icon(Icons.library_music_outlined, color: iconColor),
                      tooltip: 'All Saved Albums',
                      onPressed: () {
                        navigatorKey.currentState?.push(
                          MaterialPageRoute(
                            builder: (context) => const SavedRatingsPage(),
                          ),
                        );
                      },
                    ),
                  ),
                  Expanded(
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                      icon: Icon(Icons.format_list_bulleted, color: iconColor),
                      tooltip: 'Custom Lists',
                      onPressed: () {
                        navigatorKey.currentState?.push(
                          MaterialPageRoute(
                            builder: (context) => const CustomListsPage(),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              IconButton(
                icon: Icon(Icons.file_download, color: iconColor),
                visualDensity: VisualDensity.compact,
                tooltip: 'Import Album',
                onPressed: () async {
                  final result = await UserData.importAlbum();
                  if (result != null && mounted) {
                    final isBandcamp =
                        result['url']?.toString().contains('bandcamp.com') ??
                            false;
                    navigatorKey.currentState?.push(
                      MaterialPageRoute(
                        builder: (context) => DetailsPage(
                          album: result,
                          isBandcamp: isBandcamp,
                        ),
                      ),
                    );
                  }
                },
              ),
              Padding(
                padding: EdgeInsets.only(right: sideOffset - iconAdjustment),
                child: IconButton(
                  icon: Icon(Icons.settings, color: iconColor),
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Settings',
                  onPressed: () {
                    navigatorKey.currentState?.push(
                      MaterialPageRoute(
                        builder: (context) => SettingsPage(
                          currentTheme: _themeMode,
                          onThemeChanged: _updateTheme,
                          currentPrimaryColor: _primaryColor,
                          onPrimaryColorChanged: _updatePrimaryColor,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          body: Column(
            children: [
              const SizedBox(height: 32),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(width: sideOffset),
                    Theme(
                      data: Theme.of(context).copyWith(
                        highlightColor: Colors.transparent,
                        splashColor: Colors.transparent,
                      ),
                      child: DropdownButton<SearchPlatform>(
                        value: _selectedSearchPlatform,
                        icon: Icon(
                          Icons.arrow_drop_down,
                          size: 18,
                          color: iconColor,
                        ),
                        underline: Container(),
                        onChanged: (SearchPlatform? platform) {
                          if (platform != null) {
                            _updateSearchPlatform(platform);
                          }
                        },
                        items: [
                          _buildDropdownItem(SearchPlatform.itunes, iconColor),
                          _buildDropdownItem(SearchPlatform.spotify, iconColor),
                          _buildDropdownItem(SearchPlatform.deezer, iconColor),
                          _buildDropdownItem(SearchPlatform.discogs, iconColor),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: searchWidth - 60,
                      child: TextField(
                        controller: searchController,
                        decoration: InputDecoration(
                          labelText: 'Search Albums or Paste URL',
                          suffixIcon: IconButton(
                            icon: Icon(Icons.search, color: iconColor),
                            onPressed: () {
                              final text = searchController.text.trim();
                              if (_containsMusicUrl(text)) {
                                _processManualUrl(text);
                              } else {
                                _performSearch(text);
                              }
                            },
                          ),
                        ),
                        onChanged: (query) {
                          if (_debounce?.isActive ?? false) _debounce!.cancel();
                          if (_containsMusicUrl(query)) {
                            _debounce =
                                Timer(const Duration(milliseconds: 200), () {
                              _processManualUrl(query);
                            });
                          } else {
                            _debounce =
                                Timer(const Duration(milliseconds: 500), () {
                              _performSearch(query);
                            });
                          }
                        },
                        onTap: () {
                          ClipboardDetector.resumeNotifications();
                        },
                        onSubmitted: (text) {
                          if (_containsMusicUrl(text)) {
                            _processManualUrl(text);
                          } else {
                            _performSearch(text);
                          }
                        },
                        maxLength: 255,
                      ),
                    ),
                    SizedBox(width: sideOffset),
                  ],
                ),
              ),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : searchResults.isEmpty
                        ? Center(child: Container())
                        : Center(
                            child: SizedBox(
                              width: searchWidth,
                              child: ListView.builder(
                                itemCount: searchResults.length,
                                itemBuilder: (context, index) {
                                  final album = searchResults[index];
                                  return PlatformUI.buildAlbumCard(
                                    album: album,
                                    onTap: () {
                                      navigatorKey.currentState?.push(
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              DetailsPage(album: album),
                                        ),
                                      );
                                    },
                                  );
                                },
                              ),
                            ),
                          ),
              ),
              const Footer(),
            ],
          ),
        );
      }),
    );
  }

  DropdownMenuItem<SearchPlatform> _buildDropdownItem(
      SearchPlatform platform, Color? iconColor) {
    final Color safeIconColor = iconColor ?? Colors.grey;

    String tooltipText;
    switch (platform) {
      case SearchPlatform.itunes:
        tooltipText = 'Apple Music';
        break;
      case SearchPlatform.spotify:
        tooltipText = 'Spotify';
        break;
      case SearchPlatform.deezer:
        tooltipText = 'Deezer';
        break;
      case SearchPlatform.discogs:
        tooltipText = 'Discogs';
        break;
      default:
        tooltipText = 'Select platform';
        break;
    }

    return DropdownMenuItem<SearchPlatform>(
      value: platform,
      child: Tooltip(
        message: tooltipText,
        child: SvgPicture.asset(
          _getPlatformIconPath(platform),
          width: 26,
          height: 26,
          colorFilter: ColorFilter.mode(safeIconColor, BlendMode.srcIn),
        ),
      ),
    );
  }

  String _getPlatformIconPath(SearchPlatform platform) {
    if (platform == SearchPlatform.itunes) {
      return 'lib/icons/apple_music.svg';
    }
    if (platform == SearchPlatform.spotify) {
      return 'lib/icons/spotify.svg';
    }
    if (platform == SearchPlatform.deezer) {
      return 'lib/icons/deezer.svg';
    }
    if (platform == SearchPlatform.discogs) {
      return 'lib/icons/discogs.svg';
    }
    return 'lib/icons/spotify.svg';
  }

  Color _getPlatformColor(SearchPlatform platform) {
    if (platform == SearchPlatform.itunes) {
      return const Color(0xFFFC3C44);
    }
    if (platform == SearchPlatform.spotify) {
      return const Color(0xFF1DB954);
    }
    if (platform == SearchPlatform.deezer) {
      return const Color(0xFF00C7F2);
    }
    if (platform == SearchPlatform.discogs) {
      return const Color(0xFFFF5500);
    }
    return Colors.grey;
  }

  Color getPlatformColorForPlatform(SearchPlatform platform) {
    return _getPlatformColor(platform);
  }

  IconData getPlatformIconForPlatform(SearchPlatform platform) {
    if (platform == SearchPlatform.itunes) {
      return Icons.music_note;
    }
    if (platform == SearchPlatform.spotify) {
      return Icons.music_note;
    }
    if (platform == SearchPlatform.deezer) {
      return Icons.music_note;
    }
    if (platform == SearchPlatform.discogs) {
      return Icons.music_note;
    }
    return Icons.search;
  }

  bool _containsMusicUrl(String text) {
    final lowerText = text.toLowerCase();
    return lowerText.contains('music.apple.com') ||
        lowerText.contains('itunes.apple.com') ||
        lowerText.contains('apple.co') ||
        lowerText.contains('bandcamp.com') ||
        lowerText.contains('.bandcamp.') ||
        lowerText.contains('spotify.com') ||
        lowerText.contains('open.spotify') ||
        lowerText.contains('deezer.com') ||
        lowerText.contains('discogs.com');
  }

  void _processManualUrl(String url) {
    if (url.isEmpty) return;
    Logging.severe('Processing manually entered URL: $url');
    ClipboardDetector.processManualUrl(
      url,
      onDetected: (text) {
        setState(() {
          searchController.text = text;
          _performSearch(text);
        });
      },
      onUrlDetected: (url, searchQuery) {
        setState(() {
          searchController.text = url;
          _performSearch(searchQuery);
        });
      },
      onSnackBarMessage: (message) {
        scaffoldMessengerKey.currentState?.showSnackBar(
          SnackBar(content: Text(message)),
        );
      },
      onSearchCompleted: (success) {
        ClipboardDetector.reportSearchResult(success);
      },
    );
  }

  // Helper method for consistent hex format logging
  String _colorToHex(Color color) {
    // CRITICAL FIX: Fix the broken hex formatting - the old method was incorrect
    final int r = color.r.round();
    final int g = color.g.round();
    final int b = color.b.round();

    return '#FF${r.toRadixString(16).padLeft(2, '0')}${g.toRadixString(16).padLeft(2, '0')}${b.toRadixString(16).padLeft(2, '0')}'
        .toUpperCase();
  }
}

// Update the MaterialColorGenerator class to fix type issues and deprecated member usage
class MaterialColorGenerator {
  static MaterialColor from(Color color) {
    // Replace color.value with color.value property
    // Use toARGB32() instead of value as recommended by the deprecation warning
    return MaterialColor(color.toARGB32(), {
      50: _tintColor(color, 0.9),
      100: _tintColor(color, 0.8),
      200: _tintColor(color, 0.6),
      300: _tintColor(color, 0.4),
      400: _tintColor(color, 0.2),
      500: color,
      600: _shadeColor(color, 0.1),
      700: _shadeColor(color, 0.2),
      800: _shadeColor(color, 0.3),
      900: _shadeColor(color, 0.4),
    });
  }

  static Color _tintColor(Color color, double factor) {
    return Color.fromRGBO(
      // Fix: Use round() to convert double to int
      _bound((color.r + ((255 - color.r) * factor)).round()),
      _bound((color.g + ((255 - color.g) * factor)).round()),
      _bound((color.b + ((255 - color.b) * factor)).round()),
      1,
    );
  }

  static Color _shadeColor(Color color, double factor) {
    return Color.fromRGBO(
      // Fix: Use round() to convert double to int
      _bound((color.r - (color.r * factor)).round()),
      _bound((color.g - (color.g * factor)).round()),
      _bound((color.b - (color.b * factor)).round()),
      1,
    );
  }

  static int _bound(int value) {
    return value.clamp(0, 255);
  }
}

void someDebugOrAdminFunction() async {
  await CleanupUtility.runFullCleanup();
  // or call specific methods:
  // await CleanupUtility.fixDotZeroIssues();
  // await CleanupUtility.cleanupPlatformMatches();
}
