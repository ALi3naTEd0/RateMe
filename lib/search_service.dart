import 'dart:convert';
import 'dart:math'
    as math; // Keep this import as it's used in calculateMatchScore
import 'package:http/http.dart' as http;
import 'logging.dart';
import 'platform_service.dart';
import 'api_keys.dart';
import 'database/search_history_db.dart';
import 'database/database_helper.dart';
import 'platforms/platform_service_factory.dart';

/// Enum representing the available search platforms
enum SearchPlatform {
  spotify('Spotify'),
  itunes('iTunes'),
  bandcamp('Bandcamp'),
  deezer('Deezer'),
  discogs('Discogs');

  const SearchPlatform(this.name);
  final String name;

  @override
  String toString() {
    return name;
  }
}

class SearchService {
  final PlatformServiceFactory _factory = PlatformServiceFactory();
  String _defaultPlatform = 'spotify';

  // Fix: Change const to final for variables initialized with future values
  final Future<String?> spotifyClientId = ApiKeys.spotifyClientId;
  final Future<String?> spotifyClientSecret = ApiKeys.spotifyClientSecret;

  // Change to use DatabaseHelper for default platform
  Future<void> initialize() async {
    try {
      final db = DatabaseHelper.instance;
      final storedPlatform = await db.getSetting('defaultSearchPlatform');
      if (storedPlatform != null &&
          _factory.isPlatformSupported(storedPlatform)) {
        _defaultPlatform = storedPlatform;
      }
      Logging.severe(
          'Search service initialized with default platform: $_defaultPlatform');
    } catch (e, stack) {
      Logging.severe('Error initializing search service', e, stack);
    }
  }

  Future<String> getDefaultPlatform() async {
    // Try to get from database first
    final db = DatabaseHelper.instance;
    final storedPlatform = await db.getSetting('defaultSearchPlatform');
    if (storedPlatform != null &&
        _factory.isPlatformSupported(storedPlatform)) {
      _defaultPlatform = storedPlatform;
    }
    return _defaultPlatform;
  }

  Future<void> setDefaultPlatform(String platform) async {
    if (_factory.isPlatformSupported(platform)) {
      _defaultPlatform = platform;
      // Save to database
      final db = DatabaseHelper.instance;
      await db.saveSetting('defaultSearchPlatform', platform);
    }
  }

