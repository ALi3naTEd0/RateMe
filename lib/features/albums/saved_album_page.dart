import 'dart:async';
import 'dart:convert'; // <-- Add this line
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:rateme/core/services/theme_service.dart';
import 'package:rateme/database/database_helper.dart';
import 'package:rateme/platforms/platform_service_factory.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/services/user_data.dart';
import '../../core/services/logging.dart';
import '../../core/utils/color_utility.dart';
import '../custom_lists/custom_lists_page.dart';
import '../../core/models/album_model.dart';
import '../../ui/widgets/share_widget.dart';
import 'dart:io';
import '../../ui/widgets/skeleton_loading.dart';
import '../search/platform_match_widget.dart';
import '../../core/utils/dominant_color.dart';
import '../../ui/widgets/dominant_color_picker.dart';

class SavedAlbumPage extends StatefulWidget {
  final Map<String, dynamic>? album;
  final bool isBandcamp;
  final String? albumId;

  const SavedAlbumPage({
    super.key,
    this.album,
    this.isBandcamp = false,
    this.albumId,
  });

  @override
  State<SavedAlbumPage> createState() => _SavedAlbumPageState();
}

class _SavedAlbumPageState extends State<SavedAlbumPage> {
  static final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  Map<String, dynamic> _albumData = {};
  Album? unifiedAlbum;
  List<Track> tracks = [];
  Map<String, double> ratings = {};
  double averageRating = 0.0;
  int albumDurationMillis = 0;
  DateTime? releaseDate;
  bool isLoading = true;
  bool useDarkButtonText = false;
  final GlobalKey<RefreshIndicatorState> _refreshIndicatorKey =
      GlobalKey<RefreshIndicatorState>();
  String? albumNote;

  List<Color> dominantColors = [];
  Color? selectedDominantColor;
  bool loadingPalette = false;
  bool showColorPicker = false; // Add this line

  @override
  void initState() {
    super.initState();

    // ADD THIS CHECK:
    if ((widget.albumId == null || widget.albumId!.isEmpty) &&
        (widget.album == null || widget.album!.isEmpty)) {
      Logging.severe('ERROR: SavedAlbumPage requires either album or albumId!');
      setState(() {
        isLoading = false;
        _albumData = {
          'name': 'Error: No album selected',
          'collectionName': 'Error: No album selected',
          'artist': '',
          'artistName': '',
          'artworkUrl100': '',
          'url': '',
        };
      });
      return;
    }

    _albumData = {
      'id': '',
      'collectionId': '',
      'name': 'Unknown Album',
      'collectionName': 'Unknown Album',
      'artist': 'Unknown Artist',
      'artistName': 'Unknown Artist',
      'artworkUrl100': '',
      'url': '',
    };
    _loadButtonPreference();
    _stepLoadAlbum();
    _loadAlbumNote(); // Load the note for the album
    // Remove _loadDominantColors() from here - it will be called after album loads
  }

  Future<void> _loadButtonPreference() async {
    final dbHelper = DatabaseHelper.instance;
    final buttonPref = await dbHelper.getSetting('useDarkButtonText');
    if (mounted) {
      setState(() {
        useDarkButtonText = buttonPref == 'true';
      });
    }
  }

  Future<void> _loadAlbumNote() async {
    try {
      // Fix: Use either album ID or collectionId, ensuring we have a valid ID string
      final id = widget.albumId ??
          _albumData['id'] ??
          _albumData['collectionId'] ??
          '';
      Logging.severe('Loading album note for ID: $id');

      if (id.isEmpty) {
        Logging.severe('Cannot load album note: No valid album ID found');
        return;
      }

      final note = await UserData.getAlbumNote(id);
      Logging.severe(
          'Retrieved album note: ${note != null ? "Found" : "None"}');

      if (mounted) {
        setState(() {
          albumNote = note;
        });
      }
    } catch (e, stack) {
      Logging.severe('Error loading album note', e, stack);
    }
  }

