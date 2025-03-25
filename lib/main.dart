import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'dart:async';
import 'saved_ratings_page.dart';
import 'logging.dart';
import 'details_page.dart';
import 'user_data.dart';
import 'custom_lists_page.dart';
import 'theme.dart';
import 'footer.dart';
import 'settings_page.dart';
// Remove the unused import
// import 'navigation_util.dart';
import 'platform_service.dart'; // This replaces search_service.dart
import 'platform_ui.dart';
// Remove search_service.dart import since we use platform_service.dart instead

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Logging.setupLogging();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  ThemeMode _themeMode = ThemeMode.system;
  Color _primaryColor = const Color(0xFF864AF9);

  // Add these fields for search functionality
  final TextEditingController searchController = TextEditingController();
  List<Map<String, dynamic>> searchResults = [];
  bool _isLoading = false;
  Timer? _debounce;
  Timer? _clipboardTimer; // Add this field

  // Remove unused fields
  // String _appVersion = '';
  // String _latestVersion = '';

  // Create scaffold messenger key for showing snackbars
  final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

  // Add a static navigator key if not already present
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _startClipboardListener(); // Add this line
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _themeMode = ThemeMode.values[prefs.getInt('themeMode') ?? 0];
      _primaryColor = Color(prefs.getInt('primaryColor') ?? 0xFF864AF9);
    });
  }

  void _updateTheme(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('themeMode', mode.index);
    setState(() => _themeMode = mode);
  }

  void _updatePrimaryColor(Color color) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('primaryColor', color.toARGB32());
    setState(() => _primaryColor = color);
  }

  // Add search method
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

        // Use scaffoldMessengerKey instead of direct context
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
          // Log the clipboard content for debugging
          Logging.severe('Clipboard content detected: $text');

          // Improve URL detection with more comprehensive checks
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

          if (isAppleMusic || isBandcamp || isSpotify) {
            String platform = 'unknown';
            if (isAppleMusic) platform = 'Apple Music';
            if (isBandcamp) platform = 'Bandcamp';
            if (isSpotify) platform = 'Spotify';

            Logging.severe('Music URL detected: $platform');

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
    _clipboardTimer?.cancel(); // Add this line
    searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Calculate search width consistently for both search bar and results
    final searchWidth = MediaQuery.of(context).size.width * 0.85;
    final sideOffset = (MediaQuery.of(context).size.width - searchWidth) / 2;

    // Add a small adjustment to align icons more precisely with search bar edge
    const iconAdjustment = 8.0; // Move icons left by this amount

    return MaterialApp(
      navigatorKey: navigatorKey, // This is correct
      scaffoldMessengerKey: scaffoldMessengerKey, // This is correct
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
          // Add adjustments to the leading width
          leadingWidth: sideOffset + 120 - iconAdjustment,
          leading: Padding(
            // Apply the adjustment to leading padding
            padding: EdgeInsets.only(left: sideOffset - iconAdjustment),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                Expanded(
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.library_music_outlined),
                    tooltip: 'All Saved Albums',
                    onPressed: () {
                      // Use navigatorKey here, not context
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
                    icon: const Icon(Icons.format_list_bulleted),
                    tooltip: 'Custom Lists',
                    onPressed: () {
                      // Use navigatorKey here, not context
                      navigatorKey.currentState?.push(
                        MaterialPageRoute(
                          builder: (context) => const CustomListsPage(),
                        ),
                      );
                    },
                  ),
                ),
                Expanded(
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.file_download),
                    tooltip: 'Import Album',
                    onPressed: () async {
                      final result = await UserData.importAlbum();
                      if (result != null && mounted) {
                        final isBandcamp = result['url']
                                ?.toString()
                                .contains('bandcamp.com') ??
                            false;

                        // Use navigatorKey here, not context
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
                ),
              ],
            ),
          ),
          actions: [
            // Adjust right side too for symmetry
            Padding(
              padding: EdgeInsets.only(right: sideOffset - iconAdjustment),
              child: IconButton(
                icon: const Icon(Icons.settings),
                tooltip: 'Settings',
                onPressed: () {
                  // Use navigatorKey here, not context
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

        // ...existing code...

        body: Column(
          children: [
            const SizedBox(height: 32),

            // Search bar with proper padding and width
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24.0),
              child: Center(
                child: SizedBox(
                  width: searchWidth,
                  child: TextField(
                    controller: searchController,
                    decoration: InputDecoration(
                      labelText: 'Search Albums or Paste URL',
                      // Use a suffix icon button for search
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
                    // Add maxLength to limit input
                    maxLength: 255,
                  ),
                ),
              ),
            ),

            // Search results with same width constraint
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : searchResults.isEmpty
                      ? Center(child: Container()) // Empty state
                      : Center(
                          child: SizedBox(
                            width:
                                searchWidth, // Use the same width as search bar
                            child: ListView.builder(
                              itemCount: searchResults.length,
                              itemBuilder: (context, index) {
                                final album = searchResults[index];
                                return PlatformUI.buildAlbumCard(
                                  album: album,
                                  onTap: () {
                                    // Use navigatorKey here, not context
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

            // Footer
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
  // Define the required key
  static final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  // Remove unused fields
  // final String _appVersion = '';
  // final String _latestVersion = '';

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
    // Remove this call since we're replacing it with the implementation in _loadAppVersion
    // _checkForUpdates();
  }

  void _startClipboardListener() {
    _clipboardTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (!mounted) return;

      try {
        final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
        final text = clipboardData?.text;

        if (text != null && text.isNotEmpty && searchController.text.isEmpty) {
          // Log the clipboard content for debugging
          Logging.severe('Clipboard content detected: $text');

          // Improve URL detection with more comprehensive checks
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

          if (isAppleMusic || isBandcamp || isSpotify) {
            String platform = 'unknown';
            if (isAppleMusic) platform = 'Apple Music';
            if (isBandcamp) platform = 'Bandcamp';
            if (isSpotify) platform = 'Spotify';

            Logging.severe('Music URL detected: $platform');

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
      // Get the current version
      final appVersion = packageInfo.version;

      // Check for updates right here instead of calling a separate method
      try {
        final response = await http.get(Uri.parse(
            'https://api.github.com/repos/ALi3naTEd0/RateMe/releases/latest'));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final latestVersion = data['tag_name'].toString().replaceAll('v', '');

          if (latestVersion != appVersion && mounted) {
            // Show update dialog with the versions
            _showUpdateDialog(appVersion, latestVersion);
          }
        }
      } catch (e) {
        Logging.severe('Error checking for updates', e);
      }
    }
  }

  // Remove the now redundant method
  // Future<void> _checkUpdateNeeded(String currentVersion) async { ... }

  // Update the method signature to accept versions as parameters
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
      // Force rebuild of search results when theme changes
      if (searchResults.isNotEmpty) {
        List<Map<String, dynamic>> currentResults = List.from(searchResults);
        searchResults = [];
        // Use Future.microtask to ensure setState has completed
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
    // Calculate the search bar width - we'll use this for consistency
    final searchWidth = MediaQuery.of(context).size.width * 0.85;

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
        // Adjust leading width to align with search bar
        leadingWidth:
            (MediaQuery.of(context).size.width - searchWidth) / 2 + 120,
        leading: Padding(
          padding: EdgeInsets.only(
            left: (MediaQuery.of(context).size.width - searchWidth) / 2 - 20,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              Expanded(
                child: IconButton(
                  padding: EdgeInsets.zero,
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
                  icon: const Icon(Icons.format_list_bulleted),
                  tooltip: 'Custom Lists',
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const CustomListsPage()),
                  ),
                ),
              ),
              Expanded(
                child: IconButton(
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.file_download),
                  tooltip: 'Import Album',
                  onPressed: () async {
                    final result = await UserData.importAlbum();

                    if (result != null && mounted) {
                      final isBandcamp =
                          result['url']?.toString().contains('bandcamp.com') ??
                              false;

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
              ),
            ],
          ),
        ),
        actions: [
          // Add right padding to align with search bar
          Padding(
            padding: EdgeInsets.only(
              right: (MediaQuery.of(context).size.width - searchWidth) / 2 - 20,
            ),
            child: IconButton(
              icon: const Icon(Icons.settings),
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
          // Add spacing at the top for better positioning
          const SizedBox(height: 32),

          // Search bar with proper padding and styling
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24.0),
            child: Center(
              child: SizedBox(
                width: searchWidth, // Use the same width for consistency
                child: TextField(
                  controller: searchController,
                  decoration: InputDecoration(
                    labelText: 'Search Albums or Paste URL',
                    // Use a suffix icon button for search
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
                  // Add maxLength to limit input
                  maxLength: 255,
                ),
              ),
            ),
          ),

          // Show loading indicator or search results
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : searchResults.isEmpty
                    ? Center(child: Container()) // Empty state
                    : ListView.builder(
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
          const AppVersionFooter(),
        ],
      ),
    );
  }
}
