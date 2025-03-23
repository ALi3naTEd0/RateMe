import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // For MethodChannel
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart'; // This includes all URL launching functions
import 'package:html/parser.dart' show parse;
import 'package:intl/intl.dart';
import 'dart:convert';
import 'dart:io';
import 'user_data.dart';
import 'logging.dart';
import 'custom_lists_page.dart';
import 'share_widget.dart';
import 'package:share_plus/share_plus.dart';
// Add this import
import 'album_model.dart'; // Add this import
import 'model_mapping_service.dart';

class DetailsPage extends StatefulWidget {
  final dynamic album;
  final bool isBandcamp;
  final Map<int, double>? initialRatings;

  const DetailsPage({
    super.key,
    required this.album,
    this.isBandcamp = true,
    this.initialRatings,
  });

  @override
  State<DetailsPage> createState() => _DetailsPageState();
}

class _DetailsPageState extends State<DetailsPage> {
  Album? unifiedAlbum;
  List<dynamic> tracks = [];
  Map<int, double> ratings = {};
  double averageRating = 0.0;
  int albumDurationMillis = 0;
  DateTime? releaseDate;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      // Debug point 3: Input data
      Logging.severe('Details page input data:', widget.album);

      // Try to convert to unified model
      if (ModelMappingService.isLegacyFormat(widget.album)) {
        Logging.severe('Converting legacy album format to unified model');
        unifiedAlbum = await _convertToUnified(widget.album);

        // Debug point 4: Conversion result
        Logging.severe('Converted to unified model:', unifiedAlbum?.toJson());
      } else {
        unifiedAlbum = Album.fromJson(widget.album);
      }

      // Load additional data if needed
      if (unifiedAlbum != null) {
        await _loadAdditionalData();
      }

