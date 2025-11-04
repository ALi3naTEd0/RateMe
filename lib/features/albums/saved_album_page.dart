import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:rateme/core/services/search_service.dart';
import 'package:rateme/core/services/theme_service.dart';
import 'package:rateme/database/database_helper.dart';
import 'package:rateme/platforms/middleware/deezer_middleware.dart';
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
  bool showColorPicker = false;
  bool _refetchingArtwork = false; // Add this line

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
    _loadAlbumNote();
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
                color: selectedDominantColor ?? Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              const Text('Album Notes'),
              const Spacer(),
              // Add copy button to dialog
              if (albumNote != null && albumNote!.isNotEmpty)
                IconButton(
                  icon: Icon(
                    Icons.copy,
                    color: selectedDominantColor ?? Theme.of(context).colorScheme.primary,
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
                  color: selectedDominantColor ?? Theme.of(context).colorScheme.primary,
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(
                foregroundColor: selectedDominantColor ?? Theme.of(context).colorScheme.primary,
              ),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(controller.text),
              style: FilledButton.styleFrom(
                backgroundColor: selectedDominantColor ?? Theme.of(context).colorScheme.primary,
                foregroundColor: useDarkButtonText
                    ? Colors.black
                    : ColorUtility.getContrastingColor(
                        selectedDominantColor ?? Theme.of(context).colorScheme.primary),
              ),
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

  // Add this method after _saveDominantColor
  Future<void> _refetchArtwork() async {
    final platform = _albumData['platform']?.toString().toLowerCase() ?? '';
    if (platform != 'deezer') {
      _showSnackBar('Cover art refetch is only available for Deezer albums');
      return;
    }

    final albumId = _albumData['id']?.toString() ?? _albumData['collectionId']?.toString();
    final albumName = _albumData['name']?.toString() ?? _albumData['collectionName']?.toString() ?? '';
    final artistName = _albumData['artist']?.toString() ?? _albumData['artistName']?.toString() ?? '';
    
    if (albumId == null || albumId.isEmpty) {
      _showSnackBar('Cannot refetch: No album ID found');
      return;
    }

    setState(() => _refetchingArtwork = true);

    try {
      // Use the new fallback method
      final newArtworkUrl = await DeezerMiddleware.fetchCoverArtWithFallback(
        albumId,
        albumName,
        artistName,
      );
      
      if (newArtworkUrl != null && newArtworkUrl.isNotEmpty) {
        setState(() {
          _albumData['artworkUrl'] = newArtworkUrl;
          _albumData['artworkUrl100'] = newArtworkUrl;
        });

        final db = await DatabaseHelper.instance.database;
        await db.update(
          'albums',
          {
            'artwork_url': newArtworkUrl,
          },
          where: 'id = ?',
          whereArgs: [albumId],
        );

        _showSnackBar('Cover art updated successfully');
        _loadDominantColors();
      } else {
        _showSnackBar('Could not fetch cover art from any source');
      }
    } catch (e) {
      Logging.severe('Error refetching artwork', e);
      _showSnackBar('Error refetching cover art: $e');
    } finally {
      setState(() => _refetchingArtwork = false);
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

  // Add this new method for proper track ordering (especially for multi-disk albums)
  void _sortTracks() {
    if (tracks.isEmpty) return;
    
    Logging.severe('Sorting ${tracks.length} tracks...');
    
    // Debug: Log track info before sorting
    for (int i = 0; i < tracks.length && i < 10; i++) {
      final track = tracks[i];
      Logging.severe('Before sort - Track $i: "${track.name}" - Position: ${track.position}, Metadata: ${track.metadata}');
    }
    
    tracks.sort((a, b) {
      // ENHANCED: Handle all platforms' disc number fields with correct priority
      dynamic aDiskRaw = a.metadata['disc_number'] ??         // Spotify format (MAIN for Spotify)
                        a.metadata['discNumber'] ??           // iTunes format
                        a.metadata['disk_number'] ??          // Deezer format
                        a.metadata['disc'] ??                 // Short form
                        a.metadata['diskNumber'] ?? 1;        // Alternative
                        
      dynamic bDiskRaw = b.metadata['disc_number'] ??         // Spotify format (MAIN for Spotify)
                        b.metadata['discNumber'] ??           // iTunes format
                        b.metadata['disk_number'] ??          // Deezer format
                        b.metadata['disc'] ??                 // Short form
                        b.metadata['diskNumber'] ?? 1;        // Alternative
      
      // Ensure disk numbers are integers
      int aDisk = aDiskRaw is int ? aDiskRaw : (int.tryParse(aDiskRaw.toString()) ?? 1);
      int bDisk = bDiskRaw is int ? bDiskRaw : (int.tryParse(bDiskRaw.toString()) ?? 1);
      
      // First sort by disk number
      if (aDisk != bDisk) {
        Logging.severe('Sorting by disk: Track "${a.name}" (disk $aDisk) vs "${b.name}" (disk $bDisk)');
        return aDisk.compareTo(bDisk);
      }
      
      // Then sort by track position within the same disk
      final result = a.position.compareTo(b.position);
      if (result != 0) {
        Logging.severe('Sorting by position: Track "${a.name}" (pos ${a.position}) vs "${b.name}" (pos ${b.position})');
      }
      return result;
    });
    
    // Debug: Log track info after sorting
    Logging.severe('After sorting:');
    for (int i = 0; i < tracks.length && i < 10; i++) {
      final track = tracks[i];
      final diskNum = track.metadata['disc_number'] ??         // Spotify format (MAIN)
                     track.metadata['discNumber'] ??           // iTunes format
                     track.metadata['disk_number'] ??          // Deezer format
                     track.metadata['diskNumber'] ?? 1;        // Alternative
      Logging.severe('After sort - Track $i: "${track.name}" - Disk: $diskNum, Position: ${track.position}');
    }
    
    Logging.severe('Sorted ${tracks.length} tracks by disk and position');
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
        
        // SIMPLE FIX: Check if tracks have disc numbers
        bool hasDiscNumbers = tracks.any((track) => 
          track.metadata.containsKey('disc_number') && 
          track.metadata['disc_number'] != null);
        
        if (!hasDiscNumbers && unifiedAlbum?.platform == 'spotify') {
          Logging.severe('DB tracks missing disc numbers, refetching from API');
          // Clear tracks and let it fall through to API fetch
          tracks = [];
        } else {
          _sortTracks();
          Logging.severe('Loaded ${tracks.length} tracks from DB');
          _attachRatingsToTracks();
          return _finishLoad();
        }
      }

      // USE THE EXACT SAME METHOD AS DETAILS_PAGE - NO MODIFICATIONS
      tracks = _extractTracksFromAlbum(_albumData);
      
      if (tracks.isNotEmpty) {
        Logging.severe('Extracted ${tracks.length} tracks using details_page approach');
        _sortTracks();
        
        // Save to database
        await dbHelper.insertTracks(
            albumId.toString(), tracks.map((t) => t.toJson()).toList());
        Logging.severe('Saved ${tracks.length} tracks to database');
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
          _sortTracks();
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
              _sortTracks();
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
        _sortTracks();
        Logging.severe('Created ${tracks.length} tracks from ratings');
        _attachRatingsToTracks();
      }
      _finishLoad();
    } catch (e, stack) {
      Logging.severe('Error loading tracks', e, stack);
      setState(() => isLoading = false);
    }
  }

  // FIX: Use the EXACT SAME method as details_page.dart
  List<Track> _extractTracksFromAlbum(Map<String, dynamic> album) {
    List<Track> result = [];

    try {
      if (album['tracks'] is List) {
        final tracksList = album['tracks'] as List;
        Logging.severe('=== SAVED_ALBUM_PAGE TRACK EXTRACTION DEBUG ===');
        Logging.severe('Album: ${album['name'] ?? album['collectionName']}');
        Logging.severe('Platform: ${album['platform']}');
        Logging.severe('Extracting ${tracksList.length} tracks from album data');

        for (var i = 0; i < tracksList.length; i++) {
          try {
            final trackData = tracksList[i];
            if (trackData is Map<String, dynamic>) {
              
              // MASSIVE DEBUG: Print ALL track data for first 5 tracks
              if (i < 5) {
                Logging.severe('=== RAW TRACK $i DEBUG ===');
                Logging.severe('All keys: ${trackData.keys.toList()}');
                Logging.severe('trackId: ${trackData['trackId']}');
                Logging.severe('trackName: ${trackData['trackName']}');
                Logging.severe('trackNumber: ${trackData['trackNumber']}');
                Logging.severe('disc_number: ${trackData['disc_number']}');
                Logging.severe('disk_number: ${trackData['disk_number']}');
                Logging.severe('discNumber: ${trackData['discNumber']}');
                Logging.severe('Full track data: $trackData');
                Logging.severe('=== END RAW TRACK $i ===');
              }

              final track = Track(
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
                metadata: trackData, // CRITICAL: Keep original metadata with disc_number
              );
              
              result.add(track);
              
              // DEBUG: Print the created Track object
              if (i < 5) {
                Logging.severe('=== CREATED TRACK $i DEBUG ===');
                Logging.severe('Track ID: ${track.id}');
                Logging.severe('Track name: ${track.name}');
                Logging.severe('Track position: ${track.position}');
                Logging.severe('Metadata keys: ${track.metadata.keys.toList()}');
                Logging.severe('Metadata disc_number: ${track.metadata['disc_number']}');
                Logging.severe('Metadata disk_number: ${track.metadata['disk_number']}');
                Logging.severe('Metadata discNumber: ${track.metadata['discNumber']}');
                Logging.severe('=== END CREATED TRACK $i ===');
              }
            }
          } catch (e) {
            Logging.severe('Error parsing track at index $i: $e');
          }
        }
        
        Logging.severe('=== FINAL TRACK SUMMARY ===');
        Logging.severe('Total tracks created: ${result.length}');
        for (int i = 0; i < result.length && i < 10; i++) {
          final track = result[i];
          final discNum = track.metadata['disc_number'] ?? track.metadata['disk_number'] ?? track.metadata['discNumber'] ?? 1;
          Logging.severe('Track $i: "${track.name}" - Position: ${track.position}, Disc: $discNum');
        }
        Logging.severe('=== END SAVED_ALBUM_PAGE EXTRACTION ===');
      }
    } catch (e, stack) {
      Logging.severe('Error extracting tracks from album', e, stack);
    }

    Logging.severe('Extracted ${result.length} tracks from album');
    return result;
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

  Future<void> _refreshData() async {
    if (mounted) {
      setState(() {
        isLoading = true;
      });
    }

    // CRITICAL FIX: Use the correct method name that actually exists
    try {
      final albumId = unifiedAlbum?.id ?? _albumData['id'] ?? _albumData['collectionId'];
      final platform = unifiedAlbum?.platform ?? _albumData['platform'] ?? '';
      
      Logging.severe('=== FORCING SPOTIFY REFRESH FOR DISC NUMBERS ===');
      Logging.severe('Album ID: $albumId, Platform: $platform');
      
      if (platform.toLowerCase() == 'spotify') {
        // CRITICAL FIX: Use fetchAlbumTracks instead of fetchSpotifyAlbumDetails
        final enhancedAlbum = await SearchService.fetchAlbumTracks(_albumData);
        
        if (enhancedAlbum != null && enhancedAlbum['tracks'] is List) {
          final freshTracks = enhancedAlbum['tracks'] as List;
          Logging.severe('Got ${freshTracks.length} fresh tracks from Spotify API with disc numbers');
          
          // Debug first few tracks
          for (int i = 0; i < freshTracks.length && i < 5; i++) {
            final track = freshTracks[i];
            Logging.severe('Fresh Track $i: "${track['trackName']}" - disc_number: ${track['disc_number']}');
          }
          
          // Convert to Track objects
          tracks = freshTracks.map<Track>((trackData) {
            return Track(
              id: trackData['trackId'] ?? trackData['id'] ?? 0,
              name: trackData['trackName'] ?? trackData['name'] ?? 'Unknown',
              position: trackData['trackNumber'] ?? trackData['position'] ?? 0,
              durationMs: trackData['trackTimeMillis'] ?? trackData['durationMs'] ?? 0,
              metadata: trackData, // This now includes disc_number!
            );
          }).toList();
          
          // Convert tracks to proper format for database
          final tracksForDb = freshTracks.map<Map<String, dynamic>>((trackData) {
            return Map<String, dynamic>.from(trackData);
          }).toList();
          
          // Update database with fresh tracks that have disc_number
          final dbHelper = DatabaseHelper.instance;
          await dbHelper.insertTracks(albumId.toString(), tracksForDb);
          Logging.severe('Updated database with ${tracksForDb.length} tracks including disc_number');
          
          // Now sort with proper disc numbers
          _sortTracks();
          _attachRatingsToTracks();
          
          setState(() {
            isLoading = false;
          });
          
          scaffoldMessengerKey.currentState?.showSnackBar(
            const SnackBar(content: Text('Album refreshed with disc numbers')),
          );
          return;
        }
      }
    } catch (e, stack) {
      Logging.severe('Error during forced refresh', e, stack);
    }

    // Fallback to original refresh logic
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
      data: effectiveTheme,
      child: Scaffold(
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
                // REMOVE the refresh icon from here
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
                                // Album artwork
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
                                          errorBuilder: (context, error,
                                                  stackTrace) =>
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

                                // MOVED HERE: Refetch button directly under artwork (only for Deezer)
                                if ((_albumData['platform']?.toString().toLowerCase() ?? '') == 'deezer')
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8.0, bottom: 8.0),
                                    child: InkWell(
                                      onTap: _refetchingArtwork ? null : _refetchArtwork,
                                      borderRadius: BorderRadius.circular(8),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            if (_refetchingArtwork)
                                              const SizedBox(
                                                width: 10,
                                                height: 10,
                                                child: CircularProgressIndicator(
                                                  strokeWidth: 1.5,
                                                ),
                                              )
                                            else
                                              Icon(
                                                Icons.refresh,
                                                size: 12,
                                                color: Theme.of(context).textTheme.bodySmall?.color?.withAlpha(179),
                                              ),
                                            const SizedBox(width: 4),
                                            Text(
                                              _refetchingArtwork ? 'Refetching...' : 'Fix cover art',
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: Theme.of(context).textTheme.bodySmall?.color?.withAlpha(179),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),

                                // Collapsible Dominant Color Picker
                                if (loadingPalette)
                                  const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 8.0),
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
                                              color:
                                                  selectedDominantColor ??
                                                      Theme.of(context)
                                                          .colorScheme
                                                          .primary,
                                            ),
                                          ),
                                          style: OutlinedButton.styleFrom(
                                            side: BorderSide(
                                              color:
                                                  selectedDominantColor ??
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
                                        duration: const Duration(
                                            milliseconds: 300),
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
                                                  child:
                                                      DominantColorPicker(
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

                                // Add PlatformMatchWidget
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
                                // MODIFIED: Add refresh icon inline with release date
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 2.0),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        "Release Date: ",
                                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                      ),
                                      Text(
                                        _formatReleaseDate(),
                                        style: TextStyle(fontSize: 16),
                                      ),
                                      const SizedBox(width: 4),
                                      InkWell(
                                        onTap: _fetchAndCompareReleaseDate,
                                        borderRadius: BorderRadius.circular(12),
                                        child: Padding(
                                          padding: const EdgeInsets.all(4.0),
                                          child: Icon(
                                            Icons.refresh,
                                            size: 16,
                                            color: selectedDominantColor ?? Theme.of(context).colorScheme.primary,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                _buildInfoRow("Duration",
                                    formatDuration(albumDurationMillis)),
                                const SizedBox(height: 8),
                                _buildInfoRow("Rating",
                                    averageRating.toStringAsFixed(2),
                                    fontSize: 20),
                                const SizedBox(height: 16),

                                // Buttons row
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.center,
                                  children: [
                                    FilledButton(
                                      onPressed: _showAddToListDialog,
                                      style: FilledButton.styleFrom(
                                        backgroundColor: selectedDominantColor ?? Theme.of(context).colorScheme.primary,
                                        foregroundColor: useDarkButtonText
                                            ? Colors.black
                                            : ColorUtility.getContrastingColor(
                                                selectedDominantColor ?? Theme.of(context).colorScheme.primary),
                                      ),
                                      child: const Text('Manage Lists'),
                                    ),
                                    const SizedBox(width: 12),
                                    FilledButton.icon(
                                      onPressed: _showOptionsDialog,
                                      icon: Icon(Icons.settings,
                                          color: useDarkButtonText
                                              ? Colors.black
                                              : ColorUtility.getContrastingColor(
                                                  selectedDominantColor ?? Theme.of(context).colorScheme.primary)),
                                      label: Text('Options',
                                          style: TextStyle(
                                              color: useDarkButtonText
                                                  ? Colors.black
                                                  : ColorUtility.getContrastingColor(
                                                      selectedDominantColor ?? Theme.of(context).colorScheme.primary))),
                                      style: FilledButton.styleFrom(
                                        backgroundColor: selectedDominantColor ?? Theme.of(context).colorScheme.primary,
                                        foregroundColor: useDarkButtonText
                                            ? Colors.black
                                            : ColorUtility.getContrastingColor(
                                                selectedDominantColor ?? Theme.of(context).colorScheme.primary),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const Divider(),
                          // Track List with Ratings - Replace DataTable with ListView
                          Center(
                            child: ConstrainedBox(
                              constraints: BoxConstraints(maxWidth: (MediaQuery.of(context).size.width * 0.9).clamp(400.0, 800.0)),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                                child: Column(
                                  children: [
                                    // Header row - more compact
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha(127),
                                        borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                                      ),
                                      child: Row(
                                        children: [
                                          const SizedBox(width: 30, child: Center(child: Text('#', style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13)))),
                                          const SizedBox(width: 8),
                                          Expanded(child: Text('Title', style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13))),
                                          const SizedBox(width: 8),
                                          const SizedBox(width: 70, child: Center(child: Text('Duration', style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13)))),
                                          const SizedBox(width: 8),
                                          const SizedBox(width: 160, child: Center(child: Text('Rating', style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13)))),
                                        ],
                                      ),
                                    ),
                                    // Track rows - more compact
                                    ...tracks.asMap().entries.map((entry) {
                                      final index = entry.key;
                                      final track = entry.value;
                                      return Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: index.isEven 
                                            ? Colors.transparent 
                                            : Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha(51),
                                          borderRadius: index == tracks.length - 1 
                                            ? const BorderRadius.vertical(bottom: Radius.circular(8))
                                            : null,
                                        ),
                                        child: Row(
                                          children: [
                                            SizedBox(width: 30, child: Center(child: Text(track.position.toString(), style: TextStyle(fontSize: 13, fontWeight: FontWeight.normal)))),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Tooltip(
                                                message: track.name,
                                                child: Text(
                                                  track.name,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.normal),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            SizedBox(width: 70, child: Center(child: Text(formatDuration(track.durationMs), style: TextStyle(fontSize: 13, fontWeight: FontWeight.normal)))),
                                            const SizedBox(width: 8),
                                            SizedBox(width: 160, child: _buildCompactTrackSlider(track.id)),
                                          ],
                                        ),
                                      );
                                    }),
                                  ],
                                ),
                              ),
                            ),
                          ),

                          // Display note if exists
                          if (albumNote != null && albumNote!.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 16.0),
                              child: Container(
                                width: dataTableWidth, // Match the width of the track table
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
                                                ScaffoldMessenger.of(
                                                        context)
                                                    .showSnackBar(
                                                  const SnackBar(
                                                    content: Text(
                                                        'Notes copied to clipboard'),
                                                    duration: Duration(
                                                        seconds: 1),
                                                  ),
                                                );
                                              },
                                              child: Padding(
                                                padding:
                                                    const EdgeInsets.all(
                                                        8.0),
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
                                                    const EdgeInsets.all(
                                                        8.0),
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
                                                // Show confirmation dialog
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
                                                        onPressed:
                                                            () async {
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

                                                          if (id
                                                              .isNotEmpty) {
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
                                                                duration: Duration(
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
                                                    const EdgeInsets.all(
                                                        8.0),
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
                                        color:
                                            Theme.of(context).brightness ==
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
                                        ? Colors.grey.shade800
                                            .withAlpha(128)
                                        : Colors.grey.shade200
                                            .withAlpha(179),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.note_add,
                                        size: 16,
                                        color: selectedDominantColor ?? Theme.of(context).colorScheme.primary,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Add notes',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Theme.of(context)
                                                      .brightness ==
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
                              backgroundColor: selectedDominantColor ?? Theme.of(context).colorScheme.primary,
                              foregroundColor: useDarkButtonText
                                  ? Colors.black
                                  : ColorUtility.getContrastingColor(
                                      selectedDominantColor ?? Theme.of(context).colorScheme.primary),
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
    Logging.severe(
        'SavedAlbumPage: Showing share dialog with ${tracks.length} tracks');
    Logging.severe(
        'Tracks first ID type: ${tracks.isNotEmpty ? tracks.first.id.runtimeType : "unknown"}');
    Logging.severe(
        'Ratings map size: ${ratings.length}, with key type: ${ratings.isNotEmpty ? ratings.keys.first.runtimeType : "unknown"}');

    final stringRatings = <String, double>{};
    ratings.forEach((key, value) {
      stringRatings[key.toString()] = value;
    });

    final shareWidgetKey = GlobalKey<ShareWidgetState>();
    bool exportDarkTheme = true;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            final theme = exportDarkTheme ? ThemeData.dark() : ThemeData.light();
            return Theme(
              data: theme,
              child: AlertDialog(
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Export theme toggle at the top
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        const Text('Export Theme:'),
                        const SizedBox(width: 8),
                        ToggleButtons(
                          isSelected: [exportDarkTheme, !exportDarkTheme],
                          onPressed: (index) {
                            setState(() {
                              exportDarkTheme = index == 0;
                            });
                          },
                          children: const [
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: 12),
                              child: Text('Dark'),
                            ),
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: 12),
                              child: Text('Light'),
                            ),
                          ],
                        ),
                      ],
                    ),
                    SingleChildScrollView(
                      child: ShareWidget(
                        key: shareWidgetKey,
                        album: _albumData,
                        tracks: tracks,
                        ratings: stringRatings,
                        averageRating: averageRating,
                        selectedDominantColor: selectedDominantColor,
                        exportDarkTheme: exportDarkTheme, // Pass to ShareWidget
                      ),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      foregroundColor: selectedDominantColor ?? Theme.of(context).colorScheme.primary,
                    ),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () async {
                      // Capture the context at startup to avoid access problems
                      final navigator = Navigator.of(context);
                      
                      try {
                        final path = await shareWidgetKey.currentState?.saveAsImage();
                        
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
                    style: TextButton.styleFrom(
                      foregroundColor: selectedDominantColor ?? Theme.of(context).colorScheme.primary,
                    ),
                    child: Text(Platform.isAndroid ? 'Save & Share' : 'Save Image'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showShareOptions(String path) {
    if (Platform.isAndroid) {
      if (!mounted) return;
      showModalBottomSheet(
        context: context,
        builder: (BuildContext bottomSheetContext) {
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                ListTile(
                  leading: const Icon(Icons.download),
                  title: const Text('Save to Downloads'),
                  onTap: () async {
                    Navigator.of(bottomSheetContext).pop();
                    try {
                      final downloadDir = Directory('/storage/emulated/0/Download');
                      // --- Begin filename fix ---
                      final artist = unifiedAlbum?.artist ?? _albumData['artistName'] ?? _albumData['artist'] ?? 'UnknownArtist';
                      final albumName = unifiedAlbum?.name ?? _albumData['collectionName'] ?? _albumData['name'] ?? 'UnknownAlbum';
                      String sanitize(String s) =>
                          s.replaceAll(RegExp(r'[\\/:*?"<>|]'), '').replaceAll(' ', '_');
                      final fileName = '${sanitize(artist)}_${sanitize(albumName)}.png';
                      // --- End filename fix ---
                      final newPath = '${downloadDir.path}/$fileName';

                      // Copy from temp to Downloads
                      await File(path).copy(newPath);

                      // Scan file with MediaScanner
                      const platform = MethodChannel('com.example.rateme/media_scanner');
                      try {
                        await platform.invokeMethod('scanFile', {'path': newPath});
                      } catch (e) {
                        Logging.severe('MediaScanner error: $e');
                      }

                      if (!mounted) return;
                      scaffoldMessengerKey.currentState?.showSnackBar(
                        SnackBar(content: Text('Saved to Downloads: $fileName')),
                      );
                    } catch (e) {
                      if (!mounted) return;
                      scaffoldMessengerKey.currentState?.showSnackBar(
                        SnackBar(content: Text('Error saving file: $e')),
                      );
                    }
                  },
                ),
                // ...existing code...
              ],
            ),
          );
        },
      );
    } else {
      if (!mounted) return;
      scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(content: Text('Image saved to: $path')),
      );
    }
  }

  Widget _buildInfoRow(String label, String value, {double fontSize = 16}) {
    return Padding(
      padding: EdgeInsets.symmetric(
        vertical: label == "Rating" ? 8.0 : 2.0,
      ),
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            "$label: ",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: fontSize), // Keep bold for labels
          ),
          Tooltip(
            message: value,
            child: Text(
              value,
              style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.normal), // Normal weight for values
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
    // Track selected lists
    Map<String, bool> selectedLists = {};

    final result = await Navigator.of(context).push(
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
                        color: useDarkButtonText ? Colors.black : ColorUtility.getContrastingColor(
                            selectedDominantColor ?? Theme.of(context).colorScheme.primary)),
                    label: Text('Create New List',
                        style: TextStyle(
                            color: useDarkButtonText
                                ? Colors.black
                                : ColorUtility.getContrastingColor(
                                    selectedDominantColor ?? Theme.of(context).colorScheme.primary))),
                    style: FilledButton.styleFrom(
                      backgroundColor: selectedDominantColor ?? Theme.of(context).colorScheme.primary,
                      foregroundColor: useDarkButtonText ? Colors.black : ColorUtility.getContrastingColor(
                          selectedDominantColor ?? Theme.of(context).colorScheme.primary),
                    ),
                    onPressed: () => Navigator.of(context).pop('new'),
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
                                    activeColor: selectedDominantColor ?? Theme.of(context).colorScheme.primary,
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
                onPressed: () => Navigator.pop(context, null),
                style: TextButton.styleFrom(
                  foregroundColor: selectedDominantColor ?? Theme.of(context).colorScheme.primary,
                ),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: selectedDominantColor ?? Theme.of(context).colorScheme.primary,
                  foregroundColor: useDarkButtonText ? Colors.black : ColorUtility.getContrastingColor(
                      selectedDominantColor ?? Theme.of(context).colorScheme.primary),
                ),
                onPressed: () => Navigator.pop(context, selectedLists),
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      )
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
    final nameController = TextEditingController();
    final descController = TextEditingController();

    await Navigator.of(context).push(
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
                decoration: InputDecoration(
                  labelText: 'List Name',
                  hintText: 'e.g. Progressive Rock',
                  labelStyle: TextStyle(
                    color: selectedDominantColor ?? Theme.of(context).colorScheme.primary,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(
                      color: selectedDominantColor ?? Theme.of(context).colorScheme.primary,
                      width: 2,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: descController,
                decoration: InputDecoration(
                  labelText: 'Description (optional)',
                  hintText: 'e.g. My favorite prog rock albums',
                  labelStyle: TextStyle(
                    color: selectedDominantColor ?? Theme.of(context).colorScheme.primary,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(
                      color: selectedDominantColor ?? Theme.of(context).colorScheme.primary,
                      width: 2,
                    ),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(
                foregroundColor: selectedDominantColor ?? Theme.of(context).colorScheme.primary,
              ),
              child: const Text('Cancel'),
            ),
            FilledButton(
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
                if (mounted) {
                  Navigator.of(context).pop();
                }
              },
              style: FilledButton.styleFrom(
                backgroundColor: selectedDominantColor ?? Theme.of(context).colorScheme.primary,
                foregroundColor: useDarkButtonText
                    ? Colors.black
                    : ColorUtility.getContrastingColor(
                        selectedDominantColor ?? Theme.of(context).colorScheme.primary),
              ),
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }

  void _showOptionsDialog() {
    Navigator.of(context).push(
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
                  Navigator.of(context).pop();
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
                  Navigator.of(context).pop();
                  if (mounted) {
                    await UserData.exportAlbum(_albumData);
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.share),
                title: const Text('Share as Image'),
                onTap: () {
                  Navigator.of(context).pop();
                  _showShareDialog();
                },
              ),
              ListTile(
                leading: const Icon(Icons.close),
                title: const Text('Close'),
                onTap: () => Navigator.of(context).pop(),
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

  /// Fetch release date from Spotify and iTunes, compare, and update UI
  Future<void> _fetchAndCompareReleaseDate() async {
    if (unifiedAlbum == null) return;
    final albumName = unifiedAlbum?.name ?? '';
    final artistName = unifiedAlbum?.artistName ?? '';
    final albumUrl = unifiedAlbum?.url ?? '';
    final platform = (unifiedAlbum?.platform ?? '').toLowerCase();

    String? spotifyDate;
    String? itunesDate;
    String? deezerDate;
    String? usedDate;
    String? message;

    String? spotifyUrl;
    String? itunesUrl;
    String? deezerUrl;

    setState(() => isLoading = true);

    try {
      Logging.severe('=== RELEASE DATE DEBUG START ===');
      Logging.severe('Platform: $platform');
      Logging.severe('Album URL: $albumUrl');
      Logging.severe('Album Name: $albumName');
      Logging.severe('Artist Name: $artistName');

      // --- 1. Try to get URLs from platform matches (if available in DB) ---
      final db = await DatabaseHelper.instance.database;
      final albumId = unifiedAlbum?.id.toString() ?? '';
      Future<String?> getPlatformUrl(String plat) async {
        final rows = await db.query(
          'platform_matches',
          columns: ['url'],
          where: 'album_id = ? AND platform = ?',
          whereArgs: [albumId, plat],
          limit: 1,
        );
        return rows.isNotEmpty ? rows.first['url'] as String? : null;
      }

      spotifyUrl = await getPlatformUrl('spotify');
      itunesUrl = await getPlatformUrl('apple_music');
      deezerUrl = await getPlatformUrl('deezer');

      Logging.severe('PlatformMatch URLs:');
      Logging.severe('Spotify: $spotifyUrl');
      Logging.severe('Apple Music: $itunesUrl');
      Logging.severe('Deezer: $deezerUrl');

      // --- 2. Fetch release dates from each platform using URL if possible, else search ---
      // --- Spotify ---
      try {
        if (spotifyUrl == null) {
          // Search for the album on Spotify
          final searchResult = await SearchService.searchSpotify('$artistName $albumName');
          if (searchResult != null && searchResult['results'] is List && searchResult['results'].isNotEmpty) {
            spotifyUrl = searchResult['results'][0]['url'];
            Logging.severe('Spotify: Found album URL by search: $spotifyUrl');
          }
        }
        if (spotifyUrl != null) {
          final spotify = PlatformServiceFactory().getService('spotify');
          final details = await spotify.fetchAlbumDetails(spotifyUrl);
          spotifyDate = details?['release_date'] ?? details?['releaseDate'];
          Logging.severe('Spotify API returned date: $spotifyDate');
          if (spotifyDate != null && spotifyDate.length > 10) {
            spotifyDate = spotifyDate.substring(0, 10);
          }
        } else {
          Logging.severe('Spotify: Could not determine album URL for fetch');
        }
      } catch (e, stack) {
        Logging.severe('Spotify fetch error: $e', stack);
      }

      // --- iTunes / Apple Music ---
      try {
        if (itunesUrl == null) {
          // Search for the album on iTunes
          final searchResult = await SearchService.searchITunes('$artistName $albumName');
          if (searchResult != null && searchResult['results'] is List && searchResult['results'].isNotEmpty) {
            itunesUrl = searchResult['results'][0]['collectionViewUrl'];
            Logging.severe('iTunes: Found album URL by search: $itunesUrl');
          }
        }
        if (itunesUrl != null) {
          final itunes = PlatformServiceFactory().getService('itunes');
          final details = await itunes.fetchAlbumDetails(itunesUrl);
          itunesDate = details?['release_date'] ?? details?['releaseDate'];
          Logging.severe('iTunes API returned date: $itunesDate');
          if (itunesDate != null && itunesDate.length > 10) {
            itunesDate = itunesDate.substring(0, 10);
          }
        } else {
          Logging.severe('iTunes: Could not determine album URL for fetch');
        }
      } catch (e, stack) {
        Logging.severe('iTunes fetch error: $e', stack);
      }

      // --- Deezer ---
      try {
        if (deezerUrl == null) {
          // Search for the album on Deezer
          final searchResult = await SearchService.searchDeezer('$artistName $albumName');
          if (searchResult != null && searchResult['results'] is List && searchResult['results'].isNotEmpty) {
            deezerUrl = searchResult['results'][0]['url'];
            Logging.severe('Deezer: Found album URL by search: $deezerUrl');
          }
        }
        if (deezerUrl != null) {
          final deezer = PlatformServiceFactory().getService('deezer');
          final details = await deezer.fetchAlbumDetails(deezerUrl);
          deezerDate = details?['release_date'] ?? details?['releaseDate'];
          Logging.severe('Deezer API returned date: $deezerDate');
          if (deezerDate != null && deezerDate.length > 10) {
            deezerDate = deezerDate.substring(0, 10);
          }
        } else {
          Logging.severe('Deezer: Could not determine album URL for fetch');
        }
      } catch (e, stack) {
        Logging.severe('Deezer fetch error: $e', stack);
      }

      Logging.severe('Fetched release dates:');
      Logging.severe('Spotify: $spotifyDate');
      Logging.severe('Apple Music: $itunesDate');
      Logging.severe('Deezer: $deezerDate');

      // --- Consensus logic: use the date that matches at least 2 sources (normalized) ---
      List<String> allDates = [spotifyDate, itunesDate, deezerDate]
          .where((d) => d != null && d.isNotEmpty)
          .cast<String>()
          .toList();

      // Count occurrences of each date
      Map<String, int> dateCounts = {};
      for (var d in allDates) {
        dateCounts[d] = (dateCounts[d] ?? 0) + 1;
      }
      Logging.severe('Date counts: $dateCounts');

      // Find the date that appears at least twice
      String? consensusDate;
      dateCounts.forEach((date, count) {
        if (count >= 2) consensusDate = date;
      });

      // If no consensus, prefer Spotify > iTunes > Deezer, but only if not empty
      if (consensusDate != null) {
        usedDate = consensusDate;
        message =
            'Consensus release date: $usedDate\n(Spotify: $spotifyDate, Apple: $itunesDate, Deezer: $deezerDate)';
      } else if (spotifyDate != null && spotifyDate.isNotEmpty) {
        usedDate = spotifyDate;
        message =
            'No consensus, using Spotify: $spotifyDate\n(Apple: $itunesDate, Deezer: $deezerDate)';
      } else if (itunesDate != null && itunesDate.isNotEmpty) {
        usedDate = itunesDate;
        message =
            'No consensus, using Apple: $itunesDate\n(Spotify: $spotifyDate, Deezer: $deezerDate)';
      } else if (deezerDate != null && deezerDate.isNotEmpty) {
        usedDate = deezerDate;
        message =
            'No consensus, using Deezer: $deezerDate\n(Spotify: $spotifyDate, Apple: $itunesDate)';
      } else {
        message = 'Could not fetch release date from Spotify, Apple, or Deezer.';
      }

      Logging.severe('USED DATE: $usedDate | MESSAGE: $message');

      // Save and update UI if found
      if (usedDate != null) {
        _albumData['releaseDate'] = usedDate;
        _albumData['release_date'] = usedDate;
        if (unifiedAlbum != null) {
          try {
            final dt = DateTime.tryParse(usedDate);
            if (dt != null) {
              unifiedAlbum = Album(
                id: unifiedAlbum!.id,
                name: unifiedAlbum!.name,
                artist: unifiedAlbum!.artist,
                artworkUrl: unifiedAlbum!.artworkUrl,
                releaseDate: dt,
                platform: unifiedAlbum!.platform,
                url: unifiedAlbum!.url,
                tracks: unifiedAlbum!.tracks,
                metadata: unifiedAlbum!.metadata,
              );
            }
          } catch (_) {}
        }
        // Save to DB
        final db = await DatabaseHelper.instance.database;
        await db.update(
          'albums',
          {'release_date': usedDate},
          where: 'id = ?',
          whereArgs: [_albumData['id']],
        );
      }

      setState(() {});
      _showSnackBar(message);
      Logging.severe('=== RELEASE DATE DEBUG END ===');
    } catch (e, stack) {
      Logging.severe('Error in _fetchAndCompareReleaseDate: $e', stack);
      _showSnackBar('Error fetching release date: $e');
    } finally {
      setState(() => isLoading = false);
    }
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

  // Make the slider match DetailsPage exactly
  Widget _buildCompactTrackSlider(dynamic trackId) {
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
    if (trackIndex >= 0 && tracks[trackIndex].metadata.containsKey('rating')) {
      ratingValue = tracks[trackIndex].metadata['rating'].toDouble();
    }
    else if (ratings.containsKey(trackIdStr)) {
      ratingValue = ratings[trackIdStr] ?? 0.0;
    }
    else if (trackIndex >= 0) {
      int position = tracks[trackIndex].position;
      String positionStr = position.toString().padLeft(3, '0');

      for (String key in ratings.keys) {
        if (key.endsWith(positionStr)) {
          ratingValue = ratings[key] ?? 0.0;
          break;
        }
      }
    }

    return SizedBox(
      width: 160,
      child: Row(
        children: [
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
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
                trackHeight: 4.0, // Make track thicker
                thumbShape: RoundSliderThumbShape(enabledThumbRadius: 10.0), // Bigger thumb
                overlayShape: RoundSliderOverlayShape(overlayRadius: 16.0), // Bigger overlay
              ),
              child: Slider(
                min: 0,
                max: 10,
                divisions: 10,
                value: ratingValue,
                onChanged: (newRating) => _updateRating(trackId, newRating),
              ),
            ),
          ),
          SizedBox(
            width: 25,
            child: Text(
              ratingValue.toStringAsFixed(0),
              textAlign: TextAlign.end,
              style: TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}