  /// Search for an album on a given platform
  static Future<Map<String, dynamic>?> searchAlbum(
      String query, SearchPlatform platform) async {
    // Check if the query is a URL first
    String lowerQuery = query.toLowerCase();
    // Override platform based on URL detection
    if (lowerQuery.contains('bandcamp.com')) {
      Logging.severe(
          'URL detection in searchAlbum: Switching to Bandcamp for URL: $query');
      return await searchBandcamp(query);
    } else if (lowerQuery.contains('deezer.com')) {
      Logging.severe(
          'URL detection in searchAlbum: Switching to Deezer for URL: $query');
      return await searchDeezer(query);
    } else if (lowerQuery.contains('spotify.com')) {
      Logging.severe(
          'URL detection in searchAlbum: Switching to Spotify for URL: $query');
      return await searchSpotify(query);
    } else if (lowerQuery.contains('discogs.com')) {
      Logging.severe(
          'URL detection in searchAlbum: Switching to Discogs for URL: $query');
      // Extract release ID and type from URL
      final regExp = RegExp(r'/(master|release)/(\d+)');
      final match = regExp.firstMatch(query);
      if (match != null && match.groupCount >= 2) {
        final type = match.group(1);
        final id = match.group(2);
        Logging.severe('Detected Discogs $type ID: $id');
        try {
          // Fetch basic album info from Discogs API to display a proper preview
          final apiUrl = 'https://api.discogs.com/${type}s/$id';
          final response = await http.get(
            Uri.parse(apiUrl),
            headers: {
              'User-Agent': 'RateMe/1.0',
              'Authorization':
                  'Discogs key=${ApiKeys.discogsConsumerKey}, secret=${ApiKeys.discogsConsumerSecret}',
            },
          );
          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            // Extract title and artist info
            String title = data['title'] ?? 'Unknown Album';
            String artist = '';
            if (type == 'master') {
              if (data['artists'] != null && data['artists'].isNotEmpty) {
                artist = data['artists'][0]['name'] ?? '';
              }
            } else {
              artist = data['artists_sort'] ?? '';
            }
            if (artist.isEmpty) {
              artist = 'Unknown Artist';
            }
            // Get artwork URL if available
            String artworkUrl = '';
            if (data['images'] != null && data['images'].isNotEmpty) {
              artworkUrl = data['images'][0]['uri'] ?? '';
            }
            Logging.severe('Found Discogs album: $artist - $title');
            // Return the album with actual data, plus a flag to indicate this is from a direct URL
            return {
              'results': [
                {
                  'collectionId': id,
                  'collectionName': title,
                  'artistName': artist,
                  'artworkUrl100': artworkUrl,
                  'url': query,
                  'platform': 'discogs',
                  'isDirectUrl':
                      true, // Add this flag to indicate direct URL loading
                  'requiresFullFetch':
                      true // Add this flag to ensure tracks are fetched
                }
              ]
            };
          } else {
            Logging.severe('Discogs API error: ${response.statusCode}');
          }
        } catch (e) {
          Logging.severe('Error fetching Discogs album data: $e');
        }
      } else {
        // Fallback if API call fails
        return {
          'results': [
            {
              'collectionId': match?.group(2) ??
                  'unknown', // Use match?.group(2) instead of undefined 'id'
              'collectionName': 'Discogs Album', // Generic title
              'artistName': 'Loading details...',
              'artworkUrl100': '',
              'url': query,
              'platform': 'discogs',
            }
          ]
        };
      }
      // If URL parsing failed, proceed with search
      platform = SearchPlatform.discogs;
    } else if (lowerQuery.contains('music.apple.com') ||
        lowerQuery.contains('itunes.apple.com')) {
      Logging.severe(
          'URL detection in searchAlbum: Switching to iTunes for URL: $query');
      return await searchITunes(query);
    }
    // If it's not a URL, use the specified platform
    switch (platform) {
      case SearchPlatform.spotify:
        return await searchSpotify(query);
      case SearchPlatform.itunes:
        return await searchITunes(query);
      case SearchPlatform.bandcamp:
        return await searchBandcamp(query);
      case SearchPlatform.deezer:
        return await searchDeezer(query);
      case SearchPlatform.discogs:
        return await searchDiscogs(query);
    }
  }

  /// Method that converts search results to a List format
  /// This addresses the type mismatch in searchAlbums method
  static Future<List<dynamic>> searchAlbums(
      String query, SearchPlatform selectedSearchPlatform) async {
    try {
      // Default to iTunes if not specified
      final results = await searchITunes(query);
      // If results are null, return an empty list
      if (results == null) {
        return [];
      }
      // Extract the results list from the map
      if (results.containsKey('results') && results['results'] is List) {
        return results['results'] as List;
      }
      // Fallback: return an empty list if no results found
      return [];
    } catch (e, stack) {
      Logging.severe('Error in searchAlbums', e, stack);
      return []; // Return empty list on error
    }
  }

  // Search on iTunes - using the more sophisticated approach from the original code
  static Future<Map<String, dynamic>?> searchITunes(String query,
      {int limit = 25}) async {
    try {
      // Check if this is an Apple Music or iTunes URL
      if (query.toLowerCase().contains('music.apple.com') ||
          query.toLowerCase().contains('itunes.apple.com')) {
        Logging.severe('Detected Apple Music/iTunes album URL: $query');
        // Extract the album ID from the URL
        final regExp = RegExp(r'/album/[^/]+/(\d+)');
        final match = regExp.firstMatch(query);
        if (match != null && match.groupCount >= 1) {
          final albumId = match.group(1);
          Logging.severe('Extracted Apple Music album ID from URL: $albumId');
          // Use the iTunes lookup API to get album details
          final lookupUrl = Uri.parse(
              'https://itunes.apple.com/lookup?id=$albumId&entity=song');
          final lookupResponse = await http.get(lookupUrl);
          if (lookupResponse.statusCode == 200) {
            final data = jsonDecode(lookupResponse.body);
            if (data['resultCount'] > 0) {
              // First result is the album, others are the tracks
              final albumInfo = data['results'][0];
              final trackResults = data['results']
                  .sublist(1)
                  .where((item) => item['wrapperType'] == 'track')
                  .toList();
              // Format the album details
              final album = {
                'id': albumInfo['collectionId'],
                'collectionId': albumInfo['collectionId'],
                'name': albumInfo['collectionName'],
                'collectionName': albumInfo['collectionName'],
                'artist': albumInfo['artistName'],
                'artistName': albumInfo['artistName'],
                'artworkUrl':
                    albumInfo['artworkUrl100'].replaceAll('100x100', '600x600'),
                'artworkUrl100': albumInfo['artworkUrl100'],
                'url': albumInfo['collectionViewUrl'],
                'platform': 'itunes',
                'releaseDate': albumInfo['releaseDate'],
                'tracks': trackResults.map<Map<String, dynamic>>((track) {
                  return {
                    'trackId': track['trackId'],
                    'trackName': track['trackName'],
                    'trackNumber': track['trackNumber'],
                    'trackTimeMillis': track['trackTimeMillis'],
                    'artistName': track['artistName'],
                  };
                }).toList(),
              };
              // Return the single album with full details
              Logging.severe(
                  'Found exact Apple Music album from URL with ${trackResults.length} tracks: ${album['collectionName']}');
              return {
                'results': [album]
              };
            }
          }
        }
      }
      // Standard search handling for non-URL queries
      Logging.severe('Performing enhanced iTunes search for: $query');
      // 1. First search by general term (with limit=50)
      final searchUrl = Uri.parse(
          'https://itunes.apple.com/search?term=${Uri.encodeComponent(query)}'
          '&entity=album&limit=50&sort=recent');
      final searchResponse = await http.get(searchUrl);
      if (searchResponse.statusCode != 200) {
        throw 'iTunes API error: ${searchResponse.statusCode}';
      }
      final searchData = jsonDecode(searchResponse.body);
      Logging.severe(
          'iTunes general search returned ${searchData['resultCount']} results');
      // 2. Search specifically by artist name to improve relevance
      final artistSearchUrl = Uri.parse(
          'https://itunes.apple.com/search?term=${Uri.encodeComponent(query)}'
          '&attribute=artistTerm&entity=album&limit=100');
      final artistSearchResponse = await http.get(artistSearchUrl);
      if (artistSearchResponse.statusCode != 200) {
        throw 'iTunes artist search API error: ${artistSearchResponse.statusCode}';
      }
      final artistSearchData = jsonDecode(artistSearchResponse.body);
      Logging.severe(
          'iTunes artist-specific search returned ${artistSearchData['resultCount']} results');
      // Combine results, filter and handle duplicates
      final Map<String, dynamic> uniqueAlbums = {};
      // Process artist-specific search results (higher priority)
      _processSearchResults(artistSearchData['results'], uniqueAlbums, true);
      // Apply the same deduplication logic to general search results
      _processSearchResults(searchData['results'], uniqueAlbums, false);
      // Filter and sort results
      final validAlbums =
          _filterAndSortAlbums(uniqueAlbums.values.toList(), query);
      Logging.severe(
          'iTunes search: ${validAlbums.length} unique albums after deduplication and filtering');
      // 4. If there's a specific artist match, get their full discography
      if (validAlbums
          .where((a) =>
              a['artistName'].toString().toLowerCase() == query.toLowerCase())
          .isNotEmpty) {
        await _appendArtistDiscography(validAlbums, query);
        Logging.severe(
            'iTunes search: appended artist discography, final count: ${validAlbums.length}');
      }
      // Make sure all albums have platform set to 'itunes'
      for (var album in validAlbums) {
        album['platform'] = 'itunes';
      }

      return {'results': validAlbums};
    } catch (e, stack) {
      Logging.severe('Error searching iTunes', e, stack);
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
    try {
      if (results.isEmpty) return;
      final artistId = results.first['artistId'];
      final artistUrl = Uri.parse('https://itunes.apple.com/lookup?id=$artistId'
          '&entity=album&limit=200');
      final artistResponse = await http.get(artistUrl);
      final artistData = jsonDecode(artistResponse.body);
      Logging.severe(
          'Artist discography lookup returned ${artistData['resultCount']} items');
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
    } catch (e, stack) {
      Logging.severe('Error appending artist discography', e, stack);
    }
  }

  // Search on Spotify
  static Future<Map<String, dynamic>?> searchSpotify(String query,
      {int limit = 25}) async {
    try {
      // Check if the query is a Spotify URL
      if (query.toLowerCase().contains('spotify.com') &&
          query.toLowerCase().contains('/album/')) {
        Logging.severe('Detected Spotify album URL: $query');
        // Extract the album ID from the URL
        final regExp = RegExp(r'/album/([a-zA-Z0-9]+)');
        final match = regExp.firstMatch(query);
        if (match != null && match.groupCount >= 1) {
          final albumId = match.group(1);
          Logging.severe('Extracted Spotify album ID from URL: $albumId');
          // Get access token
          final accessToken = await _getSpotifyAccessToken();
          // Use the Spotify API to get album details
          final albumUrl =
              Uri.parse('https://api.spotify.com/v1/albums/$albumId');
          final albumResponse = await http
              .get(albumUrl, headers: {'Authorization': 'Bearer $accessToken'});
          if (albumResponse.statusCode == 200) {
            final albumData = jsonDecode(albumResponse.body);
            // Format as a single result with complete information
            final album = {
              'id': albumData['id'],
              'collectionId': albumData['id'],
              'name': albumData['name'],
              'collectionName': albumData['name'],
              'artist': albumData['artists'][0]['name'],
              'artistName': albumData['artists'][0]['name'],
              'artworkUrl': albumData['images'][0]['url'],
              'artworkUrl100': albumData['images'].length > 1
                  ? albumData['images'][1]['url']
                  : albumData['images'][0]['url'],
              'url': albumData['external_urls']['spotify'],
              'platform': 'spotify',
              'releaseDate': albumData['release_date'],
              'tracks': albumData['tracks']['items']
                  .map<Map<String, dynamic>>((track) {
                return {
                  'trackId': track['id'],
                  'trackName': track['name'],
                  'trackNumber': track['track_number'],
                  'trackTimeMillis': track['duration_ms'],
                  'artistName': track['artists'][0]['name'],
                };
              }).toList(),
            };
            // Return only this single album with full track information
            Logging.severe(
                'Found exact Spotify album from URL with ${album['tracks'].length} tracks: ${album['collectionName']}');
            return {
              'results': [album]
            };
          }
        }
      }
      // Standard search for non-URL queries
      final encodedQuery = Uri.encodeComponent(query);
      // Get access token - fix the authentication method
      String accessToken;
      try {
        // We need to get a proper access token using the client credentials flow
        // Current approach in ApiKeys.getSpotifyToken() just gives a Basic Auth token, not an access token
        accessToken = await _getSpotifyAccessToken();
        Logging.severe(
            'Got Spotify access token: ${accessToken.substring(0, 10)}...');
      } catch (e, stack) {
        Logging.severe('Error getting Spotify token', e, stack);
        throw 'Error getting Spotify token: $e';
      }
      final url = Uri.parse(
          'https://api.spotify.com/v1/search?q=$encodedQuery&type=album&limit=50');
      final response = await http
          .get(url, headers: {'Authorization': 'Bearer $accessToken'});
      if (response.statusCode != 200) {
        throw 'Spotify API error: ${response.statusCode}';
      }
      final data = jsonDecode(response.body);
      if (!data.containsKey('albums') || !data['albums'].containsKey('items')) {
        return null;
      }
      // Format results to match the expected structure
      final results = data['albums']['items'].map((album) {
        return {
          'id': album['id'],
          'collectionId': album['id'],
          'name': album['name'],
          'collectionName': album['name'],
          'artist': album['artists'][0]['name'],
          'artistName': album['artists'][0]['name'],
          'artworkUrl': album['images'][0]['url'],
          'artworkUrl100': album['images'][0]['url'],
          'url': album['external_urls']['spotify'],
          'platform': 'spotify',
          'releaseDate': album['release_date'],
        };
      }).toList();
      return {'results': results};
    } catch (e, stack) {
      Logging.severe('Error searching Spotify', e, stack);
      return null;
    }
  }

  // Add a new method to get Spotify access token using client credentials flow
  static Future<String> _getSpotifyAccessToken() async {
    try {
      // Get API keys from the database
      final clientId = await ApiKeys.spotifyClientId;
      final clientSecret = await ApiKeys.spotifyClientSecret;

      if (clientId == null ||
          clientSecret == null ||
          clientId.isEmpty ||
          clientSecret.isEmpty) {
        Logging.severe('Spotify API credentials not configured or empty');
        return '';
      }

      Logging.severe(
          'Using Spotify credentials - ID length: ${clientId.length}, Secret length: ${clientSecret.length}');

      // Method 1: Send credentials as POST body parameters (what's working in your test)
      final response = await http.post(
        Uri.parse('https://accounts.spotify.com/api/token'),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {
          'grant_type': 'client_credentials',
          'client_id': clientId,
          'client_secret': clientSecret,
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final token = data['access_token'] as String;
        Logging.severe('Successfully obtained Spotify token');
        return token;
      } else {
        // Log the full response body for debugging
        Logging.severe(
            'Spotify token error: ${response.statusCode} ${response.body}');
        throw Exception('Failed to get Spotify token: ${response.statusCode}');
      }
    } catch (e, stack) {
      Logging.severe('Error in _getSpotifyAccessToken', e, stack);
      throw Exception('Error getting Spotify token: $e');
    }
  }

  // Search on Deezer
  static Future<Map<String, dynamic>?> searchDeezer(String query,
      {int limit = 25}) async {
    try {
      // Check if the query is a Deezer URL - modified to handle country-specific URLs
      if (query.toLowerCase().contains('deezer.com') &&
          query.toLowerCase().contains('/album/')) {
        Logging.severe('Detected Deezer album URL: $query');
        // Extract the album ID from the URL - modified to handle country codes
        final RegExp regExp = RegExp(r'/album/(\d+)');
        final match = regExp.firstMatch(query);
        if (match != null && match.groupCount >= 1) {
          final albumId = match.group(1);
          Logging.severe('Extracted Deezer album ID from URL: $albumId');
          // Fetch this specific album directly
          final albumUrl = Uri.parse('https://api.deezer.com/album/$albumId');
          final albumResponse = await http.get(albumUrl);
          if (albumResponse.statusCode == 200) {
            final albumData = jsonDecode(albumResponse.body);
            // Now fetch the track information
            final tracksUrl =
                Uri.parse('https://api.deezer.com/album/$albumId/tracks');
            final tracksResponse = await http.get(tracksUrl);
            if (tracksResponse.statusCode == 200) {
              final tracksData = jsonDecode(tracksResponse.body);
              // Format as a single result with complete information
              final album = {
                'id': albumData['id'],
                'collectionId': albumData['id'],
                'name': albumData['title'],
                'collectionName': albumData['title'],
                'artist': albumData['artist']['name'],
                'artistName': albumData['artist']['name'],
                'artworkUrl': albumData['cover_big'] ??
                    albumData['cover_medium'] ??
                    albumData['cover_small'],
                'artworkUrl100':
                    albumData['cover_medium'] ?? albumData['cover_small'],
                'url': albumData['link'],
                'platform': 'deezer',
                'releaseDate': albumData['release_date'] ??
                    DateTime.now().toIso8601String(),
                'tracks': tracksData['data'].map<Map<String, dynamic>>((track) {
                  return {
                    'trackId': track['id'],
                    'trackName': track['title'],
                    'trackNumber': track['track_position'],
                    'trackTimeMillis': track['duration'] *
                        1000, // Convert seconds to milliseconds
                    'artistName': track['artist']['name'],
                  };
                }).toList(),
                'nb_tracks': albumData['nb_tracks'] ?? 0,
              };
              // Return only this single album with full track information
              Logging.severe(
                  'Found exact Deezer album from URL with ${album['tracks'].length} tracks: ${album['collectionName']}');
              return {
                'results': [album]
              };
            }
          }
        }
      }
      // Standard search for non-URL queries
      final encodedQuery = Uri.encodeComponent(query);
      final url = Uri.parse(
          'https://api.deezer.com/search/album?q=$encodedQuery&limit=50');
      Logging.severe('Deezer search URL: $url');
      final response = await http.get(url);
      if (response.statusCode != 200) {
        throw 'Deezer API error: ${response.statusCode}';
      }
      final data = jsonDecode(response.body);
      if (!data.containsKey('data')) {
        return null;
      }
      // Log the number of results we're getting
      Logging.severe(
          'Deezer search returned ${data['data'].length} results for query: $query');
      // Format results to match the expected structure
      final results = data['data'].map<Map<String, dynamic>>((album) {
        return {
          'id': album['id'],
          'collectionId': album['id'],
          'name': album['title'],
          'collectionName': album['title'],
          'artist': album['artist']['name'],
          'artistName': album['artist']['name'],
          'artworkUrl': album['cover_big'] ??
              album['cover_medium'] ??
              album['cover_small'],
          'artworkUrl100': album['cover_medium'] ?? album['cover_small'],
          'url': album['link'],
          'platform': 'deezer',
          'releaseDate':
              album['release_date'] ?? DateTime.now().toIso8601String(),
        };
      }).toList();
      return {'results': results};
    } catch (e, stack) {
      Logging.severe('Error searching Deezer', e, stack);
      return null;
    }
  }

  // Fetch album tracks for a specific album
  static Future<Map<String, dynamic>?> fetchAlbumTracks(
      Map<String, dynamic> album) async {
    try {
      // Determine platform from album data
      String platform = album['platform'] ?? 'unknown';
      if (platform == 'unknown') {
        // Try to infer platform from URL
        final url = album['url'] ?? '';
        if (url.contains('spotify.com')) {
          platform = 'spotify';
        } else if (url.contains('apple.com') || url.contains('itunes.com')) {
          platform = 'itunes';
        } else if (url.contains('deezer.com')) {
          platform = 'deezer';
        } else if (url.contains('bandcamp.com')) {
          platform = 'bandcamp';
        } else if (url.contains('discogs.com')) {
          platform = 'discogs';
        }
      }
      Logging.severe('Fetching tracks for album on platform: $platform');
      // Use appropriate fetching method based on platform
      switch (platform.toLowerCase()) {
        case 'spotify':
          return await fetchSpotifyAlbumDetails(album);
        case 'deezer':
          return await fetchDeezerAlbumDetails(album);
        case 'bandcamp':
          return await fetchBandcampAlbumDetails(album);
        case 'discogs':
          return await fetchDiscogsAlbumDetails(album);
        case 'itunes':
          return await fetchITunesAlbumDetails(album);
      }
      // Add a fallback return after the switch
      return null;
    } catch (e, stack) {
      Logging.severe('Error fetching album tracks', e, stack);
      return null;
    }
  }

  // Fetch details for Spotify albums
  static Future<Map<String, dynamic>?> fetchSpotifyAlbumDetails(
      Map<String, dynamic> album) async {
    try {
      final albumId = album['id'] ?? album['collectionId'];
      if (albumId == null) return null;
      // Get access token with the correct method
      final accessToken = await _getSpotifyAccessToken();
      // Get album details
      final url = Uri.parse('https://api.spotify.com/v1/albums/$albumId');
      final response = await http
          .get(url, headers: {'Authorization': 'Bearer $accessToken'});
      if (response.statusCode != 200) {
        throw 'Spotify API error: ${response.statusCode}';
      }
      final data = jsonDecode(response.body);
      // Parse tracks
      final tracks = data['tracks']['items'].map<Map<String, dynamic>>((track) {
        return {
          'trackId': track['id'],
          'trackName': track['name'],
          'trackNumber': track['track_number'],
          'trackTimeMillis': track['duration_ms'],
          'artistName': track['artists'][0]['name'],
        };
      }).toList();
      // Return album with tracks
      final result = Map<String, dynamic>.from(album);
      result['tracks'] = tracks;
      return result;
    } catch (e, stack) {
      Logging.severe('Error fetching Spotify album details', e, stack);
      return null;
    }
  }

  // Fetch details for Deezer albums
  static Future<Map<String, dynamic>?> fetchDeezerAlbumDetails(
      Map<String, dynamic> album) async {
    try {
      final albumId = album['id'] ?? album['collectionId'];
      if (albumId == null) return null;
      // Get album tracks
      final url = Uri.parse('https://api.deezer.com/album/$albumId/tracks');
      final response = await http.get(url);
      if (response.statusCode != 200) {
        throw 'Deezer API error: ${response.statusCode}';
      }
      final data = jsonDecode(response.body);
      // Parse tracks
      final tracks = data['data'].map<Map<String, dynamic>>((track) {
        return {
          'trackId': track['id'],
          'trackName': track['title'],
          'trackNumber': track['track_position'],
          'trackTimeMillis':
              track['duration'] * 1000, // Convert seconds to milliseconds
          'artistName': track['artist']['name'],
        };
      }).toList();
      // Return album with tracks
      final result = Map<String, dynamic>.from(album);
      result['tracks'] = tracks;
      return result;
    } catch (e, stack) {
      Logging.severe('Error fetching Deezer album details', e, stack);
      return null;
    }
  }

  // Fetch details for Bandcamp albums
  static Future<Map<String, dynamic>?> fetchBandcampAlbumDetails(
      Map<String, dynamic> album) async {
    try {
      // For Bandcamp, we typically already have the tracks in the album data
      // since it's scraped from the page. If not, we return the album as is.
      if (album.containsKey('tracks') &&
          album['tracks'] is List &&
          (album['tracks'] as List).isNotEmpty) {
        return album;
      }
      // If tracks are missing, we can try to use the platform service
      final albumUrl = album['url'];
      if (albumUrl != null && albumUrl.isNotEmpty) {
        final results = await PlatformService.searchAlbums(albumUrl);
        if (results.isNotEmpty && results[0].containsKey('tracks')) {
          album['tracks'] = results[0]['tracks'];
          return album;
        }
      }
      // For now, return the album as is
      return album;
    } catch (e, stack) {
      Logging.severe('Error fetching Bandcamp album details', e, stack);
      return null;
    }
  }

  // Fetch details for iTunes/Apple Music albums
  static Future<Map<String, dynamic>?> fetchITunesAlbumDetails(
      Map<String, dynamic> album) async {
    try {
      final collectionId = album['collectionId'] ?? album['id'];
      if (collectionId == null) return null;
      // Look up album and tracks
      final url = Uri.parse(
          'https://itunes.apple.com/lookup?id=$collectionId&entity=song');
      final response = await http.get(url);
      if (response.statusCode != 200) {
        throw 'iTunes API error: ${response.statusCode}';
      }
      final data = jsonDecode(response.body);
      // Filter to get just the tracks
      final tracks = data['results']
          .where((item) =>
              item['wrapperType'] == 'track' && item['kind'] == 'song')
          .toList();
      // Return album with tracks
      final result = Map<String, dynamic>.from(album);
      result['tracks'] = tracks;
      return result;
    } catch (e, stack) {
      Logging.severe('Error fetching iTunes album details', e, stack);
      return null;
    }
  }

  /// Fetch details for Discogs albums with smarter version selection for track durations
  static Future<Map<String, dynamic>?> fetchDiscogsAlbumDetails(
      Map<String, dynamic> album) async {
    try {
      Logging.severe('Fetching Discogs album details: ${album['url']}');
      // Extract the ID from the URL
      final RegExp regExp = RegExp(r'/(master|release)/(\d+)');
      final match = regExp.firstMatch(album['url'] as String);
      if (match == null || match.groupCount < 2) {
        Logging.severe(
            'Could not extract ID from Discogs URL: ${album['url']}');
        return null;
      }
      final type = match.group(1);
      final id = match.group(2);
      if (type == null || id == null) {
        return null;
      }
      // Build the API URL with authentication parameters directly in the URL
      final apiUrl =
          'https://api.discogs.com/${type}s/$id?key=${ApiKeys.discogsConsumerKey}&secret=${ApiKeys.discogsConsumerSecret}';
      Logging.severe('Fetching from Discogs API: $apiUrl');
      final response = await http.get(
        Uri.parse(apiUrl),
        headers: {
          'User-Agent': 'RateMe/1.0',
        },
      );
      if (response.statusCode != 200) {
        Logging.severe('Discogs API error: ${response.statusCode}');
        return album; // Return original album on error
      }
      final data = jsonDecode(response.body);
      // Extract artist name
      String artistName = '';
      if (data['artists'] != null) {
        artistName = data['artists'].map((a) => a['name']).join(', ');
      } else if (data['artists_sort'] != null) {
        artistName = data['artists_sort'];
      }
      if (artistName.isEmpty) {
        artistName = album['artistName'] ?? 'Unknown Artist';
      }
      // Extract album title
      final albumTitle =
          data['title'] ?? album['collectionName'] ?? 'Unknown Album';
      // Extract tracks from the current response first
      List<Map<String, dynamic>> tracks = <Map<String, dynamic>>[];
      int trackIndex = 0;
      if (data['tracklist'] != null) {
        for (var track in data['tracklist']) {
          // Skip headings, indexes, etc.
          if (track['type_'] == 'heading' || track['type_'] == 'index') {
            continue;
          }
          trackIndex++;
          // Create a unique numeric track ID
          int trackId = int.parse(id) * 1000 + trackIndex;
          // Extract track artist if available, or use album artist
          String trackArtist = artistName;
          if (track['artists'] != null &&
              track['artists'] is List &&
              track['artists'].isNotEmpty) {
            trackArtist = track['artists'].map((a) => a['name']).join(', ');
          }
          // Parse duration - only if it actually exists
          int durationMs = 0;
          if (track['duration'] != null &&
              track['duration'].toString().trim().isNotEmpty) {
            durationMs = parseTrackDuration(track['duration']);
            Logging.severe(
                'Parsed track ${track['title']}: duration ${track['duration']} -> ${durationMs}ms');
          }
          tracks.add({
            'trackId': trackId,
            'trackName': track['title'] ?? 'Track $trackIndex',
            'trackNumber': trackIndex,
            'trackTimeMillis': durationMs > 0 ? durationMs : null,
            'artistName': trackArtist,
          });
        }
      }
      // Check if we have track durations in the initial response
      bool hasTrackDurations = _tracksHaveDurations(tracks);
      if (hasTrackDurations) {
        Logging.severe('Original response has track durations, using those');
      } else {
        Logging.severe(
            'Original response missing track durations, will search for alternatives');
        // Now we need to build a comprehensive set of versions to try
        final List<Map<String, dynamic>> versionsToTry = [];
        // APPROACH 1: If we have a release, try its master release
        String? masterId;
        if (type == "release" && data['master_id'] != null) {
          masterId = data['master_id'].toString();
          Logging.severe('Found master release ID: $masterId for release: $id');
          versionsToTry.add({
            'id': masterId,
            'type': 'masters',
            'score': 90, // High priority
            'note': 'Master of current release',
          });
        }
        // APPROACH 2: Get specific versions from releases list
        List<dynamic> releasesVersions = [];
        // For a master, get its releases
        if (type == "master") {
          try {
            final releasesUrl =
                'https://api.discogs.com/masters/$id/versions?key=${ApiKeys.discogsConsumerKey}&secret=${ApiKeys.discogsConsumerSecret}';
            final releasesResponse = await http.get(
              Uri.parse(releasesUrl),
              headers: {'User-Agent': 'RateMe/1.0'},
            );
            if (releasesResponse.statusCode == 200) {
              final releasesData = jsonDecode(releasesResponse.body);
              if (releasesData['versions'] != null) {
                releasesVersions = releasesData['versions'];
                Logging.severe(
                    'Found ${releasesVersions.length} releases of master $id');
              }
            }
          } catch (e) {
            Logging.severe('Error fetching master versions: $e');
          }
        }
        // For a specific release, get versions from its master
        else if (masterId != null) {
          try {
            final masterReleasesUrl =
                'https://api.discogs.com/masters/$masterId/versions?key=${ApiKeys.discogsConsumerKey}&secret=${ApiKeys.discogsConsumerSecret}';
            final masterReleasesResponse = await http.get(
              Uri.parse(masterReleasesUrl),
              headers: {'User-Agent': 'RateMe/1.0'},
            );
            if (masterReleasesResponse.statusCode == 200) {
              final masterReleasesData =
                  jsonDecode(masterReleasesResponse.body);
              if (masterReleasesData['versions'] != null) {
                releasesVersions = masterReleasesData['versions'];
                Logging.severe(
                    'Found ${releasesVersions.length} releases from master $masterId');
              }
            }
          } catch (e) {
            Logging.severe('Error fetching master releases: $e');
          }
        }
        // Process and score all available releases
        final preferredCountries = ['US', 'UK', 'Japan', 'Germany', 'France'];
        final preferredFormats = ['CD', 'Digital', 'File', 'Vinyl'];
        for (var version in releasesVersions) {
          if (version['id'] != null) {
            final versionId = version['id'].toString();
            // Skip the current release if it's in the list (already tried it)
            if (type == 'release' && versionId == id) continue;
            // Score this version based on various factors
            int score = 50; // Base score
            // Factor 1: Country preference
            final country = (version['country'] as String?) ?? '';
            if (preferredCountries.contains(country)) {
              score += (5 - preferredCountries.indexOf(country)) * 5;
            }
            // Factor 2: Format preference - formats are often in a list like ["CD", "Album"]
            final format = version['format'] ?? [];
            String formatStr = '';
            if (format is List && format.isNotEmpty) {
              formatStr = format.join(', ');
              for (final preferredFormat in preferredFormats) {
                if (formatStr
                    .toLowerCase()
                    .contains(preferredFormat.toLowerCase())) {
                  score += (4 - preferredFormats.indexOf(preferredFormat)) * 5;
                  break;
                }
              }
            } else if (format is String) {
              formatStr = format;
              for (final preferredFormat in preferredFormats) {
                if (formatStr
                    .toLowerCase()
                    .contains(preferredFormat.toLowerCase())) {
                  score += (4 - preferredFormats.indexOf(preferredFormat)) * 5;
                  break;
                }
              }
            }
            // Factor 3: Major label releases often have better metadata
            final label = version['label'] as String? ?? '';
            if (label.isNotEmpty) {
              score += 5;
            }
            // Factor 4: Newer releases tend to have better data
            final year = version['released'] as String? ?? '';
            if (year.length == 4 && int.tryParse(year) != null) {
              final releaseYear = int.parse(year);
              if (releaseYear >= 2000) {
                score += 10;
              } else if (releaseYear >= 1990) {
                score += 5;
              }
            }
            versionsToTry.add({
              'id': versionId,
              'type': 'releases', // These are always specific releases
              'score': score,
              'note': 'Format: $formatStr, Country: $country',
              'country': country,
              'format': formatStr,
            });
          }
        }
        // Sort versions by score (highest first)
        versionsToTry
            .sort((a, b) => (b['score'] as int).compareTo(a['score'] as int));
        // Increase the number of versions to try - specifically for cases like Lingua Ignota
        final maxVersionsToTry = math.min(15, versionsToTry.length);
        Logging.severe(
            'Will try up to $maxVersionsToTry alternate versions to find track durations:');
        for (int i = 0; i < maxVersionsToTry; i++) {
          final version = versionsToTry[i];
          Logging.severe(
              '  ${i + 1}. ${version['type']}/${version['id']} - Score: ${version['score']} - ${version['note']}');
        }
        // Now systematically try versions until we find durations
        for (int i = 0; i < maxVersionsToTry; i++) {
          final version = versionsToTry[i];
          final versionType = version['type'] as String;
          final versionId = version['id'] as String;
          Logging.severe(
              'Trying ${i + 1}/$maxVersionsToTry: $versionType/$versionId (${version['note']})');
          try {
            final versionUrl =
                'https://api.discogs.com/$versionType/$versionId?key=${ApiKeys.discogsConsumerKey}&secret=${ApiKeys.discogsConsumerSecret}';
            final versionResponse = await http.get(
              Uri.parse(versionUrl),
              headers: {'User-Agent': 'RateMe/1.0'},
            );
            if (versionResponse.statusCode == 200) {
              final versionData = jsonDecode(versionResponse.body);
              if (versionData['tracklist'] != null) {
                // Process tracks from this version
                final versionTracks = _processDiscogsTrackList(
                    versionData['tracklist'], versionId, artistName);

                // Check if these tracks have durations
                final hasVersionDurations = _tracksHaveDurations(versionTracks);
                final durationPercentage =
                    _calculateTrackDurationPercentage(versionTracks);

                Logging.severe(
                    'Version $versionId has ${versionTracks.length} tracks with ${(durationPercentage * 100).toStringAsFixed(1)}% having durations');
                if (hasVersionDurations) {
                  Logging.severe(
                      'Found version with good track durations: $versionType/$versionId');
                  // Lower the threshold for track count difference to better handle variants
                  // Some releases might have a few bonus tracks or slightly different tracklists
                  if (tracks.isEmpty ||
                      (tracks.length - versionTracks.length).abs() <= 3 ||
                      durationPercentage > 0.7) {
                    tracks = versionTracks;
                    hasTrackDurations = true;
                    break; // Stop checking more versions
                  } else {
                    Logging.severe(
                        'Version has different track count (${versionTracks.length} vs ${tracks.length}), continuing search...');
                  }
                }
              }
            }
          } catch (e) {
            Logging.severe('Error fetching version $versionId: $e');
          }
        }
      }
      // If we still don't have track durations, we'll return what we have
      Logging.severe(
          'Final track count: ${tracks.length}, has durations: $hasTrackDurations');
      // Add the tracks to the album
      final result = Map<String, dynamic>.from(album);
      result['tracks'] = tracks;
      result['collectionName'] = albumTitle;
      result['artistName'] = artistName;
      // Add artwork if available and not already in the album data
      if (data['images'] != null &&
          data['images'].isNotEmpty &&
          (album['artworkUrl100'] == null ||
              album['artworkUrl100'].toString().isEmpty)) {
        result['artworkUrl100'] = data['images'][0]['uri'];
      }
      return result;
    } catch (e, stack) {
      Logging.severe('Error fetching Discogs album details', e, stack);
      return album; // Return the original album on error
    }
  }

  /// Process a Discogs tracklist into our standard format
  static List<Map<String, dynamic>> _processDiscogsTrackList(
      List<dynamic> tracklist, String releaseId, String defaultArtistName) {
    final tracks = <Map<String, dynamic>>[];
    int trackIndex = 0;
    for (var track in tracklist) {
      // Skip headings, indexes, etc.
      if (track['type_'] == 'heading' || track['type_'] == 'index') {
        continue;
      }
      trackIndex++;
      // Create a unique numeric track ID
      int trackId = int.parse(releaseId) * 1000 + trackIndex;
      // Extract track artist if available, or use album artist
      String trackArtist = defaultArtistName;
      if (track['artists'] != null &&
          track['artists'] is List &&
          track['artists'].isNotEmpty) {
        trackArtist = track['artists'].map((a) => a['name']).join(', ');
      }
      // Parse duration - only if it actually exists
      int durationMs = 0;
      if (track['duration'] != null &&
          track['duration'].toString().trim().isNotEmpty) {
        durationMs = parseTrackDuration(track['duration']);
        Logging.severe(
            'Parsed track ${track['title']}: duration ${track['duration']} -> ${durationMs}ms');
      }
      tracks.add({
        'trackId': trackId,
        'trackName': track['title'] ?? 'Track $trackIndex',
        'trackNumber': trackIndex,
        'trackTimeMillis': durationMs > 0 ? durationMs : null,
        'artistName': trackArtist,
      });
    }
    return tracks;
  }

  /// Check if a list of tracks has duration information
  static bool _tracksHaveDurations(List<Map<String, dynamic>> tracks) {
    if (tracks.isEmpty) return false;

    // Calculate the percentage of tracks with durations
    final percentage = _calculateTrackDurationPercentage(tracks);
    Logging.severe(
        'Track duration percentage: ${(percentage * 100).toStringAsFixed(1)}%');

    // If more than 30% of tracks have durations, consider it good
    return percentage > 0.3;
  }

  /// Calculate the percentage of tracks with durations
  static double _calculateTrackDurationPercentage(
      List<Map<String, dynamic>> tracks) {
    if (tracks.isEmpty) return 0.0;

    int tracksWithDurations = 0;
    for (var track in tracks) {
      if (track['trackTimeMillis'] != null && track['trackTimeMillis'] > 0) {
        tracksWithDurations++;
      }
    }
    return tracksWithDurations / tracks.length;
  }

  // Add the missing searchBandcamp method
  static Future<Map<String, dynamic>?> searchBandcamp(String query,
      {int limit = 10}) async {
    try {
      Logging.severe('Starting Bandcamp search with query: $query');
      // Check if this is a Bandcamp URL
      if (query.toLowerCase().contains('bandcamp.com')) {
        Logging.severe('Detected Bandcamp URL: $query');
        // Use the PlatformService.fetchBandcampAlbum method to get details
        final album = await PlatformService.fetchBandcampAlbum(query);
        if (album != null) {
          Logging.severe(
              'Successfully fetched Bandcamp album: ${album.name} by ${album.artist}');
          // Convert Album to the standard format expected by the app
          final result = {
            'id': album.id,
            'collectionId': album.id,
            'name': album.name,
            'collectionName': album.name,
            'artist': album.artist,
            'artistName': album.artist,
            'artworkUrl': album.artworkUrl,
            'artworkUrl100': album.artworkUrl,
            'url': album.url,
            'platform': 'bandcamp',
            'releaseDate': album.releaseDate.toIso8601String(),
            'tracks': album.tracks
                .map((track) => {
                      'trackId': track.id,
                      'trackName': track.name,
                      'trackNumber': track.position,
                      'trackTimeMillis': track.durationMs,
                      'artistName': album.artist,
                    })
                .toList(),
          };
          return {
            'results': [result]
          };
        }
        // If direct fetch fails, return a placeholder that indicates we're trying
        return {
          'results': [
            {
              'collectionId': DateTime.now().millisecondsSinceEpoch,
              'collectionName': 'Loading Bandcamp Album...',
              'artistName': 'Please wait...',
              'artworkUrl100': '',
              'url': query,
              'platform': 'bandcamp',
            }
          ]
        };
      }
      // Standard message for non-URL searches
      Logging.severe(
          'Bandcamp search requires a direct URL. Returning empty results.');
      return {
        'results': [],
        'message':
            'Bandcamp search requires direct URL. Please enter a Bandcamp album URL directly.',
        'platform': 'bandcamp',
      };
    } catch (e, stack) {
      Logging.severe('Error in Bandcamp search', e, stack);
      return null;
    }
  }

  // Fix the searchDiscogs method to use artistData variable
  static Future<Map<String, dynamic>?> searchDiscogs(String query,
      {int limit = 25}) async {
    try {
      Logging.severe('Starting Discogs search with query: $query');

      // Use the same credentials method for consistency
      final discogsCredentials = await _getDiscogsCredentials();
      if (discogsCredentials == null) {
        Logging.severe('Discogs API credentials not available');
        return {'results': []};
      }

      final consumerKey = discogsCredentials['key'];
      final consumerSecret = discogsCredentials['secret'];

      // Check if this is a URL
      if (query.toLowerCase().contains('discogs.com')) {
        Logging.severe('Detected Discogs URL in query: $query');
        // Extract ID and type from URL query
        final regExp = RegExp(r'/(master|release)/(\d+)');
        final match = regExp.firstMatch(query);
        if (match != null && match.groupCount >= 2) {
          final type = match.group(1);
          final id = match.group(2);
          Logging.severe('Detected Discogs $type ID: $id');
          try {
            // Use the Discogs API to get basic album details
            final apiUrl = 'https://api.discogs.com/${type}s/$id';
            final response = await http.get(
              Uri.parse(apiUrl),
              headers: {
                'User-Agent': 'RateMe/1.0',
                'Authorization':
                    'Discogs key=$consumerKey, secret=$consumerSecret',
              },
            );
            if (response.statusCode == 200) {
              final data = jsonDecode(response.body);
              // Extract basic info
              String title = data['title'] ?? 'Untitled Album';
              String artist = '';
              if (type == 'master') {
                if (data['artists'] != null && data['artists'].isNotEmpty) {
                  artist = data['artists'][0]['name'] ?? '';
                }
              } else {
                artist = data['artists_sort'] ?? '';
              }
              if (artist.isEmpty) {
                artist = 'Unknown Artist';
              }
              // Get artwork if available
              String artworkUrl = '';
              if (data['images'] != null && data['images'].isNotEmpty) {
                artworkUrl = data['images'][0]['uri'] ?? '';
              }
              // Get release year if available
              String year = '';
              if (data['year'] != null) {
                year = data['year'].toString();
              }
              Logging.severe('Got Discogs album: $artist - $title ($year)');
              // Return the preview with actual data
              return {
                'results': [
                  {
                    'collectionId': id,
                    'collectionName': title,
                    'artistName': artist,
                    'artworkUrl100': artworkUrl,
                    'releaseDate': year.isNotEmpty ? '$year-01-01' : '',
                    'url': query,
                    'platform': 'discogs',
                  }
                ]
              };
            }
          } catch (e) {
            Logging.severe('Error getting Discogs preview data: $e');
          }
        }
      }
      // Continue with regular search if not a URL or URL parsing failed
      final List<Map<String, dynamic>> allResults = [];
      // APPROACH 1: First try to find the album directly
      final albumQuery = Uri.encodeComponent(query);
      final albumUrl = Uri.parse(
          'https://api.discogs.com/database/search?q=$albumQuery&type=master&per_page=20&key=$consumerKey&secret=$consumerSecret');
      Logging.severe('Discogs API album search URL: $albumUrl');
      final albumResponse = await http.get(
        albumUrl,
        headers: {
          'User-Agent': 'RateMe/1.0',
        },
      );
      if (albumResponse.statusCode == 200) {
        final albumData = jsonDecode(albumResponse.body);
        final albumResults = albumData['results'] as List? ?? [];
        Logging.severe('Discogs found ${albumResults.length} matching albums');
        // Process album results
        for (var result in albumResults) {
          if (result['type'] == 'master' || result['type'] == 'release') {
            // Extract needed information
            final id = result['id']?.toString() ?? '';
            final title = result['title'] ?? 'Unknown Album';
            final year = result['year']?.toString() ?? '';
            // Fix URL construction - always use full https://www.discogs.com URL
            String url;
            if (result['uri'] != null &&
                result['uri'].toString().startsWith('http')) {
              // Use the URI if it's a full URL
              url = result['uri'].toString();
            } else {
              // Create proper URL with the domain
              url = 'https://www.discogs.com/${result['type']}/$id';
              Logging.severe('Constructed Discogs URL: $url');
            }
            // Extract artist from title (Discogs format is typically "Artist - Title")
            String artist = 'Unknown Artist';
            if (title.contains(' - ')) {
              final parts = title.split(' - ');
              if (parts.length >= 2) {
                artist = parts[0].trim();
                // Use the part after the first " - " as the actual title
                var actualTitle = parts.sublist(1).join(' - ').trim();
                // Only add if we have valid data
                if (id.isNotEmpty && actualTitle.isNotEmpty) {
                  allResults.add({
                    'collectionId': id,
                    'collectionName': actualTitle,
                    'artistName': artist,
                    'artworkUrl100': result['cover_image'] ?? '',
                    'url': url, // Use the corrected URL
                    'platform': 'discogs',
                    'releaseDate': year.isNotEmpty ? '$year-01-01' : '',
                  });
                }
                continue;
              }
            }
            // If we couldn't split by " - ", just use the whole title
            if (id.isNotEmpty) {
              allResults.add({
                'collectionId': id,
                'collectionName': title,
                'artistName': artist,
                'artworkUrl100': result['cover_image'] ?? '',
                'url': url, // Use the corrected URL
                'platform': 'discogs',
                'releaseDate': year.isNotEmpty ? '$year-01-01' : '',
              });
            }
          }
        }
      }
      // APPROACH 2: If we didn't find enough results, try artist search
      if (allResults.length < 5) {
        // Try to find artist and their releases
        final artistQuery = Uri.encodeComponent(query);
        final artistUrl = Uri.parse(
            'https://api.discogs.com/database/search?q=$artistQuery&type=artist&per_page=5&key=$consumerKey&secret=$consumerSecret');
        Logging.severe('Discogs API artist search URL: $artistUrl');
        final artistResponse = await http.get(
          artistUrl,
          headers: {
            'User-Agent': 'RateMe/1.0',
          },
        );
        if (artistResponse.statusCode == 200) {
          final artistData = jsonDecode(artistResponse.body);
          final artistResults = artistData['results'] as List? ?? [];
          if (artistResults.isNotEmpty) {
            Logging.severe(
                'Discogs found ${artistResults.length} matching artists');
            // Process first artist's releases
            for (int i = 0; i < math.min(2, artistResults.length); i++) {
              final artist = artistResults[i];
              final artistId = artist['id']?.toString();
              if (artistId != null) {
                try {
                  // Get artist's releases
                  final releasesUrl = Uri.parse(
                      'https://api.discogs.com/artists/$artistId/releases?sort=year&sort_order=desc&per_page=20&key=$consumerKey&secret=$consumerSecret');
                  final releasesResponse = await http.get(
                    releasesUrl,
                    headers: {
                      'User-Agent': 'RateMe/1.0',
                    },
                  );
                  if (releasesResponse.statusCode == 200) {
                    final releasesData = jsonDecode(releasesResponse.body);
                    final releases = releasesData['releases'] as List? ?? [];
                    for (var release in releases) {
                      // Only consider proper albums (not appearances on compilations etc)
                      if (release['type'] == 'master' ||
                          release['type'] == 'release') {
                        final id = release['id']?.toString() ?? '';
                        final title = release['title'] ?? 'Unknown Album';
                        final year = release['year']?.toString() ?? '';
                        final artistName = artist['title'] ?? 'Unknown Artist';
                        // Check for duplicates
                        bool isDuplicate = allResults.any((existing) {
                          return existing['collectionId'].toString() == id ||
                              existing['collectionName'] == title;
                        });
                        // Fix URL construction - always use full https://www.discogs.com URL
                        String url;
                        if (release['uri'] != null &&
                            release['uri'].toString().startsWith('http')) {
                          // Use the URI if it's a full URL
                          url = release['uri'].toString();
                        } else {
                          // Create proper URL with the domain
                          url =
                              'https://www.discogs.com/${release['type']}/$id';
                        }
                        if (!isDuplicate && id.isNotEmpty) {
                          allResults.add({
                            'collectionId': id,
                            'collectionName': title,
                            'artistName': artistName,
                            'url': url, // Use the corrected URL
                            'platform': 'discogs',
                            'releaseDate': year.isNotEmpty ? '$year-01-01' : '',
                          });
                        }
                      }
                    }
                  }
                } catch (e) {
                  Logging.severe('Error fetching artist releases: $e');
                }
              }
            }
          }
        }
      }
      Logging.severe('Total Discogs results found: ${allResults.length}');
      return {'results': allResults};
    } catch (e, stack) {
      Logging.severe('Error searching Discogs', e, stack);
      return {'results': []};
    }
  }

  /// Improved helper method to compare artist and album names across platforms
  static double calculateMatchScore(String sourceArtist, String sourceAlbum,
      String targetArtist, String targetAlbum) {
    // Handle null or empty strings gracefully - updated to remove null-aware operators
    sourceArtist = sourceArtist.isEmpty ? '' : sourceArtist;
    sourceAlbum = sourceAlbum.isEmpty ? '' : sourceAlbum;
    targetArtist = targetArtist.isEmpty ? '' : targetArtist;
    targetAlbum = targetAlbum.isEmpty ? '' : targetAlbum;
    // Log inputs for debugging
    Logging.severe(
        'Comparing: "$sourceArtist - $sourceAlbum" with "$targetArtist - $targetAlbum"');
    // First, clean album names by removing EP/Single designations for direct comparison
    final cleanSourceAlbum = removeAlbumSuffixes(sourceAlbum);
    final cleanTargetAlbum = removeAlbumSuffixes(targetAlbum);
    // If clean versions match exactly, short-circuit with a high score (0.95)
    if (cleanSourceAlbum.toLowerCase() == cleanTargetAlbum.toLowerCase() &&
        _normalizeString(sourceArtist) == _normalizeString(targetArtist)) {
      Logging.severe(
          'Album names match after removing suffixes: $cleanSourceAlbum = $cleanTargetAlbum');
      return 0.95;
    }
    // Normalize strings for comparison (lowercase, remove special chars, trim)
    final normalizedSourceArtist = _normalizeString(sourceArtist);
    final normalizedSourceAlbum = _normalizeString(sourceAlbum);
    final normalizedTargetArtist = _normalizeString(targetArtist);
    final normalizedTargetAlbum = _normalizeString(targetAlbum);
    // Artist name matching (0.0 to 1.0)
    double artistScore = 0.0;
    if (normalizedSourceArtist == normalizedTargetArtist) {
      artistScore = 1.0; // Exact match
    } else if (normalizedSourceArtist.contains(normalizedTargetArtist) ||
        normalizedTargetArtist.contains(normalizedSourceArtist)) {
      artistScore = 0.7; // Partial match
    } else {
      // Check for word-level matches (for artist names with multiple words)
      final sourceWords =
          normalizedSourceArtist.split(' ').where((w) => w.length > 2).toList();
      final targetWords =
          normalizedTargetArtist.split(' ').where((w) => w.length > 2).toList();
      // Count matching words
      int matchingWords = 0;
      for (var word in sourceWords) {
        if (targetWords.contains(word)) {
          // Only consider words with 3+ chars
          matchingWords++;
        }
      }
      if (matchingWords > 0) {
        // Partial word-level match
        artistScore = matchingWords /
            math.max(sourceWords.length, targetWords.length) *
            0.5;
      }
    }
    // Album name matching (0.0 to 1.0)
    double albumScore = 0.0;
    // Use the already cleaned album names rather than applying the replacements again
    final normalizedCleanSourceAlbum = _normalizeString(cleanSourceAlbum);
    final normalizedCleanTargetAlbum = _normalizeString(cleanTargetAlbum);
    if (normalizedCleanSourceAlbum == normalizedCleanTargetAlbum) {
      albumScore = 1.0; // Exact match after removing EP/Single designations
      Logging.severe(
          'Album names match exactly after normalization and cleaning');
    } else if (normalizedSourceAlbum == normalizedTargetAlbum) {
      albumScore = 1.0; // Exact match with original names
    } else if (normalizedSourceAlbum.contains(normalizedTargetAlbum) ||
        normalizedTargetAlbum.contains(normalizedSourceAlbum)) {
      albumScore = 0.8; // Partial match
    } else {
      // Check for word-level matches
      double similarity = _calculateJaccardSimilarity(
          normalizedCleanSourceAlbum, normalizedCleanTargetAlbum);
      albumScore = similarity * 0.7; // Scale down a bit
    }
    // Combined score with higher weight on artist match (prevent wrong artist matches)
    final finalScore = (artistScore * 0.7) + (albumScore * 0.3);
    // Log the scoring components and final score
    Logging.severe(
        'Match scores: artist=$artistScore, album=$albumScore, combined=$finalScore');
    return finalScore;
  }

  /// Helper to remove common album suffixes (EP, Single, etc.) - made public
  static String removeAlbumSuffixes(String albumName) {
    String result = albumName;
    // Remove various forms of EP/Single designations
    final suffixRegexps = [
      RegExp(r'\s*-\s*EP$', caseSensitive: false),
      RegExp(r'\s*-\s*Single$', caseSensitive: false),
      RegExp(r'\s*\(EP\)$', caseSensitive: false),
      RegExp(r'\s*\(Single\)$', caseSensitive: false),
      RegExp(r'\s*EP$', caseSensitive: false),
      RegExp(r'\s*Single$', caseSensitive: false),
    ];
    for (var regex in suffixRegexps) {
      if (regex.hasMatch(result)) {
        String beforeChange = result;
        result = result.replaceAll(regex, '').trim();
        Logging.severe('Removed suffix from "$beforeChange" -> "$result"');
      }
    }
    return result;
  }

  /// String normalization helper
  static String _normalizeString(String input) {
    if (input.isEmpty) return '';
    // Convert to lowercase
    String result = input.toLowerCase();
    // Remove special characters but keep spaces
    result = result.replaceAll(RegExp(r'[^\w\s]'), '');
    // Remove extra whitespace
    result = result.replaceAll(RegExp(r'\s+'), ' ').trim();
    return result;
  }

  /// Calculate Jaccard similarity between two strings (word-based)
  static double _calculateJaccardSimilarity(String str1, String str2) {
    if (str1.isEmpty && str2.isEmpty) return 1.0; // Both empty means they match
    if (str1.isEmpty || str2.isEmpty) return 0.0; // One empty means no match

    // Convert strings to word sets, filtering out very short words
    final set1 = str1.split(' ').where((word) => word.length > 2).toSet();
    final set2 = str2.split(' ').where((word) => word.length > 2).toSet();
    // Special case: if either set is empty after filtering
    if (set1.isEmpty || set2.isEmpty) {
      return str1.startsWith(str2) || str2.startsWith(str1) ? 0.5 : 0.0;
    }

    // Calculate intersection and union
    final intersection = set1.intersection(set2);
    final union = set1.union(set2);
    // Calculate Jaccard similarity
    final similarity = union.isEmpty ? 0.0 : intersection.length / union.length;
    return similarity;
  }

  /// Helper method to parse track durations from various formats
  static int parseTrackDuration(dynamic duration) {
    if (duration == null || duration.toString().trim().isEmpty) {
      return 0;
    }
    final durationStr = duration.toString().trim();
    Logging.severe('Parsing track duration: "$durationStr"');
    try {
      // Handle MM:SS format (e.g., "3:45")
      if (durationStr.contains(':')) {
        final parts = durationStr.split(':');
        // Handle HH:MM:SS format
        if (parts.length == 3) {
          final hours = int.tryParse(parts[0].trim()) ?? 0;
          final minutes = int.tryParse(parts[1].trim()) ?? 0;
          final seconds = int.tryParse(parts[2].trim()) ?? 0;
          final result = ((hours * 3600) + (minutes * 60) + seconds) * 1000;
          Logging.severe(
              'Parsed HH:MM:SS format: ${hours}h:${minutes}m:${seconds}s = ${result}ms');
          return result;
        }
        // Handle MM:SS format
        else if (parts.length == 2) {
          final minutes = int.tryParse(parts[0].trim()) ?? 0;
          final seconds = int.tryParse(parts[1].trim()) ?? 0;
          final result = (minutes * 60 + seconds) * 1000;
          Logging.severe(
              'Parsed MM:SS format: ${minutes}m:${seconds}s = ${result}ms');
          return result;
        }
      }
      // Try to handle formats like "3.45" (3 min 45 sec)
      else if (durationStr.contains('.')) {
        final parts = durationStr.split('.');
        if (parts.length == 2) {
          final minutes = int.tryParse(parts[0].trim()) ?? 0;
          // Handle seconds expressed as decimal or as actual seconds
          int seconds;
          if (parts[1].length == 2) {
            // Assuming it's actual seconds (e.g., "3.45" means 3:45)
            seconds = int.tryParse(parts[1].trim()) ?? 0;
          } else {
            // Assuming it's a decimal (e.g., "3.75" means 3m and 45s)
            final decimal = double.tryParse("0.${parts[1]}") ?? 0.0;
            seconds = (decimal * 60).round();
          }
          final result = (minutes * 60 + seconds) * 1000;
          Logging.severe(
              'Parsed decimal format: ${minutes}m:${seconds}s = ${result}ms');
          return result;
        }
      }
      // Try to parse as seconds directly
      final secondsValue = double.tryParse(durationStr);
      if (secondsValue != null) {
        final result = (secondsValue * 1000).round();
        Logging.severe(
            'Parsed direct seconds format: ${secondsValue}s = ${result}ms');
        return result;
      }
      // Handle time formats with text like "3 min 45 sec" or "3:45 min"
      if (durationStr.toLowerCase().contains('min') ||
          durationStr.toLowerCase().contains('sec')) {
        // Handle combined formats like "3:45 min"
        if (durationStr.contains(':') &&
            durationStr.toLowerCase().contains('min')) {
          final timeStr = durationStr.split(' ')[0].trim();
          final parts = timeStr.split(':');
          if (parts.length == 2) {
            final minutes = int.tryParse(parts[0].trim()) ?? 0;
            final seconds = int.tryParse(parts[1].trim()) ?? 0;
            final result = (minutes * 60 + seconds) * 1000;
            Logging.severe(
                'Parsed "MM:SS min" format: ${minutes}m:${seconds}s = ${result}ms');
            return result;
          }
        }
        // Handle "X min Y sec" format
        final minRegex = RegExp(r'(\d+)\s*min');
        final secRegex = RegExp(r'(\d+)\s*sec');
        int minutes = 0;
        int seconds = 0;
        final minMatch = minRegex.firstMatch(durationStr.toLowerCase());
        if (minMatch != null && minMatch.groupCount >= 1) {
          minutes = int.tryParse(minMatch.group(1)?.trim() ?? '0') ?? 0;
        }
        final secMatch = secRegex.firstMatch(durationStr.toLowerCase());
        if (secMatch != null && secMatch.groupCount >= 1) {
          seconds = int.tryParse(secMatch.group(1)?.trim() ?? '0') ?? 0;
        }
        final result = (minutes * 60 + seconds) * 1000;
        Logging.severe(
            'Parsed text format: ${minutes}m:${seconds}s = ${result}ms');
        return result;
      }
      // Special case for single digit like "3" - assume it's minutes
      if (durationStr.length <= 2 && int.tryParse(durationStr) != null) {
        final minutes = int.parse(durationStr);
        final result = minutes * 60 * 1000;
        Logging.severe(
            'Parsed single digit as minutes: ${minutes}m = ${result}ms');
        return result;
      }
      Logging.severe('Could not parse duration format: "$durationStr"');
    } catch (e) {
      Logging.severe('Error parsing track duration: "$durationStr" - $e');
    }
    // If we got here, all parsing attempts failed
    return 0;
  }

  // Find the method that saves search queries
  // Replace it with this version that uses both SharedPreferences and database
  Future<void> saveSearchQuery(String query, String platform) async {
    try {
      // Save to database
      await SearchHistoryDb.saveQuery(query, platform);
    } catch (e) {
      Logging.severe('Error saving search query: $e');
    }
  }

  // Find the method that loads search history
  // Replace it with this version that tries SQLite first
  Future<List<String>> getSearchHistory() async {
    try {
      // 1. Try to get from SQLite first
      final dbHistory = await SearchHistoryDb.getSearchHistory();
      if (dbHistory.isNotEmpty) {
        // Convert from database format to string format
        return dbHistory.map((item) {
          final query = item['query'] as String;
          final platform = item['platform'] as String;
          final timestamp = item['timestamp'] as String;
          return '$query||||$platform||||$timestamp';
        }).toList();
      }
      // 2. Fall back to SharedPreferences if database is empty
      return [];
    } catch (e) {
      Logging.severe('Error getting search history: $e');
      return [];
    }
  }

  // Find the method that clears search history
  // Replace it with this version that clears from both places
  Future<void> clearSearchHistory() async {
    try {
      // Replace SharedPreferences with SearchHistoryDb
      await SearchHistoryDb.clearSearchHistory();
    } catch (e, stack) {
      Logging.severe('Error clearing search history', e, stack);
    }
  }

  // Use database to get recent searches
  Future<List<Map<String, dynamic>>> getRecentSearches() async {
    try {
      // Replace SharedPreferences with SearchHistoryDb
      return await SearchHistoryDb.getSearchHistory(limit: 20);
    } catch (e, stack) {
      Logging.severe('Error getting recent searches', e, stack);
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> searchDiscogsAlbums(String query) async {
    List<Map<String, dynamic>> results = [];

    try {
      Logging.severe('Starting Discogs search with query: $query');

      // Get Discogs API keys
      final discogsConsumerKeyFuture = ApiKeys.discogsConsumerKey;
      final discogsConsumerSecretFuture = ApiKeys.discogsConsumerSecret;

      // Await the futures to get the actual string values
      final discogsConsumerKey = await discogsConsumerKeyFuture;
      final discogsConsumerSecret = await discogsConsumerSecretFuture;

      if (discogsConsumerKey == null || discogsConsumerSecret == null) {
        Logging.severe('Discogs API credentials not configured');
        return [];
      }

      // Now we're working with the string values, not the futures
      final albumsSearchUrl = Uri.parse(
          'https://api.discogs.com/database/search?q=${Uri.encodeComponent(query)}&type=master&per_page=20'
          '&key=$discogsConsumerKey'
          '&secret=$discogsConsumerSecret');

      Logging.severe('Discogs API album search URL: $albumsSearchUrl');
      final albumsResponse = await http.get(albumsSearchUrl);

      final artistsSearchUrl = Uri.parse(
          'https://api.discogs.com/database/search?q=${Uri.encodeComponent(query)}&type=artist&per_page=5'
          '&key=$discogsConsumerKey'
          '&secret=$discogsConsumerSecret');

      Logging.severe('Discogs API artist search URL: $artistsSearchUrl');
      // Instead of awaiting here, make the request but don't save the response to a variable
      // This avoids the unused variable warning
      http.get(artistsSearchUrl).then((artistsResponse) {
        // Process artistsResponse inside this callback if needed
        if (artistsResponse.statusCode == 200) {
          final data = jsonDecode(artistsResponse.body);
          final artistResults = data['results'] as List<dynamic>? ?? [];
          if (artistResults.isNotEmpty) {
            Logging.severe(
                'Found ${artistResults.length} artist results in callback');
          }
        }
      });

      // Process albumsResponse
      if (albumsResponse.statusCode == 200) {
        final data = jsonDecode(albumsResponse.body);
        final albumResults = data['results'] as List<dynamic>? ?? [];

        for (var result in albumResults) {
          // Process each album result
          results.add(result);
        }
      }

      Logging.severe('Total Discogs results found: ${results.length}');
    } catch (e, stack) {
      Logging.severe('Error searching Discogs', e, stack);
    }

    return results;
  }

  // Fix the discogs API key issue in search_service.dart
  Future<List<Map<String, dynamic>>> searchDiscogsAlbumsInstance(
      String query) async {
    List<Map<String, dynamic>> results = [];

    try {
      Logging.severe('Starting Discogs search with query: $query');

      // Get the Discogs API keys the same way we get Spotify keys
      final discogsCredentials = await _getDiscogsCredentials();
      if (discogsCredentials == null) {
        Logging.severe('Discogs API credentials not available');
        return [];
      }

      final consumerKey = discogsCredentials['key'];
      final consumerSecret = discogsCredentials['secret'];

      // Now use the actual string values in the URL
      final albumsSearchUrl = Uri.parse(
          'https://api.discogs.com/database/search?q=${Uri.encodeComponent(query)}&type=master&per_page=20'
          '&key=$consumerKey'
          '&secret=$consumerSecret');

      Logging.severe('Discogs API album search URL: $albumsSearchUrl');
      final albumsResponse = await http.get(albumsSearchUrl);

      final artistsSearchUrl = Uri.parse(
          'https://api.discogs.com/database/search?q=${Uri.encodeComponent(query)}&type=artist&per_page=5'
          '&key=$consumerKey'
          '&secret=$consumerSecret');

      Logging.severe('Discogs API artist search URL: $artistsSearchUrl');
      // Make the request without storing the response (since it's not used)
      await http.get(artistsSearchUrl);

      // Process the responses
      if (albumsResponse.statusCode == 200) {
        final albumData = jsonDecode(albumsResponse.body);
        if (albumData['results'] != null) {
          final albumResults = albumData['results'] as List;
          for (var result in albumResults) {
            results.add(result);
          }
        }
      }

      Logging.severe('Total Discogs results found: ${results.length}');
    } catch (e, stack) {
      Logging.severe('Error searching Discogs', e, stack);
    }

    return results;
  }

  // Add a helper method to get Discogs credentials, similar to the Spotify one
  static Future<Map<String, String>?> _getDiscogsCredentials() async {
    try {
      // Try database approach first
      final db = DatabaseHelper.instance;
      final consumerKey = await db.getSetting('discogsConsumerKey');
      final consumerSecret = await db.getSetting('discogsConsumerSecret');

      // If found in database, use those values
      if (consumerKey != null &&
          consumerSecret != null &&
          consumerKey.isNotEmpty &&
          consumerSecret.isNotEmpty) {
        Logging.severe('Successfully loaded Discogs credentials from database');
        return {'key': consumerKey, 'secret': consumerSecret};
      }

      // If not found in database, fall back to ApiKeys class
      Logging.severe(
          'Discogs keys not found in database, trying ApiKeys class');

      // Get the key and secret from ApiKeys class and wait for the Future to complete
      final apiKeyConsumerKey = await ApiKeys.discogsConsumerKey;
      final apiKeyConsumerSecret = await ApiKeys.discogsConsumerSecret;

      if (apiKeyConsumerKey != null &&
          apiKeyConsumerSecret != null &&
          apiKeyConsumerKey.isNotEmpty &&
          apiKeyConsumerSecret.isNotEmpty) {
        Logging.severe(
            'Successfully loaded Discogs credentials from ApiKeys class');

        // Also save them to the database for future use
        await db.saveSetting('discogsConsumerKey', apiKeyConsumerKey);
        await db.saveSetting('discogsConsumerSecret', apiKeyConsumerSecret);

        return {'key': apiKeyConsumerKey, 'secret': apiKeyConsumerSecret};
      }

      Logging.severe(
          'Discogs API credentials not found in either database or ApiKeys class');
      return null;
    } catch (e, stack) {
      Logging.severe('Error getting Discogs credentials', e, stack);
      return null;
    }
  }
}
