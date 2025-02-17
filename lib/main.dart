import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' show parse;
import 'package:intl/intl.dart';  // Agregamos este import
import 'dart:convert';
import 'dart:async';
// Removemos la importación de footer.dart
// Remove import 'saved_preferences_page.dart'
import 'saved_ratings_page.dart';
import 'logging.dart';
import 'details_page.dart';  // Nuevo import
// Remover imports de bandcamp_details_page.dart y album_details_page.dart
// Remove import of search_page.dart
import 'package:file_picker/file_picker.dart';
import 'user_data.dart';  // Agregar esta importación
import 'package:path_provider/path_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Configura el sistema de logging
  Logging.setupLogging();

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool isDarkMode = false;

  // Integramos las definiciones de tema desde app_theme.dart
  final ThemeData lightTheme = ThemeData.light().copyWith(
    colorScheme: const ColorScheme.light().copyWith(
      primary: const Color(0xFF864AF9),
      secondary: const Color(0xFF5E35B1),
    ),
    sliderTheme: const SliderThemeData(
      thumbColor: Color(0xFF864AF9),
      activeTrackColor: Color(0xFF864AF9),
      valueIndicatorTextStyle: TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.bold,
      ),
    ),
  );

  final ThemeData darkTheme = ThemeData.dark().copyWith(
    colorScheme: const ColorScheme.dark().copyWith(
      primary: const Color(0xFF5E35B1),
      secondary: const Color(0xFF864AF9),
    ),
    sliderTheme: const SliderThemeData(
      thumbColor: Color(0xFF5E35B1),
      activeTrackColor: Color(0xFF5E35B1),
      valueIndicatorTextStyle: TextStyle(
        color: Colors.black,
        fontWeight: FontWeight.bold,
      ),
    ),
  );

  @override
  void initState() {
    super.initState();
    _loadThemeMode();
  }

  Future<void> _loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      isDarkMode = prefs.getBool('darkMode') ?? false;
    });
  }

  void toggleTheme() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      isDarkMode = !isDarkMode;
      prefs.setBool('darkMode', isDarkMode);
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RateMe',
      debugShowCheckedModeBanner: false, // Agregar esta línea
      theme: isDarkMode ? darkTheme : lightTheme,  // Usamos las definiciones locales
      home: MusicRatingHomePage(
        toggleTheme: toggleTheme,
        themeBrightness: isDarkMode ? Brightness.dark : Brightness.light,
      ),
    );
  }
}

class MusicRatingHomePage extends StatefulWidget {
  final Function toggleTheme;
  final Brightness themeBrightness;

  const MusicRatingHomePage({
    super.key,
    required this.toggleTheme,
    required this.themeBrightness,
  });

  @override
  State<MusicRatingHomePage> createState() => _MusicRatingHomePageState();
}

class _MusicRatingHomePageState extends State<MusicRatingHomePage> {
  final TextEditingController searchController = TextEditingController();
  List<dynamic> searchResults = [];
  Timer? _debounce;

