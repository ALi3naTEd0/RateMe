import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'saved_ratings_page.dart';
import 'logging.dart';
import 'details_page.dart';
import 'user_data.dart';
import 'custom_lists_page.dart';
import 'theme.dart';
import 'footer.dart';
import 'settings_page.dart';
import 'platform_service.dart';
import 'platform_ui.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Logging.setupLogging();

  // Initialize database
  await UserData.initializeDatabase();

  // Check if migration is needed
  final migrationNeeded = await UserData.isMigrationNeeded();

  runApp(MyApp(showMigrationPrompt: migrationNeeded));
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
  ThemeMode _themeMode =
      ThemeMode.system; // Change the default theme mode to system
  Color _primaryColor = const Color(0xFF864AF9);

  final TextEditingController searchController = TextEditingController();
  List<Map<String, dynamic>> searchResults = [];
  bool _isLoading = false;
  Timer? _debounce;
  Timer? _clipboardTimer;

  final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _startClipboardListener();

    // Check if migration prompt should be shown
    if (widget.showMigrationPrompt) {
      // Add a small delay to allow the app to initialize
      Future.delayed(const Duration(seconds: 2), () {
        _showMigrationPrompt();
      });
    }
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      // Force to a valid value if the stored value is missing or invalid
      final themeIndex = prefs.getInt('themeMode');

      // Handle null or missing values
      if (themeIndex == null) {
        _themeMode = ThemeMode.system; // Default to system for everyone
        // Initialize it right away
        prefs.setInt('themeMode', ThemeMode.system.index);
      } else {
        // Map the indices explicitly to avoid potential issues
        switch (themeIndex) {
          case 0:
            _themeMode = ThemeMode.system;
            break;
          case 1:
            _themeMode = ThemeMode.light;
            break;
          case 2:
            _themeMode = ThemeMode.dark;
            break;
          default:
            _themeMode = ThemeMode.system;
            // Fix invalid value
            prefs.setInt('themeMode', ThemeMode.system.index);
        }
      }

      Logging.severe(
          'Theme mode loaded: $_themeMode (index: ${_themeMode.index}), isLinux: ${Platform.isLinux}');
      _primaryColor = Color(prefs.getInt('primaryColor') ?? 0xFF864AF9);
    });
  }

  void _updateTheme(ThemeMode mode) async {
    // Simply update the theme without platform-specific warnings
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('themeMode', mode.index);

    // Log when theme changes
    Logging.severe('Theme changed to: $mode (index: ${mode.index})');

    setState(() => _themeMode = mode);
  }

  void _updatePrimaryColor(Color color) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('primaryColor', color.toARGB32());

    setState(() => _primaryColor = color);
  }

  Future<void> _performSearch(String query) async {
    if (query.isEmpty) {
      setState(() => searchResults = []);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final results = await PlatformService.searchAlbums(query);

      if (mounted) {
        setState(() {
          searchResults = List<Map<String, dynamic>>.from(results);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          searchResults = [];
          _isLoading = false;
        });

        scaffoldMessengerKey.currentState?.showSnackBar(
          SnackBar(content: Text('Error searching: $e')),
        );
      }
    }
  }

  void _startClipboardListener() {
    _clipboardTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (!mounted) return;

      try {
        final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
        final text = clipboardData?.text;

        if (text != null && text.isNotEmpty && searchController.text.isEmpty) {
          final lowerText = text.toLowerCase();
          final bool isAppleMusic = lowerText.contains('music.apple.com') ||
              lowerText.contains('itunes.apple.com') ||
              lowerText.contains('apple.co') ||
              lowerText.contains('apple music');

          final bool isBandcamp = lowerText.contains('bandcamp.com') ||
              lowerText.contains('.bandcamp.') ||
              lowerText.contains('bandcamp:');

          final bool isSpotify = lowerText.contains('spotify.com') ||
              lowerText.contains('open.spotify');

          final bool isDeezer = lowerText.contains('deezer.com');

          if (isAppleMusic || isBandcamp || isSpotify || isDeezer) {
            String platform = 'unknown';
            if (isAppleMusic) platform = 'Apple Music';
            if (isBandcamp) platform = 'Bandcamp';
            if (isSpotify) platform = 'Spotify';
            if (isDeezer) platform = 'Deezer';

            Logging.severe('$platform URL detected in clipboard');

            setState(() {
              searchController.text = text;
              _performSearch(text);
            });

            scaffoldMessengerKey.currentState?.showSnackBar(
              SnackBar(
                  content:
                      Text('$platform URL detected and pasted into search')),
            );
          }
        }
      } catch (e) {
        Logging.severe('Error checking clipboard', e);
      }
    });
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

  @override
  void dispose() {
    _clipboardTimer?.cancel();
    searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final searchWidth = MediaQuery.of(context).size.width * 0.85;
    final sideOffset = (MediaQuery.of(context).size.width - searchWidth) / 2;

    const iconAdjustment = 8.0;

    return MaterialApp(
      navigatorKey: navigatorKey,
      scaffoldMessengerKey: scaffoldMessengerKey,
      title: 'RateMe!',
      debugShowCheckedModeBanner: false,
      theme: RateMeTheme.getTheme(Brightness.light, _primaryColor),
      darkTheme: RateMeTheme.getTheme(Brightness.dark, _primaryColor),
      themeMode: _themeMode,
      home: Scaffold(
        appBar: AppBar(
          title: const Text(
            'Rate Me!',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 24,
            ),
          ),
          centerTitle: true,
          leadingWidth:
              sideOffset + 80 - iconAdjustment, // Reduced from 120 to 80
          leading: Padding(
            padding: EdgeInsets.only(left: sideOffset - iconAdjustment),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                Expanded(
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    visualDensity:
                        VisualDensity.compact, // Add this for tighter spacing
                    icon: const Icon(Icons.library_music_outlined),
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
                    visualDensity:
                        VisualDensity.compact, // Add this for tighter spacing
                    icon: const Icon(Icons.format_list_bulleted),
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
              icon: const Icon(Icons.file_download),
              visualDensity: VisualDensity.compact, // Match the left side
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
                icon: const Icon(Icons.settings),
                visualDensity: VisualDensity.compact, // Match the left side
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
              child: Center(
                child: SizedBox(
                  width: searchWidth,
                  child: TextField(
                    controller: searchController,
                    decoration: InputDecoration(
                      labelText: 'Search Albums or Paste URL',
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.search),
                        onPressed: () => _performSearch(searchController.text),
                      ),
                    ),
                    onChanged: (query) {
                      if (_debounce?.isActive ?? false) _debounce!.cancel();
                      _debounce = Timer(const Duration(milliseconds: 500), () {
                        _performSearch(query);
                      });
                    },
                    maxLength: 255,
                  ),
                ),
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
            const AppVersionFooter(),
          ],
        ),
      ),
    );
  }
}

