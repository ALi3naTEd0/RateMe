import 'dart:convert';
import 'package:http/http.dart' as http;
import '../logging.dart';
import 'platform_service_base.dart';

class AppleMusicService extends PlatformServiceBase {
  @override
  String get platformId => 'apple_music';

  @override
  String get displayName => 'Apple Music';

  @override
  Future<String?> findAlbumUrl(String artist, String albumName) async {
    try {
      // Clean artist name by removing Discogs numbering format "(n)"
      String cleanedArtist = artist.replaceAll(RegExp(r'\s*\(\d+\)\s*$'), '');

      // Only log if we actually cleaned something
      if (cleanedArtist != artist) {
        Logging.severe(
            'Apple Music: Cleaned artist name from "$artist" to "$cleanedArtist"');
      }

      // Initial log
      Logging.severe(
          'Apple Music: Searching for "$albumName" by "$cleanedArtist"');

      // Normalize names for better matching
      final normalizedArtist = normalizeForComparison(cleanedArtist);
      final normalizedAlbum = normalizeForComparison(albumName);

      // APPROACH 0: Try artist+album as exact terms - most precise search
      final strictQuery =
          Uri.encodeComponent('artist:"$cleanedArtist" album:"$albumName"');
      final strictSearchUrl = Uri.parse(
          'https://itunes.apple.com/search?term=$strictQuery&entity=album&limit=10');

      // Reduce URL logging to just mention we're doing the search
      Logging.severe('Apple Music: Trying strict search');
      final strictResponse = await http.get(strictSearchUrl);

      if (strictResponse.statusCode == 200) {
        final data = jsonDecode(strictResponse.body);
        final results = data['results'] as List;

        if (results.isNotEmpty) {
          Logging.severe(
              'Apple Music: Found ${results.length} results from strict search');

          // Find best match considering both artist and album similarity
          final bestMatch = _findBestMatch(
              results, normalizedArtist, normalizedAlbum, 0.7, 0.7);
          if (bestMatch != null) {
            Logging.severe(
                'Apple Music: STRICT MATCH FOUND: "${bestMatch['collectionName']}" by "${bestMatch['artistName']}"');
            return bestMatch['collectionViewUrl'];
          }
        }
      }

      // Add additional direct search before artist search for exact name matches
      // This helps with cases like Kink - Tsunami where we need an exact artist/album pair
      final exactQuery = Uri.encodeComponent('"$cleanedArtist" "$albumName"');
      final exactSearchUrl = Uri.parse(
          'https://itunes.apple.com/search?term=$exactQuery&entity=album&limit=10');

      // Simplify logging - don't include full URL
      Logging.severe('Apple Music: Trying exact match search');
      final exactResponse = await http.get(exactSearchUrl);

      if (exactResponse.statusCode == 200) {
        final data = jsonDecode(exactResponse.body);
        final results = data['results'] as List;

        if (results.isNotEmpty) {
          Logging.severe(
              'Apple Music: Found ${results.length} results from exact search');

          // Score each result
          for (final album in results) {
            final resultArtist =
                normalizeForComparison(album['artistName'] ?? '');
            final resultAlbum =
                normalizeForComparison(album['collectionName'] ?? '');

            final artistScore =
                calculateStringSimilarity(normalizedArtist, resultArtist);
            final albumScore =
                calculateStringSimilarity(normalizedAlbum, resultAlbum);

            // Log for exact matches or close matches
            if (artistScore > 0.8 && albumScore > 0.8) {
              Logging.severe(
                  'Apple Music: STRONG MATCH FOUND: "${album['collectionName']}" by "${album['artistName']}" (artist: $artistScore, album: $albumScore)');
              return album['collectionViewUrl'];
            }
          }
        }
      }

      // APPROACH 1: Search by artist name only - this appears to be more reliable
      final artistQuery = Uri.encodeComponent(cleanedArtist);
      final artistSearchUrl = Uri.parse(
          'https://itunes.apple.com/search?term=$artistQuery&entity=musicArtist&attribute=artistTerm&limit=1');

      // Simplify logging
      Logging.severe('Apple Music: Searching by artist name only');
      final artistResponse = await http.get(artistSearchUrl);

      if (artistResponse.statusCode == 200) {
        final data = jsonDecode(artistResponse.body);
        final artists = data['results'] as List;

        if (artists.isNotEmpty) {
          final artistId = artists[0]['artistId'];
          Logging.severe('Apple Music: Found artist ID: $artistId');

          // APPROACH 2: Use the artistId to get all the artist's albums
          final albumsUrl = Uri.parse(
              'https://itunes.apple.com/lookup?id=$artistId&entity=album&limit=100');

          // Simplify logging
          Logging.severe('Apple Music: Looking up albums by artist ID');
          final albumsResponse = await http.get(albumsUrl);

          if (albumsResponse.statusCode == 200) {
            final albumsData = jsonDecode(albumsResponse.body);
            final results = albumsData['results'] as List;

            // Skip the first result (which is the artist)
            final albums =
                results.where((r) => r['wrapperType'] == 'collection').toList();
            Logging.severe(
                'Apple Music: Found ${albums.length} albums by this artist');

            if (albums.isNotEmpty) {
              // Score albums by name similarity
              final scoredAlbums = <Map<String, dynamic>>[];

              // Keep track of which albums we've already logged
              final Set<String> loggedAlbumNames = {};

              for (var album in albums) {
                final resultAlbum =
                    normalizeForComparison(album['collectionName']);

                // Skip duplicate album names in logs
                if (loggedAlbumNames.contains(resultAlbum)) continue;
                loggedAlbumNames.add(resultAlbum);

                final albumScore =
                    calculateStringSimilarity(normalizedAlbum, resultAlbum);

                // Only log exact matches and good potential matches
                if (albumScore > 0.99) {
                  Logging.severe(
                      'Apple Music: EXACT MATCH: "${album['collectionName']}" (score: 1.0)');
                } else if (albumScore > 0.5) {
                  Logging.severe(
                      'Apple Music: Album match candidate: "${album['collectionName']}" (score: ${albumScore.toStringAsFixed(2)})');
                }

                scoredAlbums.add({
                  'album': album,
                  'score': albumScore,
                });
              }

              // Sort by score
              scoredAlbums.sort((a, b) => b['score'].compareTo(a['score']));

              // Accept the top match if it's at least somewhat similar
              if (scoredAlbums.isNotEmpty && scoredAlbums[0]['score'] > 0.5) {
                final bestMatch = scoredAlbums[0]['album'];
                Logging.severe(
                    'Apple Music: Best match by artist ID lookup: "${bestMatch['collectionName']}" (score: ${scoredAlbums[0]['score'].toStringAsFixed(2)})');
                return bestMatch['collectionViewUrl'];
              }
            }
          }
        }
      }

      // FALLBACK: Direct combined search if artist lookup fails
      final combinedQuery = Uri.encodeComponent('$cleanedArtist $albumName');
      final searchUrl = Uri.parse(
          'https://itunes.apple.com/search?term=$combinedQuery&entity=album&limit=25');

      // Simplify logging
      Logging.severe('Apple Music: Using fallback combined search');
      final response = await http.get(searchUrl);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final results = data['results'] as List;

        if (results.isNotEmpty) {
          Logging.severe(
              'Apple Music: Found ${results.length} results from fallback search');

          // Find best match considering both artist and album similarity
          final bestMatch = _findBestMatch(
              results, normalizedArtist, normalizedAlbum, 0.7, 0.7);
          if (bestMatch != null) {
            Logging.severe(
                'Apple Music: FALLBACK MATCH FOUND: "${bestMatch['collectionName']}" by "${bestMatch['artistName']}"');
            return bestMatch['collectionViewUrl'];
          }
        }
      }

      // LAST RESORT: Try exact album name as a query
      final albumOnlyQuery = Uri.encodeComponent(albumName);
      final albumOnlyUrl = Uri.parse(
          'https://itunes.apple.com/search?term=$albumOnlyQuery&entity=album&limit=50');

      // Simplify logging
      Logging.severe('Apple Music: Using album-only search');
      final albumOnlyResponse = await http.get(albumOnlyUrl);

      if (albumOnlyResponse.statusCode == 200) {
        final albumData = jsonDecode(albumOnlyResponse.body);
        final albumResults = albumData['results'] as List;

        if (albumResults.isNotEmpty) {
          Logging.severe(
              'Apple Music: Found ${albumResults.length} albums from album-only search');

          // Score by both album and artist similarity
          final scoredResults = albumResults.map((album) {
            final resultArtist = normalizeForComparison(album['artistName']);
            final resultAlbum = normalizeForComparison(album['collectionName']);

            final artistScore =
                calculateStringSimilarity(normalizedArtist, resultArtist);
            final albumScore =
                calculateStringSimilarity(normalizedAlbum, resultAlbum);

            // Only log album-only candidates with good scores
            final combinedScore = (artistScore * 0.6) + (albumScore * 0.4);
            if (combinedScore > 0.5) {
              Logging.severe(
                  'Apple Music: Album-only candidate: "${album['collectionName']}" by "${album['artistName']}" (combinedScore: ${combinedScore.toStringAsFixed(2)})');
            }

            return {
              'album': album,
              'combinedScore': combinedScore,
              'artistScore': artistScore,
              'albumScore': albumScore,
            };
          }).toList();

          scoredResults
              .sort((a, b) => b['combinedScore'].compareTo(a['combinedScore']));

          // Changed: First prioritize albums with good artist match (to avoid Khoma instead of Kink)
          final artistMatches =
              scoredResults.where((r) => r['artistScore'] > 0.7).toList();
          if (artistMatches.isNotEmpty) {
            // Find the best album match among good artist matches
            artistMatches
                .sort((a, b) => b['albumScore'].compareTo(a['albumScore']));

            final bestArtistMatch = artistMatches.first;
            final bestMatchAlbum = bestArtistMatch['album'];

            Logging.severe(
                'Apple Music: Artist-prioritized match: "${bestMatchAlbum['collectionName']}" by "${bestMatchAlbum['artistName']}" (artist: ${bestArtistMatch['artistScore']}, album: ${bestArtistMatch['albumScore']})');

            return bestMatchAlbum['collectionViewUrl'];
          }

          // Otherwise use the combined score approach as fallback
          if (scoredResults.isNotEmpty &&
              (scoredResults[0]['combinedScore'] > 0.6 ||
                  scoredResults[0]['artistScore'] > 0.8 ||
                  scoredResults[0]['albumScore'] > 0.9)) {
            final bestMatch = scoredResults[0]['album'];
            Logging.severe(
                'Apple Music: Best match from album-only search: "${bestMatch['collectionName']}" by "${bestMatch['artistName']}" (score: ${scoredResults[0]['combinedScore']})');
            return bestMatch['collectionViewUrl'];
          }
        }
      }

      Logging.severe(
          'Apple Music: No matches found that meet confidence threshold');
      return null;
    } catch (e, stack) {
      Logging.severe('Error searching Apple Music', e, stack);
      return null;
    }
  }

  // Helper method to find the best match from results
  Map<String, dynamic>? _findBestMatch(List results, String normalizedArtist,
      String normalizedAlbum, double minArtistScore, double minAlbumScore) {
    // Track best matches
    Map<String, dynamic>? bestMatch;
    double bestCombinedScore = 0.0;

    for (final album in results) {
      final resultArtist = normalizeForComparison(album['artistName'] ?? '');
      final resultAlbum = normalizeForComparison(album['collectionName'] ?? '');

      final artistScore =
          calculateStringSimilarity(normalizedArtist, resultArtist);
      final albumScore =
          calculateStringSimilarity(normalizedAlbum, resultAlbum);
      final combinedScore = (artistScore * 0.6) + (albumScore * 0.4);

      // Log all potential matches with decent scores
      if (artistScore > 0.5 || albumScore > 0.5) {
        Logging.severe(
            'Match candidate: "${album['collectionName']}" by "${album['artistName']}" '
            '(artist: $artistScore, album: $albumScore, combined: $combinedScore)');
      }

      // Return immediately if we found an excellent match
      if (artistScore > 0.9 && albumScore > 0.9) {
        Logging.severe('Found excellent match!');
        return album;
      }

      // Track the best match that meets minimum thresholds
      if (artistScore >= minArtistScore &&
          albumScore >= minAlbumScore &&
          combinedScore > bestCombinedScore) {
        bestMatch = album;
        bestCombinedScore = combinedScore;
      }
    }

    return bestMatch;
  }

  @override
  Future<bool> verifyAlbumExists(String artist, String albumName) async {
    try {
      // Clean artist name by removing Discogs numbering format "(n)"
      String cleanedArtist = artist.replaceAll(RegExp(r'\s*\(\d+\)\s*$'), '');

      // Simplified verification - we just need to know if the album exists
      final query = Uri.encodeComponent('$cleanedArtist $albumName');
      final url = Uri.parse(
          'https://itunes.apple.com/search?term=$query&entity=album&limit=5');

      Logging.severe('Apple Music: Verification query: $url');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final albums = data['results'] as List;

        if (albums.isNotEmpty) {
          // For verification, we just need a reasonable match
          final normalizedArtist = normalizeForComparison(artist);
          final normalizedAlbum = normalizeForComparison(albumName);

          for (var album in albums) {
            final resultArtist = normalizeForComparison(album['artistName']);
            final resultAlbum = normalizeForComparison(album['collectionName']);

            final artistScore =
                calculateStringSimilarity(normalizedArtist, resultArtist);
            final albumScore =
                calculateStringSimilarity(normalizedAlbum, resultAlbum);

            // Accept any decent match for verification
            if (artistScore > 0.7 || albumScore > 0.7) {
              Logging.severe(
                  'Apple Music: Verified match found (artistScore: $artistScore, albumScore: $albumScore)');
              return true;
            }
          }
        }
      }

      Logging.severe('Apple Music: Verification failed - no matches found');
      return false;
    } catch (e, stack) {
      Logging.severe('Error verifying Apple Music album', e, stack);
      return false;
    }
  }

  @override
  Future<Map<String, dynamic>?> fetchAlbumDetails(String url) async {
    try {
      Logging.severe('Fetching Apple Music album details from URL: $url');

      // Extract the album ID from the URL - handle various URL formats
      String? albumId;

      // First try the standard format pattern
      final regExp = RegExp(r'/album/[^/]*/(\d+)|/album/(\d+)');
      final match = regExp.firstMatch(url);

      if (match != null) {
        // Get the ID from either capture group (depending on URL format)
        albumId = match.group(1) ?? match.group(2);
      }

      // If we still don't have an ID, try the iTunes URL format
      if (albumId == null) {
        final iTunesRegExp = RegExp(r'id=(\d+)');
        final iTunesMatch = iTunesRegExp.firstMatch(url);
        if (iTunesMatch != null) {
          albumId = iTunesMatch.group(1);
        }
      }

      // If we still don't have an ID, try extracting just numbers
      if (albumId == null) {
        final digits = RegExp(r'\/(\d+)(?:\?|$)').firstMatch(url);
        if (digits != null) {
          albumId = digits.group(1);
        }
      }

      if (albumId == null) {
        Logging.severe('Could not extract album ID from URL: $url');
        return null;
      }

      Logging.severe('Extracted album ID: $albumId from URL: $url');

      // Use the iTunes API to fetch album details with songs
      final apiUrl =
          'https://itunes.apple.com/lookup?id=$albumId&entity=song&limit=200';
      Logging.severe('Fetching from iTunes API: $apiUrl');

      final response = await http.get(Uri.parse(apiUrl));
      if (response.statusCode != 200) {
        Logging.severe('iTunes API error: ${response.statusCode}');
        return null;
      }

      final data = jsonDecode(response.body);
      Logging.severe('API returned resultCount: ${data['resultCount']}');

      if (data['resultCount'] == 0) {
        Logging.severe('No results found for album ID: $albumId');
        return null;
      }

      // The first result should be the album
      Map<String, dynamic>? albumData;
      List<Map<String, dynamic>> allTracks = [];

      // Find the album data (should be wrapperType: collection)
      for (var item in data['results']) {
        if (item['wrapperType'] == 'collection' &&
            item['collectionType'] == 'Album') {
          albumData = item;
          break;
        }
      }

      // If no album data found, use the first result anyway
      albumData ??= data['results'][0];

      // Fix: Check if albumData actually contains the required fields
      if (albumData == null ||
          !albumData.containsKey('collectionName') ||
          !albumData.containsKey('artistName')) {
        Logging.severe('Missing critical album data fields');
        return null;
      }

      Logging.severe(
          'Found album: ${albumData['collectionName']} by ${albumData['artistName']}');

      // Process all tracks (filter out non-tracks)
      for (var item in data['results']) {
        // Make sure it's actually a track (exclude other types like music videos)
        if (item['wrapperType'] == 'track' &&
            (item['kind'] == 'song' || item['kind'] == null)) {
          // Fix: Safely access nullable fields with null-aware operators
          final trackId = item['trackId'];
          final trackName = item['trackName'];
          final trackNumber = item['trackNumber'];
          final trackTimeMillis = item['trackTimeMillis'];
          final discNumber = item['discNumber'] ?? 1;

          // Only add the track if it has the essential fields
          if (trackId != null && trackName != null) {
            allTracks.add({
              'trackId': trackId,
              'trackName': trackName,
              'trackNumber': trackNumber ?? 0,
              'trackTimeMillis': trackTimeMillis ?? 0,
              'discNumber': discNumber,
            });
          }
        }
      }

      Logging.severe('Extracted ${allTracks.length} tracks from album');

      // Sort tracks by disc number and track number
      allTracks.sort((a, b) {
        final discA = a['discNumber'] ?? 1;
        final discB = b['discNumber'] ?? 1;
        if (discA != discB) return discA - discB;

        final trackA = a['trackNumber'] ?? 999;
        final trackB = b['trackNumber'] ?? 999;
        return trackA - trackB;
      });

      // Log first track for debugging
      if (allTracks.isNotEmpty) {
        Logging.severe('First track: ${jsonEncode(allTracks.first)}');
      }

      // Fix: Use null-aware operators when accessing potentially null values
      final collectionId = albumData['collectionId'];
      final collectionName = albumData['collectionName'] ?? 'Unknown Album';
      final artistName = albumData['artistName'] ?? 'Unknown Artist';
      final artworkUrl100 = albumData['artworkUrl100'];
      final releaseDate = albumData['releaseDate'];

      // Check if required primary ID is available
      if (collectionId == null) {
        Logging.severe('Missing collection ID in album data');
        return null;
      }

      // Create a standardized album object
      return {
        'id': collectionId,
        'collectionId': collectionId,
        'name': collectionName,
        'collectionName': collectionName,
        'artist': artistName,
        'artistName': artistName,
        'artworkUrl': artworkUrl100 != null
            ? artworkUrl100.toString().replaceAll('100x100', '600x600')
            : '',
        'artworkUrl100': artworkUrl100 ?? '',
        'releaseDate': releaseDate ?? DateTime.now().toIso8601String(),
        'url': url,
        'platform': 'apple_music',
        'tracks': allTracks,
      };
    } catch (e, stack) {
      Logging.severe('Error fetching Apple Music album details', e, stack);
      return null;
    }
  }

  @override
  String normalizeForComparison(String? input) {
    if (input == null || input.isEmpty) return '';

    // Convert to lowercase and trim
    String normalized = input.toLowerCase().trim();

    // Store the original input before removing qualifiers
    final originalNormalized = normalized;

    // Create a comparison version with removed qualifiers
    String comparisonVersion = normalized
        .replaceAll(' - ep', '')
        .replaceAll('-ep', '') // Handle no space case
        .replaceAll(' ep', '')
        .replaceAll(' - single', '')
        .replaceAll('-single', '') // Handle no space case
        .replaceAll(' single', '')
        .replaceAll(' - deluxe', '')
        .replaceAll('-deluxe', '') // Handle no space case
        .replaceAll(' deluxe', '')
        .replaceAll(' - deluxe edition', '')
        .replaceAll(' deluxe edition', '')
        .replaceAll(' - special edition', '')
        .replaceAll(' special edition', '')
        .replaceAll(' - remastered', '')
        .replaceAll(' remastered', '')
        .replaceAll(' (remastered)', '');

    // Remove special characters
    comparisonVersion = comparisonVersion.replaceAll(RegExp(r'[^\w\s]'), ' ');

    // Replace multiple spaces with a single space
    comparisonVersion =
        comparisonVersion.replaceAll(RegExp(r'\s+'), ' ').trim();

    // If using this for search, keep the original qualified version
    if (normalized.contains('deluxe') ||
        normalized.contains('ep') ||
        normalized.contains('single') ||
        normalized.contains('remastered') ||
        normalized.contains('special edition')) {
      // For search, we want to keep the qualifiers like "Deluxe Edition"
      normalized = originalNormalized;

      // Just clean up spaces and special characters
      normalized = normalized.replaceAll(RegExp(r'[^\w\s\-()]'), ' ');
      normalized = normalized.replaceAll(RegExp(r'\s+'), ' ').trim();

      // REMOVED: Don't log "Keeping qualifiers" messages
    } else {
      // For regular comparison with no special qualifiers, use the simpler version
      normalized = comparisonVersion;
    }

    // REMOVE ALL NORMALIZATION LOGGING completely - it's way too noisy

    return normalized;
  }
}