  void _showOptionsDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Options'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.file_download),
                title: const Text('Import Data'),
                onTap: () async {
                  Navigator.pop(context);
                  final success = await UserData.importData(context);
                  if (success && mounted) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const SavedRatingsPage(),
                      ),
                    );
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.file_upload),
                title: const Text('Export Data'),
                onTap: () {
                  Navigator.pop(context);
                  UserData.exportData(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete),
                title: const Text('Clear All Data'),
                onTap: () async {
                  Navigator.pop(context);
                  bool? confirm = await _showConfirmDialog();
                  if (confirm == true) {
                    await UserData.clearAllData();
                    if (mounted) {
                      setState(() {
                        searchResults = [];
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('All data cleared')),
                      );
                    }
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Future<bool?> _showConfirmDialog() {
    return showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirm Delete'),
          content: const Text('Are you sure you want to delete all data? This cannot be undone.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rate Me!'),
        centerTitle: true,
        leading: Tooltip(
          message: 'Saved Ratings',
          child: IconButton(
            icon: Icon(Icons.star,
                size: 32, color: _getStarIconColor(widget.themeBrightness)),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const SavedRatingsPage()),
            ),
          ),
        ),
        actions: [
          Tooltip(
            message: 'Theme',
            child: Transform.scale(
              scale: 0.8,
              child: Switch(
                value: widget.themeBrightness == Brightness.dark,
                onChanged: (_) => widget.toggleTheme(),
                activeColor: Theme.of(context).colorScheme.secondary,
              ),
            ),
          ),
          Tooltip(
            message: 'Settings',
            child: IconButton(
              icon: const Icon(Icons.settings),
              onPressed: _showOptionsDialog,
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
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
        ],
      ),
    );
  }

  // Add search methods from SearchPage
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

    if (query.contains('bandcamp.com')) {
      _fetchBandcampAlbumInfo(query);
    } else {
      _fetchiTunesAlbums(query);
    }
  }

  void _fetchiTunesAlbums(String query) async {
    final url = Uri.parse(
        'https://itunes.apple.com/search?term=${Uri.encodeComponent(query)}&entity=album');
    try {
      final response = await http.get(url);
      final data = jsonDecode(response.body);
      if (mounted) {
        setState(() => searchResults = data['results']);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error searching iTunes: $e')),
        );
      }
    }
  }

  void _fetchBandcampAlbumInfo(String url) async {
    try {
      final albumInfo = await BandcampService.saveAlbum(url);
      if (mounted) {
        setState(() => searchResults = [albumInfo]);
      }
    } catch (e) {
      if (mounted) {
        setState(() => searchResults = []);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load Bandcamp album: $e')),
        );
      }
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
        ? const Color(0xFF864AF9)  // Light theme primary color
        : const Color(0xFF5E35B1); // Dark theme primary color
  }
}

class BandcampService {
  static Future<Map<String, dynamic>> saveAlbum(String url) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        var document = parse(response.body);

        // Extraer datos del meta OG y datos específicos de Bandcamp
        var scriptTags = document.getElementsByTagName('script');
        Map<String, dynamic>? albumData;

        // Buscar el script con los datos del álbum
        for (var script in scriptTags) {
          String content = script.text;
          if (content.contains('data-tralbum')) {
            // Encontrar el objeto JSON del álbum
            final regex = RegExp(r'data-tralbum="([^"]*)"');
            final match = regex.firstMatch(content);
            if (match != null) {
              String jsonStr = match.group(1)!
                  .replaceAll('&quot;', '"')
                  .replaceAll('&amp;', '&');
              try {
                albumData = jsonDecode(jsonStr);
                break;
              } catch (e) {
                print('Error parsing album JSON: $e');
              }
            }
          }
        }

        // Extraer información básica del álbum
        String title = document
                .querySelector('meta[property="og:title"]')
                ?.attributes['content'] ??
            albumData?['current']?['title'] ??
            'Unknown Title';
        String artist = document
                .querySelector('meta[property="og:site_name"]')
                ?.attributes['content'] ??
            albumData?['artist'] ??
            'Unknown Artist';
        String artworkUrl = document
                .querySelector('meta[property="og:image"]')
                ?.attributes['content'] ??
            '';

        // Limpiar el título si contiene ", by "
        List<String> titleParts = title.split(', by ');
        String albumName = titleParts.isNotEmpty ? titleParts[0].trim() : title;
        String artistName = titleParts.length > 1 ? titleParts[1].trim() : artist;