class MusicRatingHomePage extends StatefulWidget {
  final Function(ThemeMode) toggleTheme;
  final ThemeMode currentTheme;
  final Function(Color) onPrimaryColorChanged;
  final Color primaryColor;

  const MusicRatingHomePage({
    super.key,
    required this.toggleTheme,
    required this.currentTheme,
    required this.onPrimaryColorChanged,
    required this.primaryColor,
  });

  @override
  State<MusicRatingHomePage> createState() => _MusicRatingHomePageState();
}

class _MusicRatingHomePageState extends State<MusicRatingHomePage> {
  static final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  final TextEditingController searchController = TextEditingController();
  List<dynamic> searchResults = [];
  Timer? _debounce;
  Timer? _clipboardTimer;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _startClipboardListener();
    _loadAppVersion();
  }

  void _startClipboardListener() {
    _clipboardTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (!mounted) return;

      try {
        final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
        final text = clipboardData?.text;

        if (text != null && text.isNotEmpty && searchController.text.isEmpty) {
          final lowerText = text.toLowerCase();
          final bool isAppleMusic = lowerText.contains('music.apple.com') ||
              lowerText.contains('itunes.apple.com') ||
              lowerText.contains('apple.co') ||
              lowerText.contains('apple music');

          final bool isBandcamp = lowerText.contains('bandcamp.com') ||
              lowerText.contains('.bandcamp.') ||
              lowerText.contains('bandcamp:');

          final bool isSpotify = lowerText.contains('spotify.com') ||
              lowerText.contains('open.spotify');

          final bool isDeezer = lowerText.contains('deezer.com');

          if (isAppleMusic || isBandcamp || isSpotify || isDeezer) {
            String platform = 'unknown';
            if (isAppleMusic) platform = 'Apple Music';
            if (isBandcamp) platform = 'Bandcamp';
            if (isSpotify) platform = 'Spotify';
            if (isDeezer) platform = 'Deezer';

            Logging.severe('$platform URL detected in clipboard');

            setState(() {
              searchController.text = text;
              _performSearch(text);
            });

            scaffoldMessengerKey.currentState?.showSnackBar(
              SnackBar(
                  content:
                      Text('$platform URL detected and pasted into search')),
            );
          }
        }
      } catch (e) {
        Logging.severe('Error checking clipboard', e);
      }
    });
  }

  @override
  void dispose() {
    _clipboardTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadAppVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    if (mounted) {
      final appVersion = packageInfo.version;

      try {
        final response = await http.get(Uri.parse(
            'https://api.github.com/repos/ALi3naTEd0/RateMe/releases/latest'));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final latestVersion = data['tag_name'].toString().replaceAll('v', '');

          if (latestVersion != appVersion && mounted) {
            _showUpdateDialog(appVersion, latestVersion);
          }
        }
      } catch (e) {
        Logging.severe('Error checking for updates', e);
      }
    }
  }

  void _showUpdateDialog(String currentVersion, String latestVersion) {
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Update Available'),
        content: Text(
            'A new version ($latestVersion) is available.\nCurrent version: $currentVersion'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Later'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _launchUpdateUrl();
            },
            child: const Text('Update Now'),
          ),
        ],
      ),
    );
  }

  void _launchUpdateUrl() {
    launchUrl(
      Uri.parse('https://github.com/ALi3naTEd0/RateMe/releases/latest'),
      mode: LaunchMode.externalApplication,
    );
  }

  void _showSnackBar(String message) {
    scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _handleSearch(String query) async {
    setState(() => _isLoading = true);

    try {
      final results = await PlatformService.searchAlbums(query);

      if (mounted) {
        setState(() {
          searchResults = results;
          _isLoading = false;
        });
      }
    } catch (e) {
      Logging.severe('Error searching albums', e);
      if (mounted) {
        setState(() {
          searchResults = [];
          _isLoading = false;
        });
        _showSnackBar('Error searching: $e');
      }
    }
  }

  void _performSearch(String query) async {
    if (query.isEmpty) {
      setState(() => searchResults = []);
      return;
    }

    await _handleSearch(query);
  }

  void _onThemeChanged(ThemeMode mode) {
    setState(() {
      widget.toggleTheme(mode);
      if (searchResults.isNotEmpty) {
        List<Map<String, dynamic>> currentResults = List.from(searchResults);
        searchResults = [];
        Future.microtask(() {
          if (mounted) {
            setState(() => searchResults = currentResults);
          }
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final searchWidth = MediaQuery.of(context).size.width * 0.85;
    final sideOffset = (MediaQuery.of(context).size.width - searchWidth) / 2;

    const iconAdjustment = 8.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Rate Me!',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 24,
          ),
        ),
        centerTitle: true,
        leadingWidth:
            sideOffset + 80 - iconAdjustment, // Reduced from 120 to 80
        leading: Padding(
          padding: EdgeInsets.only(left: sideOffset - iconAdjustment),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              Expanded(
                child: IconButton(
                  padding: EdgeInsets.zero,
                  visualDensity:
                      VisualDensity.compact, // Add this for tighter spacing
                  icon: const Icon(Icons.library_music_outlined),
                  tooltip: 'All Saved Albums',
                  onPressed: () {
                    Navigator.push(
                      context,
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
                  visualDensity:
                      VisualDensity.compact, // Add this for tighter spacing
                  icon: const Icon(Icons.format_list_bulleted),
                  tooltip: 'Custom Lists',
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const CustomListsPage()),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download),
            visualDensity: VisualDensity.compact, // Match the left side
            tooltip: 'Import Album',
            onPressed: () async {
              final result = await UserData.importAlbum();

              if (result != null && mounted) {
                final isBandcamp =
                    result['url']?.toString().contains('bandcamp.com') ?? false;

                final navigator = navigatorKey.currentState;
                if (navigator == null) return;

                navigator.push(
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
              icon: const Icon(Icons.settings),
              visualDensity: VisualDensity.compact, // Match the left side
              tooltip: 'Settings',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => SettingsPage(
                    currentTheme: widget.currentTheme,
                    onThemeChanged: _onThemeChanged,
                    currentPrimaryColor: Theme.of(context).colorScheme.primary,
                    onPrimaryColorChanged: widget.onPrimaryColorChanged,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          const SizedBox(height: 32),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24.0),
            child: Center(
              child: SizedBox(
                width: searchWidth,
                child: TextField(
                  controller: searchController,
                  decoration: InputDecoration(
                    labelText: 'Search Albums or Paste URL',
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.search),
                      onPressed: () => _performSearch(searchController.text),
                    ),
                  ),
                  onChanged: (query) {
                    if (_debounce?.isActive ?? false) _debounce!.cancel();
                    _debounce = Timer(const Duration(milliseconds: 500), () {
                      _performSearch(query);
                    });
                  },
                  maxLength: 255,
                ),
              ),
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
                                  Navigator.push(
                                    context,
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
          const AppVersionFooter(),
        ],
      ),
    );
  }
}
