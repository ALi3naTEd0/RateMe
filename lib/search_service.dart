import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' show parse;
import 'logging.dart';
import 'platform_service.dart'; // Add this import

class SearchService {
  /// Detect platform from URL or search term
  static String detectPlatform(String input) {
    if (input.contains('music.apple.com') ||
        input.contains('itunes.apple.com')) {
      return 'itunes';
    } else if (input.contains('bandcamp.com')) {
      return 'bandcamp';
    } else {
      // Default to iTunes for search terms
      return 'itunes';
    }
  }

  /// Search albums based on query or URL
  static Future<List<dynamic>> searchAlbums(String query) async {
    if (query.isEmpty) return [];

    // Handle iTunes/Apple Music URLs with improved URL parsing
    if (query.contains('music.apple.com') ||
        query.contains('itunes.apple.com') ||
        query.contains('store.apple.com')) {
      try {
        final uri = Uri.parse(query);
        final pathSegments = uri.pathSegments;

        // Debug logging
        Logging.severe('Processing iTunes URL:', {
          'url': query,
          'segments': pathSegments,
          'query': uri.queryParameters,
        });

        // Find collection/album ID
        String? collectionId;

        // Handle different URL formats
        if (pathSegments.contains('album')) {
          // Format: .../album/{albumName}/{id}
          final albumIdIndex = pathSegments.indexOf('album') + 2;
          if (albumIdIndex < pathSegments.length) {
            collectionId = pathSegments[albumIdIndex].split('?').first;
          }
        } else {
          // Try query parameters for other formats
          collectionId = uri.queryParameters['i'] ?? // store.apple.com format
              uri.queryParameters['id']; // alternative format
        }

        Logging.severe('Extracted collection ID:', collectionId);

        if (collectionId != null) {
          // First get the album info
          final url = Uri.parse(
              'https://itunes.apple.com/lookup?id=$collectionId&entity=song');
          final response = await http.get(url);
          final data = jsonDecode(response.body);

          Logging.severe('iTunes API response:', data);

          if (data['results'] != null && data['results'].isNotEmpty) {
            // Filter to get album and its tracks
            final albumData = data['results']
                .where((item) =>
                    item['wrapperType'] == 'collection' ||
                    (item['wrapperType'] == 'track' && item['kind'] == 'song'))
                .toList();

            if (albumData.isNotEmpty) {
              // Add platform identifier
              final album = albumData[0];
              album['platform'] = 'itunes';
              return [album];
            }
          }
        }
      } catch (e) {
        Logging.severe('Error processing iTunes/Apple Music URL', e);
      }
      return [];
    }

    // Handle Bandcamp URLs
    if (query.contains('bandcamp.com')) {
      try {
        final album =
            await _searchBandcamp(query); // This uses the private method
        return album;
      } catch (e) {
        Logging.severe('Error processing Bandcamp URL', e);
      }
      return [];
    }

    // Handle platform-specific searches
    final platform = PlatformService.detectPlatform(query);
    final results = await PlatformService.searchiTunesAlbums(query);
    return results.map((album) => {'platform': platform, ...album}).toList();
  }

  /// Enhanced iTunes search with better handling of clean versions
  static Future<List<dynamic>> searchiTunesAlbums(String query) async {
    try {
      // 1. First search by general term
      final searchUrl = Uri.parse(
          'https://itunes.apple.com/search?term=${Uri.encodeComponent(query)}'
          '&entity=album&limit=50&sort=recent');

      final searchResponse = await http.get(searchUrl);
      final searchData = jsonDecode(searchResponse.body);

      // 2. Search specifically by artist name to improve relevance
      final artistSearchUrl = Uri.parse(
          'https://itunes.apple.com/search?term=${Uri.encodeComponent(query)}'
          '&attribute=artistTerm&entity=album&limit=100');

      final artistSearchResponse = await http.get(artistSearchUrl);
      final artistSearchData = jsonDecode(artistSearchResponse.body);

      // Combine results, filter and handle duplicates
      final Map<String, dynamic> uniqueAlbums = {};

      // Process artist-specific search results (higher priority)
      _processSearchResults(artistSearchData['results'], uniqueAlbums, true);

      // Apply the same deduplication logic to general search results
      _processSearchResults(searchData['results'], uniqueAlbums, false);

      // Filter and sort results
      final validAlbums =
          _filterAndSortAlbums(uniqueAlbums.values.toList(), query);

      // 4. If there's a specific artist match, get their full discography
      if (validAlbums
          .where((a) =>
              a['artistName'].toString().toLowerCase() == query.toLowerCase())
          .isNotEmpty) {
        await _appendArtistDiscography(validAlbums, query);
      }

      return validAlbums;
    } catch (e) {
      Logging.severe('Error searching iTunes albums', e);
      return [];
    }
  }

