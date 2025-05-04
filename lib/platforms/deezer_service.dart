import 'dart:convert';
import 'package:http/http.dart' as http;
import '../logging.dart';
import 'platform_service_base.dart';

class DeezerService extends PlatformServiceBase {
  static const String _baseUrl = 'https://api.deezer.com';

  @override
  String get platformId => 'deezer';

  @override
  String get displayName => 'Deezer';

  @override
  Future<String?> findAlbumUrl(String artist, String albumName) async {
    try {
      Logging.severe('Searching for Deezer URL: "$albumName" by "$artist"');

      // Normalize names for better matching
      final normalizedArtist = normalizeForComparison(artist);
      final normalizedAlbum = normalizeForComparison(albumName);

      // Extract a "base version" of the album name (for EP/deluxe/etc matching)
      final String baseAlbumName = getBaseAlbumName(albumName);

      // Keep track of all possible album name versions
      final List<String> albumNameVariants = [
        albumName, // Original version
        baseAlbumName, // Base version without qualifiers
      ];

      // For EPs specifically, add a variant without the EP suffix
      if (albumName.toLowerCase().contains(" - ep") ||
          albumName.toLowerCase().contains("-ep") ||
          albumName.toLowerCase().endsWith(" ep")) {
        final strippedEpName = albumName
            .toLowerCase()
            .replaceAll(" - ep", "")
            .replaceAll("-ep", "")
            .replaceAll(" ep", "")
            .trim();

        if (!albumNameVariants.contains(strippedEpName)) {
          albumNameVariants.add(strippedEpName);
          Logging.severe('Adding EP-specific variant: "$strippedEpName"');
        }
      }

      // Remove any duplicates from our variants list
      final uniqueVariants = albumNameVariants.toSet().toList();

      // APPROACH 1: Try direct artist+album search with all album variants
      for (final variant in uniqueVariants) {
        final query = Uri.encodeComponent('artist:"$artist" album:"$variant"');
        final url = Uri.parse('$_baseUrl/search/album?q=$query&limit=10');

        // Don't log every variant - reduce log noise
        if (variant != albumName) {
          // Only log non-default variants
          Logging.severe(
              'Deezer: Using alternate album name variant "$variant"');
        }

        final response = await http.get(url);

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final results = data['data'] as List<dynamic>? ?? [];

          if (results.isNotEmpty) {
            Logging.severe(
                'Found ${results.length} Deezer results for variant "$variant"');

            // Look for a good match
            for (var album in results) {
              final resultTitle = album['title']?.toString() ?? '';
              final resultArtist = album['artist']?['name']?.toString() ?? '';

              // Normalize for comparison
              final normalizedResultTitle = normalizeForComparison(resultTitle);
              final normalizedResultArtist =
                  normalizeForComparison(resultArtist);

              // Calculate similarity scores
              final artistScore = calculateStringSimilarity(
                  normalizedArtist, normalizedResultArtist);
              final albumScore = calculateStringSimilarity(
                  normalizedAlbum, normalizedResultTitle);
              final combinedScore = (artistScore * 0.6) + (albumScore * 0.4);

              Logging.severe(
                  'Deezer match candidate: "$resultArtist - $resultTitle"');
              Logging.severe(
                  'Scores - artist: ${artistScore.toStringAsFixed(2)}, '
                  'album: ${albumScore.toStringAsFixed(2)}, '
                  'combined: ${combinedScore.toStringAsFixed(2)}');

              // IMPORTANT: Increase the threshold from 0.65 to 0.75
              // Also require both artist AND album to be decent matches (not just OR)
              // Change from: if ((combinedScore > 0.65) || (artistScore > 0.8 && albumScore > 0.4))
              if ((artistScore > 0.8 &&
                      albumScore >
                          0.6) || // Good artist match AND reasonable album match
                  (combinedScore > 0.75)) {
                // Or really good combined score
                final albumId = album['id'];
                final albumUrl = 'https://www.deezer.com/album/$albumId';
                Logging.severe(
                    'Deezer match found for variant "$variant": $albumUrl');
                return albumUrl;
              }
            }
          }
        }
      }

      // APPROACH 2: Broader search as a fallback
      final broadQuery = Uri.encodeComponent('$artist $albumName');
      final broadUrl =
          Uri.parse('$_baseUrl/search/album?q=$broadQuery&limit=10');

      Logging.severe('Deezer: Using broad search as fallback');
      final broadResponse = await http.get(broadUrl);

      if (broadResponse.statusCode == 200) {
        final broadData = jsonDecode(broadResponse.body);
        final broadResults = broadData['data'] as List<dynamic>? ?? [];

        if (broadResults.isNotEmpty) {
          Logging.severe(
              'Found ${broadResults.length} Deezer results from broad search');

          // Process results similar to before
          for (var album in broadResults) {
            final resultTitle = album['title']?.toString() ?? '';
            final resultArtist = album['artist']?['name']?.toString() ?? '';

            final normalizedResultTitle = normalizeForComparison(resultTitle);
            final normalizedResultArtist = normalizeForComparison(resultArtist);

            final artistScore = calculateStringSimilarity(
                normalizedArtist, normalizedResultArtist);
            final albumScore = calculateStringSimilarity(
                normalizedAlbum, normalizedResultTitle);
            final combinedScore = (artistScore * 0.6) + (albumScore * 0.4);

            Logging.severe(
                'Deezer broad match: "$resultArtist - $resultTitle"');
            Logging.severe(
                'Scores - artist: ${artistScore.toStringAsFixed(2)}, '
                'album: ${albumScore.toStringAsFixed(2)}, '
                'combined: ${combinedScore.toStringAsFixed(2)}');

            // IMPORTANT: Apply the same stricter threshold here too
            // Change from: if ((combinedScore > 0.65) || (artistScore > 0.8 && albumScore > 0.4))
            if ((artistScore > 0.8 &&
                    albumScore >
                        0.6) || // Good artist match AND reasonable album match
                (combinedScore > 0.75)) {
              // Or really good combined score
              final albumId = album['id'];
              final albumUrl = 'https://www.deezer.com/album/$albumId';
              Logging.severe('Deezer match found from broad search: $albumUrl');
              return albumUrl;
            }
          }
        }
      }

      Logging.severe('No matching album found on Deezer');
      return null;
    } catch (e, stack) {
      Logging.severe('Error searching Deezer', e, stack);
      return null;
    }
  }

  @override
  Future<bool> verifyAlbumExists(String artist, String albumName) async {
    try {
      // Normalize search terms to improve matching
      final normalizedArtist = normalizeForComparison(artist);
      final normalizedAlbum = normalizeForComparison(albumName);

      // Reduce log verbosity - only one log needed here
      Logging.severe('Verifying Deezer album: "$albumName" by "$artist"');

      // Try the more specific query first
      final query1 = Uri.encodeComponent(
          'artist:"$normalizedArtist" album:"$normalizedAlbum"');
      final url1 = Uri.parse('$_baseUrl/search/album?q=$query1&limit=10');
      final response1 = await http.get(url1);

      if (response1.statusCode == 200) {
        final data = jsonDecode(response1.body);

        if (data['data'] != null && data['data'].isNotEmpty) {
          // Check for matches in first query results
          final results = data['data'] as List;
          Logging.severe(
              'Deezer returned ${results.length} results for specific query');

          for (var result in results) {
            final resultArtist =
                result['artist']['name'].toString().toLowerCase();
            final resultAlbum = result['title'].toString().toLowerCase();

            // Calculate similarity
            final artistSimilarity =
                calculateStringSimilarity(resultArtist, normalizedArtist);
            final albumSimilarity =
                calculateStringSimilarity(resultAlbum, normalizedAlbum);

            // More lenient threshold for Deezer matches
            if (artistSimilarity > 0.6 || albumSimilarity > 0.6) {
              return true;
            }
          }
        }
      }

      // If first query fails, try broader search
      final query2 = Uri.encodeComponent('$normalizedArtist $normalizedAlbum');
      final url2 = Uri.parse('$_baseUrl/search/album?q=$query2&limit=10');
      final response2 = await http.get(url2);

      if (response2.statusCode == 200) {
        final data = jsonDecode(response2.body);

        if (data['data'] != null && data['data'].isNotEmpty) {
          // Check for matches in second query results
          final results = data['data'] as List;
          Logging.severe(
              'Deezer returned ${results.length} results for broad query');

          for (var result in results) {
            final resultArtist =
                result['artist']['name'].toString().toLowerCase();
            final resultAlbum = result['title'].toString().toLowerCase();

            // Calculate similarity with even more lenient threshold
            final artistSimilarity =
                calculateStringSimilarity(resultArtist, normalizedArtist);
            final albumSimilarity =
                calculateStringSimilarity(resultAlbum, normalizedAlbum);

            if (artistSimilarity > 0.5 || albumSimilarity > 0.5) {
              return true;
            }
          }
        }
      }

      return false;
    } catch (e, stack) {
      Logging.severe('Error verifying Deezer album', e, stack);
      return false;
    }
  }

  @override
  Future<Map<String, dynamic>?> fetchAlbumDetails(String url) async {
    try {
      Logging.severe('Fetching Deezer album details from URL: $url');

      // Extract the album ID from the URL
      final RegExp regExp = RegExp(r'album/(\d+)');
      final match = regExp.firstMatch(url);

      if (match == null || match.groupCount < 1) {
        Logging.severe('Invalid Deezer URL format: $url');
        return null;
      }

      final albumId = match.group(1);
      if (albumId == null) {
        Logging.severe('Could not extract album ID from URL: $url');
        return null;
      }

      // Use the Deezer API to fetch album details
      final apiUrl = '$_baseUrl/album/$albumId';
      Logging.severe('Fetching from Deezer API: $apiUrl');

      final response = await http.get(Uri.parse(apiUrl));
      if (response.statusCode != 200) {
        Logging.severe('Deezer API error: ${response.statusCode}');
        return null;
      }

      final albumData = jsonDecode(response.body);
      if (albumData['error'] != null) {
        Logging.severe('Deezer API returned error: ${albumData['error']}');
        return null;
      }

      // Extract tracks from the album data
      List<Map<String, dynamic>> tracks = [];
      if (albumData['tracks'] != null && albumData['tracks']['data'] != null) {
        for (var track in albumData['tracks']['data']) {
          tracks.add({
            'trackId': track['id'],
            'trackName': track['title'],
            'trackNumber': track['track_position'] ?? tracks.length + 1,
            'trackTimeMillis':
                track['duration'] * 1000, // Deezer duration is in seconds
          });
        }
      }

      // Create a standardized album object
      return {
        'id': albumData['id'],
        'collectionId': albumData['id'],
        'name': albumData['title'],
        'collectionName': albumData['title'],
        'artist': albumData['artist']?['name'] ?? 'Unknown Artist',
        'artistName': albumData['artist']?['name'] ?? 'Unknown Artist',
        'artworkUrl': albumData['cover_xl'] ??
            albumData['cover_big'] ??
            albumData['cover'] ??
            '',
        'artworkUrl100': albumData['cover'] ?? '',
        'releaseDate': albumData['release_date'],
        'url': url,
        'platform': 'deezer',
        'tracks': tracks,
      };
    } catch (e, stack) {
      Logging.severe('Error fetching Deezer album details', e, stack);
      return null;
    }
  }
}