  Future<void> _editAlbumNote() async {
    // Fix: Use either album ID or collectionId, ensuring we have a valid ID string
    final id =
        widget.albumId ?? _albumData['id'] ?? _albumData['collectionId'] ?? '';

    if (id.isEmpty) {
      Logging.severe('Cannot edit album note: No valid album ID found');
      return;
    }

    final newNote = await showDialog<String>(
      context: context,
      builder: (context) {
        final controller = TextEditingController(text: albumNote);
        return AlertDialog(
          title: Row(
            children: [
              Icon(
                Icons.edit_note,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              const Text('Album Notes'),
              const Spacer(),
              // Add copy button to dialog
              if (albumNote != null && albumNote!.isNotEmpty)
                IconButton(
                  icon: Icon(
                    Icons.copy,
                    color: Theme.of(context).colorScheme.primary,
                    size: 20,
                  ),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: albumNote!));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Notes copied to clipboard'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                  tooltip: 'Copy to clipboard',
                ),
            ],
          ),
          content: TextField(
            controller: controller,
            maxLines: 10,
            decoration: InputDecoration(
              hintText:
                  'Write your notes, review, or thoughts about this album...',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(controller.text),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (newNote != null) {
      // Fix: Save the note using the correct album ID
      await UserData.saveAlbumNote(id, newNote);
      Logging.severe('Saved album note for ID: $id');
      setState(() {
        albumNote = newNote;
      });
    }
  }

  // Step 1: Load album data
  Future<void> _stepLoadAlbum() async {
    setState(() => isLoading = true);
    try {
      if ((widget.albumId != null && widget.albumId!.isNotEmpty)) {
        await _loadAlbumFromDatabase(widget.albumId!);
      } else if (widget.album != null) {
        _albumData = widget.album!;
        if (!_albumData.containsKey('id') || _albumData['id'] == null) {
          _albumData['id'] = _albumData['collectionId'] ?? '';
        }
        if (!_albumData.containsKey('collectionId') ||
            _albumData['collectionId'] == null) {
          _albumData['collectionId'] = _albumData['id'] ?? '';
        }
      }
      unifiedAlbum = Album.fromJson(_albumData);

      // Load saved dominant color after album data is loaded
      await _loadSavedDominantColor();

      await _stepLoadRatings();
    } catch (e, stack) {
      Logging.severe('Error loading album', e, stack);
      setState(() => isLoading = false);
    }
  }

  // Add method to load saved dominant color
  Future<void> _loadSavedDominantColor() async {
    final albumId = widget.albumId ??
        _albumData['id']?.toString() ??
        _albumData['collectionId']?.toString() ??
        '';
    if (albumId.isNotEmpty) {
      final dbHelper = DatabaseHelper.instance;
      final savedColor = await dbHelper.getDominantColor(albumId);
      if (savedColor != null && savedColor.isNotEmpty) {
        try {
          final colorValue =
              int.parse(savedColor.replaceFirst('#', ''), radix: 16);
          setState(() {
            selectedDominantColor = Color(0xFF000000 | colorValue);
          });
          Logging.severe('Loaded saved dominant color: $savedColor');
        } catch (e) {
          Logging.severe('Error parsing saved color: $e');
        }
      }
    }
  }

  // Add method to save dominant color to database
  Future<void> _saveDominantColor(Color? color) async {
    final albumId = widget.albumId ??
        _albumData['id']?.toString() ??
        _albumData['collectionId']?.toString() ??
        '';
    if (albumId.isNotEmpty) {
      final dbHelper = DatabaseHelper.instance;
      if (color != null) {
        final colorHex =
            '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';
        await dbHelper.saveDominantColor(albumId, colorHex);
      } else {
        await dbHelper.saveDominantColor(albumId, '');
      }
    }
  }

  // Step 2: Load ratings
  Future<void> _stepLoadRatings() async {
    try {
      final albumId =
          unifiedAlbum?.id ?? _albumData['id'] ?? _albumData['collectionId'];
      final dbHelper = DatabaseHelper.instance;
      final ratingsList = await dbHelper.getRatingsForAlbum(albumId.toString());
      ratings = {
        for (var r in ratingsList)
          r['track_id'].toString(): (r['rating'] as num).toDouble()
      };
      calculateAverageRating();
      await _stepLoadTracks();
    } catch (e, stack) {
      Logging.severe('Error loading ratings', e, stack);
      setState(() => isLoading = false);
    }
  }

  // Step 3: Load tracks (DB -> metadata -> API -> fallback)
  Future<void> _stepLoadTracks() async {
    try {
      final albumId =
          unifiedAlbum?.id ?? _albumData['id'] ?? _albumData['collectionId'];
      final dbHelper = DatabaseHelper.instance;
      // Try DB
      final dbTracks = await dbHelper.getTracksForAlbum(albumId.toString());
      if (dbTracks.isNotEmpty) {
        tracks = dbTracks.map((t) => Track.fromJson(t)).toList();
        Logging.severe('Loaded ${tracks.length} tracks from DB');
        _attachRatingsToTracks();
        return _finishLoad();
      }

      // --- IMPROVED METADATA EXTRACTION ---
      // Check multiple sources for track data
      List<Track> metaTracks = [];

      // First check if tracks are directly in the album data
      if (_albumData['tracks'] is List) {
        final rawTracks = _albumData['tracks'] as List;
        Logging.severe(
            'Found ${rawTracks.length} tracks directly in album data');
        for (var t in rawTracks) {
          try {
            metaTracks.add(Track.fromJson(t));
          } catch (e) {
            Logging.severe('Error parsing track: $e');
          }
        }
      }

      // If no tracks found, check the data field
      if (metaTracks.isEmpty && _albumData['data'] != null) {
        Map<String, dynamic>? dataMap;

        // Parse the data field if it's a string
        if (_albumData['data'] is String) {
          try {
            dataMap = jsonDecode(_albumData['data']);
            Logging.severe('Successfully parsed data field as JSON');
          } catch (e) {
            Logging.severe('Error parsing data field as JSON: $e');
          }
        } else if (_albumData['data'] is Map) {
          dataMap = _albumData['data'] as Map<String, dynamic>;
        }

        // Extract tracks from the data map
        if (dataMap != null &&
            dataMap.containsKey('tracks') &&
            dataMap['tracks'] is List) {
          final rawTracks = dataMap['tracks'] as List;
          Logging.severe('Found ${rawTracks.length} tracks in data field');
          for (var t in rawTracks) {
            try {
              metaTracks.add(Track.fromJson(t));
            } catch (e) {
              Logging.severe('Error parsing track from data field: $e');
            }
          }
        }
      }

      // If we found tracks from metadata, use them and save to DB
      if (metaTracks.isNotEmpty) {
        tracks = metaTracks;
        await dbHelper.insertTracks(
            albumId.toString(), metaTracks.map((t) => t.toJson()).toList());
        Logging.severe(
            'Saved ${tracks.length} tracks from metadata to database');
        _attachRatingsToTracks();
        return _finishLoad();
      }

      // --- FIX: Skip API fetch for Bandcamp ---
      final platform = unifiedAlbum!.platform.toLowerCase();
      if (platform == 'bandcamp') {
        Logging.severe(
            'Bandcamp: Skipping API fetch, using only saved metadata and ratings');
        // Fallback: create tracks from ratings if needed
        if (tracks.isEmpty && ratings.isNotEmpty) {
          tracks = [];
          int pos = 1;
          for (final entry in ratings.entries) {
            tracks.add(Track(
              id: entry.key,
              name: 'Track $pos',
              position: pos,
              durationMs: 0,
            ));
            pos++;
          }
          Logging.severe('Created ${tracks.length} tracks from ratings');
          _attachRatingsToTracks();
        }
        return _finishLoad();
      }
      // --- END FIX ---

      // Try API for other platforms
      if (unifiedAlbum!.url.isNotEmpty) {
        final platformFactory = PlatformServiceFactory();
        if (platformFactory.isPlatformSupported(platform)) {
          final service = platformFactory.getService(platform);
          final details = await service.fetchAlbumDetails(unifiedAlbum!.url);
          if (details != null && details['tracks'] is List) {
            final fetchedTracks = <Track>[];
            for (var t in details['tracks']) {
              try {
                fetchedTracks.add(Track.fromJson(t));
              } catch (_) {}
            }
            if (fetchedTracks.isNotEmpty) {
              tracks = fetchedTracks;
              await dbHelper.insertTracks(albumId.toString(),
                  fetchedTracks.map((t) => t.toJson()).toList());
              Logging.severe(
                  'Loaded ${tracks.length} tracks from platform API');
              _attachRatingsToTracks();
              return _finishLoad();
            }
          }
        }
      }
      // Fallback: create tracks from ratings
      if (tracks.isEmpty && ratings.isNotEmpty) {
        tracks = [];
        int pos = 1;
        for (final entry in ratings.entries) {
          tracks.add(Track(
            id: entry.key,
            name: 'Track $pos',
            position: pos,
            durationMs: 0,
          ));
          pos++;
        }
        Logging.severe('Created ${tracks.length} tracks from ratings');
        _attachRatingsToTracks();
      }
      _finishLoad();
    } catch (e, stack) {
      Logging.severe('Error loading tracks', e, stack);
      setState(() => isLoading = false);
    }
  }

  // Attach ratings to tracks by id or position
  void _attachRatingsToTracks() {
    for (int i = 0; i < tracks.length; i++) {
      final tid = tracks[i].id.toString();
      double? rating = ratings[tid];
      if (rating == null) {
        // Try position-based match (for Discogs/legacy)
        String posStr = tracks[i].position.toString().padLeft(3, '0');
        for (final key in ratings.keys) {
          if (key.endsWith(posStr)) {
            rating = ratings[key];
            break;
          }
        }
      }
      if (rating != null) {
        tracks[i] = Track(
          id: tracks[i].id,
          name: tracks[i].name,
          position: tracks[i].position,
          durationMs: tracks[i].durationMs,
          metadata: {...tracks[i].metadata, 'rating': rating},
        );
      }
    }
  }

  void _finishLoad() {
    calculateAlbumDuration();
    setState(() => isLoading = false);
    // Add this line to load colors after album data is ready
    _loadDominantColors();
  }

  Future<void> _loadAlbumFromDatabase(String albumId) async {
    try {
      Logging.severe('Loading album from database: $albumId');
      final db = await DatabaseHelper.instance.database;
      final results = await db.query(
        'albums',
        where: 'id = ?',
        whereArgs: [albumId],
      );

      if (results.isEmpty) {
        Logging.severe('No album found with ID: $albumId');
        return;
      }

      final albumData = results.first;

      // Enhanced debug logging for release date fields
      Logging.severe(
          'Retrieving album release date info for "${albumData['name'] ?? albumData['id']}":');
      Logging.severe(
          'Database release_date field: ${albumData['release_date']}');
      Logging.severe('Database releaseDate field: ${albumData['releaseDate']}');

      // Extract and process raw data field if available
      if (albumData['data'] != null && albumData['data'] is String) {
        try {
          final dataJson = jsonDecode(albumData['data'] as String);
          if (dataJson is Map<String, dynamic>) {
            Logging.severe(
                'From data JSON: releaseDate field: ${dataJson['releaseDate']}');
            Logging.severe(
                'From data JSON: release_date field: ${dataJson['release_date']}');
          }
        } catch (e) {
          Logging.severe('Error parsing data JSON for debug: $e');
        }
      }

      // Ensure all artwork keys are set for UI compatibility
      String? artworkUrl = albumData['artworkUrl'] as String?;
      String? artworkUrl100 = albumData['artworkUrl100'] as String?;
      String? artworkUrlAlt =
          albumData['artwork_url'] as String?; // old snake_case

      // Prefer artworkUrl100, then artworkUrl, then artwork_url
      String resolvedArtwork =
          artworkUrl100 ?? artworkUrl ?? artworkUrlAlt ?? '';

      // First, set base album properties
      _albumData = {
        'id': albumData['id'],
        'collectionId': albumData['id'],
        'name': albumData['name'],
        'collectionName': albumData['name'],
        'artist': albumData['artist'],
        'artistName': albumData['artist'],
        // Set both keys for UI compatibility
        'artworkUrl': resolvedArtwork,
        'artworkUrl100': resolvedArtwork,
        'artwork_url': resolvedArtwork,
        'url': albumData['url'],
        'platform': albumData['platform'],
      };

      // CRITICAL FIX: Properly handle release date
      // Try multiple sources for release date in this priority order
      String? releaseDate;

      // 1. First check database column
      if (albumData['release_date'] != null &&
          albumData['release_date'].toString().isNotEmpty) {
        releaseDate = albumData['release_date'].toString();
        Logging.severe('Found primary release_date in database: $releaseDate');
      }

      // 2. Camel case variant
      else if (albumData['releaseDate'] != null &&
          albumData['releaseDate'].toString().isNotEmpty) {
        releaseDate = albumData['releaseDate'].toString();
        Logging.severe('Found alternate releaseDate in database: $releaseDate');
      }

      // 3. Check the data field as a fallback
      else if (albumData['data'] != null && albumData['data'] is String) {
        try {
          final dataJson = jsonDecode(albumData['data'] as String);
          if (dataJson is Map<String, dynamic>) {
            if (dataJson['releaseDate'] != null &&
                dataJson['releaseDate'].toString().isNotEmpty) {
              releaseDate = dataJson['releaseDate'].toString();
              Logging.severe(
                  'Found releaseDate in album metadata: $releaseDate');
            } else if (dataJson['release_date'] != null &&
                dataJson['release_date'].toString().isNotEmpty) {
              releaseDate = dataJson['release_date'].toString();
              Logging.severe(
                  'Found release_date in album metadata: $releaseDate');
            }
          }
        } catch (e) {
          Logging.severe('Error extracting release date from metadata: $e');
        }
      }

      // If we found a release date from any source, add it to our album data
      if (releaseDate != null) {
        _albumData['releaseDate'] = releaseDate;
        _albumData['release_date'] = releaseDate;
        Logging.severe('Using release date for album: $releaseDate');
      } else {
        Logging.severe('No release date found for album');
      }

      // --- Merge metadata from 'data' field ---
      if (albumData['data'] != null && albumData['data'] is String) {
        try {
          final meta = jsonDecode(albumData['data'] as String);
          if (meta is Map<String, dynamic>) {
            // Merge metadata into _albumData
            _albumData['metadata'] = meta;

            // If tracks are present in metadata, also set at top-level for easier access
            if (meta['tracks'] is List && meta['tracks'].isNotEmpty) {
              _albumData['tracks'] = meta['tracks'];
              Logging.severe(
                  'Merged ${meta['tracks'].length} tracks from album metadata');
            }
          }
        } catch (e) {
          Logging.severe('Error parsing album metadata JSON', e);
        }
      }

      Logging.severe(
          'Successfully loaded album: ${_albumData['name']} by ${_albumData['artist']}');
    } catch (e, stack) {
      Logging.severe('Error loading album from database', e, stack);
    }
  }

  void _updateRating(dynamic trackId, double newRating) async {
    try {
      // Ensure trackId is a string
      final trackIdStr = trackId.toString();

      Logging.severe('Updating rating for track $trackIdStr to $newRating');

      // Get album ID in the right format
      final albumId =
          unifiedAlbum?.id ?? _albumData['collectionId'] ?? _albumData['id'];

      if (albumId == null) {
        Logging.severe('Cannot save rating - album ID is null');
        return;
      }

      // Update state
      setState(() {
        ratings[trackIdStr] = newRating;
      });

      // Also update the track metadata if we can find the track
      for (int i = 0; i < tracks.length; i++) {
        if (tracks[i].id.toString() == trackIdStr) {
          // Create a new track with updated metadata
          final updatedTrack = Track(
            id: tracks[i].id,
            name: tracks[i].name,
            position: tracks[i].position,
            durationMs: tracks[i].durationMs,
            metadata: {...tracks[i].metadata, 'rating': newRating},
          );

          // Update the track in the list
          setState(() {
            tracks[i] = updatedTrack;
          });
          break;
        }
      }

      // Delay calculation slightly to ensure state is updated
      await Future.delayed(const Duration(milliseconds: 50));
      calculateAverageRating();

      // Save rating to SQLite instead of SharedPreferences
      final dbHelper = DatabaseHelper.instance;
      await dbHelper.saveRating(albumId.toString(), trackIdStr, newRating);

      // Verify the save
      final savedRatings =
          await dbHelper.getRatingsForAlbum(albumId.toString());

      // Log current ratings state
      Logging.severe('Current ratings map: $ratings');
      Logging.severe('Saved ratings from storage: $savedRatings');

      if (!savedRatings.any((r) =>
          r['track_id'].toString() == trackIdStr &&
          (r['rating'] as num).toDouble() == newRating)) {
        Logging.severe(
            'Warning: Rating verification failed - storage mismatch');
      } else {
        Logging.severe('Rating verified in storage successfully');
      }
    } catch (e, stack) {
      Logging.severe('Error updating rating', e, stack);
    }
  }

  Future<void> _launchRateYourMusic() async {
    final artistName = _albumData['artistName'];
    final albumName = _albumData['collectionName'];
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

  Widget _buildTrackSlider(dynamic trackId) {
    // Get the track index by ID
    int trackIndex = -1;
    final trackIdStr = trackId.toString();

    for (int i = 0; i < tracks.length; i++) {
      if (tracks[i].id.toString() == trackIdStr) {
        trackIndex = i;
        break;
      }
    }

    // Initialize rating value
    double ratingValue = 0.0;

    // Check multiple sources for ratings in this priority:
    // 1. First check if the track's metadata has a rating
    if (trackIndex >= 0 && tracks[trackIndex].metadata.containsKey('rating')) {
      ratingValue = tracks[trackIndex].metadata['rating'].toDouble();
      Logging.severe(
          'Found rating in track metadata for $trackIdStr: $ratingValue');
    }
    // 2. Check the ratings map directly
    else if (ratings.containsKey(trackIdStr)) {
      ratingValue = ratings[trackIdStr] ?? 0.0;
      Logging.severe(
          'Found rating in ratings map for $trackIdStr: $ratingValue');
    }
    // 3. Try position-based matching (for Discogs primarily)
    else if (trackIndex >= 0) {
      int position = tracks[trackIndex].position;
      String positionStr = position.toString().padLeft(3, '0');

      // Look for any rating key with this position
      for (String key in ratings.keys) {
        if (key.endsWith(positionStr)) {
          ratingValue = ratings[key] ?? 0.0;
          Logging.severe(
              'Found position-based rating for track $trackIdStr (position $positionStr): $ratingValue from key $key');
          break;
        }
      }
    }

    // Always log the final rating value for debugging
    Logging.severe(
        'Using rating $ratingValue for track $trackIdStr (ID type: ${trackId.runtimeType})');

    return SizedBox(
      width: 150,
      child: Row(
        children: [
          Expanded(
            child: SliderTheme(
              // Use selectedDominantColor directly instead of Theme.of(context)
              data: SliderThemeData(
                showValueIndicator: ShowValueIndicator.always,
                activeTrackColor: selectedDominantColor ??
                    Theme.of(context).colorScheme.primary,
                inactiveTrackColor: (selectedDominantColor ??
                        Theme.of(context).colorScheme.primary)
                    .withAlpha(76),
                thumbColor: selectedDominantColor ??
                    Theme.of(context).colorScheme.primary,
                overlayColor: (selectedDominantColor ??
                        Theme.of(context).colorScheme.primary)
                    .withAlpha(76),
                valueIndicatorColor: selectedDominantColor ??
                    Theme.of(context).colorScheme.primary,
                valueIndicatorTextStyle: TextStyle(
                  color: useDarkButtonText
                      ? Colors.black
                      : ColorUtility.getContrastingColor(
                          selectedDominantColor ??
                              Theme.of(context).colorScheme.primary),
                ),
              ),
              child: Slider(
                min: 0,
                max: 10,
                divisions: 10,
                value: ratingValue,
                label: ratingValue.toStringAsFixed(0),
                onChanged: (newRating) => _updateRating(trackId, newRating),
              ),
            ),
          ),
          SizedBox(
            width: 25,
            child: Text(
              ratingValue.toStringAsFixed(0),
              style: const TextStyle(fontSize: 16),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
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

  Future<void> _refreshData() async {
    if (mounted) {
      setState(() {
        isLoading = true;
      });
    }

    await _stepLoadAlbum();

    scaffoldMessengerKey.currentState?.showSnackBar(
      const SnackBar(content: Text('Album information refreshed')),
    );
  }

  Future<void> _loadDominantColors() async {
    setState(() => loadingPalette = true);
    final url = _albumData['artworkUrl100'] ?? _albumData['artworkUrl'] ?? '';
    if (url.isEmpty) {
      setState(() {
        dominantColors = [];
        loadingPalette = false;
      });
      return;
    }
    final colors =
        await getDominantColorsFromUrl(url.replaceAll('100x100', '600x600'));
    setState(() {
      dominantColors = colors;
      loadingPalette = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Use the responsive width factor
    final pageWidth = MediaQuery.of(context).size.width *
        ThemeService.getContentMaxWidthFactor(context);
    final horizontalPadding =
        (MediaQuery.of(context).size.width - pageWidth) / 2;

    // Get the correct icon color based on theme brightness
    final iconColor = Theme.of(context).brightness == Brightness.dark
        ? Colors.white
        : Colors.black;

    // Calculate DataTable width to fit within our constraints
    final dataTableWidth = pageWidth - 16; // Apply small padding

    // Create a custom theme with the selected dominant color if available
    final effectiveTheme = selectedDominantColor != null
        ? Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
                  primary: selectedDominantColor!,
                ),
          )
        : Theme.of(context);

    return Theme(
      data: effectiveTheme, // Apply the custom theme to the entire page
      child: Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(
            centerTitle: false,
            automaticallyImplyLeading: false,
            title: Padding(
              padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back, color: iconColor),
                    padding: const EdgeInsets.all(8.0),
                    constraints: const BoxConstraints(),
                    iconSize: 24.0,
                    splashRadius: 28.0,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _albumData['collectionName'] ??
                          _albumData['name'] ??
                          'Unknown Album',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.more_vert, color: iconColor),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    onPressed: _showOptionsDialog,
                  ),
                ],
              ),
            ),
          ),
          body: Center(
            child: isLoading
                ? _buildSkeletonAlbumDetails()
                : SizedBox(
                    width: pageWidth,
                    child: RefreshIndicator(
                      key: _refreshIndicatorKey,
                      onRefresh: _refreshData,
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            const SizedBox(height: 16),
                            // Album Info Section
                            Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                children: [
                                  // --- FIX: Use the best available artwork field ---
                                  Padding(
                                    padding: const EdgeInsets.all(8.0),
                                    child: Builder(
                                      builder: (context) {
                                        final artwork =
                                            _albumData['artworkUrl100'] ??
                                                _albumData['artworkUrl'] ??
                                                '';
                                        if (artwork.isNotEmpty) {
                                          return Image.network(
                                            artwork.replaceAll(
                                                '100x100', '600x600'),
                                            width: 300,
                                            height: 300,
                                            fit: BoxFit.cover,
                                            errorBuilder:
                                                (context, error, stackTrace) =>
                                                    const Icon(Icons.album,
                                                        size: 300),
                                          );
                                        } else {
                                          return const Icon(Icons.album,
                                              size: 300);
                                        }
                                      },
                                    ),
                                  ),

                                  // --- Collapsible Dominant Color Picker ---
                                  if (loadingPalette)
                                    const Padding(
                                      padding:
                                          EdgeInsets.symmetric(vertical: 8.0),
                                      child: CircularProgressIndicator(),
                                    )
                                  else if (dominantColors.isNotEmpty)
                                    Column(
                                      children: [
                                        // Color picker button
                                        Padding(
                                          padding: const EdgeInsets.only(
                                              bottom: 8.0),
                                          child: OutlinedButton.icon(
                                            onPressed: () {
                                              setState(() {
                                                showColorPicker =
                                                    !showColorPicker;
                                              });
                                            },
                                            icon: Icon(
                                              showColorPicker
                                                  ? Icons.palette_outlined
                                                  : Icons.palette,
                                              size: 16,
                                              color: selectedDominantColor ??
                                                  Theme.of(context)
                                                      .colorScheme
                                                      .primary,
                                            ),
                                            label: Text(
                                              showColorPicker
                                                  ? 'Hide Colors'
                                                  : 'Pick Color',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: selectedDominantColor ??
                                                    Theme.of(context)
                                                        .colorScheme
                                                        .primary,
                                              ),
                                            ),
                                            style: OutlinedButton.styleFrom(
                                              side: BorderSide(
                                                color: selectedDominantColor ??
                                                    Theme.of(context)
                                                        .colorScheme
                                                        .primary,
                                                width: 1,
                                              ),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 12,
                                                      vertical: 4),
                                              minimumSize: const Size(0, 28),
                                            ),
                                          ),
                                        ),
                                        // Expandable color picker
                                        AnimatedContainer(
                                          duration:
                                              const Duration(milliseconds: 300),
                                          height: showColorPicker ? null : 0,
                                          child: AnimatedOpacity(
                                            duration: const Duration(
                                                milliseconds: 300),
                                            opacity:
                                                showColorPicker ? 1.0 : 0.0,
                                            child: showColorPicker
                                                ? Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                            bottom: 8.0),
                                                    child: DominantColorPicker(
                                                      colors: dominantColors,
                                                      selected:
                                                          selectedDominantColor,
                                                      onSelect: (color) {
                                                        setState(() {
                                                          selectedDominantColor =
                                                              color;
                                                          showColorPicker =
                                                              false;
                                                        });
                                                        // Save the selected color to database
                                                        _saveDominantColor(
                                                            color);
                                                      },
                                                    ),
                                                  )
                                                : const SizedBox.shrink(),
                                          ),
                                        ),
                                      ],
                                    ),

                                  // Add PlatformMatchWidget with 8px top padding
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8.0),
                                    child: unifiedAlbum != null
                                        ? PlatformMatchWidget(
                                            album: unifiedAlbum!)
                                        : const SizedBox.shrink(),
                                  ),

                                  const SizedBox(height: 16),
                                  _buildInfoRow(
                                      "Artist",
                                      unifiedAlbum?.artistName ??
                                          'Unknown Artist'),
                                  _buildInfoRow("Album",
                                      unifiedAlbum?.name ?? 'Unknown Album'),
                                  _buildInfoRow(
                                      "Release Date", _formatReleaseDate()),
                                  _buildInfoRow("Duration",
                                      formatDuration(albumDurationMillis)),
                                  const SizedBox(height: 8),
                                  _buildInfoRow("Rating",
                                      averageRating.toStringAsFixed(2),
                                      fontSize: 20),
                                  const SizedBox(height: 16),

                                  // Buttons row
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      FilledButton(
                                        onPressed: _showAddToListDialog,
                                        style: FilledButton.styleFrom(
                                          backgroundColor: Theme.of(context)
                                              .colorScheme
                                              .primary,
                                          foregroundColor: useDarkButtonText
                                              ? Colors.black
                                              : ColorUtility
                                                  .getContrastingColor(
                                                      Theme.of(context)
                                                          .colorScheme
                                                          .primary),
                                        ),
                                        child: const Text('Manage Lists'),
                                      ),
                                      const SizedBox(width: 12),
                                      FilledButton.icon(
                                        onPressed: _showOptionsDialog,
                                        icon: Icon(Icons.settings,
                                            color: useDarkButtonText
                                                ? Colors.black
                                                : ColorUtility
                                                    .getContrastingColor(
                                                        Theme.of(context)
                                                            .colorScheme
                                                            .primary)),
                                        label: Text('Options',
                                            style: TextStyle(
                                                color: useDarkButtonText
                                                    ? Colors.black
                                                    : ColorUtility
                                                        .getContrastingColor(
                                                            Theme.of(context)
                                                                .colorScheme
                                                                .primary))),
                                        style: FilledButton.styleFrom(
                                          backgroundColor: Theme.of(context)
                                              .colorScheme
                                              .primary,
                                          foregroundColor: useDarkButtonText
                                              ? Colors.black
                                              : ColorUtility
                                                  .getContrastingColor(
                                                      Theme.of(context)
                                                          .colorScheme
                                                          .primary),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const Divider(),
                            // Track List with Ratings - Wrap in ConstrainedBox
                            ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: dataTableWidth,
                              ),
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                physics: const AlwaysScrollableScrollPhysics(),
                                child: DataTable(
                                  columnSpacing: 12,
                                  columns: [
                                    const DataColumn(
                                        label: SizedBox(
                                            width: 35,
                                            child: Center(child: Text('#')))),
                                    DataColumn(
                                      label: ConstrainedBox(
                                        constraints: BoxConstraints(
                                          maxWidth: MediaQuery.of(context)
                                                  .size
                                                  .width *
                                              _calculateTitleWidth(),
                                        ),
                                        child: const Text('Title'),
                                      ),
                                    ),
                                    const DataColumn(
                                        label: SizedBox(
                                            width: 65,
                                            child:
                                                Center(child: Text('Length')))),
                                    const DataColumn(
                                        label: SizedBox(
                                            width: 160,
                                            child:
                                                Center(child: Text('Rating')))),
                                  ],
                                  rows: tracks.map((track) {
                                    return DataRow(
                                      cells: [
                                        DataCell(
                                            Text(track.position.toString())),
                                        DataCell(_buildTrackTitle(
                                          track.name,
                                          MediaQuery.of(context).size.width *
                                              _calculateTitleWidth(),
                                        )),
                                        DataCell(Text(
                                            formatDuration(track.durationMs))),
                                        DataCell(_buildTrackSlider(track
                                            .id)), // Use the fixed method directly
                                      ],
                                    );
                                  }).toList(),
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),

                            // Display note if exists
                            if (albumNote != null && albumNote!.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 16.0),
                                child: Container(
                                  width:
                                      dataTableWidth, // Match the width of the track table
                                  padding: const EdgeInsets.all(12.0),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).brightness ==
                                            Brightness.dark
                                        ? Colors.grey.shade800.withAlpha(128)
                                        : Colors.grey.shade200.withAlpha(179),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary
                                          .withAlpha(77),
                                      width: 1,
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            'Notes',
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .primary,
                                            ),
                                          ),
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              // Add Copy button
                                              InkWell(
                                                onTap: () {
                                                  Clipboard.setData(
                                                      ClipboardData(
                                                          text: albumNote!));
                                                  ScaffoldMessenger.of(context)
                                                      .showSnackBar(
                                                    const SnackBar(
                                                      content: Text(
                                                          'Notes copied to clipboard'),
                                                      duration:
                                                          Duration(seconds: 1),
                                                    ),
                                                  );
                                                },
                                                child: Padding(
                                                  padding:
                                                      const EdgeInsets.all(8.0),
                                                  child: Icon(
                                                    Icons.copy,
                                                    size: 16,
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .primary,
                                                  ),
                                                ),
                                              ),
                                              // Edit button
                                              InkWell(
                                                onTap: _editAlbumNote,
                                                child: Padding(
                                                  padding:
                                                      const EdgeInsets.all(8.0),
                                                  child: Icon(
                                                    Icons.edit,
                                                    size: 16,
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .primary,
                                                  ),
                                                ),
                                              ),
                                              // Add Delete button
                                              InkWell(
                                                onTap: () {
                                                  showDialog(
                                                    context: context,
                                                    builder: (context) =>
                                                        AlertDialog(
                                                      title: const Text(
                                                          'Delete Notes'),
                                                      content: const Text(
                                                          'Are you sure you want to delete these notes?'),
                                                      actions: [
                                                        TextButton(
                                                          onPressed: () =>
                                                              Navigator.of(
                                                                      context)
                                                                  .pop(),
                                                          child: const Text(
                                                              'Cancel'),
                                                        ),
                                                        FilledButton(
                                                          onPressed: () async {
                                                            Navigator.of(
                                                                    context)
                                                                .pop();
                                                            final id = widget
                                                                    .albumId ??
                                                                _albumData[
                                                                    'id'] ??
                                                                _albumData[
                                                                    'collectionId'] ??
                                                                '';

                                                            if (id.isNotEmpty) {
                                                              await UserData
                                                                  .saveAlbumNote(
                                                                      id, '');
                                                              setState(() {
                                                                albumNote =
                                                                    null;
                                                              });
                                                              scaffoldMessengerKey
                                                                  .currentState
                                                                  ?.showSnackBar(
                                                                const SnackBar(
                                                                  content: Text(
                                                                      'Notes deleted'),
                                                                  duration:
                                                                      Duration(
                                                                          seconds:
                                                                              1),
                                                                ),
                                                              );
                                                            }
                                                          },
                                                          child: const Text(
                                                              'Delete'),
                                                        ),
                                                      ],
                                                    ),
                                                  );
                                                },
                                                child: Padding(
                                                  padding:
                                                      const EdgeInsets.all(8.0),
                                                  child: Icon(
                                                    Icons.delete_outline,
                                                    size: 16,
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .primary,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        albumNote!,
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Theme.of(context).brightness ==
                                                  Brightness.dark
                                              ? Colors.grey.shade300
                                              : Colors.grey.shade800,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                            // Add notes button
                            if (albumNote == null || albumNote!.isEmpty)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 16.0),
                                child: InkWell(
                                  onTap: _editAlbumNote,
                                  borderRadius: BorderRadius.circular(12),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12.0, vertical: 6.0),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context).brightness ==
                                              Brightness.dark
                                          ? Colors.grey.shade800.withAlpha(128)
                                          : Colors.grey.shade200.withAlpha(179),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.note_add,
                                          size: 16,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          'Add notes',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color:
                                                Theme.of(context).brightness ==
                                                        Brightness.dark
                                                    ? Colors.grey.shade300
                                                    : Colors.grey.shade700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),

                            const SizedBox(height: 20),
                            FilledButton(
                              // Changed from ElevatedButton
                              onPressed: _launchRateYourMusic,
                              style: FilledButton.styleFrom(
                                backgroundColor: Theme.of(context)
                                    .colorScheme
                                    .primary, // Will use effective theme
                                foregroundColor: useDarkButtonText
                                    ? Colors.black
                                    : ColorUtility.getContrastingColor(
                                        Theme.of(context).colorScheme.primary),
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
        ),
      ),
    );
  }

  Widget _buildSkeletonAlbumDetails() {
    final pageWidth = MediaQuery.of(context).size.width * 0.85;

    return SizedBox(
      width: pageWidth,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 16),
            // Album artwork placeholder
            Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest
                    .withAlpha((Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest
                                .a *
                            0.3)
                        .toInt()),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Center(
                child: Icon(Icons.album, size: 100, color: Colors.grey),
              ),
            ),
            const SizedBox(height: 16),

            // Album info placeholders
            ...List.generate(
                4,
                (index) => const Padding(
                      padding: EdgeInsets.symmetric(vertical: 4.0),
                      child: SkeletonLoading(width: 250, height: 20),
                    )),

            const SizedBox(height: 12),

            // Rating placeholder
            const SkeletonLoading(width: 100, height: 32),

            const SizedBox(height: 16),

            // Buttons placeholder
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SkeletonLoading(width: 120, height: 45, borderRadius: 8),
                SizedBox(width: 12),
                SkeletonLoading(width: 120, height: 45, borderRadius: 8),
              ],
            ),

            const SizedBox(height: 24),
            const Divider(),

            // Tracks table placeholder
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16.0),
              child: Column(
                children: List.generate(
                    8,
                    (index) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8.0),
                          child: Row(
                            children: [
                              // Track number
                              const SizedBox(
                                  width: 30,
                                  child: Center(
                                      child: SkeletonLoading(
                                          width: 15, height: 15))),
                              const SizedBox(width: 8),
                              // Track title
                              const Expanded(
                                  child: SkeletonLoading(height: 16)),
                              const SizedBox(width: 8),
                              // Track duration
                              const SizedBox(
                                  width: 40,
                                  child: SkeletonLoading(height: 16)),
                              const SizedBox(width: 8),
                              // Rating slider
                              Container(
                                width: 150,
                                height: 20,
                                decoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerHighest
                                      .withAlpha((Theme.of(context)
                                                  .colorScheme
                                                  .surfaceContainerHighest
                                                  .a *
                                              0.3)
                                          .toInt()),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ],
                          ),
                        )),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showShareDialog() {
    final navigator = navigatorKey.currentState;
    if (navigator == null) return;

    // First debug what we have
    Logging.severe(
        'SavedAlbumPage: Showing share dialog with ${tracks.length} tracks');
    Logging.severe(
        'Tracks first ID type: ${tracks.isNotEmpty ? tracks.first.id.runtimeType : "unknown"}');
    Logging.severe(
        'Ratings map size: ${ratings.length}, with key type: ${ratings.isNotEmpty ? ratings.keys.first.runtimeType : "unknown"}');

    // Convert ratings map to ensure all keys are strings
    final stringRatings = <String, double>{};
    ratings.forEach((key, value) {
      stringRatings[key.toString()] = value;
    });

    navigator.push(
      PageRouteBuilder(
        barrierColor: Colors.black54,
        opaque: false,
        pageBuilder: (_, __, ___) {
          final shareWidget = ShareWidget(
            key: ShareWidget.shareKey,
            album: _albumData,
            tracks: tracks, // Already List<Track>, no conversion needed
            ratings: stringRatings, // Using stringRatings for consistency
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
      child: Wrap(
        // Replace Row with Wrap to allow text to flow to next line
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            "$label: ",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: fontSize),
          ),
          Tooltip(
            message: value, // Add tooltip to show full text on hover/long press
            child: Text(
              value,
              style: TextStyle(fontSize: fontSize),
              overflow: TextOverflow.ellipsis,
            ),
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

  // Replace _showAddToListDialog with a version matching DetailsPage logic
  Future<void> _showAddToListDialog() async {
    final navigator = navigatorKey.currentState ?? Navigator.of(context);

    // Track selected lists
    Map<String, bool> selectedLists = {};

    final result = await navigator.push(
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
                      future: UserData.getOrderedCustomLists(),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) {
                          return const Center(
                              child: CircularProgressIndicator());
                        }

                        final lists = snapshot.data!;
                        Logging.info(
                            'Dialog loaded ${lists.length} custom lists');

                        // Initialize selected state for lists containing the album
                        for (var list in lists) {
                          if (!selectedLists.containsKey(list.id)) {
                            selectedLists[list.id] = list.albumIds.contains(
                                unifiedAlbum?.id.toString() ??
                                    _albumData['id']?.toString() ??
                                    _albumData['collectionId']?.toString() ??
                                    '');
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
    );

    if (result == null) return; // Dialog cancelled

    if (result == 'new') {
      await _showCreateListDialog();
      return;
    }

    try {
      // Save the album first since user made selections
      final albumToSave = unifiedAlbum?.toJson() ?? _albumData;

      // First make sure the album is saved to database
      final saveResult = await UserData.addToSavedAlbums(albumToSave);
      if (!saveResult) {
        Logging.severe('Failed to save album before adding to list');
        if (mounted) {
          scaffoldMessengerKey.currentState?.showSnackBar(
            const SnackBar(content: Text('Error saving album to database')),
          );
        }
        return;
      }

      // Get the album ID as string
      String? albumIdStr = unifiedAlbum?.id.toString() ??
          albumToSave['id']?.toString() ??
          albumToSave['collectionId']?.toString();

      if (albumIdStr == null || albumIdStr.isEmpty) {
        Logging.severe('Cannot add to list - album ID is null or empty');
        if (mounted) {
          scaffoldMessengerKey.currentState?.showSnackBar(
            const SnackBar(content: Text('Error: Album has no ID')),
          );
        }
        return;
      }

      // Handle selected lists
      final Map<String, bool> selections = result as Map<String, bool>;
      final lists = await UserData.getCustomLists();
      int addedCount = 0;
      int removedCount = 0;

      for (var list in lists) {
        final isSelected = selections[list.id] ?? false;
        final hasAlbum = list.albumIds.contains(albumIdStr);

        Logging.severe(
            'List ${list.name}: selected=$isSelected, hasAlbum=$hasAlbum');

        if (isSelected && !hasAlbum) {
          // Add to list
          list.albumIds.add(albumIdStr);
          final success = await UserData.saveCustomList(list);
          if (success) {
            addedCount++;
            Logging.severe('Added album to list ${list.name}');
          } else {
            Logging.severe('Failed to add album to list ${list.name}');
          }
        } else if (!isSelected && hasAlbum) {
          // Remove from list
          list.albumIds.remove(albumIdStr);
          final success = await UserData.saveCustomList(list);
          if (success) {
            removedCount++;
            Logging.severe('Removed album from list ${list.name}');
          } else {
            Logging.severe('Failed to remove album from list ${list.name}');
          }
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
        } else {
          scaffoldMessengerKey.currentState?.showSnackBar(
            const SnackBar(content: Text('No changes to lists')),
          );
        }
      }
    } catch (e, stack) {
      Logging.severe('Error while updating lists', e, stack);
      if (mounted) {
        scaffoldMessengerKey.currentState?.showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  // Update _showCreateListDialog to match DetailsPage logic
  Future<void> _showCreateListDialog() async {
    final navigator = navigatorKey.currentState ?? Navigator.of(context);
    final nameController = TextEditingController();
    final descController = TextEditingController();

    await navigator.push(
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
                  // Save the album first
                  final albumToSave = unifiedAlbum?.toJson() ?? _albumData;
                  await UserData.addToSavedAlbums(albumToSave);

                  // Get album ID
                  final albumIdStr = unifiedAlbum?.id.toString() ??
                      albumToSave['id']?.toString() ??
                      albumToSave['collectionId']?.toString() ??
                      '';

                  // Create the list with the album
                  final newList = CustomList(
                    id: DateTime.now().millisecondsSinceEpoch.toString(),
                    name: nameController.text,
                    description: descController.text,
                    albumIds: [albumIdStr],
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

  void _showOptionsDialog() {
    final navigator = navigatorKey.currentState ?? Navigator.of(context);

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
                    Navigator.of(context).pushReplacement(
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
                    await UserData.exportAlbum(_albumData);
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
    // ENHANCED release date formatting with better error handling
    try {
      if (unifiedAlbum?.releaseDate != null) {
        // If we have a unified album with a date
        final date = unifiedAlbum!.releaseDate;
        if (date.year == 2000 && date.month == 1 && date.day == 1) {
          // This is likely our placeholder/fallback date
          Logging.severe(
              'Detected placeholder date (Jan 1, 2000), showing as Unknown');
          return 'Unknown Date';
        }
        return DateFormat('d MMMM yyyy').format(date);
      } else if (_albumData['releaseDate'] != null) {
        // Try parsing from string
        final dateStr = _albumData['releaseDate'];
        Logging.severe('Formatting release date from string: $dateStr');
        if (dateStr is String && dateStr.isNotEmpty) {
          try {
            final date = DateTime.parse(dateStr);
            // Check if it's the placeholder date
            if (date.year == 2000 && date.month == 1 && date.day == 1) {
              Logging.severe(
                  'Detected placeholder date (Jan 1, 2000), showing as Unknown');
              return 'Unknown Date';
            }
            return DateFormat('d MMMM yyyy').format(date);
          } catch (e) {
            Logging.severe('Error parsing date string: $dateStr', e);
          }
        }
      }
    } catch (e, stack) {
      Logging.severe('Error formatting release date', e, stack);
    }

    return 'Unknown Date';
  }

  void calculateAverageRating() {
    try {
      // Convert all ratings to list of non-zero values
      var ratedTracks = ratings.entries
          .where((entry) => entry.value > 0)
          .map((entry) => entry.value)
          .toList();

      if (ratedTracks.isNotEmpty) {
        double total = ratedTracks.reduce((a, b) => a + b);
        double average = total / ratedTracks.length;

        if (mounted) {
          setState(() {
            averageRating = double.parse(average.toStringAsFixed(2));
          });
        }

        Logging.severe(
            'Average rating calculated: $averageRating from ${ratedTracks.length} tracks with values: $ratedTracks');
      } else {
        if (mounted) {
          setState(() => averageRating = 0.0);
        }
        Logging.severe('No rated tracks found, setting average to 0.0');
      }
    } catch (e, stack) {
      Logging.severe('Error calculating average rating', e, stack);
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
}
