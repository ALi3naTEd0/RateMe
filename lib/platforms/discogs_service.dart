import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:rateme/api_keys.dart';
import '../logging.dart';
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
      Logging.severe('Searching for Discogs URL: "$albumName" by "$artist"');

      // Normalize names for better matching
      final normalizedArtist = normalizeForComparison(artist);
      final normalizedAlbum = normalizeForComparison(albumName);

      // Construct search query
      final query = Uri.encodeComponent('$artist $albumName');
      final url = Uri.parse(
          '$_baseUrl/database/search?q=$query&type=release&per_page=20'
          '&key=${ApiKeys.discogsConsumerKey}'
          '&secret=${ApiKeys.discogsConsumerSecret}');

      Logging.severe('Discogs: Search URL: $url');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final results = data['results'] as List<dynamic>;

        Logging.severe('Discogs: Found ${results.length} results');

        // Try to find the best match
        for (var result in results) {
          // Extract info
          final String resultTitle = result['title'] ?? '';

          // Discogs combines artist and title in the title field, so we need to parse it
          String resultArtist = '';
          String resultAlbum = '';

          // Title is usually in format "Artist - Album"
          if (resultTitle.contains(' - ')) {
            final parts = resultTitle.split(' - ');
            resultArtist = parts[0];
            resultAlbum =
                parts.sublist(1).join(' - '); // Handle album titles with dashes
          } else {
            // If there's no dash, just use the full title as the album name
            resultArtist = resultTitle;
            resultAlbum = resultTitle;
          }

          // Normalize for comparison
          final normalizedResultArtist = normalizeForComparison(resultArtist);
          final normalizedResultAlbum = normalizeForComparison(resultAlbum);

          // Calculate similarity scores
          final artistScore = calculateStringSimilarity(
              normalizedArtist, normalizedResultArtist);
          final albumScore =
              calculateStringSimilarity(normalizedAlbum, normalizedResultAlbum);
          final combinedScore = (artistScore * 0.6) + (albumScore * 0.4);

          Logging.severe('Discogs: Match candidate: "$resultTitle"');
          Logging.severe(
              'Discogs: Scores - artist: ${artistScore.toStringAsFixed(2)}, album: ${albumScore.toStringAsFixed(2)}, combined: ${combinedScore.toStringAsFixed(2)}');

          // Check if this is a good match
          if (combinedScore > 0.7 || (artistScore > 0.8 && albumScore > 0.5)) {
            // Extract release ID or master ID
            String? id = result['id']?.toString();
            String? type = result['type'];

            // Construct URL
            if (id != null && type != null) {
              String discogsUrl;
              if (type == 'release') {
                discogsUrl = 'https://www.discogs.com/release/$id';
              } else if (type == 'master') {
                discogsUrl = 'https://www.discogs.com/master/$id';
              } else {
                continue; // Skip unknown types
              }

              // Try to fetch cover image
              final imageUrl = await _tryGetImageUrl(id, type);
              if (imageUrl != null) {
                Logging.severe('Discogs: Found image: $imageUrl');
              }

              Logging.severe(
                  'Discogs: Best match found: $discogsUrl (score: ${combinedScore.toStringAsFixed(2)})');
              return discogsUrl;
            }
          }
        }
      }

      Logging.severe('No matching release found on Discogs');
      return null;
    } catch (e, stack) {
      Logging.severe('Error searching Discogs', e, stack);
      return null;
    }
  }

  @override
  Future<bool> verifyAlbumExists(String artist, String albumName) async {
    try {
      // Similar implementation to findAlbumUrl, but just return true/false
      final normalizedArtist = normalizeForComparison(artist);
      final normalizedAlbum = normalizeForComparison(albumName);

      final query = Uri.encodeComponent('$artist $albumName');
      final url = Uri.parse(
          '$_baseUrl/database/search?q=$query&type=release&per_page=10'
          '&key=${ApiKeys.discogsConsumerKey}'
          '&secret=${ApiKeys.discogsConsumerSecret}');

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final results = data['results'] as List;

        for (var result in results) {
          final String resultTitle = result['title'] ?? '';

          // Parse artist and album from title
          String resultArtist = '';
          String resultAlbum = '';

          if (resultTitle.contains(' - ')) {
            final parts = resultTitle.split(' - ');
            resultArtist = parts[0];
            resultAlbum = parts.sublist(1).join(' - ');
          } else {
            resultArtist = resultTitle;
            resultAlbum = resultTitle;
          }

          final artistScore = calculateStringSimilarity(
              normalizeForComparison(resultArtist), normalizedArtist);
          final albumScore = calculateStringSimilarity(
              normalizeForComparison(resultAlbum), normalizedAlbum);

          if (artistScore > 0.7 || albumScore > 0.7) {
            return true;
          }
        }
      }
      return false;
    } catch (e, stack) {
      Logging.severe('Error verifying Discogs album', e, stack);
      return false;
    }
  }

  @override
  Future<Map<String, dynamic>?> fetchAlbumDetails(String url) async {
    try {
      Logging.severe('Fetching Discogs album details from URL: $url');

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
        Logging.severe('Could not extract ID from Discogs URL: $url');
        return null;
      }

      // Fetch album data from Discogs API
      String apiUrl = '$_baseUrl/$type/$id';
      apiUrl +=
          '?key=${ApiKeys.discogsConsumerKey}&secret=${ApiKeys.discogsConsumerSecret}';

      Logging.severe('Discogs API URL: $apiUrl');
      final response = await http.get(Uri.parse(apiUrl));

      if (response.statusCode != 200) {
        Logging.severe('Discogs API error: ${response.statusCode}');
        return null;
      }

      final albumData = jsonDecode(response.body);

      // Try to get the cover image
      String artworkUrl = '';

      // Method 1: Try the images array (should work with authorization)
      if (albumData['images'] != null &&
          albumData['images'] is List &&
          albumData['images'].isNotEmpty) {
        // Look for primary image or first image
        var primaryImage = albumData['images'].firstWhere(
            (img) => img['type'] == 'primary',
            orElse: () => albumData['images'][0]);

        if (primaryImage != null && primaryImage['uri'] != null) {
          artworkUrl = primaryImage['uri'];
          Logging.severe('Found Discogs image from API: $artworkUrl');
        }
      }

      // Method 2: Try alternative image URL formats (based on forum post)
      if (artworkUrl.isEmpty) {
        artworkUrl = await _tryGetImageUrl(id, type) ?? '';
      }

      // Parse artist name
      String artistName = 'Unknown Artist';
      if (albumData['artists'] != null &&
          albumData['artists'] is List &&
          albumData['artists'].isNotEmpty) {
        artistName = albumData['artists']
            .map((a) => a['name'])
            .join(', ')
            .replaceAll(' *', '')
            .replaceAll('*', ''); // Remove Discogs formatting characters
      } else if (albumData['artist'] != null) {
        artistName = albumData['artist'];
      }

      // Parse tracks
      List<Map<String, dynamic>> tracks = [];
      if (albumData['tracklist'] != null && albumData['tracklist'] is List) {
        int position = 1;
        for (var trackData in albumData['tracklist']) {
          // Skip headings and other non-track items
          if (trackData['type_'] == 'track') {
            // Parse duration
            int durationMs = 0;
            if (trackData['duration'] != null) {
              durationMs = _parseDuration(trackData['duration']);
            }

            tracks.add({
              'trackId': position,
              'trackName': trackData['title'] ?? 'Unknown Track',
              'trackNumber': position,
              'trackTimeMillis': durationMs,
            });
            position++;
          }
        }
      }

      // Create standardized album object
      return {
        'id': int.tryParse(id) ?? id,
        'collectionId': int.tryParse(id) ?? id,
        'name': albumData['title'] ?? 'Unknown Album',
        'collectionName': albumData['title'] ?? 'Unknown Album',
        'artist': artistName,
        'artistName': artistName,
        'artworkUrl': artworkUrl,
        'artworkUrl100': artworkUrl,
        'releaseDate': albumData['released'] ??
            albumData['year'] ??
            DateTime.now().year.toString(),
        'url': url,
        'platform': 'discogs',
        'tracks': tracks,
      };
    } catch (e, stack) {
      Logging.severe('Error fetching Discogs album details', e, stack);
      return null;
    }
  }

  /// Try to get image URL for a Discogs release/master
  Future<String?> _tryGetImageUrl(String id, String type) async {
    try {
      // APPROACH 1: Fetch the website and extract image URLs from the HTML
      final websiteUrl = 'https://www.discogs.com/$type/$id';
      Logging.severe('Fetching Discogs HTML page for image: $websiteUrl');

      final response = await http.get(Uri.parse(websiteUrl));

      if (response.statusCode == 200) {
        final html = response.body;

        // PRIORITY 1: Look for images directly in the image gallery section
        if (html.contains('id="image-gallery"')) {
          Logging.severe('Found image gallery section');

          // Extract the image gallery section
          int galleryStart = html.indexOf('id="image-gallery"');
          int galleryEnd = html.indexOf('</div>', galleryStart);

          if (galleryStart > 0 && galleryEnd > galleryStart) {
            String galleryHtml = html.substring(galleryStart, galleryEnd);

            // Modern Discogs uses a specific CDN format with encoded parameters
            // Example: https://i.discogs.com/XmMMgR_6A_85TC92AI1QmAguQ1h-qkcTuEobG4AVPTM/rs:fit/g:sm/q:90/h:600/w:599/...
            final modernUrlRegex = RegExp(
                r'src="(https://i\.discogs\.com/[^"]+\.jpeg)"',
                caseSensitive: false);

            final modernMatch = modernUrlRegex.firstMatch(galleryHtml);
            if (modernMatch != null && modernMatch.groupCount >= 1) {
              final imageUrl = modernMatch.group(1);
              if (imageUrl != null && imageUrl.isNotEmpty) {
                Logging.severe('Found modern CDN image in gallery: $imageUrl');
                return imageUrl;
              }
            }
          }
        }

        // PRIORITY 2: Look for meta tags with og:image
        final metaRegex = RegExp(
            r'<meta\s+property="og:image"\s+content="([^"]+)"',
            caseSensitive: false);

        final metaMatch = metaRegex.firstMatch(html);
        if (metaMatch != null && metaMatch.groupCount >= 1) {
          final imageUrl = metaMatch.group(1);
          if (imageUrl != null && imageUrl.isNotEmpty) {
            Logging.severe('Found og:image meta tag: $imageUrl');
            return imageUrl;
          }
        }

        // PRIORITY 3: General image search in the HTML content
        try {
          // Use a much simpler regex that should work reliably
          final imagePattern = "https://i.discogs.com/";
          int startIndex = 0;

          while (true) {
            startIndex = html.indexOf(imagePattern, startIndex);
            if (startIndex == -1) break;

            // Find the end of the URL (usually marked by a quote)
            int endIndex = html.indexOf('"', startIndex);
            if (endIndex == -1) endIndex = html.indexOf("'", startIndex);
            if (endIndex == -1) break;

            String imageUrl = html.substring(startIndex, endIndex);
            if (imageUrl.toLowerCase().endsWith('.jpg') ||
                imageUrl.toLowerCase().endsWith('.jpeg')) {
              Logging.severe('Found image URL with simple search: $imageUrl');
              return imageUrl;
            }

            // Move to next occurrence
            startIndex = endIndex;
          }
        } catch (e) {
          Logging.severe('Error in simple image search: $e');
        }
      }

      // APPROACH 2: If we couldn't get an image from the HTML, try the API
      String apiUrl = '$_baseUrl/$type/$id';
      apiUrl +=
          '?key=${ApiKeys.discogsConsumerKey}&secret=${ApiKeys.discogsConsumerSecret}';

      final apiResponse = await http.get(Uri.parse(apiUrl));
      if (apiResponse.statusCode == 200) {
        final data = jsonDecode(apiResponse.body);

        if (data['images'] != null &&
            data['images'] is List &&
            data['images'].isNotEmpty) {
          var primaryImage = data['images'].firstWhere(
              (img) => img['type'] == 'primary',
              orElse: () => data['images'][0]);

          if (primaryImage != null && primaryImage['uri'] != null) {
            Logging.severe('Found image from API: ${primaryImage['uri']}');
            return primaryImage['uri'];
          }
        }
      }

      Logging.severe('Could not find any Discogs image for $type/$id');
      return null;
    } catch (e, stack) {
      Logging.severe('Error getting Discogs image URL', e, stack);
      return null;
    }
  }

  /// Parse Discogs duration string to milliseconds
  int _parseDuration(String duration) {
    try {
      // Format is usually "mm:ss" but can also be "h:mm:ss"
      final parts = duration.split(':');

      if (parts.length == 2) {
        // mm:ss format
        final minutes = int.tryParse(parts[0]) ?? 0;
        final seconds = int.tryParse(parts[1]) ?? 0;
        return (minutes * 60 + seconds) * 1000;
      } else if (parts.length == 3) {
        // h:mm:ss format
        final hours = int.tryParse(parts[0]) ?? 0;
        final minutes = int.tryParse(parts[1]) ?? 0;
        final seconds = int.tryParse(parts[2]) ?? 0;
        return (hours * 3600 + minutes * 60 + seconds) * 1000;
      }

      return 0;
    } catch (e) {
      Logging.severe('Error parsing Discogs duration: $e');
      return 0;
    }
  }
}
