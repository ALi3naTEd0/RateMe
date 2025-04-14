import 'dart:convert';
import 'dart:math' as math; // Add math import for max function
import 'package:http/http.dart' as http;
import 'logging.dart';
import 'platform_service.dart';
import 'api_keys.dart';
import 'database/database_helper.dart';
import 'package:sqflite/sqflite.dart';
import 'platforms/platform_service_factory.dart'; // Add this import

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
      return await searchDiscogs(query);
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
                'nb_tracks': albumData['nb_tracks'] ?? 0
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
      return await fetchITunesAlbumDetails(album);
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

  /// Fetch details for Discogs albums
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

      // Build the API URL
      final apiUrl = '${ApiEndpoints.discogsBaseUrl}/${type}s/$id';

      Logging.severe('Fetching from Discogs API: $apiUrl');

      final response = await http.get(
        Uri.parse(apiUrl),
        headers: {
          'Authorization':
              'Discogs key=${ApiKeys.discogsConsumerKey}, secret=${ApiKeys.discogsConsumerSecret}',
          'User-Agent': 'RateMe/1.0',
        },
      );

      if (response.statusCode != 200) {
        Logging.severe(
            'Discogs API error: ${response.statusCode} - ${response.body}');
        return null;
      }

      final data = jsonDecode(response.body);

      // Extract tracks - FIXED to use integers for track IDs and positions
      final tracks = <Map<String, dynamic>>[];
      if (data['tracklist'] != null) {
        int trackIndex = 0;

        for (var track in data['tracklist']) {
          // Skip headings, indexes, etc.
          if (track['type_'] == 'heading' || track['type_'] == 'index') {
            continue;
          }

          trackIndex++;

          // Create a unique numeric track ID
          int trackId = int.parse(id) * 1000 + trackIndex;

          // Parse duration
          int durationMs = 0;
          if (track['duration'] != null && track['duration'].isNotEmpty) {
            final durationParts = track['duration'].split(':');
            if (durationParts.length == 2) {
              try {
                final minutes = int.parse(durationParts[0]);
                final seconds = int.parse(durationParts[1]);
                durationMs = (minutes * 60 + seconds) * 1000;
              } catch (e) {
                // Ignore parsing errors
              }
            }
          }

          tracks.add({
            'trackId': trackId, // Integer ID
            'trackName': track['title'] ?? 'Track $trackIndex',
            'trackNumber': trackIndex, // Integer position
            'trackTimeMillis': durationMs,
          });
        }
      }

      // Extract artist names
      String artistName = '';
      if (data['artists'] != null) {
        artistName = data['artists'].map((a) => a['name']).join(', ');
      }

      // Add the tracks to the album
      final result = Map<String, dynamic>.from(album);
      result['tracks'] = tracks;
      result['collectionName'] =
          data['title'] ?? album['collectionName'] ?? 'Unknown Album';
      result['artistName'] = artistName.isNotEmpty
          ? artistName
          : (album['artistName'] ?? 'Unknown Artist');
      result['artworkUrl100'] =
          data['images']?[0]?['uri'] ?? album['artworkUrl100'] ?? '';

      Logging.severe(
          'Successfully fetched Discogs album with ${tracks.length} tracks');

      return result;
    } catch (e, stack) {
      Logging.severe('Error fetching Discogs album details', e, stack);
      return album;
    }
  }

  /// Fetch Discogs album details - simplified implementation
  static Future<Map<String, dynamic>?> fetchDiscogsAlbumDetailsSimplified(
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

      // Build the API URL
      final apiUrl = '${ApiEndpoints.discogsBaseUrl}/${type}s/$id';

      Logging.severe('Fetching from Discogs API: $apiUrl');

      final response = await http.get(
        Uri.parse(apiUrl),
        headers: {
          'Authorization':
              'Discogs key=${ApiKeys.discogsConsumerKey}, secret=${ApiKeys.discogsConsumerSecret}',
          'User-Agent': 'RateMe/1.0',
        },
      );

      if (response.statusCode != 200) {
        Logging.severe(
            'Discogs API error: ${response.statusCode} - ${response.body}');
        return null;
      }

      final data = jsonDecode(response.body);

      // Extract tracks - FIXED to use integers for track IDs and positions
      final tracks = <Map<String, dynamic>>[];
      if (data['tracklist'] != null) {
        int trackIndex = 0;

        for (var track in data['tracklist']) {
          // Skip headings, indexes, etc.
          if (track['type_'] == 'heading' || track['type_'] == 'index') {
            continue;
          }

          trackIndex++;

          // Create a unique numeric track ID
          int trackId = int.parse(id) * 1000 + trackIndex;

          // Parse duration
          int durationMs = 0;
          if (track['duration'] != null && track['duration'].isNotEmpty) {
            final durationParts = track['duration'].split(':');
            if (durationParts.length == 2) {
              try {
                final minutes = int.parse(durationParts[0]);
                final seconds = int.parse(durationParts[1]);
                durationMs = (minutes * 60 + seconds) * 1000;
              } catch (e) {
                // Ignore parsing errors
              }
            }
          }

          tracks.add({
            'trackId': trackId, // Integer ID
            'trackName': track['title'] ?? 'Track $trackIndex',
            'trackNumber': trackIndex, // Integer position
            'trackTimeMillis': durationMs,
          });
        }
      }

      // Extract artist names
      String artistName = '';
      if (data['artists'] != null) {
        artistName = data['artists'].map((a) => a['name']).join(', ');
      }

      // IMPROVED ARTWORK HANDLING: Get better quality artwork
      String artworkUrl = album['artworkUrl100'] ?? '';

      if (data['images'] != null &&
          data['images'] is List &&
          data['images'].isNotEmpty) {
        // Get all available images
        List<dynamic> images = data['images'];

        // First try to find the primary image (usually marked as primary: true)
        var primaryImage = images.firstWhere((img) => img['type'] == 'primary',
            orElse: () => null);

        // If no primary image, use the first image
        var selectedImage = primaryImage ?? images.first;

        // Get the highest quality URL
        if (selectedImage != null) {
          // uri = original/full size, uri150 = thumbnail
          // Use the high quality image (uri) rather than the thumbnail (uri150)
          artworkUrl = selectedImage['uri'] ?? artworkUrl;

          Logging.severe('Using high-quality Discogs artwork: $artworkUrl');
        }
      }

      // Add the tracks to the album
      final result = Map<String, dynamic>.from(album);
      result['tracks'] = tracks;
      result['collectionName'] = data['title'] ?? album['collectionName'];
      result['artistName'] =
          artistName.isNotEmpty ? artistName : album['artistName'];
      result['artworkUrl100'] = artworkUrl; // Use the high quality artwork URL
      result['artworkUrl'] =
          artworkUrl; // Also set artworkUrl to ensure consistency

      Logging.severe(
          'Successfully fetched Discogs album with ${tracks.length} tracks');

      return result;
    } catch (e, stack) {
      Logging.severe('Error fetching Discogs album details', e, stack);
      return album;
    }
  }

  /// Fetch the details for a specific album on Discogs
  static Future<Map<String, dynamic>?> fetchDiscogsAlbum(String url) async {
    try {
      Logging.severe('Fetching Discogs album details: $url');

      // Use the factory to create a DiscogsService instance
      final platformFactory = PlatformServiceFactory();
      final discogsService = platformFactory.getService('discogs');

      // Use the service to fetch album details with improved image handling
      final albumDetails = await discogsService.fetchAlbumDetails(url);

      // Log the image URL we got back
      if (albumDetails != null) {
        Logging.severe(
            'Discogs album fetched with artwork URL: ${albumDetails['artworkUrl']}');
      }

      return albumDetails;
    } catch (e, stack) {
      Logging.severe('Error fetching Discogs album details', e, stack);
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

  /// Search Discogs API for albums
  static Future<Map<String, dynamic>?> searchDiscogs(String query,
      {int limit = 25}) async {
    try {
      Logging.severe('Starting Discogs search with query: $query');

      // Check if this is a URL
      if (query.toLowerCase().contains('discogs.com')) {
        Logging.severe('Detected Discogs URL in query: $query');
        // Return a placeholder with the URL for direct handling
        return {
          'results': [
            {
              'collectionId': DateTime.now().millisecondsSinceEpoch,
              'collectionName': 'Loading Discogs Album...',
              'artistName': 'Loading...',
              'artworkUrl100': '',
              'url': query,
              'platform': 'discogs',
            }
          ],
        };
      }

      final List<Map<String, dynamic>> allResults = [];

      // APPROACH 1: First try to find the artist and get their albums
      final artistQuery = Uri.encodeComponent(query);
      final artistUrl = Uri.parse(
          '${ApiEndpoints.discogsBaseUrl}${ApiEndpoints.discogsSearch}?q=$artistQuery&type=artist&per_page=5&key=${ApiKeys.discogsConsumerKey}&secret=${ApiKeys.discogsConsumerSecret}');

      Logging.severe('Discogs API artist search URL: $artistUrl');
      final artistResponse = await http.get(
        artistUrl,
        headers: {
          'Authorization':
              'Discogs key=${ApiKeys.discogsConsumerKey}, secret=${ApiKeys.discogsConsumerSecret}',
          'User-Agent': 'RateMe/1.0',
        },
      );

      if (artistResponse.statusCode == 200) {
        final artistData = jsonDecode(artistResponse.body);
        final artistResults = artistData['results'] as List? ?? [];

        if (artistResults.isNotEmpty) {
          Logging.severe(
              'Discogs found ${artistResults.length} matching artists');

          // Process each artist - prioritize exact name matches
          for (var artist in artistResults.take(2)) {
            // Limit to top 2 artists
            final artistName = artist['title'] ?? '';
            final artistId = artist['id'];

            if (artistId != null) {
              Logging.severe(
                  'Fetching releases for Discogs artist: $artistName (ID: $artistId)');

              // Get the artist's releases
              final releasesUrl = Uri.parse(
                  '${ApiEndpoints.discogsBaseUrl}/artists/$artistId/releases?sort=year&sort_order=desc&per_page=50&key=${ApiKeys.discogsConsumerKey}&secret=${ApiKeys.discogsConsumerSecret}');

              final releasesResponse = await http.get(
                releasesUrl,
                headers: {
                  'Authorization':
                      'Discogs key=${ApiKeys.discogsConsumerKey}, secret=${ApiKeys.discogsConsumerSecret}',
                  'User-Agent': 'RateMe/1.0',
                },
              );

              if (releasesResponse.statusCode == 200) {
                final releasesData = jsonDecode(releasesResponse.body);
                final releases = releasesData['releases'] as List? ?? [];

                // Process the artist's releases
                Logging.severe(
                    'Found ${releases.length} releases by artist $artistName');

                // Filter to just include albums and masters
                final filteredReleases = releases.where((release) {
                  final type = release['type'] ?? '';
                  final role = release['role'] ?? '';

                  // Keep only releases where the artist is the main artist and it's an album or master
                  return role == 'Main' &&
                      (type == 'master' || type == 'release');
                }).toList();

                // Add albums to results
                for (var release in filteredReleases) {
                  try {
                    final releaseType = release['type'] ?? 'release';
                    final releaseId = release['id'];
                    final releaseTitle = release['title'] ?? 'Unknown Album';

                    // Create consistent format URL
                    final url =
                        'https://www.discogs.com/$releaseType/$releaseId';

                    // Ensure we have all the data we need
                    String title = releaseTitle;
                    String artist = artistName;

                    // If title contains " - ", parse it as "Artist - Album"
                    if (title.contains(' - ')) {
                      final parts = title.split(' - ');
                      if (parts.length >= 2) {
                        artist = parts[0];
                        title = parts.sublist(1).join(' - ');
                      }
                    }

                    // Ensure we get the best quality image
                    String artworkUrl = '';
                    if (release['thumb'] != null &&
                        release['thumb'].isNotEmpty) {
                      artworkUrl = release['thumb'];

                      // If there's a cover_image (higher quality), use that instead
                      if (release['cover_image'] != null &&
                          release['cover_image'].isNotEmpty) {
                        artworkUrl = release['cover_image'];
                      }
                    }

                    allResults.add({
                      'collectionId': releaseId,
                      'collectionName': title,
                      'artistName': artist,
                      'artworkUrl100': artworkUrl,
                      'url': url,
                      'platform': 'discogs',
                      'year': release['year'],
                    });

                    Logging.severe(
                        'Adding Discogs artist result: $artist - $title ($url)');
                  } catch (e) {
                    Logging.severe('Error processing Discogs release: $e');
                  }
                }
              }
            }
          }
        }
      }

      // APPROACH 2: Traditional search if we have no or few results
      if (allResults.length < 10) {
        final encodedQuery = Uri.encodeComponent(query);
        final searchUrl = Uri.parse(
            '${ApiEndpoints.discogsBaseUrl}${ApiEndpoints.discogsSearch}?q=$encodedQuery&type=master&format=album&per_page=$limit');

        Logging.severe('Discogs API general search URL: $searchUrl');

        final response = await http.get(
          searchUrl,
          headers: {
            'Authorization':
                'Discogs key=${ApiKeys.discogsConsumerKey}, secret=${ApiKeys.discogsConsumerSecret}',
            'User-Agent': 'RateMe/1.0',
          },
        );

        Logging.severe(
            'Discogs API response status code: ${response.statusCode}');

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);

          if (data['results'] == null || (data['results'] as List).isEmpty) {
            Logging.severe('No results found on Discogs general search');
          } else {
            final results = data['results'] as List;
            Logging.severe(
                'Discogs search found ${results.length} albums in general search');

            // Add results from the general search
            for (var album in results) {
              try {
                // Parse the title to extract artist and album name
                String artist = '';
                String albumTitle = album['title'] ?? 'Unknown Album';

                // Discogs typically formats as "Artist - Album"
                if (albumTitle.contains(' - ')) {
                  final parts = albumTitle.split(' - ');
                  artist = parts[0];
                  albumTitle = parts.sublist(1).join(' - ');
                }

                // Ensure we have a proper URL
                String url = '';
                int masterId = album['master_id'] ?? album['id'] ?? 0;

                url = 'https://www.discogs.com/master/$masterId';

                // Check if we already have this album in our results
                bool isDuplicate = allResults.any((existingAlbum) =>
                    existingAlbum['collectionId'] == masterId ||
                    (existingAlbum['artistName'] == artist &&
                        existingAlbum['collectionName'] == albumTitle));

                // Ensure we get the best quality image
                String artworkUrl = '';
                if (album['thumb'] != null && album['thumb'].isNotEmpty) {
                  artworkUrl = album['thumb'];

                  // If there's a cover_image (higher quality), use that instead
                  if (album['cover_image'] != null &&
                      album['cover_image'].isNotEmpty) {
                    artworkUrl = album['cover_image'];
                  }
                }

                if (!isDuplicate) {
                  Logging.severe(
                      'Adding Discogs result: $artist - $albumTitle ($url)');

                  allResults.add({
                    'collectionId': masterId,
                    'collectionName': albumTitle,
                    'artistName': artist,
                    'artworkUrl100': artworkUrl,
                    'url': url,
                    'platform': 'discogs',
                    'releaseDate':
                        album['year'] != null ? '${album['year']}-01-01' : '',
                  });
                }
              } catch (e) {
                Logging.severe('Error processing Discogs album: $e');
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

  // Search Bandcamp for albums
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

  // Add this helper method to get platform display name
  static String getPlatformDisplayName(SearchPlatform platform) {
    switch (platform) {
      case SearchPlatform.itunes:
        return 'Apple Music';
      case SearchPlatform.spotify:
        return 'Spotify';
      case SearchPlatform.deezer:
        return 'Deezer';
      case SearchPlatform.discogs:
        return 'Discogs';
      case SearchPlatform.bandcamp:
        return 'Bandcamp';
    }
  }

  /// Fetch album details for any platform by URL - this will get high quality artwork
  static Future<Map<String, dynamic>?> fetchAlbumDetails(String url) async {
    try {
      Logging.severe('Fetching album details from URL: $url');

      // Determine which platform service to use
      final platformFactory = PlatformServiceFactory();
      String platformId = 'unknown';

      // Check URL patterns to determine platform
      if (url.contains('music.apple.com') || url.contains('itunes.apple.com')) {
        platformId = 'itunes';
      } else if (url.contains('spotify.com')) {
        platformId = 'spotify';
      } else if (url.contains('deezer.com')) {
        platformId = 'deezer';
      } else if (url.contains('discogs.com')) {
        platformId = 'discogs';
      } else if (url.contains('bandcamp.com')) {
        platformId = 'bandcamp';
      }

      // Get platform service
      final service = platformFactory.getService(platformId);
      final albumDetails = await service.fetchAlbumDetails(url);

      // Upgrade artwork URLs to high resolution versions
      if (albumDetails != null) {
        // Upgrade the primary artwork URL fields
        if (albumDetails.containsKey('artworkUrl')) {
          albumDetails['artworkUrl'] =
              getHighResArtworkUrl(albumDetails['artworkUrl'], platformId);
        }

        if (albumDetails.containsKey('artworkUrl100')) {
          albumDetails['artworkUrl100'] =
              getHighResArtworkUrl(albumDetails['artworkUrl100'], platformId);
        }

        Logging.severe(
            'Fetched album with upgraded artwork URL: ${albumDetails['artworkUrl'] ?? albumDetails['artworkUrl100']}');
      }

      return albumDetails;
    } catch (e, stack) {
      Logging.severe('Error fetching album details', e, stack);
      return null;
    }
  }

  /// Helper function to get high-resolution artwork URL from any platform URL
  static String getHighResArtworkUrl(String url, String platform) {
    if (url.isEmpty) return url;

    try {
      platform = platform.toLowerCase();

      if (platform == 'itunes' || platform == 'apple_music') {
        // For iTunes/Apple Music, replace 100x100 with 600x600
        return url
            .replaceAll('100x100', '600x600')
            .replaceAll('200x200', '600x600');
      } else if (platform == 'spotify') {
        // For Spotify, replace small image URLs with larger versions
        if (url.contains('i.scdn.co/image/')) {
          // Newer Spotify URL format like: https://i.scdn.co/image/{hash}/{size}
          return url
              .replaceAll('/64x64', '/640x640')
              .replaceAll('/300x300', '/640x640');
        } else {
          // Handle older Spotify URL format
          final regex = RegExp(r'\/image\/([a-zA-Z0-9]+)\/([0-9a-z]+)');
          return url.replaceAllMapped(
              regex, (match) => '/image/${match.group(1)}/ab67616d0000b273');
        }
      } else if (platform == 'deezer') {
        // For Deezer, change size to xl or 1000x1000
        return url
            .replaceAll('size=medium', 'size=xl')
            .replaceAll('size=small', 'size=xl')
            .replaceAll('/56x56', '/1000x1000')
            .replaceAll('/120x120', '/1000x1000')
            .replaceAll('/250x250', '/1000x1000')
            .replaceAll('/500x500', '/1000x1000');
      } else if (platform == 'discogs') {
        // For Discogs, try to get high-res version
        if (url.contains('-1.') || url.contains('-150.')) {
          return url.replaceAll('-1.', '-600.').replaceAll('-150.', '-600.');
        }
      }

      // For other platforms or if no specific rule applies, return the original URL
      return url;
    } catch (e) {
      return url; // Return original URL on error
    }
  }

  /// Fetch album details directly from a URL
  static Future<Map<String, dynamic>?> fetchAlbumFromUrl(
      String url, SearchPlatform platform) async {
    try {
      Logging.severe(
          'Fetching album details from URL: $url (platform: ${platform.name})');

      // Extract album ID from URL based on platform
      String? albumId;

      if (platform == SearchPlatform.itunes) {
        // Apple Music URL format: https://music.apple.com/us/album/album-name/id
        // or: https://geo.music.apple.com/us/album/album-name/id
        final regExp = RegExp(r'/album/[^/]+/(\d+)');
        final match = regExp.firstMatch(url);
        if (match != null && match.groupCount >= 1) {
          albumId = match.group(1);
          Logging.severe('Extracted Apple Music album ID: $albumId');
        }
      } else if (platform == SearchPlatform.spotify) {
        // Spotify URL format: https://open.spotify.com/album/id
        final regExp = RegExp(r'/album/([a-zA-Z0-9]+)');
        final match = regExp.firstMatch(url);
        if (match != null && match.groupCount >= 1) {
          albumId = match.group(1);
          Logging.severe('Extracted Spotify album ID: $albumId');
        }
      } else if (platform == SearchPlatform.deezer) {
        // Deezer URL format: https://www.deezer.com/album/id
        final regExp = RegExp(r'/album/(\d+)');
        final match = regExp.firstMatch(url);
        if (match != null && match.groupCount >= 1) {
          albumId = match.group(1);
          Logging.severe('Extracted Deezer album ID: $albumId');
        }
      } else if (platform == SearchPlatform.discogs) {
        // Discogs URL format: https://www.discogs.com/release/id or /master/id
        final regExp = RegExp(r'/(release|master)/(\d+)');
        final match = regExp.firstMatch(url);
        if (match != null && match.groupCount >= 2) {
          albumId = match.group(2);
          Logging.severe('Extracted Discogs album ID: $albumId');
        }
      }

      // If no ID was extracted, return null
      if (albumId == null || albumId.isEmpty) {
        Logging.severe('Could not extract album ID from URL: $url');
        return null;
      }

      // Fetch the album details based on platform and ID
      Map<String, dynamic>? result;

      if (platform == SearchPlatform.itunes) {
        // Use iTunes Lookup API
        final lookupUrl =
            'https://itunes.apple.com/lookup?id=$albumId&entity=song';
        final response = await http.get(Uri.parse(lookupUrl));

        if (response.statusCode == 200) {
          final jsonResponse = json.decode(response.body);
          if (jsonResponse['resultCount'] > 0) {
            // Process the response to get album details with tracks
            result = _processItunesLookupResponse(jsonResponse);
          }
        }
      }

      return result;
    } catch (e) {
      Logging.severe('Error fetching album from URL: $e');
      return null;
    }
  }

  /// Process iTunes lookup response to get album details
  static Map<String, dynamic>? _processItunesLookupResponse(
      Map<String, dynamic> response) {
    try {
      final results = response['results'] as List;
      if (results.isEmpty) return null;

      // The first result is the album
      final albumInfo = results[0];

      // Extract tracks from the remaining results
      final tracks = <Map<String, dynamic>>[];
      for (int i = 1; i < results.length; i++) {
        final track = results[i];
        if (track['wrapperType'] == 'track') {
          tracks.add({
            'trackId': track['trackId'],
            'trackName': track['trackName'],
            'trackNumber': track['trackNumber'],
            'trackTimeMillis': track['trackTimeMillis']
          });
        }
      }

      // Create the album object
      final album = {
        'collectionId': albumInfo['collectionId'],
        'collectionName': albumInfo['collectionName'],
        'artistName': albumInfo['artistName'],
        'artworkUrl100': albumInfo['artworkUrl100'],
        'releaseDate': albumInfo['releaseDate'],
        'url': albumInfo['collectionViewUrl'],
        'platform': 'itunes',
        'tracks': tracks
      };

      Logging.severe(
          'Successfully processed iTunes album: ${album['collectionName']} with ${tracks.length} tracks');

      return {
        'results': [album]
      };
    } catch (e) {
      Logging.severe('Error processing iTunes lookup response: $e');
      return null;
    }
  }

  /// Search for albums
  static Future<List<Map<String, dynamic>>> search(String query,
      {String platform = 'itunes'}) async {
    // Direct URL detection and handling
    if (query.toLowerCase().startsWith('http')) {
      final lowerQuery = query.toLowerCase();

      // Check if this is a direct music platform URL that should be handled specially
      if (lowerQuery.contains('deezer.com/album/') ||
          lowerQuery.contains('music.apple.com/') ||
          lowerQuery.contains('itunes.apple.com/') ||
          lowerQuery.contains('spotify.com/album/') ||
          lowerQuery.contains('discogs.com/')) {
        Logging.severe(
            'Detected direct URL in search: $query - fetching details directly');

        // Determine which platform this URL belongs to
        String urlPlatform = 'unknown';
        if (lowerQuery.contains('deezer.com')) {
          urlPlatform = 'deezer';
        } else if (lowerQuery.contains('music.apple.com') ||
            lowerQuery.contains('itunes.apple.com')) {
          urlPlatform = 'apple_music';
        } else if (lowerQuery.contains('spotify.com')) {
          urlPlatform = 'spotify';
        } else if (lowerQuery.contains('discogs.com')) {
          urlPlatform = 'discogs';
        }

        try {
          // Get the appropriate service for this platform
          final platformFactory = PlatformServiceFactory();
          if (platformFactory.isPlatformSupported(urlPlatform)) {
            final service = platformFactory.getService(urlPlatform);

            // Fetch album details directly using the URL
            final details = await service.fetchAlbumDetails(query);

            if (details != null) {
              Logging.severe('Successfully fetched details directly from URL');
              return [details]; // Return as a single-item list
            } else {
              Logging.severe(
                  'Failed to fetch details from URL, will try standard search');
            }
          }
        } catch (e, stack) {
          Logging.severe('Error fetching album details from URL', e, stack);
        }
      }
    }

    // If we reach here, either:
    // 1. The query is not a URL
    // 2. URL handling failed
    // 3. The URL is not for a supported platform
    // Proceed with standard search...

    // ...existing code for standard search...

    // Add return statement to fix "body_might_complete_normally" error
    return [];
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
        // Partial word-level match score
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

    // Log the normalization result for debugging
    Logging.severe('Normalized "$input" to "$result"');

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
    Logging.severe(
        'Jaccard similarity between "$str1" and "$str2": $similarity');

    return similarity;
  }

  // ...existing code...
}
