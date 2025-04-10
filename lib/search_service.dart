import 'dart:convert';
import 'package:http/http.dart' as http;
import 'logging.dart';
import 'platform_service.dart';
import 'api_keys.dart';
import 'database/database_helper.dart';
import 'package:sqflite/sqflite.dart';

// Define an enum for the different search platforms
enum SearchPlatform {
  itunes,
  spotify,
  deezer;

  String get displayName {
    switch (this) {
      case SearchPlatform.itunes:
        return 'Apple Music';
      case SearchPlatform.spotify:
        return 'Spotify';
      case SearchPlatform.deezer:
        return 'Deezer';
    }
  }
}

class SearchService {
  // Search albums across multiple platforms
  static Future<List<dynamic>> searchAlbums(String query,
      [SearchPlatform platform = SearchPlatform.itunes]) async {
    try {
      Logging.severe('Searching for "$query" on ${platform.displayName}');

      // Check if the query is a URL
      bool isUrl = query.contains('http');

      // If it's a URL, use the existing platform service to handle it
      if (isUrl) {
        return PlatformService.searchAlbums(query);
      }

      // Otherwise, use platform-specific search
      switch (platform) {
        case SearchPlatform.itunes:
          return await _searchItunes(query);
        case SearchPlatform.spotify:
          return await _searchSpotify(query);
        case SearchPlatform.deezer:
          return await _searchDeezer(query);
      }
    } catch (e, stack) {
      Logging.severe('Error searching albums', e, stack);
      return [];
    }
  }

  // Search on iTunes - using the more sophisticated approach from the original code
  static Future<List<dynamic>> _searchItunes(String query) async {
    try {
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

      return validAlbums;
    } catch (e, stack) {
      Logging.severe('Error searching iTunes', e, stack);
      return [];
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
  static Future<List<dynamic>> _searchSpotify(String query) async {
    try {
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
        return [];
      }

      // Format results to match the expected structure
      return data['albums']['items'].map((album) {
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
    } catch (e, stack) {
      Logging.severe('Error searching Spotify', e, stack);
      return [];
    }
  }

  // Add a new method to get Spotify access token using client credentials flow
  static Future<String> _getSpotifyAccessToken() async {
    try {
      // Use constants directly since ApiKeys values are already constants
      const clientId = ApiKeys.spotifyClientId;
      const clientSecret = ApiKeys.spotifyClientSecret;

      // Encode credentials and create authorization header
      const credentials = "$clientId:$clientSecret";
      final bytes = utf8.encode(credentials);
      final base64Credentials = base64.encode(bytes);

      // Make token request
      final tokenUrl = Uri.parse('https://accounts.spotify.com/api/token');
      final response = await http.post(
        tokenUrl,
        headers: {
          'Authorization': 'Basic $base64Credentials',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {'grant_type': 'client_credentials'},
      );

      if (response.statusCode != 200) {
        Logging.severe(
            'Spotify token error: ${response.statusCode} ${response.body}');
        throw 'Failed to get Spotify token: ${response.statusCode}';
      }

      final data = jsonDecode(response.body);
      if (!data.containsKey('access_token')) {
        throw 'No access token in Spotify response';
      }

      return data['access_token'];
    } catch (e, stack) {
      Logging.severe('Error in _getSpotifyAccessToken', e, stack);
      rethrow;
    }
  }

  // Search on Deezer
  static Future<List<dynamic>> _searchDeezer(String query) async {
    try {
      final encodedQuery = Uri.encodeComponent(query);
      // Increase limit from 25 to 50 to get more results
      final url = Uri.parse(
          'https://api.deezer.com/search/album?q=$encodedQuery&limit=50');

      Logging.severe('Deezer search URL: $url');

      final response = await http.get(url);
      if (response.statusCode != 200) {
        throw 'Deezer API error: ${response.statusCode}';
      }

      final data = jsonDecode(response.body);
      if (!data.containsKey('data')) {
        return [];
      }

      // Log the number of results we're getting
      Logging.severe(
          'Deezer search returned ${data['data'].length} results for query: $query');

      // Format results to match the expected structure
      return data['data'].map<Map<String, dynamic>>((album) {
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
    } catch (e, stack) {
      Logging.severe('Error searching Deezer', e, stack);
      return [];
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
        case 'itunes':
        default:
          return await fetchITunesAlbumDetails(album);
      }
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

  // Save search history to database
  static Future<void> saveSearchHistory(
      String query, SearchPlatform platform) async {
    try {
      final db = await DatabaseHelper.instance.database;

      // Save search query to database
      await db.insert(
        'search_history',
        {
          'query': query,
          'platform': platform.name,
          'timestamp': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      // Don't throw error for search history issues
      Logging.severe('Error saving search history', e);
    }
  }

  // Get recent searches from database
  static Future<List<Map<String, dynamic>>> getRecentSearches(
      {int limit = 10}) async {
    try {
      final db = await DatabaseHelper.instance.database;

      // Get recent searches from database
      return await db.query(
        'search_history',
        orderBy: 'timestamp DESC',
        limit: limit,
      );
    } catch (e) {
      Logging.severe('Error getting recent searches', e);
      return [];
    }
  }
}