        return {
          'collectionId': DateTime.now().millisecondsSinceEpoch,
          'collectionName': albumName,
          'artistName': artistName,
          'artworkUrl100': artworkUrl,
          'url': url,
          'albumData': albumData, // Guardamos los datos completos para usar en extractTracks
        };
      }
      throw Exception('Failed to load Bandcamp album');
    } catch (e) {
      throw Exception('Failed to fetch album info: $e');
    }
  }

  static List<Map<String, dynamic>> extractTracks(dynamic document) {
    List<Map<String, dynamic>> tracks = [];
    try {
      var scriptTags = document.getElementsByTagName('script');
      Map<String, dynamic>? trackInfo;

      // Primer intento: buscar en data-tralbum
      for (var script in scriptTags) {
        String content = script.text;
        if (content.contains('data-tralbum')) {
          final regex = RegExp(r'data-tralbum="([^"]*)"');
          final match = regex.firstMatch(content);
          if (match != null) {
            String jsonStr = match.group(1)!
                .replaceAll('&quot;', '"')
                .replaceAll('&amp;', '&');
            try {
              trackInfo = jsonDecode(jsonStr);
              if (trackInfo!.containsKey('trackinfo')) {
                List<dynamic> trackList = trackInfo['trackinfo'];
                for (int i = 0; i < trackList.length; i++) {
                  var track = trackList[i];
                  tracks.add({
                    'trackId': DateTime.now().millisecondsSinceEpoch + i,
                    'trackNumber': i + 1,
                    'title': track['title'] ?? 'Unknown Track',
                    'duration': (track['duration'] ?? 0) * 1000,
                  });
                }
                return tracks;
              }
            } catch (e) {
              print('Error parsing data-tralbum JSON: $e');
            }
          }
        }
      }

      // Segundo intento: buscar en TralbumData
      for (var script in scriptTags) {
        String content = script.text;
        if (content.contains('TralbumData')) {
          int start = content.indexOf('TralbumData = ') + 'TralbumData = '.length;
          int end = content.indexOf('};', start) + 1;
          String jsonStr = content.substring(start, end);
          
          try {
            trackInfo = jsonDecode(jsonStr);
            if (trackInfo!.containsKey('trackinfo')) {
              List<dynamic> trackList = trackInfo['trackinfo'];
              for (int i = 0; i < trackList.length; i++) {
                var track = trackList[i];
                tracks.add({
                  'trackId': DateTime.now().millisecondsSinceEpoch + i,
                  'trackNumber': i + 1,
                  'title': track['title'] ?? 'Unknown Track',
                  'duration': (track['duration'] ?? 0) * 1000,
                });
              }
              return tracks;
            }
          } catch (e) {
            print('Error parsing TralbumData JSON: $e');
          }
        }
      }

      // Tercer intento: parsear directamente la tabla de tracks
      var trackRows = document.querySelectorAll('table#track_table tr.track_row_view');
      if (trackRows.isNotEmpty) {
        for (int i = 0; i < trackRows.length; i++) {
          var row = trackRows[i];
          var title = row.querySelector('.track-title')?.text?.trim() ?? 'Unknown Track';
          var durationElement = row.querySelector('.time');
          int duration = 0;

          if (durationElement != null) {
            var durationText = durationElement.text.trim();
            var parts = durationText.split(':');
            if (parts.length == 2) {
              duration = (int.parse(parts[0]) * 60 + int.parse(parts[1])) * 1000;
            }
          }

          tracks.add({
            'trackId': DateTime.now().millisecondsSinceEpoch + i,
            'trackNumber': i + 1,
            'title': title,
            'duration': duration,
          });
        }
      }
    } catch (e) {
      print('Error extracting tracks: $e');
    }
    
    return tracks;
  }

  static int _parseDuration(String duration) {
    try {
      final regex = RegExp(r'PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?');
      final match = regex.firstMatch(duration);
      
      if (match != null) {
        final hours = int.tryParse(match.group(1) ?? '0') ?? 0;
        final minutes = int.tryParse(match.group(2) ?? '0') ?? 0;
        final seconds = int.tryParse(match.group(3) ?? '0') ?? 0;
        return (hours * 3600 + minutes * 60 + seconds) * 1000;
      }

      // Try parsing MM:SS format
      final parts = duration.split(':');
      if (parts.length == 2) {
        final minutes = int.tryParse(parts[0]) ?? 0;
        final seconds = int.tryParse(parts[1]) ?? 0;
        return (minutes * 60 + seconds) * 1000;
      }
    } catch (e) {
      print('Error parsing duration: $e');
    }
    return 0;
  }

  static DateTime? extractReleaseDate(dynamic document) {
    var element = document.querySelector('.tralbumData.tralbum-credits');
    if (element != null) {
      RegExp dateRegExp = RegExp(r'released (\w+ \d{1,2}, \d{4})');
      var match = dateRegExp.firstMatch(element.text);
      if (match != null) {
        try {
          return DateFormat('MMMM d, yyyy').parse(match.group(1)!);
        } catch (e) {
          print('Error parsing date: $e');
        }
      }
    }
    return null;
  }
}
