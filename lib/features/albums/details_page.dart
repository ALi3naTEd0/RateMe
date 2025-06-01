import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:rateme/core/services/theme_service.dart';
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
  String? albumNote;

  // Add a key for the RefreshIndicator
  final GlobalKey<RefreshIndicatorState> _refreshIndicatorKey =
      GlobalKey<RefreshIndicatorState>();

  List<Color> dominantColors = [];
  Color? selectedDominantColor;
  bool loadingPalette = false;
  bool showColorPicker = false; // Add this line

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

    // Add this line to define dataTableWidth
    final dataTableWidth = pageWidth - 32; // Apply padding for the data table

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
        builder: (context) => MaterialApp(
          navigatorKey: navigatorKey,
          scaffoldMessengerKey: scaffoldMessengerKey,
          debugShowCheckedModeBanner: false,
          theme: effectiveTheme,
          home: Scaffold(
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
                  ],
                ),
              ),
            ),
            body: Center(
              child: isLoading
                  ? _buildSkeletonAlbumDetails()
                  : SizedBox(
                      width: pageWidth, // Apply consistent width constraint
                      child: RefreshIndicator(
                        key: _refreshIndicatorKey,
                        onRefresh: _refreshData,
                        child: SingleChildScrollView(
                          // To enable pull-to-refresh, we need to ensure there's enough content or that it's scrollable
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

                              // Add PlatformMatchWidget below the artwork
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
                                    _buildInfoRow(
                                        "Release Date", _formatReleaseDate()),
                                    _buildInfoRow("Duration",
                                        formatDuration(albumDurationMillis)),
                                    const SizedBox(height: 8),
                                    _buildInfoRow("Rating",
                                        averageRating.toStringAsFixed(2),
                                        fontSize: 20),
                                    const SizedBox(height: 16),

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
                                                          Theme.of(context)
                                                              .colorScheme
                                                              .primary)),
                                          label: Text(
                                            'Options',
                                            style: TextStyle(
                                                color: useDarkButtonText
                                                    ? Colors.black
                                                    : ColorUtility
                                                        .getContrastingColor(
                                                            Theme.of(context)
                                                                .colorScheme
                                                                .primary)),
                                          ),
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
                              // DataTable for tracks - make sure it fits within the width constraint
                              ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth: dataTableWidth,
                                ),
                                child: _buildTrackList(),
                              ),

                              // NOTES SECTION - MOVED TO HERE (below tracks, above RateYourMusic)
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
                                            color: Theme.of(context)
                                                .colorScheme
                                                .primary,
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
                                  backgroundColor: Theme.of(context)
                                      .colorScheme
                                      .primary, // Will use effective theme
                                  foregroundColor: useDarkButtonText
                                      ? Colors.black
                                      : ColorUtility.getContrastingColor(
                                          Theme.of(context)
                                              .colorScheme
                                              .primary),
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

  Widget _buildInfoRow(String label, String value, {double fontSize = 16}) {
    return Padding(
      padding: EdgeInsets.symmetric(
        vertical: label == "Rating" ? 8.0 : 2.0,
      ),
      child: Wrap(
        // Use Wrap to allow text to flow to next line
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

  Widget _buildTrackSlider(dynamic trackId) {
    final ratingKey = trackId.toString();
    return SizedBox(
      width: 150,
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
                valueIndicatorColor: selectedDominantColor ??
                    Theme.of(context).colorScheme.primary,
                valueIndicatorTextStyle: TextStyle(
                  color: useDarkButtonText
                      ? Colors.black
                      : ColorUtility.getContrastingColor(
                          selectedDominantColor ??
                              Theme.of(context).colorScheme.primary),
                ),
                showValueIndicator: ShowValueIndicator.always,
              ),
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

  Future<void> _showAddToListDialog() async {
    final navigator = navigatorKey.currentState ?? Navigator.of(context);

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

      try {
        // Save the album first since user made selections
        final albumToSave = unifiedAlbum?.toJson() ?? widget.album;

        // First make sure the album is saved to database
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
    });
  }

  void _showCreateListDialog() {
    final navigator = navigatorKey.currentState ?? Navigator.of(context);
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
                  // Save the album first
                  final albumToSave = unifiedAlbum?.toJson() ?? widget.album;
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
                  navigator.pop();
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
    final navigator = navigatorKey.currentState;
    if (navigator == null) return;

    // Attach ratings to tracks INSIDE the dialog builder to ensure fresh data
    _attachRatingsToTracks();

    Logging.severe('Share dialog: tracks with ratings attached');
    for (var track in tracks) {
      if (track.metadata.containsKey('rating')) {
        Logging.severe(
            'Track ${track.name} has rating: ${track.metadata['rating']}');
      }
    }

    navigator.push(
      PageRouteBuilder(
        barrierColor: Colors.black54,
        opaque: false,
        pageBuilder: (_, __, ___) {
          final shareWidget = ShareWidget(
            key: ShareWidget.shareKey,
            album: unifiedAlbum?.toJson() ?? widget.album,
            tracks: tracks,
            ratings: ratings, // Keep this for backward compatibility
            averageRating: averageRating,
            selectedDominantColor:
                selectedDominantColor, // Pass the selected color
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
                      final downloadDir =
                          Directory('/storage/emulated/0/Download');
                      final fileName =
                          'RateMe_${DateTime.now().millisecondsSinceEpoch}.png';
                      final newPath = '${downloadDir.path}/$fileName';

                      // Copy from temp to Downloads
                      await File(path).copy(newPath);

                      // Scan file with MediaScanner
                      const platform =
                          MethodChannel('com.example.rateme/media_scanner');
                      try {
                        await platform
                            .invokeMethod('scanFile', {'path': newPath});
                      } catch (e) {
                        Logging.severe('MediaScanner error: $e');
                      }

                      // Use scaffoldMessengerKey instead of context after async gap
                      if (mounted) {
                        scaffoldMessengerKey.currentState?.showSnackBar(
                          SnackBar(
                              content: Text('Saved to Downloads: $fileName')),
                        );
                      }
                    } catch (e) {
                      // Use scaffoldMessengerKey instead of context after async gap
                      if (mounted) {
                        scaffoldMessengerKey.currentState?.showSnackBar(
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
                    Navigator.of(bottomSheetContext).pop();
                    try {
                      await Share.shareXFiles([XFile(path)]);
                    } catch (e) {
                      // Use scaffoldMessengerKey instead of context after async gap
                      if (mounted) {
                        scaffoldMessengerKey.currentState?.showSnackBar(
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
    } else {
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
    scaffoldMessengerKey.currentState?.showSnackBar(
      const SnackBar(content: Text('Album refreshed')),
    );
  }

  // When building the track list section
  Widget _buildTrackList() {
    // Wrap the DataTable in a SingleChildScrollView with horizontal scrolling
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const AlwaysScrollableScrollPhysics(),
      child: DataTable(
        // Set a minimum width for the table to ensure it scrolls on small screens
        // This should be wide enough to show all content properly
        columnSpacing: 12.0,
        horizontalMargin: 12.0,
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
                    MediaQuery.of(context).size.width * _calculateTitleWidth(),
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
                MediaQuery.of(context).size.width * _calculateTitleWidth(),
              )),
              DataCell(Text(formatDuration(track.durationMs))),
              DataCell(_buildTrackSlider(trackId)),
            ],
          );
        }).toList(),
      ),
    );
  }
}
