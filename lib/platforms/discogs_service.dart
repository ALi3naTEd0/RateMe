import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:rateme/core/api/api_keys.dart';
import '../core/services/logging.dart';
import '../database/api_key_manager.dart';
import 'platform_service_base.dart';

class DiscogsService extends PlatformServiceBase {
  static const String _baseUrl = 'https://api.discogs.com';

  @override
  String get platformId => 'discogs';

  @override
  String get displayName => 'Discogs';

  @override
  Future<String?> findAlbumUrl(String artist, String albumName) async {
    try {
      Logging.severe('Discogs: Searching for "$albumName" by "$artist"');

      // Clean artist name by removing suffix like "Artist (5)"
      final cleanArtist = artist.replaceAll(RegExp(r'\s*\(\d+\)$'), '');

      // Normalize names for better matching
      final normalizedArtist = normalizeForComparison(cleanArtist);
      final normalizedAlbum = normalizeForComparison(albumName);

      // Single log for normalized terms
      Logging.severe('Discogs: Using normalized search terms');

      // NEW: Check if the artist name contains spaces between individual letters (like "E L U C I D")
      bool isSpacedLetterFormat = _isSpacedLetterFormat(artist);

      // Try with condensed artist name first for spaced letter artists
      if (isSpacedLetterFormat) {
        // NEW: For artists with spaced letters format, also create a version without spaces
        final noSpacesArtist = cleanArtist.replaceAll(' ', '');
        Logging.severe(
            'Discogs: Artist appears to have spaced letters format. Using both "$cleanArtist" and "$noSpacesArtist" for search');

        // Try first with the condensed version (no spaces)
        final condensedQuery =
            Uri.encodeComponent('"$noSpacesArtist" "$albumName"');
        final condensedUrl = Uri.parse(
            '$_baseUrl/database/search?q=$condensedQuery&type=release&per_page=50');

        Logging.severe('Discogs condensed search query: $condensedUrl');

        // Attempt search with condensed artist name
        final apiCredentials = await _getDiscogsCredentials();
        if (apiCredentials != null) {
          final response = await http.get(condensedUrl, headers: {
            'Authorization':
                'Discogs key=${apiCredentials['key']}, secret=${apiCredentials['secret']}'
          });

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            final results = data['results'] as List<dynamic>? ?? [];

            if (results.isNotEmpty) {
              Logging.severe(
                  'Found ${results.length} Discogs results for condensed search');

              // Process these results first - they might be better matches
              final String? matchUrl = _processSearchResults(results,
                  noSpacesArtist, albumName, normalizedArtist, normalizedAlbum);

              if (matchUrl != null) {
                Logging.severe(
                    'Found match using condensed artist name: $matchUrl');
                return matchUrl;
              }
            }
          }
        }
      }

      // Continue with regular search patterns - original approach

      // APPROACH 1: Try a more specific search format with quotes to get precise matches
      final exactQuery = Uri.encodeComponent('"$cleanArtist" "$albumName"');
      final exactUrl = Uri.parse(
          '$_baseUrl/database/search?q=$exactQuery&type=release&per_page=50');

      // APPROACH 2: Try a general search as fallback
      final generalQuery = Uri.encodeComponent('$cleanArtist $albumName');
      final generalUrl = Uri.parse(
          '$_baseUrl/database/search?q=$generalQuery&type=release&per_page=100');

      // Define search approaches to try in order
      final searchApproaches = [
        {'url': exactUrl, 'description': 'exact quoted search'},
        {'url': generalUrl, 'description': 'general search'},
      ];

      // Get API credentials
      final apiCredentials = await _getDiscogsCredentials();
      if (apiCredentials == null) {
        Logging.severe('Discogs API credentials not configured');
        return null;
      }

      // Try each search approach until we find a good match
      for (final approach in searchApproaches) {
        final searchUrl = approach['url'] as Uri;
        final description = approach['description'];

        // Simplify URL logging - don't include the full URL
        Logging.severe('Discogs: Trying $description strategy');

        final response = await http.get(searchUrl, headers: {
          'Authorization':
              'Discogs key=${apiCredentials['key']}, secret=${apiCredentials['secret']}'
        });

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final results = data['results'] as List<dynamic>? ?? [];

          if (results.isNotEmpty) {
            Logging.severe(
                'Found ${results.length} Discogs results for $description');

            // Process results with the original artist name
            final String? matchUrl = _processSearchResults(results, cleanArtist,
                albumName, normalizedArtist, normalizedAlbum);

            if (matchUrl != null) {
              return matchUrl;
            }
          }
        }
      }

