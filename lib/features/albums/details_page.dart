import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:rateme/core/services/theme_service.dart';
import 'package:rateme/platforms/middleware/deezer_middleware.dart';
import 'package:rateme/platforms/platform_service_factory.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/models/album_model.dart';
import '../../core/utils/color_utility.dart';
import '../../database/database_helper.dart';
import '../../core/services/logging.dart';
import '../../core/services/user_data.dart';
import '../custom_lists/custom_lists_page.dart';
import '../../ui/widgets/share_widget.dart';
import 'package:share_plus/share_plus.dart';
import '../search/platform_match_widget.dart';
import '../../ui/widgets/skeleton_loading.dart';
import '../../core/services/search_service.dart';
import '../../core/utils/dominant_color.dart';
import '../../ui/widgets/dominant_color_picker.dart';

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

  Album? unifiedAlbum;
  List<Track> tracks = [];
  Map<String, double> ratings = {};
  double averageRating = 0.0;
  int albumDurationMillis = 0;
  DateTime? releaseDate;
  bool isLoading = true;
  bool useDarkButtonText = false;
  String? albumNote;

  // Add a key for the RefreshIndicator
  final GlobalKey<RefreshIndicatorState> _refreshIndicatorKey =
      GlobalKey<RefreshIndicatorState>();

  List<Color> dominantColors = [];
  Color? selectedDominantColor;
  bool loadingPalette = false;
  bool showColorPicker = false; // Add this line
  bool _refetchingArtwork = false; // Add this line

  @override
  void initState() {
    super.initState();
    _initialize();
    _loadButtonTextPreference(); // Add this line to load the button text preference
    _loadAlbumNote(); // Load the note for the album
    _loadDominantColors(); // Add this
  }

  // Add this method to load the button text preference
  Future<void> _loadButtonTextPreference() async {
    try {
      final dbHelper = DatabaseHelper.instance;
      final buttonPref = await dbHelper.getSetting('useDarkButtonText');
      if (mounted) {
        setState(() {
          useDarkButtonText = buttonPref == 'true';
        });
      }
    } catch (e) {
      Logging.severe('Error loading button text preference', e);
    }
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
      } else if (widget.isBandcamp || widget.album['platform'] == 'bandcamp') {
        // Handle Bandcamp album
        unifiedAlbum = Album(
          id: widget.album['collectionId'] ?? widget.album['id'] ?? 0,
          name: widget.album['collectionName'] ??
              widget.album['name'] ??
              'Unknown Album',
          artist: widget.album['artistName'] ??
              widget.album['artist'] ??
              'Unknown Artist',
          artworkUrl:
              widget.album['artworkUrl100'] ?? widget.album['artworkUrl'] ?? '',
          url: widget.album['url'] ?? '',
          platform: 'bandcamp',
          releaseDate: widget.album['releaseDate'] != null
              ? DateTime.parse(widget.album['releaseDate'])
              : DateTime.now(),
          metadata: widget.album,
          tracks: widget.album['tracks'] != null
              ? (widget.album['tracks'] as List)
                  .map<Track>((track) => Track(
                        id: track['trackId'] ?? track['id'] ?? 0,
                        name: track['trackName'] ??
                            track['title'] ??
                            'Unknown Track',
                        position:
                            track['trackNumber'] ?? track['position'] ?? 0,
                        durationMs: track['trackTimeMillis'] ??
                            track['duration_ms'] ??
                            track['durationMs'] ??
                            0,
                        metadata: track,
                      ))
                  .toList()
              : [],
        );
      } else if (widget.album['platform'] == 'deezer') {
        // Handle Deezer album
        unifiedAlbum = Album(
          id: widget.album['collectionId'] ?? widget.album['id'] ?? 0,
          name: widget.album['collectionName'] ??
              widget.album['name'] ??
              'Unknown Album',
          artist: widget.album['artistName'] ??
              widget.album['artist'] ??
              'Unknown Artist',
          artworkUrl:
              widget.album['artworkUrl100'] ?? widget.album['artworkUrl'] ?? '',
          url: widget.album['url'] ?? '',
          platform: 'deezer',
          releaseDate: widget.album['releaseDate'] != null
              ? DateTime.parse(widget.album['releaseDate'])
              : DateTime.now(),
          metadata: widget.album,
          tracks: _extractTracksFromAlbum(widget.album),
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
                    trackData['duration_ms'] ??
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
      // Use the search service to fetch tracks for any platform
      final albumWithTracks =
          await SearchService.fetchAlbumTracks(widget.album);

      if (albumWithTracks != null &&
          albumWithTracks['tracks'] is List &&
          albumWithTracks['tracks'].isNotEmpty) {
        widget.album['tracks'] = albumWithTracks['tracks'];
        Logging.severe(
            'Fetched ${albumWithTracks['tracks'].length} tracks from API');
      } else {
        Logging.severe('Failed to fetch tracks from API');
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

  Future<void> _loadAlbumNote() async {
    try {
      // Fix: Convert any numeric ID to string
      final albumId = widget.album['id'] != null
          ? widget.album['id'].toString()
          : widget.album['collectionId']?.toString() ?? '';

      Logging.severe('Loading album note for ID: $albumId');

      if (albumId.isEmpty) {
        Logging.severe('Cannot load album note: No valid album ID found');
        return;
      }

      final note = await UserData.getAlbumNote(albumId);
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
    // Fix: Use a consistent ID field and ensure it's a string
    final albumId = widget.album['id'] != null
        ? widget.album['id'].toString()
        : widget.album['collectionId']?.toString() ?? '';

    if (albumId.isEmpty) {
      Logging.severe('Cannot edit album note: No valid album ID found');
      return;
    }

    final newNote = await showDialog<String>(
      context: context,
      builder: (context) {
        final controller = TextEditingController(text: albumNote);
        // Update to match the same dialog design as SavedAlbumPage
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
                  color: Theme.of(context).colorScheme.primary,
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
      await UserData.saveAlbumNote(albumId, newNote);
      Logging.severe('Saved album note for ID: $albumId');
      setState(() {
        albumNote = newNote;
      });
    }
  }

  Future<void> _loadDominantColors() async {
    setState(() => loadingPalette = true);

    // First try to load saved dominant color from database
    final albumId = widget.album['id']?.toString() ??
        widget.album['collectionId']?.toString() ??
        '';
    if (albumId.isNotEmpty) {
      final dbHelper = DatabaseHelper.instance;
      final savedColor = await dbHelper.getDominantColor(albumId);
      if (savedColor != null) {
        try {
          // Parse the color value (stored as hex string)
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

    final url =
        widget.album['artworkUrl100'] ?? widget.album['artworkUrl'] ?? '';
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

  // Add method to save dominant color to database
  Future<void> _saveDominantColor(Color? color) async {
    final albumId = widget.album['id']?.toString() ??
        widget.album['collectionId']?.toString() ??
        '';
    if (albumId.isNotEmpty) {
      final dbHelper = DatabaseHelper.instance;
      if (color != null) {
        // Convert color to hex string
        final colorHex =
            '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';
        await dbHelper.saveDominantColor(albumId, colorHex);
      } else {
        // Save empty string to clear the color
        await dbHelper.saveDominantColor(albumId, '');
      }
    }
  }

  // Add this method after _loadDominantColors
  Future<void> _refetchArtwork() async {
    final platform = widget.album['platform']?.toString().toLowerCase() ?? unifiedAlbum?.platform.toLowerCase() ?? '';
    if (platform != 'deezer') {
      scaffoldMessengerKey.currentState?.showSnackBar(
        const SnackBar(content: Text('Cover art refetch is only available for Deezer albums')),
      );
      return;
    }

    final albumId = widget.album['id']?.toString() ?? widget.album['collectionId']?.toString();
    final albumName = widget.album['name']?.toString() ?? widget.album['collectionName']?.toString() ?? '';
    final artistName = widget.album['artist']?.toString() ?? widget.album['artistName']?.toString() ?? '';
    
    if (albumId == null || albumId.isEmpty) {
      scaffoldMessengerKey.currentState?.showSnackBar(
        const SnackBar(content: Text('Cannot refetch: No album ID found')),
      );
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
        widget.album['artworkUrl'] = newArtworkUrl;
        widget.album['artworkUrl100'] = newArtworkUrl;

        if (unifiedAlbum != null) {
          unifiedAlbum = Album(
            id: unifiedAlbum!.id,
            name: unifiedAlbum!.name,
            artist: unifiedAlbum!.artist,
            artworkUrl: newArtworkUrl,
            releaseDate: unifiedAlbum!.releaseDate,
            platform: unifiedAlbum!.platform,
            url: unifiedAlbum!.url,
            tracks: unifiedAlbum!.tracks,
            metadata: unifiedAlbum!.metadata,
          );
        }

        final db = await DatabaseHelper.instance.database;
        await db.update(
          'albums',
          {
            'artwork_url': newArtworkUrl,
          },
          where: 'id = ?',
          whereArgs: [albumId],
        );

        setState(() {});

        scaffoldMessengerKey.currentState?.showSnackBar(
          const SnackBar(content: Text('Cover art updated successfully')),
        );
        
        _loadDominantColors();
      } else {
        scaffoldMessengerKey.currentState?.showSnackBar(
          const SnackBar(content: Text('Could not fetch cover art from any source')),
        );
      }
    } catch (e) {
      Logging.severe('Error refetching artwork', e);
      scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(content: Text('Error refetching cover art: $e')),
      );
    } finally {
      setState(() => _refetchingArtwork = false);
    }
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
                    unifiedAlbum?.collectionName ?? 'Unknown Album',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // REMOVE the reload button from AppBar
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

                          // MOVED HERE: Refetch button directly under artwork (only for Deezer)
                          if ((widget.album['platform']?.toString().toLowerCase() ?? unifiedAlbum?.platform.toLowerCase() ?? '') == 'deezer')
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

                          // --- Collapsible Dominant Color Picker ---
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
                                  padding:
                                      const EdgeInsets.only(bottom: 8.0),
                                  child: OutlinedButton.icon(
                                    onPressed: () {
                                      setState(() {
                                        showColorPicker = !showColorPicker;
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
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 4),
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
                                    duration:
                                        const Duration(milliseconds: 300),
                                    opacity: showColorPicker ? 1.0 : 0.0,
                                    child: showColorPicker
                                        ? Padding(
                                            padding: const EdgeInsets.only(
                                                bottom: 8.0),
                                            child: DominantColorPicker(
                                              colors: dominantColors,
                                              selected:
                                                  selectedDominantColor,
                                              onSelect: (color) {
                                                setState(() {
                                                  selectedDominantColor =
                                                      color;
                                                  showColorPicker = false;
                                                });
                                                // Save the selected color to database
                                                _saveDominantColor(color);
                                              },
                                            ),
                                          )
                                        : const SizedBox.shrink(),
                                  ),
                                ),
                              ],
                            ),

                          // Add PlatformMatchWidget below the color picker
                          if (unifiedAlbum != null)
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 0.0),
                              child: PlatformMatchWidget(
                                album: unifiedAlbum!,
                                showTitle: false,
                                buttonSize: 40.0,
                              ),
                            ),

                          // Album info section
                          Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              children: [
                                _buildInfoRow(
                                    "Artist",
                                    unifiedAlbum?.artistName ??
                                        'Unknown Artist'),
                                _buildInfoRow(
                                    "Album",
                                    unifiedAlbum?.collectionName ??
                                        'Unknown Album'),
                                // MODIFIED: Add refresh icon inline with release date
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 2.0),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        "Release Date: ",
                                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                      ),
                                      Text(
                                        _formatReleaseDate(),
                                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.normal),
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
                                    averageRating.toStringAsFixed(2)),

                                // Buttons row - KEEP AT CURRENT POSITION
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.center,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    FilledButton(
                                      onPressed: () {
                                        _showAddToListDialog();
                                      },
                                      style: FilledButton.styleFrom(
                                        backgroundColor: selectedDominantColor ?? Theme.of(context).colorScheme.primary,
                                        foregroundColor: useDarkButtonText
                                            ? Colors.black
                                            : ColorUtility
                                                .getContrastingColor(
                                                    selectedDominantColor ?? Theme.of(context).colorScheme.primary),
                                        minimumSize: const Size(150, 45),
                                      ),
                                      child: const Text('Save Album'),
                                    ),
                                    const SizedBox(width: 12),
                                    FilledButton.icon(
                                      icon: Icon(Icons.settings,
                                          color: useDarkButtonText
                                              ? Colors.black
                                              : ColorUtility
                                                  .getContrastingColor(
                                                      selectedDominantColor ?? Theme.of(context).colorScheme.primary)),
                                      label: Text(
                                        'Options',
                                        style: TextStyle(
                                            color: useDarkButtonText
                                                ? Colors.black
                                                : ColorUtility
                                                    .getContrastingColor(
                                                        selectedDominantColor ?? Theme.of(context).colorScheme.primary)),
                                      ),
                                      style: FilledButton.styleFrom(
                                        backgroundColor: selectedDominantColor ?? Theme.of(context).colorScheme.primary,
                                        foregroundColor: useDarkButtonText
                                            ? Colors.black
                                            : ColorUtility
                                                .getContrastingColor(
                                                    selectedDominantColor ?? Theme.of(context).colorScheme.primary),
                                        minimumSize: const Size(150, 45),
                                      ),
                                      onPressed: () {
                                        _showOptionsDialog();
                                      },
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const Divider(),
                          // Restore original DataTable approach with dynamic width
                          _buildTrackList(),

                          // NOTES SECTION - MOVED TO HERE (below tracks, above RateYourMusic)
                          const SizedBox(height: 20),

                          // Display note if exists - remove fixed width, let it size naturally
                          if (albumNote != null && albumNote!.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16.0),
                              child: Container(
                                // Remove fixed width constraint - let it size naturally
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
                                                          // Store context in local variable before async gap
                                                          final currentContext =
                                                              context;
                                                          Navigator.of(
                                                                  currentContext)
                                                              .pop();

                                                          // Get album ID
                                                          final albumId = widget
                                                                          .album[
                                                                      'id'] !=
                                                                  null
                                                              ? widget
                                                                  .album[
                                                                      'id']
                                                                  .toString()
                                                              : widget.album[
                                                                          'collectionId']
                                                                      ?.toString() ??
                                                                  '';

                                                          if (albumId
                                                              .isNotEmpty) {
                                                            // Save empty note (effectively deleting it)
                                                            await UserData
                                                                .saveAlbumNote(
                                                                    albumId,
                                                                    '');

                                                            // Fix: Add mounted check before using context after async gap
                                                            if (mounted) {
                                                              setState(() {
                                                                albumNote =
                                                                    null;
                                                              });
                                                              // Use scaffoldMessengerKey instead of context after async gap
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
                                                  // Change from error color to primary color
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

  Widget _buildInfoRow(String label, String value, {double fontSize = 14}) {
    // Special handling for Rating to make it bigger
    final effectiveFontSize = label == "Rating" ? 18.0 : fontSize;
    
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
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: effectiveFontSize),
          ),
          Tooltip(
            message: value,
            child: Text(
              value,
              style: TextStyle(fontSize: effectiveFontSize, fontWeight: FontWeight.normal),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // When building the track list section - use the same approach as SavedAlbumPage
  Widget _buildTrackList() {
    // Calculate a reasonable table width based on content
    final screenWidth = MediaQuery.of(context).size.width;
    final maxTableWidth = (screenWidth * 0.9).clamp(400.0, 800.0); // Reasonable limits
    
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxTableWidth),
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
                    const SizedBox(width: 30, child: Center(child: Text('#', style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13)))), // Changed from w600 to w500
                    const SizedBox(width: 8),
                    Expanded(child: Text('Title', style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13))), // Changed from w600 to w500
                    const SizedBox(width: 8),
                    const SizedBox(width: 70, child: Center(child: Text('Duration', style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13)))), // Changed from w600 to w500
                    const SizedBox(width: 8),
                    const SizedBox(width: 160, child: Center(child: Text('Rating', style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13)))), // Changed from w600 to w500
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
    );
  }

  // Make the slider bigger and more usable
  Widget _buildCompactTrackSlider(dynamic trackId) {
    final ratingKey = trackId.toString();
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
                value: ratings[ratingKey] ?? 0.0,
                onChanged: (newRating) => _updateRating(trackId, newRating),
              ),
            ),
          ),
          SizedBox(
            width: 25,
            child: Text(
              (ratings[ratingKey] ?? 0).toStringAsFixed(0),
              textAlign: TextAlign.end,
              style: TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

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
      ),
    );

    // FIX: Move the .then() logic here as direct await/if statements
    if (result == null) return; // Dialog cancelled

    if (result == 'new') {
      _showCreateListDialog();
      return;
    }

    try {
      // CRITICAL FIX: Ensure Spotify albums get disc numbers before saving
      Map<String, dynamic> albumToSave = unifiedAlbum?.toJson() ?? widget.album;
      
      // If this is a Spotify album, ensure we have proper disc numbers in tracks
      if (albumToSave['platform'] == 'spotify') {
        Logging.severe('=== ENSURING SPOTIFY DISC NUMBERS BEFORE SAVE ===');
        
        // Check if tracks already have disc_number data
        bool hasDiscNumbers = false;
        if (albumToSave['tracks'] is List && (albumToSave['tracks'] as List).isNotEmpty) {
          final firstTrack = (albumToSave['tracks'] as List)[0];
          if (firstTrack is Map<String, dynamic> && firstTrack.containsKey('disc_number')) {
            hasDiscNumbers = true;
            Logging.severe('Tracks already have disc_number data');
          }
        }
        
        // If no disc numbers, fetch fresh data from Spotify API
        if (!hasDiscNumbers) {
          Logging.severe('No disc numbers found, fetching fresh Spotify data');
          final enhancedAlbum = await SearchService.fetchAlbumTracks(albumToSave);
          
          if (enhancedAlbum != null && enhancedAlbum['tracks'] is List) {
            albumToSave = enhancedAlbum;
            Logging.severe('Updated album with ${(enhancedAlbum['tracks'] as List).length} tracks including disc numbers');
            
            // Debug first few tracks
            final tracksList = enhancedAlbum['tracks'] as List;
            for (int i = 0; i < tracksList.length && i < 3; i++) {
              final track = tracksList[i];
              Logging.severe('Enhanced Track $i: "${track['trackName']}" - disc_number: ${track['disc_number']}');
            }
          } else {
            Logging.severe('Failed to enhance Spotify album with disc numbers');
          }
        }
      }

      // First make sure the album is saved to database (now with disc numbers)
      final saveResult = await UserData.addToSavedAlbums(albumToSave);

      // --- Save dominant color if selected ---
      final albumIdStr = unifiedAlbum?.id.toString() ??
          albumToSave['id']?.toString() ??
          albumToSave['collectionId']?.toString();
      if (albumIdStr != null &&
          albumIdStr.isNotEmpty &&
          selectedDominantColor != null) {
        await DatabaseHelper.instance.saveDominantColor(albumIdStr,
            '#${selectedDominantColor!.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}');
        Logging.severe('Saved dominant color for album $albumIdStr');
      }
      // --- end dominant color save ---

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
      String? albumId = unifiedAlbum?.id.toString() ??
          albumToSave['id']?.toString() ??
          albumToSave['collectionId']?.toString();

      if (albumId == null || albumId.isEmpty) {
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
        final hasAlbum = list.albumIds.contains(albumId);

        Logging.severe(
            'List ${list.name}: selected=$isSelected, hasAlbum=$hasAlbum');

        if (isSelected && !hasAlbum) {
          // Add to list
          list.albumIds.add(albumId);
          final success = await UserData.saveCustomList(list);
          if (success) {
            addedCount++;
            Logging.severe('Added album to list ${list.name}');
          } else {
            Logging.severe('Failed to add album to list ${list.name}');
          }
        } else if (!isSelected && hasAlbum) {
          // Remove from list
          list.albumIds.remove(albumId);
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

  void _showCreateListDialog() {
    final nameController = TextEditingController();
    final descController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
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
                  // CRITICAL FIX: Store navigator before async operations
                  final navigator = Navigator.of(context);
                  
                  // CRITICAL FIX: Ensure Spotify albums have disc numbers before saving
                  Map<String, dynamic> albumToSave = unifiedAlbum?.toJson() ?? widget.album;
                  
                  // If this is a Spotify album, ensure we have proper disc numbers in tracks
                  if (albumToSave['platform'] == 'spotify') {
                    Logging.severe('=== ENSURING SPOTIFY DISC NUMBERS FOR NEW LIST ===');
                    
                    // Check if tracks already have disc_number data
                    bool hasDiscNumbers = false;
                    if (albumToSave['tracks'] is List && (albumToSave['tracks'] as List).isNotEmpty) {
                      final firstTrack = (albumToSave['tracks'] as List)[0];
                      if (firstTrack is Map<String, dynamic> && firstTrack.containsKey('disc_number')) {
                        hasDiscNumbers = true;
                      }
                    }
                    
                    // If no disc numbers, fetch fresh data from Spotify API
                    if (!hasDiscNumbers) {
                      final enhancedAlbum = await SearchService.fetchAlbumTracks(albumToSave);
                      if (enhancedAlbum != null && enhancedAlbum['tracks'] is List) {
                        albumToSave = enhancedAlbum;
                        Logging.severe('Enhanced album for new list with disc numbers');
                      }
                    }
                  }

                  await UserData.addToSavedAlbums(albumToSave);

                  // Get album ID
                  final albumIdStr = unifiedAlbum?.id.toString() ??
                      albumToSave['id']?.toString() ??
                      albumToSave['collectionId']?.toString() ??
                      '';

                  // --- Save dominant color if selected ---
                  if (albumIdStr.isNotEmpty && selectedDominantColor != null) {
                    await DatabaseHelper.instance.saveDominantColor(albumIdStr,
                        '#${selectedDominantColor!.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}');
                    Logging.severe(
                        'Saved dominant color for album $albumIdStr');
                  }
                  // --- end dominant color save ---

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
                  
                  // FIX: Use stored navigator instead of Navigator.of(context)
                  navigator.pop();
                } else {
                  // FIX: If name is empty, we can still use context directly since no async gap
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
                        builder: (_) => DetailsPage(
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
                  final albumToExport = unifiedAlbum?.toJson() ?? widget.album;
                  if (mounted) {
                    await UserData.exportAlbum(albumToExport);
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

  // Fix the _attachRatingsToTracks method
  void _attachRatingsToTracks() {
    Logging.severe('Attaching ratings to ${tracks.length} tracks');
    Logging.severe('Available ratings: $ratings');

    for (int i = 0; i < tracks.length; i++) {
      final tid = tracks[i].id.toString();
      double? rating = ratings[tid];

      if (rating == null) {
        // Try position-based match (for Discogs/legacy)
        String posStr = tracks[i].position.toString().padLeft(3, '0');
        for (final key in ratings.keys) {
          if (key.endsWith(posStr)) {
            rating = ratings[key];
            Logging.severe(
                'Found position-based rating for track $tid: $rating from key $key');
            break;
          }
        }
      }

      if (rating != null && rating > 0) {
        // Create new track with rating in metadata
        tracks[i] = Track(
          id: tracks[i].id,
          name: tracks[i].name,
          position: tracks[i].position,
          durationMs: tracks[i].durationMs,
          metadata: {...tracks[i].metadata, 'rating': rating},
        );
        Logging.severe('Attached rating $rating to track ${tracks[i].name}');
      } else {
        Logging.severe('No rating found for track $tid (${tracks[i].name})');
      }
    }
  }

  void _showShareDialog() {
    _attachRatingsToTracks();

    Logging.severe('Share dialog: tracks with ratings attached');
    for (var track in tracks) {
      if (track.metadata.containsKey('rating')) {
        Logging.severe(
            'Track ${track.name} has rating: ${track.metadata['rating']}');
      }
    }

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
                    // Export theme toggle at the top (single location)
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
                        album: unifiedAlbum?.toJson() ?? widget.album,
                        tracks: tracks,
                        ratings: ratings,
                        averageRating: averageRating,
                        selectedDominantColor: selectedDominantColor,
                        exportDarkTheme: exportDarkTheme,
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
                      // Store references before async gap
                      final navigator = Navigator.of(context);
                      final scaffoldMessenger = ScaffoldMessenger.of(context);
                      
                      try {
                        final path = await shareWidgetKey.currentState?.saveAsImage();

                        // Check if the widget is still mounted before using navigator
                        if (!mounted) return;
                        
                        if (path != null) {
                          navigator.pop();
                          _showShareOptions(path);
                        }
                      } catch (e) {
                        // Check if the widget is still mounted before showing the error
                        if (mounted) {
                          navigator.pop();
                          scaffoldMessenger.showSnackBar(
                            SnackBar(content: Text('Error saving image: $e')),
                          );
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
                      final artist = unifiedAlbum?.artist ?? widget.album['artistName'] ?? widget.album['artist'] ?? 'UnknownArtist';
                      final albumName = unifiedAlbum?.name ?? widget.album['collectionName'] ?? widget.album['name'] ?? 'UnknownAlbum';
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
                ListTile(
                  leading: const Icon(Icons.share),
                  title: const Text('Share Image'),
                  onTap: () async {
                    Navigator.of(bottomSheetContext).pop();
                    try {
                      await SharePlus.instance.share(ShareParams(
                        files: [XFile(path)],
                      ));
                    } catch (e) {
                      if (!mounted) return;
                      scaffoldMessengerKey.currentState?.showSnackBar(
                        SnackBar(content: Text('Error sharing: $e')),
                      );
                    }
                  },
                ),
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

  // Helper method to extract tracks from album data
  List<Track> _extractTracksFromAlbum(Map<String, dynamic> album) {
    List<Track> result = [];

    try {
      if (album['tracks'] is List) {
        final tracksList = album['tracks'] as List;
        Logging.severe('=== DETAILS_PAGE TRACK EXTRACTION DEBUG ===');
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
                metadata: trackData,
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
        Logging.severe('=== END DETAILS_PAGE EXTRACTION ===');
      }
    } catch (e, stack) {
      Logging.severe('Error extracting tracks from album', e, stack);
    }

    Logging.severe('Extracted ${result.length} tracks from album');
    return result; // FIX: Moved return statement outside the try-catch to ensure it always executes
  }

  // Add this method to handle refresh
  Future<void> _refreshData() async {
    Logging.severe('Refreshing album details');

    // Reset loading state
    setState(() {
      ratings = {};
      tracks = [];
      isLoading = true;
    });

    // Reload all data
    await _initialize();

    Logging.severe('Refresh complete, loaded ${tracks.length} tracks');

    // Show a success message
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Album refreshed')),
      );
    }
  }

  // Implement the method to fetch and compare release date
  Future<void> _fetchAndCompareReleaseDate() async {
    if (unifiedAlbum == null) return;

    final albumName = unifiedAlbum?.name ?? '';
    final artistName = unifiedAlbum?.artistName ?? '';
    final albumUrl = unifiedAlbum?.url ?? '';
    final platform = unifiedAlbum?.platform.toLowerCase() ?? ''; // FIX: Removed duplicate ?? operator

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
          Logging.severe('Deezer: could not determine album URL for fetch');
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
          whereArgs: [unifiedAlbum?.id.toString()],
        );
      }

      if (!mounted) return;
      
      setState(() {});
      
      // FIX: Use scaffoldMessengerKey instead of ScaffoldMessenger.of(context)
      scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(content: Text(message)),
      );
      Logging.severe('=== RELEASE DATE DEBUG END ===');
    } catch (e, stack) {
      Logging.severe('Error in _fetchAndCompareReleaseDate: $e', stack);
      
      if (!mounted) return;
      
      scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(content: Text('Error fetching release date: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }
}