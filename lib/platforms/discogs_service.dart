import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:rateme/api_keys.dart';
import '../logging.dart';
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

      // Normalize artist name by removing suffix like "Artist (5)"
      final normalizedArtist =
          normalizeForComparison(artist.replaceAll(RegExp(r'\s*\(\d+\)$'), ''));
      final normalizedAlbum = normalizeForComparison(albumName);

      // Log the normalized values to debug
      Logging.severe(
          'Discogs normalized search: artist="$normalizedArtist", album="$normalizedAlbum"');

      // Construct search query
      final query = Uri.encodeComponent('$normalizedArtist $normalizedAlbum');
      final url = Uri.parse('$_baseUrl/database/search?q=$query&type=release');

      Logging.severe('Discogs search query: $url');

      // Get API credentials
      final apiCredentials = await _getDiscogsCredentials();
      if (apiCredentials == null) {
        Logging.severe('Discogs API credentials not configured');
        return null;
      }

      final response = await http.get(url, headers: {
        'Authorization':
            'Discogs key=${apiCredentials['key']}, secret=${apiCredentials['secret']}'
      });

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final results = data['results'] as List<dynamic>? ?? [];

        if (results.isNotEmpty) {
          Logging.severe('Found ${results.length} Discogs results');

          // Look for a good match
          for (var release in results) {
            final resultTitle = release['title']?.toString() ?? '';

            // Extract artist from title (Discogs format is usually "Artist - Album" or "Artist (5) - Album")
            String resultArtist = '';
            String resultAlbum = resultTitle;

            if (resultTitle.contains(' - ')) {
              final parts = resultTitle.split(' - ');
              resultArtist = parts[0];
              resultAlbum = parts.sublist(1).join(' - ');
            }

            // Normalize for comparison - specifically removing Discogs "(#)" style suffixes
            final normalizedResultArtist = normalizeForComparison(
                resultArtist.replaceAll(RegExp(r'\s*\(\d+\)$'), ''));
            final normalizedResultAlbum = normalizeForComparison(resultAlbum);

            // Calculate similarity scores
            final artistScore = calculateStringSimilarity(
                normalizedArtist, normalizedResultArtist);
            final albumScore = calculateStringSimilarity(
                normalizedAlbum, normalizedResultAlbum);

            // Increase artist importance for matching (was 0.6 artist, 0.4 album)
            // Now 0.7 artist, 0.3 album to ensure artist match is more important
            final combinedScore = (artistScore * 0.7) + (albumScore * 0.3);

            Logging.severe(
                'Discogs match candidate: "$resultArtist - $resultAlbum"');
            Logging.severe(
                'Scores - artist: ${artistScore.toStringAsFixed(2)}, '
                'album: ${albumScore.toStringAsFixed(2)}, '
                'combined: ${combinedScore.toStringAsFixed(2)}');

            // Stricter matching criteria to prevent false positives:
            // 1. Either a high combined score (>0.7 instead of 0.65)
            // 2. Or a very high artist match (>0.85 instead of 0.8) AND decent album match (>0.5)
            if ((combinedScore > 0.7) ||
                (artistScore > 0.85 && albumScore > 0.5)) {
              // Return the URL to the album on Discogs website
              final resourceId = release['id']?.toString();
              if (resourceId != null) {
                final albumUrl = 'https://www.discogs.com/release/$resourceId';
                Logging.severe('Discogs match found: $albumUrl');
                return albumUrl;
              }
            }
          }
        }
      }

      Logging.severe('No matching album found on Discogs');
      return null;
    } catch (e, stack) {
      Logging.severe('Error searching Discogs', e, stack);
      return null;
    }
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

      // Normalize artist name by removing suffix like "Artist (5)"
      final normalizedArtist =
          normalizeForComparison(artist.replaceAll(RegExp(r'\s*\(\d+\)$'), ''));
      final normalizedAlbum = normalizeForComparison(albumName);

      // Log the normalized values to debug
      Logging.severe(
          'Discogs verification: normalized artist="$normalizedArtist", album="$normalizedAlbum"');

      final query = Uri.encodeComponent('$artist $albumName');
      final url = Uri.parse(
          '$_baseUrl/database/search?q=$query&type=release&per_page=10');

      final response = await http.get(url, headers: {
        'Authorization':
            'Discogs key=${apiCredentials['key']}, secret=${apiCredentials['secret']}'
      });

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final results = data['results'] as List? ?? [];

        for (var result in results) {
          final String resultTitle = result['title'] ?? '';

          // Parse artist and album from title
          String resultArtist = '';
          String resultAlbum = '';

          if (resultTitle.contains(' - ')) {
            final parts = resultTitle.split(' - ');
            // Remove Discogs artist numbering like "Artist (5)" -> "Artist"
            resultArtist = parts[0].replaceAll(RegExp(r'\s*\(\d+\)$'), '');
            resultAlbum = parts.sublist(1).join(' - ');

            Logging.severe(
                'Discogs verification candidate: Artist="$resultArtist", Album="$resultAlbum"');
          } else {
            // If title doesn't follow "Artist - Album" format, use the whole title as album name
            resultAlbum = resultTitle;
            Logging.severe(
                'Discogs verification candidate (no artist): Album="$resultAlbum"');
          }

          final artistScore = calculateStringSimilarity(
              normalizeForComparison(resultArtist), normalizedArtist);
          final albumScore = calculateStringSimilarity(
              normalizeForComparison(resultAlbum), normalizedAlbum);

          Logging.severe(
              'Verification scores - artist: ${artistScore.toStringAsFixed(2)}, album: ${albumScore.toStringAsFixed(2)}');

          // Both artist AND album must match with good scores for verification
          // The original logic only required one OR the other to be >0.7
          if (artistScore > 0.7 && albumScore > 0.6) {
            Logging.severe(
                'Discogs verification successful - good match on both artist and album');
            return true;
          }
        }
      }

      Logging.severe('Discogs: Verification failed - no matches found');
      return false;
    } catch (e, stack) {
      Logging.severe('Error verifying Discogs album', e, stack);
      return false;
    }
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
      Logging.severe('Direct API call: $apiUrl');
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

        // Extract artwork URL
        String artworkUrl = '';
        if (data['images'] != null &&
            data['images'] is List &&
            data['images'].isNotEmpty) {
          artworkUrl = data['images'][0]['uri'] ?? '';
        }

        // Create standardized album object
        return {
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
}
