import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:sqflite/sqflite.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import '../album_model.dart';
import '../logging.dart';
import '../widgets/skeleton_loading.dart';
import '../platforms/platform_service_factory.dart';
import '../search_service.dart';
import '../database/database_helper.dart';

/// Widget that displays buttons to open an album in various streaming platforms
class PlatformMatchWidget extends StatefulWidget {
  final Album album;
  final bool showTitle;
  final double buttonSize;

  const PlatformMatchWidget({
    super.key,
    required this.album,
    this.showTitle = true,
    this.buttonSize = 40.0,
  });

  @override
  State<PlatformMatchWidget> createState() => _PlatformMatchWidgetState();
}

class _PlatformMatchWidgetState extends State<PlatformMatchWidget> {
  bool _isLoading = false;
  final Map<String, String?> _platformUrls = {};
  final List<String> _supportedPlatforms = [
    'spotify',
    'apple_music',
    'deezer',
    'discogs', // Add Discogs to supported platforms
  ];

  // Create a factory instance to access platform services
  final _platformFactory = PlatformServiceFactory();

  @override
  void initState() {
    super.initState();
    _loadPlatformMatches();
  }

  Future<void> _loadPlatformMatches() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      // More concise logging
      Logging.severe(
          'Loading platform matches: ${widget.album.name} (${widget.album.platform})');

      // Always add the source platform itself to _platformUrls - this ensures we always show the source platform
      if (widget.album.url.isNotEmpty) {
        String currentPlatform = widget.album.platform.toLowerCase();

        // Normalize iTunes to apple_music
        if (currentPlatform == 'itunes') {
          currentPlatform = 'apple_music';
        }

        _platformUrls[currentPlatform] = widget.album.url;

        // For URL-based platform detection
        String urlDetectedPlatform =
            _determinePlatformFromUrl(widget.album.url);
        if (urlDetectedPlatform.isNotEmpty &&
            urlDetectedPlatform != currentPlatform) {
          Logging.severe(
              'PlatformMatch: URL-detected platform ($urlDetectedPlatform) different from album platform ($currentPlatform)');
          // Add the URL-detected platform as well
          _platformUrls[urlDetectedPlatform] = widget.album.url;
        }
      }

      // First try to load platform matches from the database
      final savedMatches = await _loadMatchesFromDatabase();

      if (savedMatches.isNotEmpty) {
        Logging.severe(
            'Loaded ${savedMatches.length} platform matches from database');

        // NEW CODE: Instead of blindly accepting the saved matches,
        // run them through verification for poor matches
        await _verifyAndUpdateSavedMatches(savedMatches);

        setState(() {
          _isLoading = false;
        });
        return;
      }

