import 'package:flutter/material.dart';
import 'dart:async';
import 'core/utils/color_utility.dart';
import 'database/api_key_manager.dart';
import 'features/albums/saved_ratings_page.dart';
import 'core/services/logging.dart';
import 'features/albums/details_page.dart';
import 'core/services/search_service.dart';
import 'features/settings/settings_service.dart';
import 'core/services/user_data.dart';
import 'features/custom_lists/custom_lists_page.dart';
import 'ui/widgets/footer.dart';
import 'features/settings/settings_page.dart';
import 'features/platforms/platform_ui.dart';
import 'database/database_helper.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'features/notifications/global_notifications.dart';
import 'core/utils/clipboard_detector.dart';
import 'database/cleanup_utility.dart';
import 'core/services/theme_service.dart' as ts;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'features/preload/preload_service.dart';
import 'platforms/middleware/discogs_middleware.dart';
import 'platforms/middleware/deezer_middleware.dart'; // Add import for Deezer middleware

Future<void> main() async {
  try {
    // Initialize Flutter binding
    WidgetsFlutterBinding.ensureInitialized();
    // Initialize database factory
    await _initializeDatabaseFactory();
    // Initialize logging first
    Logging.initialize();
    Logging.severe('===== Logging system initialized =====');
    // CRITICAL FIX: Preload theme settings before building the UI
    await PreloadService.preloadEssentialSettings();
    // Get the preloaded color for the initial UI render
    Color initialThemeColor = PreloadService.primaryColor;
    runApp(MyApp(initialColor: initialThemeColor));
    // Initialize services
    await ApiKeyManager.instance.initialize();
    await DatabaseHelper.initialize();
    await ts.ThemeService.initialize();
    // Start clipboard listener
    ClipboardDetector.startClipboardListener(
      onDetected: (url) {
        // Handle URL detection
      },
      onSnackBarMessage: (message) {
        // Show message
      },
      onUrlDetected: (url, query) {
        // Handle URL with query
      },
      onSearchCompleted: (success) {
        // Handle search completion
      },
    );
    Logging.severe('MAIN: Application initialized');
  } catch (e, stack) {
    Logging.severe('MAIN: Error initializing application', e, stack);
  }
}

/// Initialize the appropriate database factory based on platform
Future<void> _initializeDatabaseFactory() async {
  // Log that we're initializing database factory
  Logging.severe('Initializing database factory for current platform');
  try {
    // For desktop platforms and non-Android/iOS, use FFI
    if (kIsWeb) {
      // Web has its own initialization in sqflite package
      Logging.severe('Web platform detected, using default factory');
    } else if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      // Initialize FFI for desktop platforms
      Logging.severe('Desktop platform detected, using FFI database factory');
      // Initialize FFI
      sqfliteFfiInit();
      // Set global factory
      databaseFactory = databaseFactoryFfi;
    } else {
      // Android/iOS use the regular factory which is already set up
      Logging.severe('Mobile platform detected, using default factory');
    }
  } catch (e) {
    Logging.severe('Error initializing database factory: $e');
    // In case of failure, try to use FFI as a fallback
    try {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      Logging.severe('Falling back to FFI database factory after error');
    } catch (fallbackError) {
      Logging.severe(
          'Critical error: Failed to initialize any database factory: $fallbackError');
    }
  }
}