      Logging.severe(
          'No matching album found on Discogs that meets BOTH artist and album criteria');
      return null;
    } catch (e, stack) {
      Logging.severe('Error searching Discogs', e, stack);
      return null;
    }
  }

  // Helper method to process search results and find best match
  String? _processSearchResults(List<dynamic> results, String searchArtist,
      String albumName, String normalizedArtist, String normalizedAlbum) {
    // Process and score all results
    final scoredResults = <Map<String, dynamic>>[];

    for (var release in results) {
      final resultTitle = release['title']?.toString() ?? '';

      // Extract artist and album using the improved helper method
      final extracted = _extractArtistAndAlbum(resultTitle);
      final resultArtist = extracted['artist'] ?? '';
      final resultAlbum = extracted['album'] ?? resultTitle;

      // Clean and normalize result values
      final cleanResultArtist =
          resultArtist.replaceAll(RegExp(r'\s*\(\d+\)$'), '');
      final normalizedResultArtist = normalizeForComparison(cleanResultArtist);
      final normalizedResultAlbum = normalizeForComparison(resultAlbum);

      // Calculate similarity scores
      final artistScore =
          calculateStringSimilarity(normalizedArtist, normalizedResultArtist);
      final albumScore =
          calculateStringSimilarity(normalizedAlbum, normalizedResultAlbum);

      // IMPORTANT: Both artist and album need to match reasonably well
      // Use minimum thresholds for each instead of just combined score
      final artistMatchLevel = _getMatchLevel(artistScore);
      final albumMatchLevel = _getMatchLevel(albumScore);

      // Combined score weighted toward artist matching (70% artist, 30% album)
      final combinedScore = (artistScore * 0.7) + (albumScore * 0.3);

      // Log for debugging when at least one score is decent
      if (artistScore > 0.5 || albumScore > 0.5) {
        Logging.severe(
            'Discogs match candidate: "$resultArtist - $resultAlbum"');
        Logging.severe(
            'Artist score: ${artistScore.toStringAsFixed(2)} ($artistMatchLevel), '
            'Album score: ${albumScore.toStringAsFixed(2)} ($albumMatchLevel), '
            'Combined: ${combinedScore.toStringAsFixed(2)}');
      }

      scoredResults.add({
        'release': release,
        'resultArtist': resultArtist,
        'resultAlbum': resultAlbum,
        'artistScore': artistScore,
        'albumScore': albumScore,
        'artistMatchLevel': artistMatchLevel,
        'albumMatchLevel': albumMatchLevel,
        'combinedScore': combinedScore,
      });
    }

    // Sort by combined score
    scoredResults
        .sort((a, b) => b['combinedScore'].compareTo(a['combinedScore']));

    // Log only top matches for debugging (maximum 3)
    for (var i = 0; i < math.min(3, scoredResults.length); i++) {
      final match = scoredResults[i];
      if (i == 0) {
        // Only log the best match in detail
        Logging.severe(
            'Discogs top match: "${match['resultArtist']} - ${match['resultAlbum']}" '
            '(artist score: ${match['artistScore'].toStringAsFixed(2)}, '
            'album score: ${match['albumScore'].toStringAsFixed(2)})');
      }
    }

    // Apply match criteria and return URL if found
    for (var scoredMatch in scoredResults) {
      final artistScore = scoredMatch['artistScore'] as double;
      final albumScore = scoredMatch['albumScore'] as double;

      // Check our matching criteria for various quality levels
      if ((artistScore > 0.95 && albumScore > 0.9) || // Perfect match
          (artistScore > 0.85 && albumScore > 0.7) || // Strong match
          (artistScore > 0.9 && albumScore > 0.6) || // Good artist match
          (artistScore > 0.75 && albumScore > 0.65) || // Acceptable match
          (albumScore > 0.9 && artistScore > 0.6)) {
        // Compilation match

        final resourceId = scoredMatch['release']['id']?.toString();
        if (resourceId != null) {
          return 'https://www.discogs.com/release/$resourceId';
        }
      }
    }

    return null;
  }

  // Helper method to get a text description of match quality
  String _getMatchLevel(double score) {
    if (score > 0.95) return '(perfect)';
    if (score > 0.85) return '(excellent)';
    if (score > 0.75) return '(good)';
    if (score > 0.6) return '(fair)';
    if (score > 0.4) return '(poor)';
    return '(no match)';
  }

  // Improved helper method to extract artist and album from Discogs title format
  Map<String, String> _extractArtistAndAlbum(String discogsTitle) {
    // Discogs usually formats as "Artist - Album" or "Various - Album" or "Artist (5) - Album"
    String artist = '';
    String album = discogsTitle;

    // Check for the standard "Artist - Album" format
    if (discogsTitle.contains(' - ')) {
      final parts = discogsTitle.split(' - ');
      // The artist is the first part
      artist = parts[0].trim();
      // The album is everything after the first dash
      album = parts.sublist(1).join(' - ').trim();

      // Special handling for "Various" artists
      if (artist.toLowerCase() == 'various') {
        artist = 'Various Artists';
      }

      // Handle common artist formatting patterns in Discogs

      // 1. Multiple artists notation: "Artist 1, Artist 2"
      if (artist.contains(', ')) {
        // Keep just the first artist for better matching
        final firstArtist = artist.split(', ')[0].trim();
        Logging.severe(
            'Extracted primary artist from multiartist: "$firstArtist" (original: "$artist")');
        artist = firstArtist;
      }

      // 2. Artist numbering: "Artist (5)" - preserve for now as it's handled elsewhere

      // If album contains additional artist info like "feat.", move it to the artist field
      final featRegexes = [
        RegExp(r'\(feat\.\s+([^)]+)\)$'),
        RegExp(r'\(featuring\s+([^)]+)\)$'),
        RegExp(r'\(with\s+([^)]+)\)$'),
      ];

      for (final regex in featRegexes) {
        final featMatch = regex.firstMatch(album);
        if (featMatch != null) {
          final featArtists = featMatch.group(1);
          if (featArtists != null) {
            artist += ' feat. $featArtists';
            album = album.replaceAll(featMatch.group(0)!, '').trim();
            break;
          }
        }
      }

      // Handle common album type notations
      final albumTypeMarkers = [
        'EP',
        'LP',
        'Single',
        'Remixes',
        'Remix',
        'Album',
        'Compilation'
      ];
      for (final marker in albumTypeMarkers) {
        final pattern =
            RegExp(r'\(\s*' + marker + r'\s*\)', caseSensitive: false);
        if (pattern.hasMatch(album)) {
          Logging.severe('Detected $marker notation in album: "$album"');
          // Don't remove, but log that we found it
        }
      }
    }

    return {
      'artist': artist,
      'album': album,
    };
  }

  @override
  Future<bool> verifyAlbumExists(String artist, String albumName) async {
    try {
      // Get API credentials
      final apiCredentials = await _getDiscogsCredentials();
      if (apiCredentials == null) {
        Logging.severe('Discogs API credentials not configured');
        return false;
      }

      // Clean artist name by removing suffix like "Artist (5)"
      final cleanArtist = artist.replaceAll(RegExp(r'\s*\(\d+\)$'), '');

      // Normalize for comparison
      final normalizedArtist = normalizeForComparison(cleanArtist);
      final normalizedAlbum = normalizeForComparison(albumName);

      // Log the normalized values for debugging
      Logging.severe(
          'Discogs verification: normalized artist="$normalizedArtist", album="$normalizedAlbum"');

      // First try with both artist and album in quotes for exact matching
      final exactQuery = Uri.encodeComponent('"$cleanArtist" "$albumName"');
      final exactUrl = Uri.parse(
          '$_baseUrl/database/search?q=$exactQuery&type=release&per_page=10');

      final response = await http.get(exactUrl, headers: {
        'Authorization':
            'Discogs key=${apiCredentials['key']}, secret=${apiCredentials['secret']}'
      });

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final results = data['results'] as List? ?? [];

        if (results.isEmpty) {
          // Try a more general search if exact search yields nothing
          final generalQuery = Uri.encodeComponent('$cleanArtist $albumName');
          final generalUrl = Uri.parse(
              '$_baseUrl/database/search?q=$generalQuery&type=release&per_page=20');

          final generalResponse = await http.get(generalUrl, headers: {
            'Authorization':
                'Discogs key=${apiCredentials['key']}, secret=${apiCredentials['secret']}'
          });

          if (generalResponse.statusCode == 200) {
            final generalData = jsonDecode(generalResponse.body);
            return await _processVerificationResults(
                generalData['results'] as List? ?? [],
                normalizedArtist,
                normalizedAlbum);
          }

          Logging.severe('Discogs: Verification returned no results');
          return false;
        }

        return await _processVerificationResults(
            results, normalizedArtist, normalizedAlbum);
      }

      Logging.severe('Discogs: Verification failed - API error');
      return false;
    } catch (e, stack) {
      Logging.severe('Error verifying Discogs album', e, stack);
      return false;
    }
  }

  // Helper method to process verification results
  Future<bool> _processVerificationResults(
      List results, String normalizedArtist, String normalizedAlbum) async {
    // Score all results
    final List<Map<String, dynamic>> scoredMatches = [];
    for (var result in results) {
      final String resultTitle = result['title'] ?? '';
      final extracted = _extractArtistAndAlbum(resultTitle);

      final resultArtist = extracted['artist'] ?? '';
      final resultAlbum = extracted['album'] ?? '';

      // Clean up the artist name from Discogs numbering
      final cleanResultArtist =
          resultArtist.replaceAll(RegExp(r'\s*\(\d+\)$'), '');

      // Calculate similarity scores
      final artistScore = calculateStringSimilarity(
          normalizedArtist, normalizeForComparison(cleanResultArtist));

      final albumScore = calculateStringSimilarity(
          normalizedAlbum, normalizeForComparison(resultAlbum));

      // For verification, we require BOTH artist AND album to match at reasonable levels
      final isGoodMatch = (artistScore > 0.75 && albumScore > 0.65) ||
          (artistScore > 0.85 && albumScore > 0.5) ||
          (albumScore > 0.9 && artistScore > 0.6);

      final combinedScore = (artistScore * 0.7) + (albumScore * 0.3);

      Logging.severe(
          'Discogs verification candidate: "$resultArtist - $resultAlbum"');
      Logging.severe('  - Scores: artist=${artistScore.toStringAsFixed(2)}, '
          'album=${albumScore.toStringAsFixed(2)}, '
          'combined=${combinedScore.toStringAsFixed(2)}, '
          'goodMatch=$isGoodMatch');

      scoredMatches.add({
        'artistScore': artistScore,
        'albumScore': albumScore,
        'combinedScore': combinedScore,
        'isGoodMatch': isGoodMatch,
      });
    }

    // Sort by combined score
    scoredMatches
        .sort((a, b) => b['combinedScore'].compareTo(a['combinedScore']));

    // Check if any match meets our criteria
    for (final match in scoredMatches) {
      if (match['isGoodMatch'] == true) {
        Logging.severe(
            'Discogs: Verification successful! Found match with scores: '
            'artist=${match['artistScore'].toStringAsFixed(2)}, '
            'album=${match['albumScore'].toStringAsFixed(2)}, '
            'combined=${match['combinedScore'].toStringAsFixed(2)}');
        return true;
      }
    }

    Logging.severe('Discogs: Verification failed - no suitable matches found');
    return false;
  }

  @override
  Future<Map<String, dynamic>?> fetchAlbumDetails(String url) async {
    try {
      Logging.severe('Fetching Discogs details: $url');

      // Extract the release or master ID from the URL
      String? id;
      String type = 'release'; // Default to release

      if (url.contains('/release/')) {
        final regExp = RegExp(r'/release/(\d+)');
        final match = regExp.firstMatch(url);
        id = match?.group(1);
      } else if (url.contains('/master/')) {
        final regExp = RegExp(r'/master/(\d+)');
        final match = regExp.firstMatch(url);
        id = match?.group(1);
        type = 'master';
      }

      if (id == null) {
        Logging.severe('Could not extract ID from URL: $url');
        return null;
      }

      // Get API credentials
      final apiCredentials = await _getDiscogsCredentials();
      if (apiCredentials == null) {
        Logging.severe('Discogs API credentials not configured');
        return null;
      }

      // API call to get album details
      final apiUrl = '$_baseUrl/${type}s/$id';
      final response = await http.get(Uri.parse(apiUrl), headers: {
        'Authorization':
            'Discogs key=${apiCredentials['key']}, secret=${apiCredentials['secret']}',
        'User-Agent': 'RateMe/1.0'
      });

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        // Extract artist name - and remove Discogs numbering if present
        String artistName = 'Unknown Artist';
        if (data['artists'] != null &&
            data['artists'] is List &&
            data['artists'].isNotEmpty) {
          // Join multiple artists and remove Discogs special characters
          artistName = data['artists']
              .map((a) =>
                  a['name'].toString().replaceAll(RegExp(r'\s*\(\d+\)$'), ''))
              .join(', ')
              .replaceAll(' *', '')
              .replaceAll('*', '');
        } else if (data['artist'] != null) {
          // Remove Discogs numbering from single artist name
          artistName =
              data['artist'].toString().replaceAll(RegExp(r'\s*\(\d+\)$'), '');
        }

        // Extract album title
        final albumTitle = data['title'] ?? 'Unknown Album';

        // Extract tracks
        List<Map<String, dynamic>> tracks = [];
        if (data['tracklist'] != null && data['tracklist'] is List) {
          int position = 1;
          for (var trackData in data['tracklist']) {
            // Skip non-track items
            if (trackData['type_'] != 'heading' &&
                trackData['type_'] != 'index') {
              String trackName = trackData['title'] ?? 'Track $position';

              // Parse duration if available
              int durationMs = 0;
              if (trackData['duration'] != null &&
                  trackData['duration'].toString().trim().isNotEmpty) {
                final parts = trackData['duration'].toString().split(':');
                if (parts.length == 2) {
                  final minutes = int.tryParse(parts[0]) ?? 0;
                  final seconds = int.tryParse(parts[1]) ?? 0;
                  durationMs = (minutes * 60 + seconds) * 1000;
                }
              }

              tracks.add({
                'trackId': '${id}_$position',
                'trackName': trackName,
                'trackNumber': position,
                'trackTimeMillis': durationMs,
              });

              position++;
            }
          }
        }

        // Simplify logging - just log track count
        Logging.severe(
            'Extracted ${tracks.length} tracks from Discogs response');

        // Extract artwork URL - simplified logging
        String artworkUrl = '';
        if (data['images'] != null && data['images'] is List) {
          if (data['images'].isNotEmpty) {
            artworkUrl = data['images'][0]['uri'] ?? '';
          }
        }

        // Create standardized album object - ensure both artworkUrl fields are set
        final result = {
          'id': id,
          'collectionId': id,
          'name': albumTitle,
          'collectionName': albumTitle,
          'artist': artistName,
          'artistName': artistName,
          'artworkUrl': artworkUrl,
          'artworkUrl100': artworkUrl,
          'releaseDate': data['released'] ??
              data['year'] ??
              DateTime.now().year.toString(),
          'url': url,
          'platform': 'discogs',
          'tracks': tracks,
        };

        return result;
      } else {
        Logging.severe('Discogs API error: ${response.statusCode}');
        return null;
      }
    } catch (e, stack) {
      Logging.severe('Error fetching Discogs album details', e, stack);
      return null;
    }
  }

  // Helper method to get Discogs API credentials - fixed return type issue
  Future<Map<String, String>?> _getDiscogsCredentials() async {
    try {
      // First try to get credentials from the API key manager
      final apiKeyManager = ApiKeyManager.instance;
      final credentials = await apiKeyManager.getApiKey('discogs');

      if (credentials['key'] != null && credentials['secret'] != null) {
        // Create a new Map with non-nullable String values to match return type
        return {'key': credentials['key']!, 'secret': credentials['secret']!};
      }

      // Fallback to ApiKeys class if not found in database
      final apiKey = await ApiKeys.discogsConsumerKey;
      final apiSecret = await ApiKeys.discogsConsumerSecret;

      if (apiKey != null && apiSecret != null) {
        // Store in the API key manager for future use
        await apiKeyManager.saveApiKey('discogs', apiKey, apiSecret);
        return {'key': apiKey, 'secret': apiSecret};
      }

      return null;
    } catch (e, stack) {
      Logging.severe('Error getting Discogs credentials', e, stack);
      return null;
    }
  }

  // Reuse the _isSpacedLetterFormat method from the platform_service_base class
  bool _isSpacedLetterFormat(String input) {
    // First check if string contains multiple spaces
    if (!input.contains(' ')) return false;

    // Count single letters followed by spaces
    List<String> parts = input.split(' ');

    // If most parts are single letters, it's probably a spaced-letter format
    int singleLetterCount = parts.where((part) => part.length == 1).length;

    // Consider it spaced-letter format if more than 60% are single letters and at least 2 single letters
    return singleLetterCount >= 2 && singleLetterCount / parts.length > 0.6;
  }
}