      // If no saved matches, find them and save to database
      await _findMatchingAlbums();
    } catch (e, stack) {
      Logging.severe('Error loading platform matches', e, stack);
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// Load platform matches from the database
  Future<Map<String, String?>> _loadMatchesFromDatabase() async {
    try {
      final albumId = widget.album.id.toString();
      final db = await DatabaseHelper.instance.database;

      final results = await db.query(
        'platform_matches',
        where: 'album_id = ?',
        whereArgs: [albumId],
      );

      if (results.isEmpty) return {};

      Map<String, String?> matches = {};
      for (var row in results) {
        final platform = row['platform'] as String;
        final url = row['url'] as String?;

        // Normalize iTunes to apple_music when loading from database
        final normalizedPlatform =
            platform.toLowerCase() == 'itunes' ? 'apple_music' : platform;

        // Only add if not already present (prefer apple_music over itunes)
        if (!matches.containsKey(normalizedPlatform)) {
          matches[normalizedPlatform] = url;
        }
      }

      return matches;
    } catch (e, stack) {
      Logging.severe('Error loading platform matches from database', e, stack);
      return {};
    }
  }

  /// Save platform matches to the database
  Future<void> _savePlatformMatches() async {
    try {
      final albumId = widget.album.id.toString();
      final db = await DatabaseHelper.instance.database;

      // First check if the platform_matches table exists
      final tableCheck = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='platform_matches'");

      // Create the table if it doesn't exist
      if (tableCheck.isEmpty) {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS platform_matches (
            album_id TEXT,
            platform TEXT,
            url TEXT,
            verified INTEGER DEFAULT 0,
            timestamp TEXT,
            PRIMARY KEY (album_id, platform)
          )
        ''');
      }

      // Before inserting, normalize any 'itunes' keys to 'apple_music'
      Map<String, String?> normalizedUrls = {};

      for (var entry in _platformUrls.entries) {
        final platform =
            entry.key.toLowerCase() == 'itunes' ? 'apple_music' : entry.key;

        // Only add if the URL is not empty
        if (entry.value != null && entry.value!.isNotEmpty) {
          // If we already have apple_music and this is itunes with same URL, skip it
          if (platform == 'apple_music' &&
              normalizedUrls.containsKey('apple_music') &&
              normalizedUrls['apple_music'] == entry.value) {
            continue;
          }

          normalizedUrls[platform] = entry.value;
        }
      }

      // Insert/update platform matches with normalized platforms
      for (var entry in normalizedUrls.entries) {
        await db.insert(
          'platform_matches',
          {
            'album_id': albumId,
            'platform': entry.key,
            'url': entry.value,
            'verified': 1,
            'timestamp': DateTime.now().toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      Logging.severe(
          'Saved ${normalizedUrls.length} platform matches to database');

      // Clean up any duplicate entries in the database (fix existing data)
      await _cleanupDuplicatePlatforms(db, albumId);
    } catch (e, stack) {
      Logging.severe('Error saving platform matches to database', e, stack);
    }
  }

  // Add this new method to clean up existing duplicates
  Future<void> _cleanupDuplicatePlatforms(Database db, String albumId) async {
    try {
      // First check if both 'itunes' and 'apple_music' exist for this album
      final results = await db.query(
        'platform_matches',
        where: 'album_id = ? AND (platform = ? OR platform = ?)',
        whereArgs: [albumId, 'itunes', 'apple_music'],
      );

      // Exit early if we don't have any Apple platforms
      if (results.length <= 1) return;

      // Check for duplicate URLs
      String? itunesUrl;
      String? appleMusicUrl;

      for (var row in results) {
        final platform = row['platform'] as String;
        final url = row['url'] as String?;

        if (platform == 'itunes') itunesUrl = url;
        if (platform == 'apple_music') appleMusicUrl = url;
      }

      // If they have the same URL, delete the 'itunes' entry
      if (itunesUrl != null &&
          appleMusicUrl != null &&
          itunesUrl == appleMusicUrl) {
        await db.delete(
          'platform_matches',
          where: 'album_id = ? AND platform = ?',
          whereArgs: [albumId, 'itunes'],
        );
        Logging.severe(
            'Removed duplicate itunes platform match for album $albumId');
      }
    } catch (e) {
      Logging.severe('Error cleaning up duplicate platforms: $e');
    }
  }

  Future<void> _findMatchingAlbums() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      // Initialize with existing URL if album is from one of our platforms
      final currentPlatform = widget.album.platform.toLowerCase();

      // Check if this is a bandcamp album
      final isBandcamp = currentPlatform == 'bandcamp' ||
          widget.album.url.toLowerCase().contains('bandcamp.com');

      if (isBandcamp) {
        // For bandcamp albums, add the original URL as a bandcamp platform URL
        _platformUrls['bandcamp'] = widget.album.url;
      } else if (_supportedPlatforms.contains(currentPlatform)) {
        _platformUrls[currentPlatform] = widget.album.url;
      }

      // Always ensure the source platform URL is available regardless of platform
      if (widget.album.url.isNotEmpty) {
        // Figure out which platform the album's URL belongs to
        String sourcePlatform = _determinePlatformFromUrl(widget.album.url);
        if (sourcePlatform.isNotEmpty) {
          _platformUrls[sourcePlatform] = widget.album.url;
        }
      }

      // Create search query from album and artist
      // Clean artist name by removing Discogs numbering (e.g., "Artist (5)" -> "Artist")
      String artist = widget.album.artist.trim();
      String cleanedArtist = artist.replaceAll(RegExp(r'\s*\(\d+\)\s*$'), '');

      // Only log if we actually cleaned something
      if (artist != cleanedArtist) {
        Logging.severe(
            'Cleaned artist name from "$artist" to "$cleanedArtist" for search');
      }

      final albumName = widget.album.name.trim();

      // Search for the album on each platform we don't already have
      await Future.wait(_supportedPlatforms
          .where((platform) => !_platformUrls.containsKey(platform))
          .map((platform) async {
        if (_platformFactory.isPlatformSupported(platform)) {
          final service = _platformFactory.getService(platform);
          // Use cleaned artist name for search
          final url = await service.findAlbumUrl(cleanedArtist, albumName);
          if (url != null) {
            _platformUrls[platform] = url;
          }
        }
      }));

      // Fix for Discogs URLs: Ensure they're website URLs, not API URLs
      if (_platformUrls.containsKey('discogs') &&
          _platformUrls['discogs'] != null) {
        final discogsUrl = _platformUrls['discogs']!;

        // Check if it's an API URL and convert it
        if (discogsUrl.contains('api.discogs.com') ||
            discogsUrl.contains('/api/')) {
          // Extract ID from URL - assuming format like https://api.discogs.com/masters/2243191
          final regExp = RegExp(r'/(masters|releases)/(\d+)');
          final match = regExp.firstMatch(discogsUrl);

          if (match != null && match.groupCount >= 2) {
            final type = match.group(1); // masters or releases
            final id = match.group(2); // the numeric ID

            if (type != null && id != null) {
              // Convert to website URL
              final correctedUrl = 'https://www.discogs.com/$type/$id';
              _platformUrls['discogs'] = correctedUrl;
            }
          }
        }
      }

      // Verify matches for accuracy - remove potentially incorrect matches
      await _verifyMatches();

      // Save verified matches to database for future use
      await _savePlatformMatches();
    } catch (e, stack) {
      Logging.severe('Error finding matching albums', e, stack);
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// Verify that matches are accurate by checking if they meet minimum match criteria
  Future<void> _verifyMatches() async {
    final List<String> platformsToVerify = [..._supportedPlatforms, 'bandcamp'];
    final String artistName = widget.album.artist;
    // Clean artist name for verification as well
    final String cleanedArtistName =
        artistName.replaceAll(RegExp(r'\s*\(\d+\)\s*$'), '');
    final String albumName = widget.album.name;

    // Check if the current platform is iTunes, and if so, make sure apple_music is also marked as current
    final String currentPlatform = widget.album.platform.toLowerCase();
    final bool isITunesOrAppleMusic =
        currentPlatform == 'itunes' || currentPlatform == 'apple_music';

    // Handle album names with EP/Single designations
    String cleanedAlbumName = albumName;
    if (albumName.toLowerCase().contains("ep") ||
        albumName.toLowerCase().contains("single")) {
      cleanedAlbumName = SearchService.removeAlbumSuffixes(albumName);
    }

    // Track platforms to remove due to failed verification
    final List<String> platformsToRemove = [];

    for (final platform in platformsToVerify) {
      if (_platformUrls.containsKey(platform)) {
        final url = _platformUrls[platform];

        if (url == null || url.isEmpty) {
          platformsToRemove.add(platform);
          continue;
        }

        // Skip verification for source platform
        if ((isITunesOrAppleMusic && platform == 'apple_music') ||
            (platform == currentPlatform)) {
          continue;
        }

        // Special handling for Discogs to be more lenient
        if (platform == 'discogs') {
          // For Discogs, we'll trust the URL format directly and be more lenient
          if (url.contains('/master/') || url.contains('/release/')) {
            continue; // Skip further verification for Discogs
          }
        }

        // Special case for Spotify with EP/Single in the source album name
        if (platform == 'spotify' &&
            (albumName.toLowerCase().contains("ep") ||
                albumName.toLowerCase().contains("single"))) {
          try {
            if (_platformFactory.isPlatformSupported(platform)) {
              final service = _platformFactory.getService(platform);
              final albumDetails = await service.fetchAlbumDetails(url);

              if (albumDetails != null) {
                // For Spotify EP/Singles, do a special check
                String spotifyAlbumName = albumDetails['collectionName'] ?? '';
                String spotifyArtistName = albumDetails['artistName'] ?? '';

                // Check artist match directly - use cleanedArtistName for this comparison
                bool artistMatches =
                    normalizeForComparison(spotifyArtistName) ==
                        normalizeForComparison(cleanedArtistName);

                // Check if the album names match after cleaning
                bool albumsMatch = normalizeForComparison(spotifyAlbumName) ==
                    normalizeForComparison(cleanedAlbumName);

                if (artistMatches && albumsMatch) {
                  // Direct match after cleanup, keep this URL
                  continue;
                }

                // Standard scoring as fallback - also use cleanedArtistName
                double matchScore = SearchService.calculateMatchScore(
                    cleanedArtistName,
                    cleanedAlbumName,
                    spotifyArtistName,
                    spotifyAlbumName);

                // Lowered threshold just for Spotify EP/Single matches
                const double threshold = 0.45;
                if (matchScore >= threshold) {
                  // Good enough match for Spotify with EP/Single
                  continue;
                }
              }

              // If we get here, the Spotify match failed verification
              platformsToRemove.add(platform);
            }
          } catch (e) {
            Logging.severe('Error in special Spotify verification: $e');
          }

          // Skip regular verification for Spotify in this case
          continue;
        }

        // Normal verification for other platforms and non-EP/Single Spotify matches
        if (url.contains('/search?') || url.contains('/search/')) {
          // For search URLs, we need stricter verification
          bool isValidMatch = false;

          try {
            if (_platformFactory.isPlatformSupported(platform)) {
              final service = _platformFactory.getService(platform);
              // Get album details if possible to compare accurately
              final albumDetails = await service.fetchAlbumDetails(url);

              if (albumDetails != null) {
                // Use the improved match scoring algorithm from SearchService
                // Use cleanedArtistName for more accurate matching
                final matchScore = SearchService.calculateMatchScore(
                    cleanedArtistName,
                    cleanedAlbumName,
                    albumDetails['artistName'] ?? '',
                    albumDetails['collectionName'] ?? '');

                // All platforms share the same threshold for consistency
                const double threshold = 0.7;
                isValidMatch = matchScore >= threshold;
                // Only log scores below threshold
                if (!isValidMatch) {
                  Logging.severe(
                      'Low match score for $platform: $matchScore (below threshold: $threshold)');
                }
              } else {
                // Fall back to basic verification if detailed info isn't available
                // Also use cleanedArtistName here
                isValidMatch = await service.verifyAlbumExists(
                    cleanedArtistName, cleanedAlbumName);
              }
            }
          } catch (e) {
            Logging.severe('Error verifying with platform service: $e');
          }

          if (!isValidMatch) {
            platformsToRemove.add(platform);
          }
        } else {
          // For direct URLs, attempt to fetch details and verify match quality
          try {
            if (_platformFactory.isPlatformSupported(platform)) {
              final service = _platformFactory.getService(platform);
              final albumDetails = await service.fetchAlbumDetails(url);

              if (albumDetails != null) {
                // Use the improved match scoring algorithm - with cleanedArtistName
                final matchScore = SearchService.calculateMatchScore(
                    cleanedArtistName,
                    cleanedAlbumName,
                    albumDetails['artistName'] ?? '',
                    albumDetails['collectionName'] ?? '');

                // Only log low scores
                if (matchScore < 0.7) {
                  Logging.severe(
                      'Low direct URL match score for $platform: $matchScore');
                }

                // IMPORTANT FIX: Use platform-specific thresholds for better accuracy
                double threshold;
                if (platform == 'deezer') {
                  // Higher threshold specifically for Deezer due to the inconsistent matching
                  threshold = 0.7; // Increased from 0.5
                } else {
                  threshold = 0.5; // Default for other platforms
                }

                // Apply additional check for Deezer to require both artist and album to match well
                if (platform == 'deezer') {
                  final artistScore = calculateStringSimilarity(
                      normalizeForComparison(cleanedArtistName),
                      normalizeForComparison(albumDetails['artistName'] ?? ''));

                  final albumScore = calculateStringSimilarity(
                      normalizeForComparison(cleanedAlbumName),
                      normalizeForComparison(
                          albumDetails['collectionName'] ?? ''));

                  // For Deezer, must have good artist match AND acceptable album match
                  if (artistScore > 0.8 && albumScore < 0.5) {
                    Logging.severe(
                        'Removing Deezer match despite good artist score: artist=$artistScore, album=$albumScore');
                    platformsToRemove.add(platform);
                  }
                }

                if (matchScore < threshold) {
                  Logging.severe(
                      'Removing $platform match due to low match score: $matchScore (threshold: $threshold)');
                  platformsToRemove.add(platform);
                }
              }
            }
          } catch (e) {
            Logging.severe('Error verifying direct URL match: $e');
          }
        }
      }
    }

    // Remove invalid platforms
    for (final platform in platformsToRemove) {
      _platformUrls.remove(platform);
    }

    Logging.severe(
        'After verification, have ${_platformUrls.length} valid platform matches: ${_platformUrls.keys.join(', ')}');
  }

  // NEW METHOD: Verify saved matches and update poor ones
  Future<void> _verifyAndUpdateSavedMatches(
      Map<String, String?> savedMatches) async {
    try {
      // First, add all saved matches to our platform URLs
      _platformUrls.addAll(savedMatches);

      // Then verify each one individually
      String artist = widget.album.artist;
      // Clean artist name by removing Discogs numbering
      String cleanedArtist = artist.replaceAll(RegExp(r'\s*\(\d+\)\s*$'), '');

      // Only log if we actually cleaned something
      if (artist != cleanedArtist) {
        Logging.severe(
            'Cleaned artist name from "$artist" to "$cleanedArtist" for verification');
      }

      final albumName = widget.album.name;

      // Log which album we're checking
      Logging.severe(
          'Verifying saved matches for "$albumName" by "$cleanedArtist"');

      // Flag to track whether we need to update the database
      bool needsDatabaseUpdate = false;

      // Check for missing key platforms and search for them
      List<String> keyPlatforms = [
        'spotify',
        'apple_music',
        'deezer',
        'discogs'
      ];
      List<String> missingPlatforms = keyPlatforms
          .where((platform) =>
              !_platformUrls.containsKey(platform) ||
              _platformUrls[platform] == null ||
              _platformUrls[platform]!.isEmpty)
          .toList();

      if (missingPlatforms.isNotEmpty) {
        // Simplify to a single log with all missing platforms
        Logging.severe('Missing platforms: ${missingPlatforms.join(", ")}');

        // Search for each missing platform
        for (final platform in missingPlatforms) {
          if (_platformFactory.isPlatformSupported(platform)) {
            Logging.severe('Searching for missing platform: $platform');
            final service = _platformFactory.getService(platform);
            final url = await service.findAlbumUrl(cleanedArtist, albumName);

            if (url != null) {
              _platformUrls[platform] = url;
              needsDatabaseUpdate = true;
              Logging.severe(
                  'Found match for missing platform $platform: $url');
            }
          }
        }
      }

      // List of platforms to verify
      final platformsToVerify = savedMatches.keys.toList();

      // Skip the album's own platform - always trust that URL
      final currentPlatform = widget.album.platform.toLowerCase();
      final normalizedCurrentPlatform =
          currentPlatform == 'itunes' ? 'apple_music' : currentPlatform;

      // For each saved match
      for (final platform in platformsToVerify) {
        // Skip the album's own platform - we trust that URL
        if (platform == normalizedCurrentPlatform) continue;

        final url = savedMatches[platform];
        if (url == null || url.isEmpty) continue;

        // Verify match quality by fetching album details
        if (_platformFactory.isPlatformSupported(platform)) {
          final service = _platformFactory.getService(platform);

          try {
            // Fetch album details to check match quality
            final albumDetails = await service.fetchAlbumDetails(url);

            if (albumDetails != null) {
              final resultArtist = albumDetails['artistName'] ?? '';
              final resultAlbum = albumDetails['collectionName'] ?? '';

              // Clean result artist name for fair comparison
              final cleanedResultArtist =
                  resultArtist.replaceAll(RegExp(r'\s*\(\d+\)\s*$'), '');

              // Check for both artist and album match - using cleaned artist names
              final artistScore = calculateStringSimilarity(
                  normalizeForComparison(cleanedArtist),
                  normalizeForComparison(cleanedResultArtist));

              final albumScore = calculateStringSimilarity(
                  normalizeForComparison(albumName),
                  normalizeForComparison(resultAlbum));

              final combinedScore = (artistScore * 0.6) + (albumScore * 0.4);

              // Log the match quality
              Logging.severe(
                  'Match quality for $platform: artist=$artistScore, album=$albumScore, combined=$combinedScore');

              // If match quality is poor (adjust threshold as needed)
              if ((platform == 'spotify' && combinedScore < 0.5) ||
                  (platform != 'spotify' && combinedScore < 0.4)) {
                Logging.severe(
                    'Poor match detected for $platform. Searching for better match.');

                // Remove the bad match from our URLs
                _platformUrls.remove(platform);

                // Try to find a better match - use cleaned artist name
                final newUrl =
                    await service.findAlbumUrl(cleanedArtist, albumName);

                if (newUrl != null && newUrl != url) {
                  // Verify the new match is better
                  final newDetails = await service.fetchAlbumDetails(newUrl);

                  if (newDetails != null) {
                    final newArtistScore = calculateStringSimilarity(
                        normalizeForComparison(cleanedArtist),
                        normalizeForComparison(newDetails['artistName'] ?? ''));

                    final newAlbumScore = calculateStringSimilarity(
                        normalizeForComparison(albumName),
                        normalizeForComparison(
                            newDetails['collectionName'] ?? ''));

                    final newCombinedScore =
                        (newArtistScore * 0.6) + (newAlbumScore * 0.4);

                    Logging.severe(
                        'New match quality for $platform: artist=$newArtistScore, album=$newAlbumScore, combined=$newCombinedScore');

                    // If new match is better, use it
                    if (newCombinedScore > combinedScore) {
                      _platformUrls[platform] = newUrl;
                      needsDatabaseUpdate = true;
                      Logging.severe(
                          'Replaced $platform match with better URL: $newUrl');
                    } else {
                      Logging.severe(
                          'Keeping original $platform match as new match was not better');
                      // Restore the original match if we couldn't verify the new one
                      _platformUrls[platform] = url;
                    }
                  } else {
                    // Restore the original match if we couldn't verify the new one
                    _platformUrls[platform] = url;
                  }
                } else if (newUrl != null) {
                  // Same URL but mark it as verified again
                  _platformUrls[platform] = url;
                  Logging.severe('Re-verified $platform match with same URL');
                } else {
                  // No match found, remove it
                  Logging.severe(
                      'Removed poor $platform match with no replacement found');
                  needsDatabaseUpdate = true;
                }
              } else {
                Logging.severe('Verified $platform match with good quality');
              }
            }
          } catch (e) {
            Logging.severe('Error verifying $platform match: $e');
            // Keep the original match if verification fails
            _platformUrls[platform] = url;
          }
        }
      }

      // Update the database if we found better matches
      if (needsDatabaseUpdate) {
        await _savePlatformMatches();
        Logging.severe('Updated database with improved platform matches');
      }
    } catch (e, stack) {
      Logging.severe('Error during match verification', e, stack);
    }
  }

  // Helper to normalize for comparison
  String normalizeForComparison(String input) {
    return input
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), '') // Remove special chars
        .replaceAll(RegExp(r'\s+'), ' ') // Normalize whitespace
        .trim();
  }

  // Calculate string similarity
  double calculateStringSimilarity(String s1, String s2) {
    // Simple exact match
    if (s1 == s2) return 1.0;

    // Return the service from platform_service_base
    final service = _platformFactory.getService('spotify'); // Use any service
    return service.calculateStringSimilarity(s1, s2);
  }

  /// Determine which platform a URL belongs to
  String _determinePlatformFromUrl(String url) {
    final lowerUrl = url.toLowerCase();
    String platform = '';

    if (lowerUrl.contains('spotify.com') || lowerUrl.contains('open.spotify')) {
      platform = 'spotify';
    } else if (lowerUrl.contains('music.apple.com') ||
        lowerUrl.contains('itunes.apple.com')) {
      platform = 'apple_music'; // Always return 'apple_music' for consistency
    } else if (lowerUrl.contains('deezer.com')) {
      platform = 'deezer';
    } else if (lowerUrl.contains('bandcamp.com')) {
      platform = 'bandcamp';
    } else if (lowerUrl.contains('discogs.com')) {
      platform = 'discogs';
    }

    if (platform.isNotEmpty) {
      Logging.severe('Detected platform from URL: $platform for URL: $url');
    }

    return platform;
  }

  @override
  Widget build(BuildContext context) {
    // Don't show anything if we have no matches
    if (_isLoading) {
      return _buildSkeletonButtons();
    }

    // Get list of platforms that have valid URLs
    final availablePlatforms = _platformUrls.entries
        .where((entry) => entry.value != null && entry.value!.isNotEmpty)
        .map((entry) => entry.key)
        .toList();

    // Don't show anything if no platform links are available
    if (availablePlatforms.isEmpty) {
      return const SizedBox.shrink();
    }

    // Remove iTunes if we also have Apple Music (they're the same service)
    if (availablePlatforms.contains('apple_music') &&
        availablePlatforms.contains('itunes')) {
      availablePlatforms.remove('itunes');
    }

    // Fix the order of platforms
    // Define order of platforms
    final platformOrder = [
      'apple_music',
      'spotify',
      'deezer',
      'discogs',
      'bandcamp'
    ];
    final sortedPlatforms = <String>[];
    for (final platform in platformOrder) {
      if (availablePlatforms.contains(platform)) {
        sortedPlatforms.add(platform);
      }
    }

    // Then add any remaining platforms
    for (final platform in availablePlatforms) {
      if (!sortedPlatforms.contains(platform)) {
        sortedPlatforms.add(platform);
      }
    }

    // Debug the order and URLs only once with a simplified message
    Logging.severe('Available platforms: ${sortedPlatforms.join(', ')}');
    for (final platform in sortedPlatforms) {
      Logging.severe('$platform URL: ${_platformUrls[platform]}');
    }

    // MODIFIED: Always show platform match widget, even if only the source platform is available
    // This ensures the refresh button is always available
    // Removed the condition that was hiding the widget when only the source platform was available

    return Padding(
      // Reduce padding to make the entire widget more compact vertically
      padding: const EdgeInsets.symmetric(vertical: 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: sortedPlatforms.map((platform) {
              final button = _buildPlatformButton(platform);
              // Reduce spacers between buttons even further
              return sortedPlatforms.indexOf(platform) <
                      sortedPlatforms.length - 1
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        button,
                        const SizedBox(width: 6),
                      ],
                    )
                  : button;
            }).toList(),
          ),

          // MODIFIED: Always show the refresh button for consistency
          // This helps users refresh platform matches regardless of the source
          Padding(
            padding: const EdgeInsets.only(top: 4.0),
            child: InkWell(
              onTap: _isLoading ? null : _refreshPlatformMatches,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0),
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.grey.shade800.withAlpha(128)
                      : Colors.grey.shade200.withAlpha(179),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // MODIFIED: Use primary color for the refresh icon to match app styling
                    Icon(
                      Icons.refresh,
                      size: 12,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Refresh matches',
                      style: TextStyle(
                        fontSize: 10,
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.grey.shade300
                            : Colors.grey.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Build skeleton loading buttons while waiting for platform matches
  Widget _buildSkeletonButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildSkeletonButton(),
        const SizedBox(width: 16),
        _buildSkeletonButton(),
        const SizedBox(width: 16),
        _buildSkeletonButton(),
      ],
    );
  }

  /// Build an individual skeleton button
  Widget _buildSkeletonButton() {
    return SkeletonLoading(
      width: widget.buttonSize,
      height: widget.buttonSize,
      borderRadius: widget.buttonSize / 2,
    );
  }

  Widget _buildPlatformButton(String platform) {
    final bool hasMatch =
        _platformUrls.containsKey(platform) && _platformUrls[platform] != null;

    // Check if this is the current platform of the album
    // Fix iTunes/Apple Music platform comparison
    bool isSelected = false;

    final String currentPlatform = widget.album.platform.toLowerCase();
    final String normalizedCurrentPlatform =
        currentPlatform == 'itunes' ? 'apple_music' : currentPlatform;

    if (platform == normalizedCurrentPlatform) {
      isSelected = true;
    }

    // Only log once - remove duplicate logging
    Logging.severe(
      'Platform $platform URL: ${_platformUrls[platform]}, isSelected: $isSelected',
    );

    // Use SVG icons for better quality
    String iconPath;
    switch (platform) {
      case 'spotify':
        iconPath = 'lib/icons/spotify.svg';
        break;
      case 'apple_music':
        iconPath = 'lib/icons/apple_music.svg';
        break;
      case 'deezer':
        iconPath = 'lib/icons/deezer.svg';
        break;
      case 'bandcamp':
        iconPath = 'lib/icons/bandcamp.svg';
        break;
      case 'discogs':
        iconPath = 'lib/icons/discogs.svg';
        break;
      default:
        iconPath = '';
    }

    // Determine icon color based on theme and selection state
    final isDarkTheme = Theme.of(context).brightness == Brightness.dark;
    // Use primary color if selected, otherwise use default icon color
    final iconColor = isSelected
        ? Theme.of(context).colorScheme.primary
        : (isDarkTheme ? Colors.white : Colors.black);

    // Create button content
    final buttonContent = SizedBox(
      width: widget.buttonSize,
      height: widget.buttonSize,
      child: iconPath.isNotEmpty
          ? Padding(
              padding: const EdgeInsets.all(4.0), // Reduced from 8.0 to 4.0
              child: SvgPicture.asset(
                iconPath,
                height: widget.buttonSize - 8, // Increased from 16 to 8
                width: widget.buttonSize - 8, // Increased from 16 to 8
                colorFilter: ColorFilter.mode(iconColor, BlendMode.srcIn),
              ),
            )
          : Icon(
              Icons.music_note,
              size: widget.buttonSize - 8, // Increased from 16 to 8
              color: iconColor,
            ),
    );

    // Add context menu for desktop platforms (right click)
    // and support long press for mobile platforms
    return Opacity(
      opacity: hasMatch ? 1.0 : 0.5,
      child: Tooltip(
        message: hasMatch
            ? (isSelected
                ? _getPlatformName(
                    platform) // Simply show the platform name without "Current platform:"
                : _getPlatformName(platform))
            : 'No match found in ${_getPlatformName(platform)}',
        child: GestureDetector(
          onLongPress: hasMatch
              ? () => _showContextMenu(platform, _platformUrls[platform]!)
              : null,
          child: InkWell(
            onTap: hasMatch ? () => _openUrl(_platformUrls[platform]!) : null,
            borderRadius: BorderRadius.circular(widget.buttonSize / 2),
            onSecondaryTap: hasMatch
                ? () => _showContextMenu(platform, _platformUrls[platform]!)
                : null,
            child: buttonContent,
          ),
        ),
      ),
    );
  }

  // Show context menu for mobile platforms via long press
  void _showContextMenu(String platform, String url) {
    final RenderBox button = context.findRenderObject() as RenderBox;
    final Offset position = button.localToGlobal(Offset.zero);
    final Size buttonSize = button.size;

    // Position menu below the button and centered horizontally
    const double menuWidth = 200; // Estimated menu width
    final double centerX = position.dx + (buttonSize.width / 2);
    final double leftPosition = centerX - (menuWidth / 2);
    final RelativeRect rect = RelativeRect.fromLTRB(
      leftPosition, // LEFT: centered horizontally
      position.dy + buttonSize.height + 5, // TOP: just below the button
      MediaQuery.of(context).size.width - leftPosition - menuWidth, // RIGHT
      0, // BOTTOM: not constrained
    );

    showMenu<String>(
      context: context,
      position: rect,
      items: [
        PopupMenuItem<String>(
          value: 'copy',
          height: 26, // Set a smaller height for more compact appearance
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: Row(
            children: [
              const Icon(Icons.copy, size: 26),
              const SizedBox(width: 6),
              Text('Copy ${_getPlatformName(platform)} URL'),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'open',
          height: 26, // Set a smaller height for more compact appearance
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: Row(
            children: [
              const Icon(Icons.open_in_new, size: 26),
              const SizedBox(width: 6),
              Text(_getPlatformName(platform)),
            ],
          ),
        ),
        // Add Share option
        PopupMenuItem<String>(
          value: 'share',
          height: 26, // Set a smaller height for more compact appearance
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: Row(
            children: [
              const Icon(Icons.share, size: 26),
              const SizedBox(width: 6),
              Text('Share ${_getPlatformName(platform)} Link'),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == 'copy') {
        _copyUrlToClipboard(platform, url);
      } else if (value == 'open') {
        _openUrl(url);
      } else if (value == 'share') {
        _shareUrl(platform, url);
      }
    });
  }

  // Copy URL to clipboard and show feedback
  void _copyUrlToClipboard(String platform, String url) async {
    try {
      await Clipboard.setData(ClipboardData(text: url));
      // Show feedback using a snackbar
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('${_getPlatformName(platform)} URL copied to clipboard'),
            duration: const Duration(seconds: 2),
          ),
        );
      }

      Logging.severe('Copied URL to clipboard: $url');
    } catch (e, stack) {
      Logging.severe('Error copying URL to clipboard', e, stack);
    }
  }

  // Add new method to handle sharing
  void _shareUrl(String platform, String url) async {
    try {
      // For desktop platforms, copy to clipboard and show a message
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        await Clipboard.setData(ClipboardData(text: url));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  '${_getPlatformName(platform)} URL copied to clipboard for sharing'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } else {
        // For mobile platforms, use the share plugin
        Share.share(
          'Check out this album on ${_getPlatformName(platform)}: $url',
          subject: 'Album link from RateMe',
        );
      }
      Logging.severe('Shared URL: $url');
    } catch (e, stack) {
      Logging.severe('Error sharing URL', e, stack);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error sharing: $e'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  String _getPlatformName(String platform) {
    switch (platform) {
      case 'spotify':
        return 'Spotify';
      case 'apple_music':
        return 'Apple Music';
      case 'deezer':
        return 'Deezer';
      case 'bandcamp':
        return 'Bandcamp';
      case 'discogs':
        return 'Discogs';
      default:
        return platform.split('_').map((s) => s.capitalize()).join(' ');
    }
  }

  Future<void> _openUrl(String url) async {
    try {
      // Log the URL we're trying to open
      Logging.severe('Opening URL: $url');
      final uri = Uri.parse(url);
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e, stack) {
      Logging.severe('Error opening URL: $url', e, stack);
    }
  }

  // Add this method to refresh platform matches for this album
  Future<void> _refreshPlatformMatches() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      // Delete existing platform matches from database
      final albumId = widget.album.id.toString();
      final db = await DatabaseHelper.instance.database;

      await db.delete(
        'platform_matches',
        where: 'album_id = ?',
        whereArgs: [albumId],
      );

      Logging.severe('Deleted existing platform matches for album $albumId');

      // Clear current platform URLs
      _platformUrls.clear();

      // Find matches from scratch
      await _findMatchingAlbums();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Platform matches refreshed'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e, stack) {
      Logging.severe('Error refreshing platform matches', e, stack);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error refreshing platform matches: $e'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
}

// Define the extension outside the class
extension StringExtension on String {
  String capitalize() {
    return isEmpty ? this : '${this[0].toUpperCase()}${substring(1)}';
  }
}
