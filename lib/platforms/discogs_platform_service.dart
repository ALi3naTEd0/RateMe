import 'dart:convert';
import 'package:http/http.dart' as http;
import '../logging.dart';
import 'platform_service_base.dart';

class DiscogsPlatformService extends PlatformServiceBase {
  static const String _baseApiUrl = 'https://api.discogs.com';

  @override
  String get platformId => 'discogs';

  @override
  String get displayName => 'Discogs';

  /// Fetches album directly from a Discogs URL
  Future<Map<String, dynamic>?> fetchAlbumByUrl(String url) async {
    try {
      Logging.severe('Fetching Discogs album by URL: $url');

      // Extract release ID and type from URL
      final RegExp regExp = RegExp(r'/(master|release)/(\d+)');
      final match = regExp.firstMatch(url);

      if (match == null || match.groupCount < 2) {
        Logging.severe('Invalid Discogs URL format: $url');
        return null;
      }

      final type = match.group(1);
      final id = match.group(2);

      if (type == null || id == null) {
        Logging.severe('Could not extract type/ID from Discogs URL: $url');
        return null;
      }

      Logging.severe('Extracted Discogs $type ID: $id');

      // Use the Discogs API to fetch the album details
      final apiUrl = '$_baseApiUrl/${type}s/$id';
      Logging.severe('Fetching from Discogs API: $apiUrl');

      final response = await http.get(
        Uri.parse(apiUrl),
        headers: {'User-Agent': 'RateMe/1.0'},
      );

      if (response.statusCode != 200) {
        Logging.severe(
            'Error from Discogs API: ${response.statusCode} ${response.body}');
        return null;
      }

      final data = json.decode(response.body);
      Logging.severe('Successfully received data from Discogs API');

      // Extract the relevant album data
      String artistName = '';
      String albumName = '';
      String artworkUrl = '';

      try {
        // Different JSON structure depending on master or release
        if (type == 'master') {
          if (data['artists'] != null && data['artists'].isNotEmpty) {
            artistName = data['artists'][0]['name'] ?? '';
          }
          albumName = data['title'] ?? '';

          // Get artwork
          if (data['images'] != null && data['images'].isNotEmpty) {
            artworkUrl = data['images'][0]['uri'] ?? '';
          }
        } else {
          // For releases
          artistName = data['artists_sort'] ?? '';
          albumName = data['title'] ?? '';

          // Get artwork
          if (data['images'] != null && data['images'].isNotEmpty) {
            artworkUrl = data['images'][0]['uri'] ?? '';
          }
        }

        Logging.severe(
            'Parsed Discogs data - Artist: $artistName, Album: $albumName');

        if (artistName.isEmpty || albumName.isEmpty) {
          Logging.severe('Missing artist or album name from Discogs data');
          return null;
        }

        // Create a standardized album object
        Logging.severe('Creating standardized album object for Discogs album');

        // Standard album format compatible with our app
        final result = {
          'collectionId': id,
          'collectionName': albumName,
          'artistName': artistName,
          'artworkUrl100': artworkUrl,
          'trackCount': data['tracklist']?.length ?? 0,
          'url': url,
          'platform': 'discogs',
        };

        Logging.severe(
            'Successfully created album data for: $artistName - $albumName');
        return result;
      } catch (e, stack) {
        Logging.severe('Error parsing Discogs API response data', e, stack);
        return null;
      }
    } catch (e, stack) {
      Logging.severe('Error fetching Discogs album from URL', e, stack);
      return null;
    }
  }

  @override
  Future<bool> verifyAlbumExists(String artist, String albumName) async {
    // Implementation for verification
    // ...existing code if any...
    return false;
  }

  @override
  Future<Map<String, dynamic>?> fetchAlbumDetails(String url) async {
    return await fetchAlbumByUrl(url);
  }

  @override
  Future<String?> findAlbumUrl(String artist, String album) async {
    // Implementation for finding album URL
    // ...existing code if any...
    return null;
  }
}
