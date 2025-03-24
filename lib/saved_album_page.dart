import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:html/parser.dart' show parse;
import 'user_data.dart';
import 'logging.dart';
import 'custom_lists_page.dart';
import 'album_model.dart'; // Add this import
import 'share_widget.dart';
import 'dart:io';

class SavedAlbumPage extends StatefulWidget {
  final Map<String, dynamic> album;
  final bool isBandcamp;

  const SavedAlbumPage({
    super.key,
    required this.album,
    required this.isBandcamp,
  });

  @override
  State<SavedAlbumPage> createState() => _SavedAlbumPageState();
}

class _SavedAlbumPageState extends State<SavedAlbumPage> {
  static final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  Album? unifiedAlbum;
  List<Track> tracks = [];
  Map<int, double> ratings = {};
  double averageRating = 0.0;
  int albumDurationMillis = 0; // Add this
  DateTime? releaseDate; // Add this
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      // Convert legacy album to unified model
      unifiedAlbum = Album.fromJson(widget.album);
      Logging.severe(
          'Initialized album in unified model: ${unifiedAlbum?.name}');

      // Load ratings first
      await _loadRatings();

      // Then load tracks based on platform
      if (unifiedAlbum?.platform == 'bandcamp') {
        await _fetchBandcampTracks();
      } else {
        await _fetchItunesTracks();
      }

