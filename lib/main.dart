import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' show parse;
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/services.dart';  // Add this import for Clipboard
import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'saved_ratings_page.dart';
import 'logging.dart';
import 'details_page.dart';
import 'package:file_picker/file_picker.dart';
import 'user_data.dart';
import 'package:path_provider/path_provider.dart';
import 'custom_lists_page.dart';
import 'theme.dart';
import 'footer.dart';
import 'settings_page.dart';
import 'data_migration_service.dart';
import 'search_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Logging.setupLogging();
  
  try {
    // Check if migration is needed, but don't start automatic migration
    final needsMigration = await DataMigrationService.isMigrationNeeded();
    if (needsMigration) {
      Logging.severe('Data migration is needed, but will wait for user initiation');
    } else {
      Logging.severe('Data is already in the latest format');
    }
  } catch (e) {
    Logging.severe('Error checking migration status', e);
  }
  
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool isDarkMode = false;
  Color primaryColor = const Color(0xFF864AF9); // Default color

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      isDarkMode = prefs.getBool('darkMode') ?? false;
      primaryColor = Color(prefs.getInt('primaryColor') ?? 0xFF864AF9);
    });
  }

  void toggleTheme() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      isDarkMode = !isDarkMode;
    });
    await prefs.setBool('darkMode', isDarkMode);
  }

  void updatePrimaryColor(Color color) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      primaryColor = color;
    });
    await prefs.setInt('primaryColor', color.value);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RateMe',
      debugShowCheckedModeBanner: false,
      theme: isDarkMode 
        ? RateMeTheme.getTheme(Brightness.dark, primaryColor)
        : RateMeTheme.getTheme(Brightness.light, primaryColor),
      home: MusicRatingHomePage(
        toggleTheme: toggleTheme,
        themeBrightness: isDarkMode ? Brightness.dark : Brightness.light,
        onPrimaryColorChanged: updatePrimaryColor,  // Add this line
      ),
    );
  }
}

class MusicRatingHomePage extends StatefulWidget {
  final Function toggleTheme;
  final Brightness themeBrightness;
  final Function(Color) onPrimaryColorChanged;  // Add this line

  const MusicRatingHomePage({
    super.key,
    required this.toggleTheme,
    required this.themeBrightness,
    required this.onPrimaryColorChanged,  // Add this line
  });

  @override
  State<MusicRatingHomePage> createState() => _MusicRatingHomePageState();
}

class _MusicRatingHomePageState extends State<MusicRatingHomePage> {
  final TextEditingController searchController = TextEditingController();
  List<dynamic> searchResults = [];
  Timer? _debounce;
  String appVersion = '';
  bool _updateAvailable = false;
  String _latestVersion = '';
  Timer? _clipboardTimer;

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
          if (text.contains('music.apple.com') || text.contains('bandcamp.com')) {
            if (searchController.text.isEmpty) {
              setState(() {
                searchController.text = text;
                _performSearch(text);
              });
              // Show clipboard feedback in English
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('URL detected and copied'),
                    duration: Duration(seconds: 2),
                  ),
                );
              }
            }
          }
        }
      } catch (e) {
        print('Error checking clipboard: $e');
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
      final response = await http.get(
        Uri.parse('https://api.github.com/repos/ALi3naTEd0/RateMe/releases/latest')
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final latestVersion = data['tag_name'].toString().replaceAll('v', '');
        
        if (latestVersion != appVersion) {
          setState(() {
            _updateAvailable = true;
            _latestVersion = latestVersion;
          });
          _showUpdateDialog();
        }
      }
    } catch (e) {
      print('Error checking for updates: $e');
    }
  }

  void _showUpdateDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Update Available'),
        content: Text('A new version ($_latestVersion) is available.\nCurrent version: $appVersion'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Later'),
          ),
          TextButton(
            onPressed: () {
              launchUrl(
                Uri.parse('https://github.com/ALi3naTEd0/RateMe/releases/latest'),
                mode: LaunchMode.externalApplication,
              );
              Navigator.pop(context);
            },
            child: const Text('Update Now'),
          ),
        ],
      ),
    );
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
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const SavedRatingsPage()),
                ),
              ),
            ),
            Expanded(
              child: IconButton(
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.format_list_bulleted),
                tooltip: 'Custom Lists',
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const CustomListsPage()),
                ),
              ),
            ),
            Expanded(
              child: IconButton(
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.file_download),
                tooltip: 'Import Album',
                onPressed: () async {
                  final album = await UserData.importAlbum(context);
                  if (album != null && mounted) {
                    _showAlbumDetails(context, album);
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
                  onThemeChanged: (mode) => widget.toggleTheme(),
                  currentPrimaryColor: Theme.of(context).colorScheme.primary,
                  onPrimaryColorChanged: widget.onPrimaryColorChanged,
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
            child: SizedBox(
              width: MediaQuery.of(context).size.width * 0.85,
              child: TextField(
                controller: searchController,
                decoration: InputDecoration(
                  labelText: 'Search Albums or Paste URL',
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.search),
                    onPressed: () => _performSearch(searchController.text),
                  ),
                ),
                onChanged: _onSearchChanged,
                maxLength: 255,
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
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
                  onTap: () => _showAlbumDetails(context, album),
                );
              },
            ),
          ),
          const AppVersionFooter(),
        ],
      ),
    );
  }

  Future<void> _handleImageSave(String imagePath) async {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.download),
                title: const Text('Save to Downloads'),
                onTap: () async {
                  Navigator.pop(context);
                  try {
                    final downloadDir = Directory('/storage/emulated/0/Download');
                    final fileName = 'RateMe_${DateTime.now().millisecondsSinceEpoch}.png';
                    final newPath = '${downloadDir.path}/$fileName';
                    await File(imagePath).copy(newPath);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Saved to Downloads: $fileName')),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error saving file: $e')),
                      );
                    }
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.share),
                title: const Text('Share Image'),
                onTap: () async {
                  Navigator.pop(context);
                  try {
                    await Share.shareXFiles([XFile(imagePath)]);
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error sharing: $e')),
                      );
                    }
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _launchUrl(String url) async {
    try { 
      final uri = Uri.parse(url);
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (error, stackTrace) {
      Logging.severe('Error launching URL', error, stackTrace);
      // ...error handling...
    }
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _performSearch(query);
    });
  }

  void _performSearch(String query) async {
    if (query.isEmpty) {
      setState(() => searchResults = []);
      return;
    }

    setState(() => searchResults = []); // Clear results while loading
    final results = await SearchService.searchAlbums(query);
    
    if (mounted) {
      setState(() => searchResults = results);
    }
  }

  void _showAlbumDetails(BuildContext context, dynamic album) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DetailsPage(
          album: album,
          isBandcamp: album['url']?.toString().contains('bandcamp.com') ?? false,
        ),
      ),
    );
  }

  Color _getStarIconColor(Brightness themeBrightness) {
    return themeBrightness == Brightness.light
        ? const Color(0xFF864AF9)
        : const Color(0xFF5E35B1);
  }
}
