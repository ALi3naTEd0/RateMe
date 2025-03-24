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
import 'navigation_util.dart';
import 'platform_service.dart'; // Add this import

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

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _themeMode = ThemeMode.values[prefs.getInt('themeMode') ?? 0];
      _primaryColor = Color(prefs.getInt('primaryColor') ?? 0xFF864AF9);
    });
  }

  void toggleTheme(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('themeMode', mode.index);
    setState(() {
      _themeMode = mode;
    });
  }

  void updatePrimaryColor(Color color) async {
    final prefs = await SharedPreferences.getInstance();
    final colorValue = color.toARGB32(); // Using toARGB32 instead of value
    await prefs.setInt('primaryColor', colorValue);
    setState(() {
      _primaryColor = color;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: NavigationUtil.navigatorKey,
      scaffoldMessengerKey: GlobalKey<ScaffoldMessengerState>(),
      title: 'RateMe!',
      debugShowCheckedModeBanner: false,
      theme: RateMeTheme.getTheme(Brightness.light, _primaryColor),
      darkTheme: RateMeTheme.getTheme(Brightness.dark, _primaryColor),
      themeMode: _themeMode,
      home: MusicRatingHomePage(
        toggleTheme: toggleTheme,
        themeBrightness: _themeMode == ThemeMode.dark
            ? Brightness.dark
            : (_themeMode == ThemeMode.light
                ? Brightness.light
                : MediaQuery.platformBrightnessOf(context)),
        onPrimaryColorChanged: updatePrimaryColor,
      ),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  ThemeMode _themeMode = ThemeMode.system;
  Color _primaryColor = const Color(0xFF864AF9);

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _themeMode = ThemeMode.values[prefs.getInt('themeMode') ?? 0];
      _primaryColor = Color(prefs.getInt('primaryColor') ?? 0xFF864AF9);
    });
  }

  void toggleTheme(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('themeMode', mode.index);
    setState(() {
      _themeMode = mode;
    });
  }

  void updatePrimaryColor(Color color) async {
    final prefs = await SharedPreferences.getInstance();
    final colorValue = color.toARGB32(); // Using toARGB32 instead of value
    await prefs.setInt('primaryColor', colorValue);
    setState(() {
      _primaryColor = color;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Get platform brightness using MediaQuery instead of window
    final brightness = MediaQuery.platformBrightnessOf(context);

    return MaterialApp(
      navigatorKey: NavigationUtil.navigatorKey,
      scaffoldMessengerKey: GlobalKey<ScaffoldMessengerState>(),
      title: 'RateMe!',
      debugShowCheckedModeBanner: false,
      theme: RateMeTheme.getTheme(Brightness.light, _primaryColor),
      darkTheme: RateMeTheme.getTheme(Brightness.dark, _primaryColor),
      themeMode: _themeMode,
      home: MusicRatingHomePage(
        toggleTheme: toggleTheme,
        themeBrightness: _themeMode == ThemeMode.dark
            ? Brightness.dark
            : (_themeMode == ThemeMode.light ? Brightness.light : brightness),
        onPrimaryColorChanged: updatePrimaryColor,
      ),
    );
  }
}

class MusicRatingHomePage extends StatefulWidget {
  final Function(ThemeMode) toggleTheme;
  final Brightness themeBrightness;
  final Function(Color) onPrimaryColorChanged; // Add this line

  const MusicRatingHomePage({
    super.key,
    required this.toggleTheme,
    required this.themeBrightness,
    required this.onPrimaryColorChanged, // Add this line
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
  String appVersion = '';
  String _latestVersion = '';
  Timer? _clipboardTimer;
  bool _isLoading = false; // Add this line

  @override
  void initState() {
    super.initState();
    _startClipboardListener();
    _loadAppVersion();
    _checkForUpdates();
  }

  void _startClipboardListener() {
    _clipboardTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (!mounted) return;

      try {
        final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
        final text = clipboardData?.text;

        if (text != null && text.isNotEmpty) {
          if (text.contains('music.apple.com') ||
              text.contains('bandcamp.com')) {
            if (searchController.text.isEmpty) {
              setState(() {
                searchController.text = text;
                _performSearch(text);
              });
              // Show clipboard feedback in English
              if (mounted) {
                _showSnackBar('URL detected and copied');
              }
            }
          }
        }
      } catch (e) {
        Logging.severe(
            'Error checking clipboard', e); // Replace print with logging
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
    setState(() {
      appVersion = packageInfo.version;
    });
  }

  // Check for updates by comparing current version with latest GitHub release
  Future<void> _checkForUpdates() async {
    try {
      final response = await http.get(Uri.parse(
          'https://api.github.com/repos/ALi3naTEd0/RateMe/releases/latest'));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final latestVersion = data['tag_name'].toString().replaceAll('v', '');

        if (latestVersion != appVersion) {
          setState(() {
            _latestVersion = latestVersion;
          });
          _showUpdateDialog();
        }
      }
    } catch (e) {
      Logging.severe(
          'Error checking for updates', e); // Replace print with logging
    }
  }

  void _showUpdateDialog() {
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Update Available'),
        content: Text(
            'A new version ($_latestVersion) is available.\nCurrent version: $appVersion'),
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

  void _showAlbumDetails(dynamic album) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DetailsPage(
          album: album,
          isBandcamp:
              album['url']?.toString().contains('bandcamp.com') ?? false,
        ),
      ),
    ).then((_) => _loadSavedAlbums()); // Fix: Add the missing method
  }

  Future<void> _loadSavedAlbums() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      // Replace this line to avoid using undefined _savedAlbums
      // Instead just update loading state since we don't need to store saved albums
      // in the home page (they're already tracked in UserData)
      setState(() => _isLoading = false);
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showSnackBar('Error loading saved albums');
      }
    }
  }

  void _performSearch(String query) async {
    if (query.isEmpty) {
      setState(() => searchResults = []);
      return;
    }

    // Use the _handleSearch method here instead of duplicating code
    await _handleSearch(query);
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _performSearch(query);
    });
  }

  @override
  Widget build(BuildContext context) {
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
        leading: Row(
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
                  // Remove context parameter
                  final result = await UserData.importAlbum();

                  if (result != null && mounted) {
                    final isBandcamp =
                        result['url']?.toString().contains('bandcamp.com') ??
                            false;

                    // Get navigator from key instead of using context
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
        leadingWidth: 120,
        actions: [
          // Remove the backup options icon and just keep the settings icon
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => SettingsPage(
                  currentTheme: widget.themeBrightness == Brightness.dark
                      ? ThemeMode.dark
                      : ThemeMode.light,
                  onThemeChanged: (mode) => widget.toggleTheme(mode),
                  currentPrimaryColor: Theme.of(context).colorScheme.primary,
                  onPrimaryColorChanged: widget.onPrimaryColorChanged,
                ),
              ),
            ),
          ),
        ],
      ),
      body: _isLoading // Use the _isLoading field here
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                const SizedBox(height: 32),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24.0),
                  child: SizedBox(
                    width: MediaQuery.of(context).size.width * 0.85,
                    child: TextField(
                      controller: searchController,
                      decoration: InputDecoration(
                        labelText: 'Search Albums or Paste URL',
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.search),
                          onPressed: () =>
                              _performSearch(searchController.text),
                        ),
                      ),
                      onChanged: _onSearchChanged,
                      maxLength: 255,
                    ),
                  ),
                ),
                Expanded(
                  child: searchResults.isEmpty
                      ? Center(
                          child:
                              Container()) // Replace 'No results found' with empty container
                      : ListView.builder(
                          itemCount: searchResults.length,
                          itemBuilder: (context, index) {
                            final album = searchResults[index];
                            return ListTile(
                              leading: Image.network(
                                album['artworkUrl100'],
                                width: 50,
                                height: 50,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) =>
                                    const Icon(Icons.album),
                              ),
                              title: Text(album['collectionName']),
                              subtitle: Text(album['artistName']),
                              // Fix: Use the BuildContext directly from this closure
                              onTap: () => _showAlbumDetails(
                                  album), // Use _showAlbumDetails here
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
