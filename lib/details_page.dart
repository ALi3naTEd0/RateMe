import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // For MethodChannel
import 'package:url_launcher/url_launcher.dart'; // This includes all URL launching functions
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart'; // Add this import
import 'dart:io';
import 'dart:convert'; // Add this import for jsonEncode
import 'package:http/http.dart' as http; // Add this import for HTTP requests
import 'user_data.dart';
import 'logging.dart';
import 'custom_lists_page.dart';
import 'share_widget.dart';
import 'package:share_plus/share_plus.dart';
import 'album_model.dart'; // Add this import
import 'saved_album_page.dart'; // Add this import

class DetailsPage extends StatefulWidget {
  final dynamic album;
  final bool isBandcamp;
  final Map<int, double>? initialRatings;

  const DetailsPage({
    super.key,
    required this.album,
    this.isBandcamp = false,
    this.initialRatings,
  });

  @override
  State<DetailsPage> createState() => _DetailsPageState();
}

class _DetailsPageState extends State<DetailsPage> {
  static final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  Album? unifiedAlbum;
  List<Track> tracks = [];
  Map<String, double> ratings = {};
  double averageRating = 0.0;
  int albumDurationMillis = 0;
  DateTime? releaseDate;
  bool isLoading = true;
  bool useDarkButtonText = false;

  @override
  void initState() {
    super.initState();
    _initialize();
    _loadButtonPreference();
  }

  Future<void> _initialize() async {
    try {
      Logging.severe(
          'Initializing details page for album: ${widget.album['collectionName'] ?? widget.album['name'] ?? 'Unknown'} from platform ${widget.album['platform'] ?? 'unknown'}');

      // Log the raw album data for debugging
      Logging.severe('Raw album data in details page: ${jsonEncode({
            'id': widget.album['collectionId'] ?? widget.album['id'],
            'name': widget.album['collectionName'] ?? widget.album['name'],
            'artist': widget.album['artistName'] ?? widget.album['artist'],
            'platform': widget.album['platform'],
            'hasTracks': widget.album.containsKey('tracks'),
            'trackCount': widget.album['tracks'] is List
                ? (widget.album['tracks'] as List).length
                : widget.album['trackCount'] ?? 0,
            'firstTrackKeys': widget.album['tracks'] is List &&
                    (widget.album['tracks'] as List).isNotEmpty
                ? (widget.album['tracks'][0] as Map<String, dynamic>)
                    .keys
                    .toList()
                : [],
          })}');

      // If album has no tracks, try to fetch them from the API before proceeding
      if (widget.album['tracks'] == null ||
          (widget.album['tracks'] is List && widget.album['tracks'].isEmpty)) {
        Logging.severe('Album has no tracks, attempting to fetch from API');
        await _fetchTracksIfMissing();
      }

      // Convert to unified model if needed
      if (widget.album is Album) {
        unifiedAlbum = widget.album;
      } else if (widget.album['platform'] == 'spotify') {
        // Handle Spotify album with detailed logging
        Logging.severe('Converting Spotify album to unified model');

        // Make sure we have all the required fields
        unifiedAlbum = Album(
          id: widget.album['id'] ?? widget.album['collectionId'] ?? 0,
          name: widget.album['name'] ??
              widget.album['collectionName'] ??
              'Unknown Album',
          artist: widget.album['artist'] ??
              widget.album['artistName'] ??
              'Unknown Artist',
          artworkUrl:
              widget.album['artworkUrl'] ?? widget.album['artworkUrl100'] ?? '',
          url: widget.album['url'] ?? '',
          platform: 'spotify',
          releaseDate: widget.album['releaseDate'] != null
              ? DateTime.tryParse(widget.album['releaseDate']) ?? DateTime.now()
              : DateTime.now(),
          metadata: widget.album,
          tracks: _extractTracksFromAlbum(widget.album),
        );

        Logging.severe(
            'Successfully converted Spotify album to unified model with ${unifiedAlbum?.tracks.length ?? 0} tracks');
      } else if (widget.isBandcamp) {
        // Handle Bandcamp album
        unifiedAlbum = Album(
          id: widget.album['collectionId'] ?? widget.album['id'] ?? 0,
          name: widget.album['collectionName'] ?? 'Unknown Album',
          artist: widget.album['artistName'] ?? 'Unknown Artist',
          artworkUrl: widget.album['artworkUrl100'] ?? '',
          url: widget.album['url'] ?? '',
          platform: 'bandcamp',
          releaseDate: widget.album['releaseDate'] != null
              ? DateTime.parse(widget.album['releaseDate'])
              : DateTime.now(),
          metadata: widget.album,
          tracks: widget.album['tracks'] != null
              ? (widget.album['tracks'] as List)
                  .map<Track>((track) => Track(
                        id: track['trackId'] ?? 0,
                        name: track['trackName'] ?? 'Unknown Track',
                        position: track['trackNumber'] ?? 0,
                        durationMs: track['trackTimeMillis'] ?? 0,
                        metadata: track,
                      ))
                  .toList()
              : [],
        );
      } else {
        // iTunes album
        unifiedAlbum = Album.fromLegacy(widget.album);
      }