class MyApp extends StatefulWidget {
  final bool showMigrationPrompt;
  final Color initialColor;
  const MyApp({
    super.key,
    this.showMigrationPrompt = false,
    required this.initialColor,
  });

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  ThemeMode _themeMode = ThemeMode.system;
  // Set the app default color
  Color _primaryColor = ColorUtility.defaultColor;
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
    _primaryColor = widget.initialColor;
    // Single initialization log
    Logging.severe('MAIN: Application initialized');
    _loadTheme();
    // Add a listener to ensure ThemeService changes are applied
    ts.ThemeService.addGlobalListener(_updateThemeState);
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
    ts.ThemeService.addGlobalListener(() {
      if (mounted) {
        setState(() {
          _themeMode = ts.ThemeService.themeMode;
          _primaryColor = ts.ThemeService.primaryColor;
          // Reduce frequency of log messages
        });
      }
    });
  }

  void _setupGlobalListeners() {
    GlobalNotifications.onSearchPlatformChanged.listen((platform) {
      if (_selectedSearchPlatform != platform) {
        // We can keep this log as it's a user-initiated action
        Logging.severe('Default search platform changed to: ${platform.name}');
        setState(() {
          _selectedSearchPlatform = platform;
          final currentQuery = searchController.text.trim();
          if (currentQuery.isNotEmpty) {
            Future.delayed(const Duration(milliseconds: 100), () {
              _performSearch(currentQuery);
            });
          }
        });
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
              Logging.severe(
                  'Loaded default search platform: ${_selectedSearchPlatform.name}');
            });
          }
        }
      }
    } catch (e) {
      Logging.severe('Error loading search platform', e);
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

  void _updateSearchPlatform(SearchPlatform platform) async {
    try {
      setState(() {
        _selectedSearchPlatform = platform;
        final currentQuery = searchController.text.trim();
        if (currentQuery.isNotEmpty) {
          Future.delayed(const Duration(milliseconds: 100), () {
            _performSearch(currentQuery);
          });
        }
      });
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
          await SearchService.searchAlbum(query, '', _selectedSearchPlatform);
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

  Future<void> _loadTheme() async {
    try {
      final prevMode = _themeMode; // Store previous mode for comparison
      // Update state with ThemeService values
      setState(() {
        _themeMode = ts.ThemeService.themeMode;
        _primaryColor = ts.ThemeService.primaryColor;
        // Remove redundant logging
      });
      // Log only when theme mode changes
      if (prevMode != _themeMode) {
        Logging.severe('Theme mode changed from $prevMode to $_themeMode');
      }
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
    ts.ThemeService.removeGlobalListener(_updateThemeState);
    super.dispose();
  }

  void _updateThemeState() {
    setState(() {
      // Update the UI when theme changes
      _themeMode = ts.ThemeService.themeMode;
      _primaryColor = ts.ThemeService.primaryColor;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Calculate responsive width based on device
    final pageWidth = MediaQuery.of(context).size.width *
        (Platform.isAndroid || Platform.isIOS ? 0.95 : 0.85);

    // Always use a fixed 85% width for the search bar on all platforms
    final searchBarWidth = MediaQuery.of(context).size.width * 0.85;

    // First, store the current values to ensure they don't change during build
    final currentThemeMode = _themeMode; // Make a local copy
    // Remove unused variable warning by not declaring it if we're not using it
    // final currentPrimaryColor = _primaryColor; // Make a local copy
    final searchWidth = MediaQuery.of(context).size.width * 0.85;
    final sideOffset = (MediaQuery.of(context).size.width - searchWidth) / 2;
    const iconAdjustment = 8.0;
    // CRITICAL FIX: Completely disable build logging to reduce spam
    // Most build logs are not useful for debugging and create noise
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
          currentThemeMode, // Use the local copy to prevent inconsistency
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
                      width: searchBarWidth - 60, // Use fixed 85% width for all platforms
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
                              width: pageWidth, // Use responsive width for content
                              child: ListView.builder(
                                itemCount: searchResults.length,
                                itemBuilder: (context, index) {
                                  final album = searchResults[index];
                                  return PlatformUI.buildAlbumCard(
                                    album: album,
                                    onTap: () {
                                      // Check platform and use appropriate middleware
                                      if (album['platform'] == 'discogs') {
                                        // Use Discogs middleware
                                        DiscogsMiddleware
                                            .showDetailPageWithPreload(
                                                context, album);
                                      } else if (album['platform'] ==
                                              'deezer' &&
                                          album['useDeezerMiddleware'] ==
                                              true) {
                                        // Use Deezer middleware for accurate date fetching
                                        Logging.severe(
                                            'Using DeezerMiddleware for Deezer album');
                                        DeezerMiddleware
                                            .showDetailPageWithPreload(
                                                context, album);
                                      } else {
                                        // Use the original approach for other platforms
                                        navigatorKey.currentState?.push(
                                          MaterialPageRoute(
                                            builder: (context) =>
                                                DetailsPage(album: album),
                                          ),
                                        );
                                      }
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
    // Keep this log as it's user-initiated
    Logging.severe('Processing user-entered URL: $url');
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
}

// Update the MaterialColorGenerator class to fix type issues and deprecated member usage
class MaterialColorGenerator {
  static MaterialColor from(Color color) {
    // Replace color.value with color.toARGB32() as recommended by the deprecation warning
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