      if (mounted) {
        setState(() => isLoading = false);
      }
    } catch (e) {
      Logging.severe('Error initializing saved album page', e);
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _loadRatings() async {
    try {
      final List<Map<String, dynamic>> savedRatings =
          await UserData.getSavedAlbumRatings(widget.album['collectionId']);

      if (mounted) {
        Map<int, double> ratingsMap = {};
        for (var rating in savedRatings) {
          ratingsMap[rating['trackId']] = rating['rating'].toDouble();
        }

        setState(() {
          ratings = ratingsMap;
          calculateAverageRating();
        });
      }
    } catch (e) {
      Logging.severe('Error loading ratings', e);
    }
  }

  void calculateAverageRating() {
    var ratedTracks = ratings.values.where((rating) => rating > 0).toList();
    if (ratedTracks.isNotEmpty) {
      double total = ratedTracks.reduce((a, b) => a + b);
      if (mounted) {
        setState(() {
          averageRating = total / ratedTracks.length;
          averageRating = double.parse(averageRating.toStringAsFixed(2));
        });
      }
    } else {
      if (mounted) setState(() => averageRating = 0.0);
    }
  }

  void calculateAlbumDuration() {
    int totalDuration = 0;
    if (widget.isBandcamp) {
      for (var track in tracks) {
        totalDuration += track.durationMs;
      }
    } else {
      for (var track in tracks) {
        totalDuration += track.durationMs;
      }
    }
    if (mounted) setState(() => albumDurationMillis = totalDuration);
  }

  Future<void> _fetchBandcampTracks() async {
    final url = widget.album['url'];
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final document = parse(response.body);
        var ldJsonScript =
            document.querySelector('script[type="application/ld+json"]');

        if (ldJsonScript != null) {
          final ldJson = jsonDecode(ldJsonScript.text);

          if (ldJson != null &&
              ldJson['track'] != null &&
              ldJson['track']['itemListElement'] != null) {
            List<Track> tracksData = [];
            var trackItems = ldJson['track']['itemListElement'] as List;

            final albumId = widget.album['collectionId'];
            final savedRatings = await UserData.getSavedAlbumRatings(albumId);

            for (int i = 0; i < trackItems.length; i++) {
              var item = trackItems[i];
              var track = item['item'];

              var props = track['additionalProperty'] as List;
              var trackIdProp = props.firstWhere((p) => p['name'] == 'track_id',
                  orElse: () => {'value': 0});
              int trackId = trackIdProp['value'];

              String duration = track['duration'] ?? '';
              int durationMillis = _parseDuration(duration);

              tracksData.add(Track(
                id: trackId,
                name: track['name'],
                position: i + 1,
                durationMs: durationMillis,
                metadata: track,
              ));

              var savedRating = savedRatings.firstWhere(
                (r) => r['trackId'] == trackId,
                orElse: () => {'rating': 0.0},
              );

              ratings[trackId] = savedRating['rating'].toDouble();
            }

            if (mounted) {
              setState(() {
                tracks = tracksData;
                try {
                  String dateStr = ldJson['datePublished'];
                  releaseDate =
                      DateFormat("d MMMM yyyy HH:mm:ss 'GMT'").parse(dateStr);
                } catch (e) {
                  try {
                    releaseDate = DateTime.parse(
                        ldJson['datePublished'].replaceAll(' GMT', 'Z'));
                  } catch (e) {
                    releaseDate = DateTime.now();
                  }
                }
                isLoading = false;
                calculateAlbumDuration();
                calculateAverageRating();
              });
            }
          }
        }
      }
    } catch (error, stackTrace) {
      Logging.severe('Error fetching Bandcamp tracks', error, stackTrace);
      if (mounted) setState(() => isLoading = false);
    }
  }

  int _parseDuration(String isoDuration) {
    try {
      if (isoDuration.isEmpty) return 0;

      // Extract numbers between letters using regex
      final regex = RegExp(r'(\d+)(?=[HMS])');
      final matches = regex.allMatches(isoDuration);
      final parts = matches.map((m) => int.parse(m.group(1)!)).toList();

      int totalMillis = 0;
      if (parts.length >= 3) {
        // H:M:S
        totalMillis = ((parts[0] * 3600) + (parts[1] * 60) + parts[2]) * 1000;
      } else if (parts.length == 2) {
        // M:S
        totalMillis = ((parts[0] * 60) + parts[1]) * 1000;
      } else if (parts.length == 1) {
        // S
        totalMillis = parts[0] * 1000;
      }
      return totalMillis;
    } catch (e) {
      Logging.severe('Error parsing duration: $isoDuration - $e');
      return 0;
    }
  }

  Future<void> _fetchItunesTracks() async {
    try {
      final url = Uri.parse(
          'https://itunes.apple.com/lookup?id=${unifiedAlbum?.id}&entity=song');
      final response = await http.get(url);
      final data = jsonDecode(response.body);

      // Convert iTunes tracks to unified model
      List<Track> unifiedTracks = [];
      for (var trackData in data['results']) {
        if (trackData['wrapperType'] == 'track' &&
            trackData['kind'] == 'song') {
          unifiedTracks.add(Track(
            id: trackData['trackId'],
            name: trackData['trackName'],
            position: trackData['trackNumber'],
            durationMs: trackData['trackTimeMillis'] ?? 0,
            metadata: trackData,
          ));
        }
      }

      if (mounted) {
        setState(() {
          tracks = unifiedTracks;
          isLoading = false;
          calculateAlbumDuration();
        });
      }
    } catch (e) {
      Logging.severe('Error fetching iTunes tracks', e);
      if (mounted) setState(() => isLoading = false);
    }
  }

  void _updateRating(int trackId, double newRating) async {
    setState(() {
      ratings[trackId] = newRating;
      calculateAverageRating();
    });

    int albumId = widget.album['collectionId'];
    await UserData.saveRating(albumId, trackId, newRating);
  }

  Future<void> _launchRateYourMusic() async {
    final artistName = widget.album['artistName'];
    final albumName = widget.album['collectionName'];
    final url =
        'https://rateyourmusic.com/search?searchterm=${Uri.encodeComponent(artistName)}+${Uri.encodeComponent(albumName)}&searchtype=l';

    try {
      final uri = Uri.parse(url);
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (error, stackTrace) {
      Logging.severe('Error launching RateYourMusic', error, stackTrace);
      if (mounted) {
        _showSnackBar('Could not open RateYourMusic');
      }
    }
  }

  String formatDuration(int millis) {
    int seconds = (millis ~/ 1000) % 60;
    int minutes = (millis ~/ 1000) ~/ 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  double _calculateTitleWidth() {
    if (tracks.isEmpty) return 0.4;
    return (0.5 - (tracks.length / 100).clamp(0.0, 0.4))
        .toDouble()
        .clamp(0.2, 0.5);
  }

  Widget _buildTrackSlider(int trackId) {
    return SizedBox(
      width: 150,
      child: Row(
        children: [
          Expanded(
            child: SliderTheme(
              data: Theme.of(context)
                  .sliderTheme, // Replace getSliderTheme with direct theme access
              child: Slider(
                min: 0,
                max: 10,
                divisions: 10,
                value: ratings[trackId] ?? 0.0,
                label: (ratings[trackId] ?? 0.0).toStringAsFixed(0),
                onChanged: (newRating) => _updateRating(trackId, newRating),
              ),
            ),
          ),
          SizedBox(
            width: 25,
            child: Text(
              (ratings[trackId] ?? 0).toStringAsFixed(0),
              style: const TextStyle(fontSize: 16),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      // Add this wrapper
      navigatorKey: navigatorKey,
      scaffoldMessengerKey: scaffoldMessengerKey,
      theme: Theme.of(context),
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        appBar: AppBar(
          title: Text(widget.album['collectionName'] ?? 'Unknown Album'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                child: Column(
                  children: [
                    // Album Info Section
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          Image.network(
                            widget.album['artworkUrl100']
                                    ?.replaceAll('100x100', '600x600') ??
                                '',
                            width: 300,
                            height: 300,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                const Icon(Icons.album, size: 300),
                          ),
                          const SizedBox(height: 16),
                          _buildInfoRow("Artist",
                              unifiedAlbum?.artistName ?? 'Unknown Artist'),
                          _buildInfoRow(
                              "Album", unifiedAlbum?.name ?? 'Unknown Album'),
                          _buildInfoRow("Release Date", _formatReleaseDate()),
                          _buildInfoRow(
                              "Duration", formatDuration(albumDurationMillis)),
                          const SizedBox(height: 8),
                          _buildInfoRow(
                              "Rating", averageRating.toStringAsFixed(2),
                              fontSize: 20),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ElevatedButton(
                                onPressed: _showAddToListDialog,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor:
                                      Theme.of(context).colorScheme.primary,
                                  minimumSize: const Size(150, 45),
                                ),
                                child: const Text('Manage Lists',
                                    style: TextStyle(color: Colors.white)),
                              ),
                              const SizedBox(width: 12),
                              ElevatedButton.icon(
                                icon: const Icon(Icons.settings,
                                    color: Colors.white),
                                label: const Text('Options',
                                    style: TextStyle(color: Colors.white)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor:
                                      Theme.of(context).colorScheme.primary,
                                  minimumSize: const Size(150, 45),
                                ),
                                onPressed: () => _showOptionsDialog(),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const Divider(),
                    // Track List with Ratings
                    DataTable(
                      columnSpacing: 12,
                      columns: [
                        const DataColumn(
                            label: SizedBox(
                                width: 35, child: Center(child: Text('#')))),
                        DataColumn(
                          label: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: MediaQuery.of(context).size.width *
                                  _calculateTitleWidth(),
                            ),
                            child: const Text('Title'),
                          ),
                        ),
                        const DataColumn(
                            label: SizedBox(
                                width: 65,
                                child: Center(child: Text('Length')))),
                        const DataColumn(
                            label: SizedBox(
                                width: 160,
                                child: Center(child: Text('Rating')))),
                      ],
                      rows: tracks.map((track) {
                        final trackId = track.id;
                        return DataRow(
                          cells: [
                            DataCell(Text(track.position.toString())),
                            DataCell(
                              ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth: MediaQuery.of(context).size.width *
                                      _calculateTitleWidth(),
                                ),
                                child: Text(
                                  track.name,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            DataCell(Text(formatDuration(track.durationMs))),
                            DataCell(_buildTrackSlider(trackId)),
                          ],
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: _launchRateYourMusic,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                      ),
                      child: const Text(
                        'Rate on RateYourMusic',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
      ),
    );
  }

  void _showShareDialog() {
    final navigator = navigatorKey.currentState;
    if (navigator == null) return;

    navigator.push(
      PageRouteBuilder(
        barrierColor: Colors.black54,
        opaque: false,
        pageBuilder: (_, __, ___) {
          final shareWidget = ShareWidget(
            key: ShareWidget.shareKey,
            album: widget.album,
            tracks: tracks.map((t) => t.toJson()).toList(),
            ratings: ratings,
            averageRating: averageRating,
          );

          return AlertDialog(
            content: SingleChildScrollView(child: shareWidget),
            actions: [
              TextButton(
                onPressed: () => navigator.pop(),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () async {
                  try {
                    final path =
                        await ShareWidget.shareKey.currentState?.saveAsImage();
                    if (mounted && path != null) {
                      navigator.pop();
                      _showShareOptions(path);
                    }
                  } catch (e) {
                    if (mounted) {
                      navigator.pop();
                      _showSnackBar('Error saving image: $e');
                    }
                  }
                },
                child: Text(Platform.isAndroid ? 'Save & Share' : 'Save Image'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showShareOptions(String path) {
    // ...existing code...
  }

  Widget _buildInfoRow(String label, String value, {double fontSize = 16}) {
    return Padding(
      padding: EdgeInsets.symmetric(
        vertical: label == "Rating" ? 8.0 : 2.0,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            "$label: ",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: fontSize),
          ),
          Text(
            value,
            style: TextStyle(fontSize: fontSize),
          ),
        ],
      ),
    );
  }

  void _showSnackBar(String message) {
    scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _showAddToListDialog() {
    final navigator = navigatorKey.currentState;
    if (navigator == null) return;

    navigator
        .push(
      PageRouteBuilder(
        barrierColor: Colors.black54,
        opaque: false,
        pageBuilder: (_, __, ___) => AlertDialog(
          title: const Text('Add to List'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.add),
                title: const Text('Create New List'),
                onTap: () => navigator.pop('new'),
              ),
              const Divider(),
              FutureBuilder<List<CustomList>>(
                future: UserData.getCustomLists(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const CircularProgressIndicator();
                  }
                  final lists = snapshot.data!;
                  return SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: lists
                          .map((list) => ListTile(
                                title: Text(list.name),
                                onTap: () => navigator.pop(list.id),
                              ))
                          .toList(),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    )
        .then((result) async {
      if (result == 'new') {
        _showCreateListDialog();
      } else if (result != null) {
        final lists = await UserData.getCustomLists();
        final selectedList = lists.firstWhere((list) => list.id == result);
        selectedList.albumIds.add(widget.album['collectionId'].toString());
        await UserData.saveCustomList(selectedList);
        _showSnackBar('Added to "${selectedList.name}"');
      }
    });
  }

  void _showCreateListDialog() async {
    final nameController = TextEditingController();
    final descController = TextEditingController();

    final navigator = navigatorKey.currentState;
    if (navigator == null) return;

    final createResult = await navigator.push<bool>(
      PageRouteBuilder(
        barrierColor: Colors.black54,
        opaque: false,
        pageBuilder: (_, __, ___) => AlertDialog(
          title: const Text('Create New List'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'List Name',
                  hintText: 'e.g. Progressive Rock',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: descController,
                decoration: const InputDecoration(
                  labelText: 'Description (optional)',
                  hintText: 'e.g. My favorite prog rock albums',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => navigator.pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => navigator.pop(true),
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );

    if (createResult == true && nameController.text.isNotEmpty) {
      final newList = CustomList(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: nameController.text,
        description: descController.text,
        albumIds: [widget.album['collectionId'].toString()],
      );
      await UserData.saveCustomList(newList);
      if (mounted) {
        _showSnackBar('Added to new list');
      }
    }
  }

  void _showOptionsDialog() {
    final navigator = navigatorKey.currentState;
    if (navigator == null) return;

    navigator.push(
      PageRouteBuilder(
        barrierColor: Colors.black54,
        opaque: false,
        pageBuilder: (_, __, ___) => AlertDialog(
          title: const Text('Album Options'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.file_download),
                title: const Text('Import Album'),
                onTap: () async {
                  navigator.pop();
                  final album = await UserData.importAlbum();
                  if (album != null && mounted) {
                    navigator.pushReplacement(
                      MaterialPageRoute(
                        builder: (_) => SavedAlbumPage(
                          album: album,
                          isBandcamp: album['url']
                                  ?.toString()
                                  .contains('bandcamp.com') ??
                              false,
                        ),
                      ),
                    );
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.file_upload),
                title: const Text('Export Album'),
                onTap: () async {
                  navigator.pop();
                  if (mounted) {
                    await UserData.exportAlbum(widget.album);
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.share),
                title: const Text('Share as Image'),
                onTap: () {
                  navigator.pop();
                  _showShareDialog();
                },
              ),
              ListTile(
                leading: const Icon(Icons.close),
                title: const Text('Close'),
                onTap: () => navigator.pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatReleaseDate() {
    // Fix release date formatting
    try {
      if (unifiedAlbum?.releaseDate != null) {
        return DateFormat('d MMMM yyyy').format(unifiedAlbum!.releaseDate);
      } else if (widget.album['releaseDate'] != null) {
        final dateStr = widget.album['releaseDate'];
        if (dateStr is String) {
          final date = DateTime.parse(dateStr);
          return DateFormat('d MMMM yyyy').format(date);
        }
      }
    } catch (e) {
      Logging.severe('Error formatting release date', e);
    }

    return 'Unknown Date';
  }
}