  /// Fetch album information from Bandcamp
  static Future<Map<String, dynamic>?> fetchBandcampAlbumInfo(
      String url) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final document = parse(response.body);
        var ldJsonScript =
            document.querySelector('script[type="application/ld+json"]');

        if (ldJsonScript != null) {
          final ldJson = jsonDecode(ldJsonScript.text);

          // Extract metadata from JSON-LD
          return {
            'id': ldJson['@id'] ?? url.hashCode,
            'name': ldJson['name'] ?? 'Unknown Album',
            'artist': ldJson['byArtist']?['name'] ?? 'Unknown Artist',
            'artworkUrl': ldJson['image'] ?? '',
            'url': url,
            'platform': 'bandcamp',
            'releaseDate': ldJson['datePublished'],
            'metadata': ldJson,
          };
        }
      }
      throw Exception('Failed to load Bandcamp album');
    } catch (e) {
      Logging.severe('Failed to fetch Bandcamp album info', e);
      return null;
    }
  }

  /// Process search results and handle duplicates
  static void _processSearchResults(List<dynamic> results,
      Map<String, dynamic> uniqueAlbums, bool isArtistSearch) {
    for (var item in results) {
      if (item['wrapperType'] == 'collection' &&
          item['collectionType'] == 'Album') {
        final String albumName = item['collectionName'].toString();
        final String artistName = item['artistName'].toString();

        final String cleanAlbumName = albumName
            .replaceAll(RegExp(r' - Single$'), '')
            .replaceAll(RegExp(r' - EP$'), '');

        final String albumKey = "${artistName}_$cleanAlbumName".toLowerCase();

        if (uniqueAlbums.containsKey(albumKey)) {
          _handleDuplicate(uniqueAlbums, albumKey, item);
        } else {
          _addNewAlbum(uniqueAlbums, albumKey, item);
        }
      }
    }
  }

  /// Handle duplicate album entries
  static void _handleDuplicate(
      Map<String, dynamic> uniqueAlbums, String albumKey, dynamic newItem) {
    final existing = uniqueAlbums[albumKey];

    if ((newItem['trackCount'] ?? 0) > (existing['trackCount'] ?? 0)) {
      uniqueAlbums[albumKey] = newItem;
    }

    if (existing['collectionExplicitness'] !=
        newItem['collectionExplicitness']) {
      if (newItem['collectionExplicitness'] == 'explicit') {
        uniqueAlbums[albumKey] = newItem;
      }

      if (newItem['collectionExplicitness'] == 'cleaned' &&
          !newItem['collectionName'].toString().contains('(Clean)')) {
        final cleanItem = Map<String, dynamic>.from(newItem);
        cleanItem['collectionName'] = "${cleanItem['collectionName']} (Clean)";
        uniqueAlbums["${albumKey}_clean"] = cleanItem;
      }
    }
  }

  /// Add new album to unique albums map
  static void _addNewAlbum(
      Map<String, dynamic> uniqueAlbums, String albumKey, dynamic item) {
    if (item['collectionExplicitness'] == 'cleaned' &&
        !item['collectionName'].toString().contains('(Clean)')) {
      item = Map<String, dynamic>.from(item);
      item['collectionName'] = "${item['collectionName']} (Clean)";
    }

    uniqueAlbums[albumKey] = item;
  }

  /// Filter and sort album results
  static List<dynamic> _filterAndSortAlbums(
      List<dynamic> albums, String query) {
    // Filter out albums with no track information
    final validAlbums = albums.where((album) {
      return album['trackCount'] != null && album['trackCount'] > 0;
    }).toList();

    // Separate exact artist match albums from others
    final artistAlbums = <dynamic>[];
    final otherAlbums = <dynamic>[];

    for (var album in validAlbums) {
      if (album['artistName'].toString().toLowerCase() == query.toLowerCase()) {
        artistAlbums.add(album);
      } else {
        otherAlbums.add(album);
      }
    }

    // Sort by release date (newest first)
    sortByDate(dynamic a, dynamic b) {
      final DateTime dateA = DateTime.parse(a['releaseDate']);
      final DateTime dateB = DateTime.parse(b['releaseDate']);
      return dateB.compareTo(dateA);
    }

    artistAlbums.sort(sortByDate);
    otherAlbums.sort(sortByDate);

    // Combine results prioritizing exact artist match
    return [...artistAlbums, ...otherAlbums];
  }

  /// Append artist's full discography to results
  static Future<void> _appendArtistDiscography(
      List<dynamic> results, String query) async {
    final artistId = results.first['artistId'];
    final artistUrl = Uri.parse('https://itunes.apple.com/lookup?id=$artistId'
        '&entity=album&limit=200');

    final artistResponse = await http.get(artistUrl);
    final artistData = jsonDecode(artistResponse.body);

    for (var item in artistData['results']) {
      if (item['wrapperType'] == 'collection' &&
          item['collectionType'] == 'Album') {
        bool alreadyAdded = results.any((existing) {
          return existing['collectionId'] == item['collectionId'];
        });

        if (!alreadyAdded) {
          if (item['collectionExplicitness'] == 'cleaned' &&
              !item['collectionName'].toString().contains('(Clean)')) {
            item = Map<String, dynamic>.from(item);
            item['collectionName'] = "${item['collectionName']} (Clean)";
          }

          if (item['artistName'].toString().toLowerCase() ==
              query.toLowerCase()) {
            results.insert(
                results
                    .where((a) =>
                        a['artistName'].toString().toLowerCase() ==
                        query.toLowerCase())
                    .length,
                item);
          } else {
            results.add(item);
          }
        }
      }
    }
  }

  static int _parseBandcampDuration(String duration) {
    try {
      final regex = RegExp(r'PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?');
      final match = regex.firstMatch(duration);

      if (match != null) {
        final hours = int.tryParse(match.group(1) ?? '0') ?? 0;
        final minutes = int.tryParse(match.group(2) ?? '0') ?? 0;
        final seconds = int.tryParse(match.group(3) ?? '0') ?? 0;
        return (hours * 3600 + minutes * 60 + seconds) * 1000;
      }
    } catch (e) {
      Logging.severe('Error parsing duration', e);
    }
    return 0;
  }

  /// Search Bandcamp URL - specific handler for Bandcamp URLs
  static Future<List<dynamic>> _searchBandcamp(String url) async {
    try {
      Logging.severe('BANDCAMP SEARCH START: $url');

      // Safety check
      if (url.trim().isEmpty) {
        Logging.severe('BANDCAMP URL EMPTY');
        return [];
      }

      Logging.severe('Processing Bandcamp URL: $url');

      final response = await http.get(Uri.parse(url));

      Logging.severe('BANDCAMP HTTP STATUS: ${response.statusCode}');

      if (response.statusCode != 200) {
        Logging.severe('BANDCAMP HTTP ERROR: ${response.statusCode}');
        return [];
      }

      final document = parse(response.body);

      // Try to get JSON-LD data first (most reliable)
      var ldJsonScript =
          document.querySelector('script[type="application/ld+json"]');

      Logging.severe('BANDCAMP JSON-LD SCRIPT FOUND: ${ldJsonScript != null}');

      if (ldJsonScript != null && ldJsonScript.text.isNotEmpty) {
        try {
          Logging.severe('PARSING BANDCAMP JSON-LD DATA');
          final ldJson = jsonDecode(ldJsonScript.text);
          Logging.severe('BANDCAMP JSON-LD PARSED SUCCESSFULLY');

          // Log important LD+JSON fields
          Logging.severe('BANDCAMP JSON-LD FIELDS:');
          Logging.severe('- @type: ${ldJson['@type']}');
          Logging.severe('- name: ${ldJson['name']}');
          Logging.severe('- byArtist: ${ldJson['byArtist']?['name']}');
          Logging.severe('- image: ${ldJson['image']}');

          // Create unique ID for Bandcamp
          final uniqueId = url.hashCode;
          Logging.severe('BANDCAMP GENERATED ID: $uniqueId');

          final albumData = {
            'collectionId': uniqueId,
            'id': uniqueId,
            'collectionName': ldJson['name'] ?? 'Unknown Album',
            'artistName': ldJson['byArtist']?['name'] ??
                ldJson['author']?['name'] ??
                'Unknown Artist',
            'artworkUrl100': ldJson['image'] ?? '',
            'url': url,
            'platform': 'bandcamp',
            'releaseDate':
                ldJson['datePublished'] ?? DateTime.now().toIso8601String(),
          };

          Logging.severe(
              'BANDCAMP ALBUM DATA CREATED: ${jsonEncode(albumData)}');

          // Process tracks if available
          if (ldJson['track'] != null &&
              ldJson['track']['itemListElement'] != null) {
            Logging.severe('BANDCAMP TRACKS FOUND');
            final tracks = [];
            final trackItems = ldJson['track']['itemListElement'] as List;
            Logging.severe('BANDCAMP TRACK COUNT: ${trackItems.length}');

            for (var item in trackItems) {
              final track = item['item'];
              final position = item['position'] ?? tracks.length + 1;

              var trackId = DateTime.now().millisecondsSinceEpoch;
              try {
                final props = track['additionalProperty'] as List;
                final trackIdProp = props.firstWhere(
                    (p) => p['name'] == 'track_id',
                    orElse: () => {'value': trackId});
                trackId = trackIdProp['value'] ?? trackId;
              } catch (e) {
                Logging.severe('Error extracting track ID: $e');
              }

              tracks.add({
                'trackId': trackId,
                'trackNumber': position,
                'trackName': track['name'] ?? 'Track $position',
                'trackTimeMillis':
                    _parseBandcampDuration(track['duration'] ?? ''),
              });
            }

            albumData['tracks'] = tracks;
            Logging.severe('BANDCAMP TRACKS PROCESSED: ${tracks.length}');
          } else {
            Logging.severe('NO BANDCAMP TRACKS FOUND IN JSON-LD');
          }

          Logging.severe('RETURNING BANDCAMP ALBUM DATA');
          return [albumData];
        } catch (e, stack) {
          Logging.severe('ERROR PARSING BANDCAMP JSON-LD DATA: $e', e, stack);
          // Continue to fallback methods
        }
      }

      // Fallback to meta tags
      Logging.severe('BANDCAMP FALLBACK TO META TAGS');
      final title = document
          .querySelector('meta[property="og:title"]')
          ?.attributes['content'];
      final artist = document
          .querySelector('meta[property="og:site_name"]')
          ?.attributes['content'];
      final artwork = document
          .querySelector('meta[property="og:image"]')
          ?.attributes['content'];

      Logging.severe('BANDCAMP META TAGS:');
      Logging.severe('- title: $title');
      Logging.severe('- artist: $artist');
      Logging.severe('- artwork: $artwork');

      if (title != null) {
        final albumName =
            title.contains(', by') ? title.split(', by').first.trim() : title;
        final artistName = artist ??
            (title.contains(', by')
                ? title.split(', by').last.trim()
                : 'Unknown Artist');

        final albumData = {
          'collectionId': url.hashCode,
          'id': url.hashCode,
          'collectionName': albumName,
          'artistName': artistName,
          'artworkUrl100': artwork ?? '',
          'url': url,
          'platform': 'bandcamp',
          'releaseDate': DateTime.now().toIso8601String(),
        };

        Logging.severe(
            'Created Bandcamp data from meta tags: $albumName by $artistName');
        return [albumData];
      }

      // Last resort - return minimal data
      Logging.severe(
          'Could not extract proper metadata from Bandcamp URL, using fallback');
      final fallbackData = {
        'collectionId': url.hashCode,
        'id': url.hashCode,
        'collectionName': 'Unknown Album',
        'artistName': 'Unknown Artist',
        'artworkUrl100': '',
        'url': url,
        'platform': 'bandcamp',
        'releaseDate': DateTime.now().toIso8601String(),
      };
      Logging.severe('RETURNING BANDCAMP MINIMAL FALLBACK DATA');
      return [fallbackData];
    } catch (e, stack) {
      Logging.severe('ERROR PROCESSING BANDCAMP URL: $e', e, stack);

      final errorFallbackData = {
        'collectionId': url.hashCode,
        'id': url.hashCode,
        'collectionName': 'Unknown Album (Error)',
        'artistName': 'Unknown Artist',
        'artworkUrl100': '',
        'url': url,
        'platform': 'bandcamp',
        'releaseDate': DateTime.now().toIso8601String(),
      };
      Logging.severe('RETURNING BANDCAMP ERROR FALLBACK DATA');
      return [errorFallbackData];
    }
  }
}
