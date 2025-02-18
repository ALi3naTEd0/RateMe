import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' show parse;
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
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
  bool isDarkMode = false;

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
      debugShowCheckedModeBanner: false,
      theme: isDarkMode ? darkTheme : lightTheme,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rate Me!'),
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
          IconButton(
            icon: const Icon(Icons.storage),
            tooltip: 'Backup Options',
            onPressed: _showOptionsDialog,
          ),
          Transform.scale(
            scale: 0.8,
            child: Switch(
              value: widget.themeBrightness == Brightness.dark,
              onChanged: (_) => widget.toggleTheme(),
              activeColor: Theme.of(context).colorScheme.secondary,
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
        ],
      ),
    );
  }

  void _showOptionsDialog() {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Backup Options'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.file_download),
                title: const Text('Import Backup'),
                onTap: () async {
                  Navigator.pop(dialogContext);
                  
                  if (!mounted) return;
                  final scaffoldContext = context;
                  
                  final success = await UserData.importData(scaffoldContext);
                  if (success && mounted) {
                    ScaffoldMessenger.of(scaffoldContext).showSnackBar(
                      const SnackBar(
                        content: Text('Data imported successfully!'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.file_upload),
                title: const Text('Export Backup'),
                onTap: () async {
                  Navigator.pop(dialogContext);
                  if (!mounted) return;
                  await UserData.exportData(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete),
                title: const Text('Clear All Data'),
                onTap: () async {
                  Navigator.pop(dialogContext);
                  if (!mounted) return;
                  bool? confirm = await _showConfirmDialog();
                  if (confirm == true) {
                    await UserData.clearAllData();
                    if (mounted) {
                      setState(() => searchResults = []);
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
              onPressed: () => Navigator.pop(dialogContext),
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

  void _showAboutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('About Rate Me!'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Version: 1.0.0+1'),
              const SizedBox(height: 12),
              const Text('Author: Eduardo Antonio Fortuny Ruvalcaba'),
              const SizedBox(height: 12),
              const Text('License: GPL-3.0'),
              const SizedBox(height: 12),
              InkWell(
                child: Text(
                  'GitHub Repository',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    decoration: TextDecoration.underline
                  ),
                ),
                onTap: () async {
                  final uri = Uri.parse('https://github.com/ALi3naTEd0/RateMe');
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              child: const Text('Close'),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        );
      },
    );
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
        ? const Color(0xFF864AF9)
        : const Color(0xFF5E35B1);
  }
}

class BandcampService {
  static Future<Map<String, dynamic>> saveAlbum(String url) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        var document = parse(response.body);

        var scriptTags = document.getElementsByTagName('script');
        Map<String, dynamic>? albumData;

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
                albumData = jsonDecode(jsonStr);
                break;
              } catch (e) {
                print('Error parsing album JSON: $e');
              }
            }
          }
        }

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

        List<String> titleParts = title.split(', by ');
        String albumName = titleParts.isNotEmpty ? titleParts[0].trim() : title;
        String artistName = titleParts.length > 1 ? titleParts[1].trim() : artist;

        // Extract or generate a consistent ID for the album
        int albumId = albumData?['id'] ?? 
                     albumData?['current']?['id'] ?? 
                     url.hashCode;  // Use URL as fallback

        return {
          'collectionId': albumId,  // Use real Bandcamp ID
          'collectionName': albumName,
          'artistName': artistName,
          'artworkUrl100': artworkUrl,
          'url': url,
          'albumData': albumData,
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
      // Get JSON-LD directly
      var ldJsonScript = document.querySelector('script[type="application/ld+json"]');
      if (ldJsonScript != null) {
        var ldJson = jsonDecode(ldJsonScript.text);
        if (ldJson != null && ldJson['track'] != null && ldJson['track']['itemListElement'] != null) {
          var trackItems = ldJson['track']['itemListElement'] as List;
          
          for (var item in trackItems) {
            var track = item['item'];
            var props = track['additionalProperty'] as List;
            var trackIdProp = props.firstWhere(
              (p) => p['name'] == 'track_id',
              orElse: () => {'value': null}
            );

            tracks.add({
              'trackId': trackIdProp['value'],
              'trackNumber': item['position'],
              'title': track['name'],
              'duration': _parseDuration(track['duration']),
            });
          }
          
          return tracks;
        }
      }

      // If no JSON-LD, look in TralbumData (fallback)
      var scriptTags = document.getElementsByTagName('script');
      Map<String, dynamic>? trackInfo;

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

      // Ensure consistent trackId generation
      for (int i = 0; i < tracks.length; i++) {
        // Use track title as part of the ID to maintain consistency
        String titleHash = tracks[i]['title'].toString().hashCode.toString();
        tracks[i]['trackId'] = int.parse('${DateTime.now().year}$titleHash');
      }

      Logging.severe('Generated track IDs: ${tracks.map((t) => '${t['title']}: ${t['trackId']}')}');
      
      return tracks;
    } catch (e) {
      Logging.severe('Error extracting tracks: $e');
      return [];
    }
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
