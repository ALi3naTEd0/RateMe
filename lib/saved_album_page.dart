import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:html/parser.dart' show parse;
import 'user_data.dart';
import 'logging.dart';
import 'custom_lists_page.dart';
import 'album_model.dart';
import 'share_widget.dart';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'widgets/skeleton_loading.dart';
import 'platform_service.dart'; // Add this import to fix the undefined identifier
import 'widgets/platform_match_widget.dart'; // Add this import

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
  Map<String, double> ratings = {};
  double averageRating = 0.0;
  int albumDurationMillis = 0; // Add this
  DateTime? releaseDate; // Add this
  bool isLoading = true;
  bool useDarkButtonText = false;

  // Add refresh indicator key
  final GlobalKey<RefreshIndicatorState> _refreshIndicatorKey =
      GlobalKey<RefreshIndicatorState>();

  @override
  void initState() {
    super.initState();
    _initialize();
    _loadButtonPreference();
  }

  Future<void> _loadButtonPreference() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        useDarkButtonText = prefs.getBool('useDarkButtonText') ?? false;
      });
    }
  }

  Future<void> _initialize() async {
    try {
      // Convert legacy album to unified model
      unifiedAlbum = Album.fromJson(widget.album);
      Logging.severe(
          'Initialized album in unified model: ${unifiedAlbum?.name}');

      // More reliable platform detection - check the ID format first
      String detectedPlatform = 'unknown';
      final albumId = unifiedAlbum?.id ??
          widget.album['id'] ??
          widget.album['collectionId'];

      // Log the ID we're processing
      Logging.severe(
          'Processing album ID: $albumId (type: ${albumId.runtimeType})');

      // Check ID format - Spotify IDs are typically alphanumeric and around 22 chars
      if (albumId is String &&
          albumId.length > 10 &&
          !albumId.contains(RegExp(r'^[0-9]+$'))) {
        detectedPlatform = 'spotify';
        Logging.severe('Detected Spotify album ID based on format: $albumId');
      } else if (widget.isBandcamp ||
          widget.album['url']?.toString().contains('bandcamp.com') == true) {
        detectedPlatform = 'bandcamp';
        Logging.severe('Detected Bandcamp album based on URL');
      } else if (widget.album['url']?.toString().contains('deezer.com') ==
          true) {
        detectedPlatform = 'deezer';
        Logging.severe('Detected Deezer album based on URL');
      } else if (albumId is int ||
          (albumId is String && int.tryParse(albumId) != null)) {
        detectedPlatform = 'itunes';
        Logging.severe('Detected iTunes album based on numeric ID: $albumId');
      }

      // Use explicitly set platform if available
      final storedPlatform = unifiedAlbum?.platform.toLowerCase() ??
          widget.album['platform']?.toString().toLowerCase();

      if (storedPlatform != null &&
          storedPlatform.isNotEmpty &&
          storedPlatform != 'unknown') {
        detectedPlatform = storedPlatform;
        Logging.severe('Using explicitly set platform: $detectedPlatform');
      }

      // Load ratings first
      await _loadRatings();

      // Then load tracks based on detected platform
      Logging.severe('Fetching tracks using platform: $detectedPlatform');

      if (detectedPlatform == 'bandcamp') {
        await _fetchBandcampTracks();
      } else if (detectedPlatform == 'spotify') {
        await _fetchSpotifyTracks();
      } else if (detectedPlatform == 'deezer') {
        await _fetchDeezerTracks();
      } else {
        await _fetchItunesTracks();
      }

      if (mounted) {
        setState(() => isLoading = false);
      }
    } catch (e, stack) {
      Logging.severe('Error initializing saved album page', e, stack);
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _loadRatings() async {
    try {
      // Add debugging for album ID
      final albumId = unifiedAlbum?.id ??
          widget.album['collectionId'] ??
          widget.album['id'];
      Logging.severe(
          'Loading ratings for album ID: $albumId (${albumId.runtimeType})');

      final List<Map<String, dynamic>> savedRatings =
          await UserData.getSavedAlbumRatings(albumId);
      Logging.severe('Found ${savedRatings.length} ratings for this album');

      if (savedRatings.isNotEmpty) {
        Logging.severe('Sample rating: ${savedRatings.first}');
      }

      if (mounted) {
        // Use strings as keys for all ratings
        Map<String, double> ratingsMap = {};

        for (var rating in savedRatings) {
          try {
            // Always store track ID as string
            String trackId = rating['trackId'].toString();
            ratingsMap[trackId] = rating['rating'].toDouble();
            Logging.severe(
                'Added rating for track $trackId: ${rating['rating']}');
          } catch (e) {
            Logging.severe(
                'Error processing rating: $e - Data: ${rating.toString()}');
          }
        }

        setState(() {
          ratings = ratingsMap;
          calculateAverageRating();
        });
      }
    } catch (e, stack) {
      Logging.severe('Error loading ratings', e, stack);
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

  Future<void> _fetchBandcampTracks() async {
    final url = widget.album['url'];
    try {
      Logging.severe('BANDCAMP: Starting to fetch tracks from URL: $url');

      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final document = parse(response.body);
        var ldJsonScript =
            document.querySelector('script[type="application/ld+json"]');

        if (ldJsonScript != null) {
          final ldJson = jsonDecode(ldJsonScript.text);
          Logging.severe('BANDCAMP: Successfully parsed JSON-LD data');

          // Extract title parts without changing the album name yet
          final fullTitle = ldJson['name'] ?? '';
          String artistName = ldJson['byArtist']?['name'] ?? '';

          // Update title extraction logic
          String albumTitle = fullTitle;
          if (fullTitle.contains(',')) {
            final parts = fullTitle.split(',');
            if (parts.length >= 2) {
              albumTitle = parts[0].trim();
              artistName = parts[1].replaceAll('by', '').trim();
            }
          }

          // Update the album with correct title/artist
          widget.album['collectionName'] = albumTitle;
          widget.album['artistName'] = artistName;

          if (unifiedAlbum != null) {
            unifiedAlbum = Album(
              id: unifiedAlbum!.id,
              name: albumTitle,
              artist: artistName,
              artworkUrl: unifiedAlbum!.artworkUrl,
              url: unifiedAlbum!.url,
              platform: unifiedAlbum!.platform,
              releaseDate: unifiedAlbum!.releaseDate,
              metadata: unifiedAlbum!.metadata,
              tracks: unifiedAlbum!.tracks,
            );
          }

          // Process tracks first
          if (ldJson['track'] != null &&
              ldJson['track']['itemListElement'] != null) {
            List<Track> tracksData = [];
            Map<int, double> tempRatings = {};
            var trackItems = ldJson['track']['itemListElement'] as List;

            final albumId =
                widget.album['collectionId'] ?? widget.album['id'] ?? url;
            final savedRatings = await UserData.getSavedAlbumRatings(albumId);

            Logging.severe('BANDCAMP: Processing ${trackItems.length} tracks');

            for (int i = 0; i < trackItems.length; i++) {
              try {
                var item = trackItems[i];
                var track = item['item'];

                // Get track ID from additionalProperty
                var props = track['additionalProperty'] as List;
                var trackIdProp = props.firstWhere(
                    (p) => p['name'] == 'track_id',
                    orElse: () => {'value': (albumId.hashCode * 1000) + i});
                int trackId = trackIdProp['value'];

                // Parse duration correctly
                String duration = track['duration'] ?? '';
                int durationMillis = _parseBandcampDuration(duration);
                Logging.severe(
                    'Duration for track ${i + 1}: $duration -> ${durationMillis}ms');

                tracksData.add(Track(
                  id: trackId,
                  name: track['name'],
                  position: i + 1,
                  durationMs: durationMillis,
                  metadata: track,
                ));

                // Look for existing rating
                var savedRating = savedRatings.firstWhere(
                  (r) => r['trackId'].toString() == trackId.toString(),
                  orElse: () => {'rating': 0.0},
                );
                tempRatings[trackId] = savedRating['rating'].toDouble();
              } catch (e) {
                Logging.severe('Error processing track ${i + 1}: $e');
              }
            }

            if (mounted) {
              setState(() {
                tracks = tracksData;
                ratings = Map.fromEntries(tempRatings.entries
                    .map((e) => MapEntry(e.key.toString(), e.value)));
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

  int _parseBandcampDuration(String duration) {
    try {
      if (duration.isEmpty) return 0;

      if (duration.startsWith('P')) {
        // Parse format like "PT4M31S"
        final hours = RegExp(r'(\d+)H').firstMatch(duration)?.group(1);
        final minutes = RegExp(r'(\d+)M').firstMatch(duration)?.group(1);
        final seconds = RegExp(r'(\d+)S').firstMatch(duration)?.group(1);

        int totalSeconds = 0;
        if (hours != null) totalSeconds += int.parse(hours) * 3600;
        if (minutes != null) totalSeconds += int.parse(minutes) * 60;
        if (seconds != null) totalSeconds += int.parse(seconds);

        Logging.severe('Parsed duration $duration to ${totalSeconds * 1000}ms');
        return totalSeconds * 1000;
      }
      return 0;
    } catch (e) {
      Logging.severe('Error parsing duration: $duration - $e');
      return 0;
    }
  }

  Future<void> _fetchSpotifyTracks() async {
    try {
      Logging.severe(
          'Fetching Spotify tracks for album ID: ${unifiedAlbum?.id}');

      // If the album already has tracks, use them
      if (widget.album['tracks'] != null &&
          widget.album['tracks'] is List &&
          (widget.album['tracks'] as List).isNotEmpty) {
        Logging.severe(
            'Using existing tracks from album data (${widget.album['tracks'].length} tracks)');

        List<Track> spotifyTracks = [];
        for (var trackData in widget.album['tracks']) {
          try {
            spotifyTracks.add(Track(
              id: trackData['id'] ?? trackData['trackId'] ?? 0,
              name: trackData['name'] ??
                  trackData['trackName'] ??
                  'Unknown Track',
              position: trackData['position'] ?? trackData['trackNumber'] ?? 0,
              durationMs:
                  trackData['durationMs'] ?? trackData['trackTimeMillis'] ?? 0,
              metadata: trackData,
            ));
          } catch (e) {
            Logging.severe('Error parsing Spotify track: $e');
          }
        }

        if (mounted) {
          setState(() {
            tracks = spotifyTracks;
            calculateAlbumDuration();
          });
        }
        return;
      }

      // If we don't have tracks, try to use the ones from the unified model
      if (unifiedAlbum != null && unifiedAlbum!.tracks.isNotEmpty) {
        Logging.severe(
            'Using tracks from unified album model (${unifiedAlbum!.tracks.length} tracks)');

        if (mounted) {
          setState(() {
            tracks = unifiedAlbum!.tracks;
            calculateAlbumDuration();
          });
        }
        return;
      }

      // As a last resort, fetch tracks from the Spotify API
      final albumId = unifiedAlbum?.id;
      if (albumId != null) {
        Logging.severe('Fetching tracks from Spotify API for album: $albumId');

        // Use PlatformService to fetch the full album data with tracks
        final spotifyAlbum =
            await PlatformService.fetchSpotifyAlbum(albumId.toString());

        if (spotifyAlbum != null && spotifyAlbum['tracks'] != null) {
          List<Track> spotifyTracks = [];

          for (var trackData in spotifyAlbum['tracks']) {
            try {
              spotifyTracks.add(Track(
                id: trackData['trackId'] ?? trackData['id'] ?? 0,
                name: trackData['trackName'] ??
                    trackData['name'] ??
                    'Unknown Track',
                position:
                    trackData['position'] ?? trackData['trackNumber'] ?? 0,
                durationMs: trackData['trackTimeMillis'] ??
                    trackData['durationMs'] ??
                    0,
                metadata: trackData,
              ));
            } catch (e) {
              Logging.severe('Error parsing Spotify API track: $e');
            }
          }

          if (spotifyTracks.isNotEmpty) {
            Logging.severe(
                'Retrieved ${spotifyTracks.length} tracks from Spotify API');
            if (mounted) {
              setState(() {
                tracks = spotifyTracks;
                calculateAlbumDuration();
              });
            }
            return;
          }
        } else {
          Logging.severe(
              'Failed to fetch Spotify album data or tracks from API');
        }
      }

      // If we still don't have tracks, display empty list
      Logging.severe('No tracks available for this Spotify album');
      if (mounted) {
        setState(() {
          tracks = [];
          isLoading = false;
        });
      }
    } catch (e, stack) {
      Logging.severe('Error fetching Spotify tracks', e, stack);
      if (mounted) {
        setState(() {
          tracks = [];
          isLoading = false;
        });
      }
    }
  }

  Future<void> _fetchDeezerTracks() async {
    try {
      Logging.severe(
          'Fetching Deezer tracks for album ID: ${unifiedAlbum?.id}');

      // First try to get tracks from the album's data field
      if (widget.album['data'] != null) {
        try {
          // Parse the stored data that might contain tracks
          Map<String, dynamic> fullData = jsonDecode(widget.album['data']);
          if (fullData['tracks'] != null && fullData['tracks'] is List) {
            List<Track> deezerTracks = [];
            for (var trackData in fullData['tracks']) {
              try {
                deezerTracks.add(Track(
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
              } catch (e) {
                Logging.severe('Error parsing stored Deezer track: $e');
              }
            }

            if (deezerTracks.isNotEmpty) {
              Logging.severe(
                  'Using ${deezerTracks.length} tracks from saved album data');
              if (mounted) {
                setState(() {
                  tracks = deezerTracks;
                  calculateAlbumDuration();
                });
              }
              return;
            }
          }
        } catch (e) {
          Logging.severe('Error parsing saved album data: $e');
        }
      }

      // If the album already has tracks, use them
      if (widget.album['tracks'] != null &&
          widget.album['tracks'] is List &&
          (widget.album['tracks'] as List).isNotEmpty) {
        Logging.severe(
            'Using existing tracks from album data (${widget.album['tracks'].length} tracks)');

        List<Track> deezerTracks = [];
        for (var trackData in widget.album['tracks']) {
          try {
            deezerTracks.add(Track(
              id: trackData['id'] ?? trackData['trackId'] ?? 0,
              name: trackData['name'] ??
                  trackData['trackName'] ??
                  'Unknown Track',
              position: trackData['position'] ?? trackData['trackNumber'] ?? 0,
              durationMs:
                  trackData['durationMs'] ?? trackData['trackTimeMillis'] ?? 0,
              metadata: trackData,
            ));
          } catch (e) {
            Logging.severe('Error parsing Deezer track: $e');
          }
        }

        if (mounted) {
          setState(() {
            tracks = deezerTracks;
            calculateAlbumDuration();
          });
        }
        return;
      }

      // If we don't have tracks, try to use the ones from the unified model
      if (unifiedAlbum != null && unifiedAlbum!.tracks.isNotEmpty) {
        Logging.severe(
            'Using tracks from unified album model (${unifiedAlbum!.tracks.length} tracks)');

        if (mounted) {
          setState(() {
            tracks = unifiedAlbum!.tracks;
            calculateAlbumDuration();
          });
        }
        return;
      }

      // As a last resort, try to fetch them from the Deezer API
      final albumId = unifiedAlbum?.id;
      if (albumId != null) {
        final deezerAlbum =
            await PlatformService.fetchDeezerAlbum(albumId.toString());
        if (deezerAlbum != null && deezerAlbum['tracks'] is List) {
          List<Track> fetchedTracks = [];
          for (var trackData in deezerAlbum['tracks']) {
            fetchedTracks.add(Track(
              id: trackData['trackId'] ?? trackData['id'] ?? 0,
              name: trackData['trackName'] ??
                  trackData['name'] ??
                  'Unknown Track',
              position: trackData['trackNumber'] ?? trackData['position'] ?? 0,
              durationMs: trackData['trackTimeMillis'] ?? 0,
              metadata: trackData,
            ));
          }

          if (fetchedTracks.isNotEmpty) {
            Logging.severe(
                'Retrieved ${fetchedTracks.length} tracks from Deezer API');
            if (mounted) {
              setState(() {
                tracks = fetchedTracks;
                calculateAlbumDuration();
              });
            }
            return;
          }
        }
      }

      // If we still don't have tracks, show empty list
      Logging.severe('No tracks available for this Deezer album');
      if (mounted) {
        setState(() {
          tracks = [];
          isLoading = false;
        });
      }
    } catch (e, stack) {
      Logging.severe('Error fetching Deezer tracks', e, stack);
      if (mounted) {
        setState(() {
          tracks = [];
          isLoading = false;
        });
      }
    }
  }

  Future<void> _fetchItunesTracks() async {
    try {
      Logging.severe(
          'Fetching iTunes tracks for album ID: ${unifiedAlbum?.id}');

      // Check if this is an iTunes ID (numeric) or another platform's ID
      final albumId = unifiedAlbum?.id;
      bool isiTunesId = false;

      if (albumId is int) {
        isiTunesId = true;
      } else if (albumId is String) {
        isiTunesId = int.tryParse(albumId) != null;
      }

      // If not an iTunes ID, use existing tracks
      if (!isiTunesId) {
        Logging.severe(
            'ID ${unifiedAlbum?.id} is not an iTunes ID, using existing tracks');

        if (unifiedAlbum != null && unifiedAlbum!.tracks.isNotEmpty) {
          Logging.severe(
              'Using ${unifiedAlbum!.tracks.length} tracks from unified album model');
          setState(() {
            tracks = unifiedAlbum!.tracks;
            calculateAlbumDuration();
          });
          return;
        }

        if (widget.album['tracks'] != null && widget.album['tracks'] is List) {
          Logging.severe(
              'Using ${widget.album['tracks'].length} tracks from album data');
          List<Track> parsedTracks = [];
          for (var trackData in widget.album['tracks']) {
            try {
              parsedTracks.add(Track(
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
            } catch (e) {
              Logging.severe('Error parsing track: $e');
            }
          }

          setState(() {
            tracks = parsedTracks;
            calculateAlbumDuration();
          });
          return;
        }

        // No tracks available
        Logging.severe('No tracks available for this non-iTunes album');
        setState(() {
          tracks = [];
        });
        return;
      }

      // If we have an iTunes ID, fetch from the API
      final url = Uri.parse(
          'https://itunes.apple.com/lookup?id=${unifiedAlbum?.id}&entity=song');
      final response = await http.get(url);

      Logging.severe(
          'iTunes API response: status=${response.statusCode}, content-type=${response.headers['content-type']}');

      // Debug the response
      if (response.statusCode != 200) {
        Logging.severe('iTunes API error response: ${response.body}');
      }

      final data = jsonDecode(response.body);

      Logging.severe(
          'iTunes API response parsed: resultCount=${data['resultCount']}');

      // Check if we have results before processing
      if (data['results'] == null || data['results'].isEmpty) {
        Logging.severe('No results found in iTunes API response');
        setState(() {
          tracks = [];
          isLoading = false;
        });
        return;
      }

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

          // Verify ratings after loading tracks
          if (ratings.isNotEmpty) {
            Logging.severe('Ratings after track load: ${ratings.length} items');
            Logging.severe('Rating keys: ${ratings.keys.join(', ')}');
            Logging.severe('Track IDs: ${tracks.map((t) => t.id).join(', ')}');
          } else {
            Logging.severe('No ratings found after track load');
          }
        });
      }
    } catch (e, stack) {
      Logging.severe('Error fetching iTunes tracks', e, stack);
      if (mounted) {
        setState(() {
          tracks = [];
          isLoading = false;
        });
      }
    }
  }

  void _updateRating(dynamic trackId, double newRating) async {
    try {
      // Ensure trackId is a string
      final trackIdStr = trackId.toString();

      Logging.severe('Updating rating for track $trackIdStr to $newRating');

      // Get album ID in the right format
      final albumId = unifiedAlbum?.id ??
          widget.album['collectionId'] ??
          widget.album['id'];

      if (albumId == null) {
        Logging.severe('Cannot save rating - album ID is null');
        return;
      }

      // Update state
      setState(() {
        ratings[trackIdStr] = newRating;
      });

      // Delay calculation slightly to ensure state is updated
      await Future.delayed(const Duration(milliseconds: 50));
      calculateAverageRating();

      // Save to storage
      await UserData.saveRating(albumId, trackId, newRating);

      // Verify the save
      final savedRatings = await UserData.getSavedAlbumRatings(albumId);

      // Log current ratings state
      Logging.severe('Current ratings map: $ratings');
      Logging.severe('Saved ratings from storage: $savedRatings');

      if (!savedRatings.any((r) =>
          r['trackId'].toString() == trackIdStr && r['rating'] == newRating)) {
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

  Widget _buildTrackSlider(dynamic trackId) {
    // Always use string keys for ratings lookup
    final trackIdStr = trackId.toString();

    return SizedBox(
      width: 150,
      child: Row(
        children: [
          Expanded(
            child: SliderTheme(
              data: const SliderThemeData(
                showValueIndicator: ShowValueIndicator.always,
              ),
              child: Slider(
                min: 0,
                max: 10,
                divisions: 10,
                value: ratings[trackIdStr] ?? 0.0,
                label: (ratings[trackIdStr] ?? 0.0).toStringAsFixed(0),
                onChanged: (newRating) => _updateRating(trackId, newRating),
              ),
            ),
          ),
          SizedBox(
            width: 25,
            child: Text(
              (ratings[trackIdStr] ?? 0).toStringAsFixed(0),
              // Explicitly define the const value in another way:
              style: const TextStyle(
                fontSize: 16,
              ),
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
    Logging.severe('Refreshing saved album details');

    // Set loading state
    setState(() {
      isLoading = true;
      tracks = [];
      ratings = {};
      averageRating = 0.0;
    });

    // Reload everything
    await _initialize();

    Logging.severe(
        'Saved album refresh complete, loaded ${tracks.length} tracks');

    // Show feedback to user
    scaffoldMessengerKey.currentState?.showSnackBar(
      const SnackBar(content: Text('Album information refreshed')),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Calculate page width consistently with other pages (85% of screen width)
    final pageWidth = MediaQuery.of(context).size.width * 0.85;
    final horizontalPadding =
        (MediaQuery.of(context).size.width - pageWidth) / 2;

    // Calculate DataTable width to fit within our constraints
    final dataTableWidth = pageWidth - 16; // Apply small padding

    return MaterialApp(
      navigatorKey: navigatorKey,
      scaffoldMessengerKey: scaffoldMessengerKey,
      debugShowCheckedModeBanner: false,
      theme: Theme.of(context),
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
                    widget.album['collectionName'] ?? 'Unknown Album',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          // Remove the actions property completely to remove the 3-dot menu icon
        ),
        body: isLoading
            ? _buildSkeletonAlbumDetails()
            : Center(
                // Center the content
                child: SizedBox(
                  width: pageWidth, // Apply consistent width constraint
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
                                _buildInfoRow(
                                    "Rating", averageRating.toStringAsFixed(2),
                                    fontSize: 20),
                                const SizedBox(height: 16),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    FilledButton(
                                      onPressed: _showAddToListDialog,
                                      style: FilledButton.styleFrom(
                                        backgroundColor: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                        foregroundColor: useDarkButtonText
                                            ? Colors.black
                                            : Colors.white,
                                        minimumSize: const Size(150, 45),
                                      ),
                                      child: const Text('Manage Lists'),
                                    ),
                                    const SizedBox(width: 12),
                                    FilledButton.icon(
                                      icon: Icon(Icons.settings,
                                          color: useDarkButtonText
                                              ? Colors.black
                                              : Colors.white),
                                      label: Text('Options',
                                          style: TextStyle(
                                              color: useDarkButtonText
                                                  ? Colors.black
                                                  : Colors.white)),
                                      style: FilledButton.styleFrom(
                                        backgroundColor: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                        foregroundColor: useDarkButtonText
                                            ? Colors.black
                                            : Colors.white,
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
                          // Track List with Ratings - Wrap in ConstrainedBox
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
                                        child: Center(child: Text('#')))),
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
                              foregroundColor: useDarkButtonText
                                  ? Colors.black
                                  : Colors.white,
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
            album: widget.album,
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

    // Track selected lists
    Map<String, bool> selectedLists = {};

    navigator
        .push(
      PageRouteBuilder(
        barrierColor: Colors.black54,
        opaque: false,
        pageBuilder: (_, __, ___) => StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: const Text('Add to List'),
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
                      minimumSize: const Size(200, 45),
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
      if (result == null) return;

      if (result == 'new') {
        _showCreateListDialog();
        return;
      }

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
          content: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.4,
              maxWidth: MediaQuery.of(context).size.width * 0.85,
            ),
            child: SingleChildScrollView(
              child: Column(
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
            ),
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