      if (mounted) {
        setState(() => isLoading = false);
      }
    } catch (e) {
      Logging.severe('Error initializing details page', e);
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  Future<Album?> _convertToUnified(Map<String, dynamic> legacyData) async {
    try {
      // For iTunes data
      if (legacyData['collectionId'] != null) {
        return ModelMappingService.mapItunesSearchResult(legacyData);
      }
      // Add more platform checks as needed
      return null;
    } catch (e) {
      Logging.severe('Error converting to unified model', e);
      return null;
    }
  }

  Future<void> _loadAdditionalData() async {
    // Load tracks, ratings, etc.
    if (unifiedAlbum == null) return;

    try {
      // Load tracks based on platform
      if (unifiedAlbum!.platform == 'itunes') {
        await _fetchItunesTracks();
      } else if (unifiedAlbum!.platform == 'bandcamp') {
        await _fetchBandcampTracks();
      }

      // Load ratings
      await _loadRatings();
    } catch (e) {
      Logging.severe('Error loading additional data', e);
    }
  }

  Future<void> _loadRatings() async {
    try {
      int albumId = unifiedAlbum?.id ?? DateTime.now().millisecondsSinceEpoch;
      List<Map<String, dynamic>> savedRatings =
          await UserData.getSavedAlbumRatings(albumId);

      Map<int, double> ratingsMap = {};
      for (var rating in savedRatings) {
        ratingsMap[rating['trackId']] = rating['rating'].toDouble();
      }

      if (mounted) {
        setState(() {
          ratings = ratingsMap;
          calculateAverageRating();
        });
      }
    } catch (e) {
      Logging.severe('Error loading ratings', e);
    }
  }

  Future<void> _fetchBandcampTracks() async {
    final url = unifiedAlbum?.url;
    try {
      final response = await http.get(Uri.parse(url!));
      if (response.statusCode == 200) {
        final document = parse(response.body);
        var ldJsonScript =
            document.querySelector('script[type="application/ld+json"]');

        if (ldJsonScript != null) {
          final ldJson = jsonDecode(ldJsonScript.text);

          if (ldJson != null && ldJson['track'] != null) {
            var trackItems = ldJson['track']['itemListElement'] as List;
            List<Map<String, dynamic>> tracksData = [];

            final albumId = unifiedAlbum?.id;
            final oldRatingsByPosition =
                await UserData.migrateAlbumRatings(albumId!);

            for (int i = 0; i < trackItems.length; i++) {
              var item = trackItems[i];
              var track = item['item'];
              var props = track['additionalProperty'] as List;

              var trackIdProp = props.firstWhere((p) => p['name'] == 'track_id',
                  orElse: () => {'value': null});
              int trackId = trackIdProp['value'];
              int position = i + 1;

              if (oldRatingsByPosition.containsKey(position)) {
                final oldRating = oldRatingsByPosition[position];
                if (oldRating != null) {
                  double rating = (oldRating['rating'] as num).toDouble();
                  await UserData.saveNewRating(
                      albumId, trackId, position, rating);
                  ratings[trackId] = rating;
                }
              }

              tracksData.add({
                'trackId': trackId,
                'trackNumber': position,
                'title': track['name'],
                'duration': _parseDuration(track['duration']),
                'position': position,
              });
            }

            if (mounted) {
              setState(() {
                tracks = tracksData;
                try {
                  releaseDate = DateFormat("d MMMM yyyy HH:mm:ss 'GMT'")
                      .parse(ldJson['datePublished']);
                } catch (e) {
                  try {
                    releaseDate = DateTime.parse(ldJson['datePublished']);
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

      // Filter only audio tracks, excluding video content
      var trackList = data['results']
          .where((track) =>
              track['wrapperType'] == 'track' && track['kind'] == 'song')
          .toList();

      if (mounted) {
        setState(() {
          tracks = trackList;
          // Fix date parsing
          if (unifiedAlbum?.releaseDate != null) {
            releaseDate = unifiedAlbum!.releaseDate;
          } else {
            releaseDate = DateTime.now();
          }
          // Calculate total duration
          calculateAlbumDuration();
        });
      }
    } catch (error, stackTrace) {
      Logging.severe('Error fetching iTunes tracks', error, stackTrace);
      if (mounted) setState(() => isLoading = false);
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
    if (unifiedAlbum?.platform == 'bandcamp') {
      for (var track in tracks) {
        totalDuration += track['duration'] as int;
      }
    } else {
      // For iTunes tracks
      for (var track in tracks) {
        if (track['trackTimeMillis'] != null) {
          totalDuration += track['trackTimeMillis'] as int;
        }
      }
    }
    if (mounted) setState(() => albumDurationMillis = totalDuration);
  }

  void _updateRating(int trackId, double newRating) async {
    setState(() {
      ratings[trackId] = newRating;
      calculateAverageRating();
    });

    int albumId = unifiedAlbum?.id ?? DateTime.now().millisecondsSinceEpoch;
    await UserData.saveRating(albumId, trackId, newRating);
  }

  Future<void> _launchRateYourMusic() async {
    final artistName = unifiedAlbum?.artistName;
    final albumName = unifiedAlbum?.collectionName;
    final url =
        'https://rateyourmusic.com/search?searchterm=${Uri.encodeComponent(artistName!)}+${Uri.encodeComponent(albumName!)}&searchtype=l';

    try {
      final uri = Uri.parse(url);
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (error, stackTrace) {
      Logging.severe('Error launching RateYourMusic', error, stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open RateYourMusic')),
        );
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

  String _formatReleaseDate() {
    if (unifiedAlbum?.platform == 'bandcamp') {
      if (releaseDate == null) return 'Unknown Date';
      return DateFormat('d MMMM yyyy').format(releaseDate!);
    } else {
      // Fix date formatting for non-bandcamp platforms
      final date = unifiedAlbum?.releaseDate ?? DateTime.now();
      return DateFormat('d MMMM yyyy').format(date);
    }
  }

  Widget _buildTrackTitle(String title, double maxWidth) {
    return Tooltip(
      message: title,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Text(
          title,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    double titleWidthFactor = _calculateTitleWidth();

    return Scaffold(
      appBar: AppBar(
        title: Text(unifiedAlbum?.collectionName ?? 'Unknown Album'),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Image.network(
                      unifiedAlbum?.artworkUrl100
                              .replaceAll('100x100', '600x600') ??
                          '',
                      width: 300,
                      height: 300,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          const Icon(Icons.album, size: 300),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        _buildInfoRow("Artist",
                            unifiedAlbum?.artistName ?? 'Unknown Artist'),
                        _buildInfoRow("Album",
                            unifiedAlbum?.collectionName ?? 'Unknown Album'),
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
                              onPressed: () async {
                                // Save album with filtered tracks
                                final albumToSave = unifiedAlbum?.toJson();
                                albumToSave?['tracks'] = tracks;
                                await _saveAlbum();

                                // Add to saved albums list
                                await UserData.addToSavedAlbums(albumToSave!);

                                if (!mounted) return;
                                _showAddToListDialog(context);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    Theme.of(context).colorScheme.primary,
                                minimumSize: const Size(150, 45),
                              ),
                              child: const Text('Save Album',
                                  style: TextStyle(color: Colors.white)),
                            ),
                            const SizedBox(width: 12),
                            ElevatedButton.icon(
                              icon: const Icon(Icons.settings,
                                  color: Colors
                                      .white), // Changed from more_vert to settings
                              label: const Text('Options',
                                  style: TextStyle(color: Colors.white)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    Theme.of(context).colorScheme.primary,
                                minimumSize: const Size(150, 45),
                              ),
                              onPressed: () => _showOptionsDialog(context),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                  const Divider(),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columnSpacing: 12,
                      headingTextStyle:
                          const TextStyle(fontWeight: FontWeight.bold),
                      columns: [
                        const DataColumn(
                          label: SizedBox(
                            width: 35, // Reducido de 40
                            child: Center(child: Text('No.')),
                          ),
                          numeric: true,
                        ),
                        const DataColumn(
                          label: Center(child: Text('Title')),
                        ),
                        DataColumn(
                          label: Container(
                            width: 65, // Reducido de 70
                            alignment: Alignment.center,
                            child: const Text('Length',
                                textAlign: TextAlign.center),
                          ),
                        ),
                        DataColumn(
                          label: Container(
                            width: 160, // Reducido de 175
                            alignment: Alignment.center,
                            child: const Text('Rating',
                                textAlign: TextAlign.center),
                          ),
                        ),
                      ],
                      rows: tracks.map((track) {
                        final trackId = track['trackId'] ?? 0;
                        final duration = unifiedAlbum?.platform == 'bandcamp'
                            ? track['duration'] ?? 0
                            : track['trackTimeMillis'] ?? 0;

                        return DataRow(
                          cells: [
                            DataCell(
                              SizedBox(
                                width: 35, // Reducido de 40
                                child: Center(
                                  child: Text(track['trackNumber'].toString()),
                                ),
                              ),
                            ),
                            DataCell(_buildTrackTitle(
                              unifiedAlbum?.platform == 'bandcamp'
                                  ? track['title']
                                  : track['trackName'],
                              MediaQuery.of(context).size.width *
                                  titleWidthFactor,
                            )),
                            DataCell(
                              SizedBox(
                                width: 70,
                                child: Text(
                                  formatDuration(duration),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                            DataCell(_buildTrackSlider(trackId)),
                          ],
                        );
                      }).toList(),
                    ),
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
    );
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
            width: 25, // Fixed width for rating number
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

  void _showOptionsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Album Options'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.file_download),
              title: const Text('Import Album'),
              onTap: () async {
                Navigator.pop(context);
                // ...existing import code...
              },
            ),
            ListTile(
              leading: const Icon(Icons.file_upload),
              title: const Text('Export Album'),
              onTap: () async {
                Navigator.pop(context);
                if (!mounted) return;
                if (unifiedAlbum != null) {
                  await UserData.exportAlbum(context, unifiedAlbum!.toJson());
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.share),
              title: const Text('Share as Image'),
              onTap: () => _showShareDialog(context),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddToListDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add to List'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('Create New List'),
              onTap: () => Navigator.pop(context, 'new'),
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
                        .map((CustomList list) => ListTile(
                              title: Text(list.name),
                              onTap: () => Navigator.pop(context, list.id),
                            ))
                        .toList(),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    ).then((result) async {
      if (result == 'new') {
        final nameController = TextEditingController();
        final descController = TextEditingController();

        final createResult = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
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
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Create'),
              ),
            ],
          ),
        );

        if (createResult == true && nameController.text.isNotEmpty) {
          final newList = CustomList(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            name: nameController.text,
            description: descController.text,
            albumIds: [unifiedAlbum?.id.toString() ?? ''],
          );
          await UserData.saveCustomList(newList);
        }
      } else if (result != null) {
        final lists = await UserData.getCustomLists();
        final selectedList = lists.firstWhere((list) => list.id == result);
        if (!selectedList.albumIds.contains(unifiedAlbum?.id.toString())) {
          selectedList.albumIds.add(unifiedAlbum?.id.toString() ?? '');
          await UserData.saveCustomList(selectedList);
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Album added to list successfully')),
        );
      }
    });
  }

  void _showShareDialog(BuildContext context) {
    Navigator.pop(context); // Close options dialog
    showDialog(
      context: context,
      builder: (context) {
        final shareWidget = ShareWidget(
          key: ShareWidget.shareKey,
          album: unifiedAlbum?.toJson() ?? {},
          tracks: tracks,
          ratings: ratings,
          averageRating: averageRating,
        );
        return AlertDialog(
          content: SingleChildScrollView(child: shareWidget),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                try {
                  final path =
                      await ShareWidget.shareKey.currentState?.saveAsImage();
                  if (mounted && path != null) {
                    Navigator.pop(context);
                    if (!mounted) return;

                    if (Platform.isAndroid) {
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
                                      final downloadDir = Directory(
                                          '/storage/emulated/0/Download');
                                      final fileName =
                                          'RateMe_${DateTime.now().millisecondsSinceEpoch}.png';
                                      final newPath =
                                          '${downloadDir.path}/$fileName';

                                      // Copy from temp to Downloads
                                      await File(path).copy(newPath);

                                      // Scan file with MediaScanner
                                      const platform = MethodChannel(
                                          'com.example.rateme/media_scanner');
                                      try {
                                        await platform.invokeMethod(
                                            'scanFile', {'path': newPath});
                                      } catch (e) {
                                        Logging.severe(
                                            'MediaScanner error: $e'); // Replace print with proper logging
                                      }

                                      if (mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                              content: Text(
                                                  'Saved to Downloads: $fileName')),
                                        );
                                      }
                                    } catch (e) {
                                      if (mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                              content: Text(
                                                  'Error saving file: $e')),
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
                                      await Share.shareXFiles([XFile(path)]);
                                    } catch (e) {
                                      if (mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                              content:
                                                  Text('Error sharing: $e')),
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
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Image saved to: $path')),
                      );
                    }
                  }
                } catch (e) {
                  if (mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error saving image: $e')),
                    );
                  }
                }
              },
              child: Text(Platform.isAndroid ? 'Save & Share' : 'Save Image'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _saveAlbum() async {
    try {
      // Keep using Map<String, dynamic> for albumToSave
      await UserData.addToSavedAlbums(unifiedAlbum?.toJson() ?? {});

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Album saved successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving album: $e')),
        );
      }
    }
  }
}