      // Set tracks from unified model
      tracks = unifiedAlbum?.tracks ?? [];

      // Debug the tracks
      Logging.severe('Extracted ${tracks.length} tracks from album');
      if (tracks.isNotEmpty) {
        Logging.severe('First track: ${jsonEncode({
              'id': tracks[0].id,
              'name': tracks[0].name,
              'position': tracks[0].position,
              'duration': tracks[0].durationMs,
            })}');
      }

      // Ensure tracks is never null
      if (tracks.isEmpty && widget.album['tracks'] is List) {
        // Handle case where tracks are in the album data but not parsed
        try {
          final tracksList = widget.album['tracks'] as List;
          for (var trackData in tracksList) {
            if (trackData is Map<String, dynamic>) {
              tracks.add(Track(
                id: trackData['trackId'] ?? trackData['id'] ?? 0,
                name: trackData['trackName'] ??
                    trackData['name'] ??
                    'Unknown Track',
                position:
                    trackData['trackNumber'] ?? trackData['position'] ?? 0,
                durationMs: trackData['trackTimeMillis'] ??
                    trackData['durationMs'] ??
                    0,
                metadata: trackData,
              ));
            }
          }
          Logging.severe(
              'Manually parsed ${tracks.length} tracks from album data');
        } catch (e, stack) {
          Logging.severe('Error parsing track data', e, stack);
        }
      }

      // Calculate durations
      calculateAlbumDuration();

      // Load ratings
      if (widget.initialRatings != null) {
        ratings = Map.from(widget.initialRatings!);
      } else {
        await _loadRatings();
      }

      if (mounted) {
        setState(() {
          isLoading = false;
          calculateAverageRating();
        });
      }
    } catch (e, stack) {
      Logging.severe('Error initializing details page', e, stack);
      if (mounted) setState(() => isLoading = false);
    }
  }

  // Add this new method to fetch tracks for albums that are missing them
  Future<void> _fetchTracksIfMissing() async {
    try {
      final albumId = widget.album['collectionId'] ?? widget.album['id'];
      if (albumId == null) return;

      Logging.severe('Fetching missing tracks for album ID: $albumId');

      // Try the regular iTunes lookup first
      final url =
          Uri.parse('https://itunes.apple.com/lookup?id=$albumId&entity=song');
      final response = await http.get(url);
      final data = jsonDecode(response.body);

      // Check if we got tracks
      if (data['results'] != null && data['results'].length > 1) {
        final tracks = data['results']
            .skip(1) // Skip the album info (first result)
            .where((item) =>
                item['wrapperType'] == 'track' && item['kind'] == 'song')
            .toList();

        if (tracks.isNotEmpty) {
          Logging.severe('Found ${tracks.length} tracks via direct API call');
          widget.album['tracks'] = tracks;
          return;
        }
      }

      // If no tracks found, try alternate albums
      Logging.severe('No tracks found, searching for alternate album version');
      final artistName = widget.album['artistName'] ?? '';
      final albumName = widget.album['collectionName'] ?? '';

      if (artistName.isNotEmpty && albumName.isNotEmpty) {
        final searchUrl = Uri.parse(
            'https://itunes.apple.com/search?term=${Uri.encodeComponent("$artistName $albumName")}'
            '&entity=album&limit=5');

        final searchResponse = await http.get(searchUrl);
        final searchData = jsonDecode(searchResponse.body);

        if (searchData['results'] != null && searchData['results'].isNotEmpty) {
          // Find similar albums
          for (var album in searchData['results']) {
            if (album['collectionId'] != albumId &&
                album['artistName'] == artistName &&
                album['collectionName']
                    .toString()
                    .contains(albumName.split('(')[0].trim())) {
              // Try this album instead
              final altUrl = Uri.parse(
                  'https://itunes.apple.com/lookup?id=${album['collectionId']}&entity=song');
              final altResponse = await http.get(altUrl);
              final altData = jsonDecode(altResponse.body);

              if (altData['results'] != null && altData['results'].length > 1) {
                final altTracks = altData['results']
                    .skip(1)
                    .where((item) =>
                        item['wrapperType'] == 'track' &&
                        item['kind'] == 'song')
                    .toList();

                if (altTracks.isNotEmpty) {
                  Logging.severe(
                      'Found ${altTracks.length} tracks from alternate album: ${album['collectionName']}');
                  widget.album['tracks'] = altTracks;
                  return;
                }
              }
            }
          }
        }
      }

      // If all else fails, create dummy tracks based on trackCount
      if (widget.album['trackCount'] != null &&
          widget.album['trackCount'] > 0) {
        Logging.severe(
            'Creating dummy tracks based on trackCount: ${widget.album['trackCount']}');
        final List<dynamic> dummyTracks = [];

        for (int i = 1; i <= widget.album['trackCount']; i++) {
          dummyTracks.add({
            'trackId': albumId * 1000 + i,
            'trackName': 'Track $i',
            'trackNumber': i,
            'trackTimeMillis': 0,
            'kind': 'song',
            'wrapperType': 'track',
          });
        }

        widget.album['tracks'] = dummyTracks;
      }
    } catch (e, stack) {
      Logging.severe('Error fetching missing tracks', e, stack);
    }
  }

  Future<void> _loadRatings() async {
    try {
      final albumId = unifiedAlbum?.id ?? '';
      final savedRatings = await UserData.getSavedAlbumRatings(albumId);

      Map<String, double> ratingsMap = {};
      for (var rating in savedRatings) {
        ratingsMap[rating['trackId'].toString()] = rating['rating'].toDouble();
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
    albumDurationMillis =
        tracks.fold(0, (sum, track) => sum + track.durationMs);
  }

  void _updateRating(dynamic trackId, double newRating) async {
    final ratingKey = trackId.toString();

    // Add logging to track what's happening
    Logging.severe('Updating rating for track $trackId to $newRating');

    setState(() {
      ratings[ratingKey] = newRating;
      calculateAverageRating();
    });

    // Make sure we have a valid album ID
    final albumId = unifiedAlbum?.id ?? DateTime.now().millisecondsSinceEpoch;

    // Save the rating with proper ID handling
    await UserData.saveRating(albumId, trackId, newRating);
    Logging.severe(
        'Rating saved successfully for album $albumId, track $trackId');
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
        scaffoldMessengerKey.currentState?.showSnackBar(
          const SnackBar(content: Text('Could not open RateYourMusic')),
        );
      }
    }
  }

  String formatDuration(int millis) {
    if (millis == 0) return '--:--';
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

  @override
  Widget build(BuildContext context) {
    // Calculate page width consistently with other pages (85% of screen width)
    final pageWidth = MediaQuery.of(context).size.width * 0.85;
    final horizontalPadding =
        (MediaQuery.of(context).size.width - pageWidth) / 2;

    // Calculate DataTable width to fit within our constraints
    // This allows the DataTable to scale properly while staying within our pageWidth
    final dataTableWidth = pageWidth - 16; // Apply small padding

    return MaterialApp(
      navigatorKey: navigatorKey,
      scaffoldMessengerKey: scaffoldMessengerKey,
      debugShowCheckedModeBanner: false,
      theme: Theme.of(context), // Use parent theme
      home: Scaffold(
        appBar: AppBar(
          centerTitle: false,
          automaticallyImplyLeading: false,
          title: Padding(
            padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  onPressed: () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    unifiedAlbum?.collectionName ?? 'Unknown Album',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
        body: isLoading
            ? const Center(child: CircularProgressIndicator())
            : Center(
                // Center the content
                child: SizedBox(
                  width: pageWidth, // Apply consistent width constraint
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const SizedBox(height: 16),
                        // Album artwork
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
                        // Album info section
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            children: [
                              _buildInfoRow("Artist",
                                  unifiedAlbum?.artistName ?? 'Unknown Artist'),
                              _buildInfoRow(
                                  "Album",
                                  unifiedAlbum?.collectionName ??
                                      'Unknown Album'),
                              _buildInfoRow(
                                  "Release Date", _formatReleaseDate()),
                              _buildInfoRow("Duration",
                                  formatDuration(albumDurationMillis)),
                              const SizedBox(height: 8),
                              _buildInfoRow(
                                  "Rating", averageRating.toStringAsFixed(2),
                                  fontSize: 20),
                              const SizedBox(height: 16),
                              // Buttons row
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  FilledButton(
                                    onPressed: () async {
                                      // Remove the auto-save here
                                      _showAddToListDialog(); // Just show the dialog directly
                                    },
                                    style: FilledButton.styleFrom(
                                      backgroundColor:
                                          Theme.of(context).colorScheme.primary,
                                      foregroundColor: useDarkButtonText
                                          ? Colors.black
                                          : Colors.white,
                                      minimumSize: const Size(150, 45),
                                    ),
                                    child: const Text('Save Album'),
                                  ),
                                  const SizedBox(width: 12),
                                  FilledButton.icon(
                                    // Changed from ElevatedButton.icon
                                    icon: Icon(Icons.settings,
                                        color: useDarkButtonText
                                            ? Colors.black
                                            : Colors.white),
                                    label: Text(
                                      'Options',
                                      style: TextStyle(
                                          color: useDarkButtonText
                                              ? Colors.black
                                              : Colors.white),
                                    ),
                                    style: FilledButton.styleFrom(
                                      backgroundColor:
                                          Theme.of(context).colorScheme.primary,
                                      foregroundColor: useDarkButtonText
                                          ? Colors.black
                                          : Colors.white,
                                      minimumSize: const Size(150, 45),
                                    ),
                                    onPressed: () => _showOptionsDialog(),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                            ],
                          ),
                        ),
                        const Divider(),
                        // DataTable for tracks - make sure it fits within the width constraint
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: dataTableWidth,
                          ),
                          child: DataTable(
                            columnSpacing: 12,
                            columns: [
                              const DataColumn(
                                label: SizedBox(
                                  width: 35,
                                  child: Center(child: Text('#')),
                                ),
                              ),
                              DataColumn(
                                label: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxWidth:
                                        MediaQuery.of(context).size.width *
                                            _calculateTitleWidth(),
                                  ),
                                  child: const Text('Title'),
                                ),
                              ),
                              const DataColumn(
                                label: SizedBox(
                                  width: 65,
                                  child: Center(child: Text('Length')),
                                ),
                              ),
                              const DataColumn(
                                label: SizedBox(
                                  width: 160,
                                  child: Center(child: Text('Rating')),
                                ),
                              ),
                            ],
                            rows: tracks.map((track) {
                              final trackId = track.id;
                              return DataRow(
                                cells: [
                                  DataCell(Text(track.position.toString())),
                                  DataCell(_buildTrackTitle(
                                    track.name,
                                    MediaQuery.of(context).size.width *
                                        _calculateTitleWidth(),
                                  )),
                                  DataCell(
                                      Text(formatDuration(track.durationMs))),
                                  DataCell(_buildTrackSlider(trackId)),
                                ],
                              );
                            }).toList(),
                          ),
                        ),
                        const SizedBox(height: 20),
                        FilledButton(
                          // Changed from ElevatedButton
                          onPressed: _launchRateYourMusic,
                          style: FilledButton.styleFrom(
                            backgroundColor:
                                Theme.of(context).colorScheme.primary,
                            foregroundColor:
                                useDarkButtonText ? Colors.black : Colors.white,
                            minimumSize: const Size(150, 45),
                          ),
                          child: const Text('Rate on RateYourMusic'),
                        ),
                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ),
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

  Widget _buildTrackSlider(dynamic trackId) {
    final ratingKey = trackId.toString();
    return SizedBox(
      width: 150,
      child: Row(
        children: [
          Expanded(
            child: SliderTheme(
              data: Theme.of(context).sliderTheme,
              child: Slider(
                min: 0,
                max: 10,
                divisions: 10,
                value: ratings[ratingKey] ?? 0.0,
                label: (ratings[ratingKey] ?? 0.0).toStringAsFixed(0),
                onChanged: (newRating) => _updateRating(trackId, newRating),
              ),
            ),
          ),
          SizedBox(
            width: 25,
            child: Text(
              (ratings[ratingKey] ?? 0).toStringAsFixed(0),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
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
                  final album =
                      await UserData.importAlbum(); // Remove context parameter
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
                  if (!mounted) return;
                  if (unifiedAlbum != null) {
                    await UserData.exportAlbum(
                        unifiedAlbum!.toJson()); // Remove context parameter
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.share),
                title: const Text('Share as Image'),
                onTap: () => _showShareDialog(),
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

  void _showAddToListDialog() {
    final navigator = navigatorKey.currentState;
    if (navigator == null) return;

    // Track selected lists
    Map<String, bool> selectedLists = {};

    navigator
        .push(
      PageRouteBuilder(
        barrierColor: Colors.black54,
        opaque: false,
        pageBuilder: (_, __, ___) => StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: const Text('Save to Lists'),
            content: SizedBox(
              width: MediaQuery.of(context).size.width * 0.5,
              height: MediaQuery.of(context).size.height * 0.5,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FilledButton.icon(
                    icon: Icon(Icons.add,
                        color: useDarkButtonText ? Colors.black : Colors.white),
                    label: Text('Create New List',
                        style: TextStyle(
                            color: useDarkButtonText
                                ? Colors.black
                                : Colors.white)),
                    style: FilledButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor:
                          useDarkButtonText ? Colors.black : Colors.white,
                    ),
                    onPressed: () => navigator.pop('new'),
                  ),
                  const Divider(),
                  Expanded(
                    child: FutureBuilder<List<CustomList>>(
                      future: UserData.getCustomLists(),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) {
                          return const Center(
                              child: CircularProgressIndicator());
                        }
                        final lists = snapshot.data!;

                        // Initialize selected state for lists containing the album
                        for (var list in lists) {
                          if (!selectedLists.containsKey(list.id)) {
                            selectedLists[list.id] = list.albumIds
                                .contains(unifiedAlbum?.id.toString());
                          }
                        }

                        return ListView(
                          children: lists
                              .map((list) => CheckboxListTile(
                                    title: Text(list.name),
                                    subtitle:
                                        Text('${list.albumIds.length} albums'),
                                    value: selectedLists[list.id] ?? false,
                                    onChanged: (bool? value) {
                                      setState(() {
                                        selectedLists[list.id] = value ?? false;
                                      });
                                    },
                                  ))
                              .toList(),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => navigator.pop(null),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor:
                      useDarkButtonText ? Colors.black : Colors.white,
                ),
                onPressed: () => navigator.pop(selectedLists),
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    )
        .then((result) async {
      if (result == null) return; // Dialog cancelled

      if (result == 'new') {
        _showCreateListDialog();
        return;
      }

      // Save the album first since user made selections
      final albumToSave = unifiedAlbum?.toJson();
      albumToSave?['tracks'] = tracks;
      await _saveAlbum();
      await UserData.addToSavedAlbums(albumToSave!);

      // Handle selected lists
      final Map<String, bool> selections = result as Map<String, bool>;
      final lists = await UserData.getCustomLists();
      int addedCount = 0;
      int removedCount = 0;

      for (var list in lists) {
        final isSelected = selections[list.id] ?? false;
        final hasAlbum = list.albumIds.contains(unifiedAlbum?.id.toString());

        if (isSelected && !hasAlbum) {
          // Add to list
          list.albumIds.add(unifiedAlbum?.id.toString() ?? '');
          await UserData.saveCustomList(list);
          addedCount++;
        } else if (!isSelected && hasAlbum) {
          // Remove from list
          list.albumIds.remove(unifiedAlbum?.id.toString());
          await UserData.saveCustomList(list);
          removedCount++;
        }
      }

      if (mounted) {
        String message = '';
        if (addedCount > 0) message += 'Added to $addedCount lists. ';
        if (removedCount > 0) message += 'Removed from $removedCount lists.';
        if (message.isNotEmpty) {
          scaffoldMessengerKey.currentState?.showSnackBar(
            SnackBar(content: Text(message.trim())),
          );
        }
      }
    });
  }

  void _showCreateListDialog() {
    final navigator = navigatorKey.currentState;
    if (navigator == null) return;

    final nameController = TextEditingController();
    final descController = TextEditingController();

    navigator.push(
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
              onPressed: () => navigator.pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                if (nameController.text.isNotEmpty) {
                  final newList = CustomList(
                    id: DateTime.now().millisecondsSinceEpoch.toString(),
                    name: nameController.text,
                    description: descController.text,
                    albumIds: [unifiedAlbum?.id.toString() ?? ''],
                  );
                  await UserData.saveCustomList(newList);
                  if (mounted) {
                    scaffoldMessengerKey.currentState?.showSnackBar(
                      SnackBar(content: Text('Created list "${newList.name}"')),
                    );
                  }
                }
                navigator.pop();
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }

  void _showShareDialog() {
    final navigator = navigatorKey.currentState;
    if (navigator == null) return;

    // Add some debug logging
    Logging.severe(
        'Preparing to show share dialog with ${tracks.length} tracks');
    if (tracks.isNotEmpty) {
      Logging.severe(
          'First track: ${tracks[0].id} (${tracks[0].id.runtimeType}), ${tracks[0].name}');
    }

    // Log some info about the ratings map
    Logging.severe('Ratings map has ${ratings.length} entries');
    if (ratings.isNotEmpty) {
      Logging.severe(
          'First rating key type: ${ratings.keys.first.runtimeType}');
    }

    // Convert ratings to string keys and ensure all track IDs are properly represented
    final stringRatings = <String, double>{};
    for (var entry in ratings.entries) {
      stringRatings[entry.key.toString()] = entry.value;
    }

    // Add ratings for any missing tracks with zero values
    for (var track in tracks) {
      final trackIdStr = track.id.toString();
      if (!stringRatings.containsKey(trackIdStr)) {
        stringRatings[trackIdStr] = 0.0;
      }
    }

    navigator.push(
      PageRouteBuilder(
        barrierColor: Colors.black54,
        opaque: false,
        pageBuilder: (_, __, ___) {
          final shareWidget = ShareWidget(
            key: ShareWidget.shareKey,
            album: unifiedAlbum?.toJson() ?? {},
            tracks: tracks,
            ratings: stringRatings, // Use our prepared string ratings map
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
                    // Call saveAsImage through the widget's state key
                    final path =
                        await ShareWidget.shareKey.currentState?.saveAsImage();
                    if (mounted && path != null) {
                      navigator.pop();
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
                                      navigator.pop();
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
                                          scaffoldMessengerKey.currentState
                                              ?.showSnackBar(
                                            SnackBar(
                                                content: Text(
                                                    'Saved to Downloads: $fileName')),
                                          );
                                        }
                                      } catch (e) {
                                        if (mounted) {
                                          scaffoldMessengerKey.currentState
                                              ?.showSnackBar(
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
                                      navigator.pop();
                                      try {
                                        await Share.shareXFiles([XFile(path)]);
                                      } catch (e) {
                                        if (mounted) {
                                          scaffoldMessengerKey.currentState
                                              ?.showSnackBar(
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
                        scaffoldMessengerKey.currentState?.showSnackBar(
                          SnackBar(content: Text('Image saved to: $path')),
                        );
                      }
                    }
                  } catch (e) {
                    if (mounted) {
                      navigator.pop();
                      scaffoldMessengerKey.currentState?.showSnackBar(
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
      ),
    );
  }

  Future<void> _saveAlbum() async {
    try {
      if (unifiedAlbum == null) return;

      Logging.severe(
          'Saving album: ${unifiedAlbum!.name} (ID: ${unifiedAlbum!.id})');

      // Convert album to JSON with full track data
      final albumData = unifiedAlbum!.toJson();

      // Ensure tracks are properly serialized
      albumData['tracks'] = tracks.map((track) => track.toJson()).toList();

      // Log what we're trying to save
      Logging.severe(
          'Saving album with ${tracks.length} tracks and ID type: ${unifiedAlbum!.id.runtimeType}');

      // Save album first and wait for completion
      await UserData.addToSavedAlbums(albumData);

      // Verify the album was saved
      final albumExists =
          await UserData.albumExists(unifiedAlbum!.id.toString());
      if (!albumExists) {
        Logging.severe(
            'WARNING: Album may not have been saved correctly. ID: ${unifiedAlbum!.id}');
      } else {
        Logging.severe('Album saved successfully. ID: ${unifiedAlbum!.id}');
      }

      // Brief delay to ensure album is saved before ratings
      await Future.delayed(const Duration(milliseconds: 500));

      // Save ratings separately with improved error handling
      int ratingsSaved = 0;
      for (var entry in ratings.entries) {
        try {
          // Parse track ID - properly handle numeric strings
          dynamic trackId;
          if (int.tryParse(entry.key) != null) {
            trackId = int.parse(entry.key);
          } else {
            trackId = entry.key; // Keep as string if not numeric
          }

          // Only save non-zero ratings (important!)
          if (entry.value > 0) {
            await UserData.saveRating(
              unifiedAlbum!.id,
              trackId,
              entry.value,
            );
            ratingsSaved++;
            Logging.severe('Saved rating for track $trackId: ${entry.value}');
          }
        } catch (e) {
          Logging.severe('Error saving rating for track ${entry.key}: $e');
        }
      }

      Logging.severe(
          'Saved $ratingsSaved ratings for album ${unifiedAlbum!.id}');

      if (mounted) {
        scaffoldMessengerKey.currentState?.showSnackBar(
          const SnackBar(content: Text('Album saved successfully')),
        );
      }
    } catch (e, stack) {
      Logging.severe('Error saving album', e, stack);
      if (mounted) {
        scaffoldMessengerKey.currentState?.showSnackBar(
          SnackBar(content: Text('Error saving album: $e')),
        );
      }
    }
  }

  // Helper method to extract tracks from album data
  List<Track> _extractTracksFromAlbum(Map<String, dynamic> album) {
    List<Track> result = [];

    try {
      if (album['tracks'] is List) {
        final tracksList = album['tracks'] as List;
        Logging.severe(
            'Extracting ${tracksList.length} tracks from album data');

        for (var i = 0; i < tracksList.length; i++) {
          try {
            final trackData = tracksList[i];
            if (trackData is Map<String, dynamic>) {
              result.add(Track(
                id: trackData['trackId'] ??
                    trackData['id'] ??
                    (album['id'] * 1000 + i + 1),
                name: trackData['trackName'] ??
                    trackData['name'] ??
                    'Track ${i + 1}',
                position:
                    trackData['trackNumber'] ?? trackData['position'] ?? i + 1,
                durationMs: trackData['trackTimeMillis'] ??
                    trackData['durationMs'] ??
                    0,
                metadata: trackData,
              ));
            }
          } catch (e) {
            Logging.severe('Error parsing track at index $i: $e');
          }
        }
      }
    } catch (e, stack) {
      Logging.severe('Error extracting tracks from album', e, stack);
    }

    return result;
  }

  // Add this method to DetailsPage
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

  Future<void> _loadButtonPreference() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        useDarkButtonText = prefs.getBool('useDarkButtonText') ?? false;
      });
    }
  }
}
