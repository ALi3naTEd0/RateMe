import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:html/parser.dart' show parse;
import 'package:intl/intl.dart';
import 'album_model.dart';
import 'logging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_keys.dart'; // Add this import
import 'dart:io'; // Add this import

/// Service to handle interactions with different music platforms
class PlatformService {
  // Add Spotify API constants
  static const String _spotifyTokenEndpoint =
      'https://accounts.spotify.com/api/token';
  static const String _spotifySearchEndpoint =
      'https://api.spotify.com/v1/search';
  static const String _spotifyAlbumEndpoint =
      'https://api.spotify.com/v1/albums';

  // Update to use the imported API keys from api_keys.dart
  static const String _spotifyClientId = ApiKeys.spotifyClientId;
  static const String _spotifyClientSecret = ApiKeys.spotifyClientSecret;

  // Token storage keys
  static const String _spotifyTokenKey = 'spotify_access_token';
  static const String _spotifyTokenExpiryKey = 'spotify_token_expiry';

  // Add Deezer API endpoints
  static const String _deezerSearchEndpoint = 'https://api.deezer.com/search';
  static const String _deezerAlbumEndpoint = 'https://api.deezer.com/album';

  /// Detect platform from URL or search term
  static String detectPlatform(String input) {
    if (input.contains('music.apple.com') ||
        input.contains('itunes.apple.com')) {
      return 'itunes';
    } else if (input.contains('bandcamp.com')) {
      return 'bandcamp';
    } else if (input.contains('spotify.com') ||
        input.contains('open.spotify')) {
      return 'spotify';
    } else if (input.contains('deezer.com')) {
      return 'deezer';
    } else {
      // Default to iTunes for search terms
      return 'itunes';
    }
  }

  // Change from variable to function declaration
  static Map<String, dynamic> normalizeResult(
      Map<String, dynamic> album, String platform) {
    album['platform'] = platform;
    return album;
  }

  /// Search for albums across all platforms
  static Future<List<dynamic>> searchAlbums(String query) async {
    if (query.isEmpty) return [];

    // Handle iTunes/Apple Music URLs
    if (query.contains('music.apple.com') ||
        query.contains('itunes.apple.com')) {
      try {
        final uri = Uri.parse(query);
        final pathSegments = uri.pathSegments;

        String? collectionId;
        if (pathSegments.contains('album')) {
          final albumIdIndex = pathSegments.indexOf('album') + 2;
          if (albumIdIndex < pathSegments.length) {
            collectionId = pathSegments[albumIdIndex].split('?').first;
          }
        } else {
          collectionId = uri.queryParameters['i'] ?? uri.queryParameters['id'];
        }

        if (collectionId != null) {
          final url = Uri.parse(
              'https://itunes.apple.com/lookup?id=$collectionId&entity=song');
          final response = await http.get(url);
          final data = jsonDecode(response.body);

          if (data['results'] != null && data['results'].isNotEmpty) {
            // Get album info (first result)
            final albumInfo = data['results'][0];

            // Get tracks (remaining results)
            final tracks = data['results']
                .skip(1) // Skip the first result (album info)
                .where((item) =>
                    item['wrapperType'] == 'track' && item['kind'] == 'song')
                .toList();

            // Add tracks to album info
            albumInfo['tracks'] = tracks;

            // Return just the album with its tracks
            return [normalizeResult(albumInfo, 'itunes')];
          }
        }
      } catch (e) {
        Logging.severe('Error processing iTunes/Apple Music URL', e);
      }
      return [];
    }

    // Handle Spotify URLs
    if (query.contains('spotify.com') || query.contains('open.spotify')) {
      try {
        final albumId = _extractSpotifyAlbumId(query);
        if (albumId != null) {
          Logging.severe('Spotify album ID extracted: $albumId');
          final album = await fetchSpotifyAlbum(albumId);
          return album != null ? [normalizeResult(album, 'spotify')] : [];
        } else {
          Logging.severe('Could not extract Spotify album ID from URL: $query');
        }
      } catch (e) {
        Logging.severe('Error processing Spotify URL', e);
      }
      return [];
    }

    // Handle Deezer URLs
    if (query.contains('deezer.com')) {
      try {
        final albumId = _extractDeezerAlbumId(query);
        if (albumId != null) {
          Logging.severe('Deezer album ID extracted: $albumId');
          final album = await fetchDeezerAlbum(albumId);
          return album != null ? [normalizeResult(album, 'deezer')] : [];
        } else {
          Logging.severe('Could not extract Deezer album ID from URL: $query');
        }
      } catch (e) {
        Logging.severe('Error processing Deezer URL', e);
      }
      return [];
    }

    // Handle platform-specific searches
    final platform = detectPlatform(query);
    try {
      switch (platform) {
        case 'spotify':
          final results = await searchSpotifyAlbums(query);
          return results
              .map((album) => normalizeResult(album, 'spotify'))
              .toList();
        case 'bandcamp':
          final album = await fetchBandcampAlbum(query);
          return album != null
              ? [normalizeResult(album.toJson(), 'bandcamp')]
              : [];
        case 'deezer':
          final results = await searchDeezerAlbums(query);
          return results
              .map((album) => normalizeResult(album, 'deezer'))
              .toList();
        case 'itunes':
        default:
          final results = await searchiTunesAlbums(query);
          return results
              .map((album) => normalizeResult(album, 'itunes'))
              .toList();
      }
    } catch (e) {
      Logging.severe('Error searching albums', e);
      return [];
    }
  }

  /// Extract Spotify album ID from URL
  static String? _extractSpotifyAlbumId(String url) {
    try {
      final uri = Uri.parse(url);
      final pathSegments = uri.pathSegments;

      // Handle different Spotify URL formats
      if (pathSegments.contains('album') &&
          pathSegments.length > pathSegments.indexOf('album') + 1) {
        return pathSegments[pathSegments.indexOf('album') + 1];
      }

      // Handle shortened URLs that redirect
      if (pathSegments.isNotEmpty && pathSegments.last.length >= 22) {
        // This might be an album ID directly in the path
        return pathSegments.last;
      }

      return null;
    } catch (e) {
      Logging.severe('Error extracting Spotify album ID', e);
      return null;
    }
  }

  /// Extract Deezer album ID from URL
  static String? _extractDeezerAlbumId(String url) {
    try {
      final uri = Uri.parse(url);
      final pathSegments = uri.pathSegments;

      // Handle standard Deezer URLs: https://www.deezer.com/album/12345
      if (pathSegments.contains('album') &&
          pathSegments.length > pathSegments.indexOf('album') + 1) {
        return pathSegments[pathSegments.indexOf('album') + 1];
      }

      // Handle alternative formats: https://www.deezer.com/en/album/12345
      for (int i = 0; i < pathSegments.length - 1; i++) {
        if (pathSegments[i] == 'album' && pathSegments.length > i + 1) {
          return pathSegments[i + 1];
        }
      }

      return null;
    } catch (e) {
      Logging.severe('Error extracting Deezer album ID', e);
      return null;
    }
  }

  /// Get Spotify access token
  static Future<String?> _getSpotifyToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final storedToken = prefs.getString(_spotifyTokenKey);
      final expiryTime = prefs.getInt(_spotifyTokenExpiryKey) ?? 0;

      // Check if token is still valid
      if (storedToken != null &&
          expiryTime > DateTime.now().millisecondsSinceEpoch) {
        Logging.severe('Using cached Spotify token');
        return storedToken;
      }

      Logging.severe('Requesting new Spotify token');

      // Get new token
      final basicAuth =
          base64Encode(utf8.encode('$_spotifyClientId:$_spotifyClientSecret'));
      final response = await http.post(
        Uri.parse(_spotifyTokenEndpoint),
        headers: {
          'Authorization': 'Basic $basicAuth',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {'grant_type': 'client_credentials'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final accessToken = data['access_token'];
        final expiresIn = data['expires_in'] as int; // Ensure this is an int

        // Save token with expiry time - make sure it's an int
        final expiryTimeMs =
            DateTime.now().millisecondsSinceEpoch + (expiresIn * 1000);
        await prefs.setString(_spotifyTokenKey, accessToken);
        await prefs.setInt(_spotifyTokenExpiryKey, expiryTimeMs);

        Logging.severe(
            'New Spotify token obtained, expires in $expiresIn seconds');
        return accessToken;
      } else {
        Logging.severe(
            'Failed to get Spotify token: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e) {
      Logging.severe('Error getting Spotify token', e);
      return null;
    }
  }

  /// Search Spotify for albums
  static Future<List<dynamic>> searchSpotifyAlbums(String query) async {
    try {
      Logging.severe('Searching Spotify for: $query');
      final token = await _getSpotifyToken();
      if (token == null) {
        Logging.severe('No Spotify token available');
        return [];
      }

      final url = Uri.parse(
          '$_spotifySearchEndpoint?q=${Uri.encodeComponent(query)}&type=album&limit=50');
      final response = await http.get(
        url,
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode != 200) {
        Logging.severe(
            'Spotify search failed: ${response.statusCode} - ${response.body}');
        return [];
      }

      final data = jsonDecode(response.body);
      final albums = data['albums']['items'] as List;
      Logging.severe('Found ${albums.length} Spotify albums');

      // For performance reasons, only get full details for top 5 albums
      final List<dynamic> result = [];
      for (var i = 0; i < albums.length && i < 5; i++) {
        final fullAlbum = await fetchSpotifyAlbum(albums[i]['id']);
        if (fullAlbum != null) {
          result.add(fullAlbum);
        }
      }

      // For remaining albums, add basic info without tracks
      if (albums.length > 5) {
        for (var i = 5; i < albums.length; i++) {
          var album = albums[i];
          result.add({
            'collectionId': album['id'],
            'collectionName': album['name'],
            'artistName': album['artists'][0]['name'],
            'artworkUrl100':
                album['images'].isNotEmpty ? album['images'][0]['url'] : '',
            'url': album['external_urls']['spotify'],
            'platform': 'spotify',
            'releaseDate': album['release_date'],
            'trackCount': album['total_tracks'],
            'wrapperType': 'collection',
            'collectionType': 'Album',
            'tracks': [], // Empty tracks for basic info
            'metadata': album,
          });
        }
      }

      return result;
    } catch (e) {
      Logging.severe('Error searching Spotify albums', e);
      return [];
    }
  }

  /// Search Deezer for albums
  static Future<List<dynamic>> searchDeezerAlbums(String query) async {
    try {
      Logging.severe('Searching Deezer for: $query');

      final url = Uri.parse(
          '$_deezerSearchEndpoint/album?q=${Uri.encodeComponent(query)}&limit=50');
      final response = await http.get(url);

      if (response.statusCode != 200) {
        Logging.severe(
            'Deezer search failed: ${response.statusCode} - ${response.body}');
        return [];
      }

      final data = jsonDecode(response.body);
      final albums = data['data'] as List;
      Logging.severe('Found ${albums.length} Deezer albums');

      // For performance reasons, only get full details for top 5 albums
      final List<dynamic> result = [];
      for (var i = 0; i < albums.length && i < 5; i++) {
        final fullAlbum = await fetchDeezerAlbum(albums[i]['id'].toString());
        if (fullAlbum != null) {
          result.add(fullAlbum);
        }
      }

      // For remaining albums, add basic info without tracks
      if (albums.length > 5) {
        for (var i = 5; i < albums.length; i++) {
          var album = albums[i];
          result.add({
            'id': album['id'],
            'collectionId': album['id'],
            'name': album['title'],
            'collectionName': album['title'],
            'artist': album['artist']['name'],
            'artistName': album['artist']['name'],
            'artworkUrl':
                album['cover_xl'] ?? album['cover_big'] ?? album['cover'],
            'artworkUrl100': album['cover'],
            'url': album['link'],
            'platform': 'deezer',
            'releaseDate': album['release_date'],
            'trackCount': album['nb_tracks'],
            'metadata': album,
          });
        }
      }

      return result;
    } catch (e) {
      Logging.severe('Error searching Deezer albums', e);
      return [];
    }
  }

  /// Fetch a Spotify album by ID
  static Future<Map<String, dynamic>?> fetchSpotifyAlbum(String albumId) async {
    try {
      Logging.severe('Fetching Spotify album: $albumId');
      final token = await _getSpotifyToken();
      if (token == null) return null;

      final url = Uri.parse('$_spotifyAlbumEndpoint/$albumId');
      final response = await http.get(
        url,
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode != 200) {
        Logging.severe('Failed to fetch Spotify album: ${response.statusCode}');
        return null;
      }

      final spotifyAlbum = jsonDecode(response.body);

      // Log entire album response for debugging
      Logging.severe('Spotify album raw data: ${jsonEncode({
            'id': spotifyAlbum['id'],
            'name': spotifyAlbum['name'],
            'artist': spotifyAlbum['artists'][0]['name'],
            'images': spotifyAlbum['images'],
            'urls': spotifyAlbum['external_urls'],
            'releaseDate': spotifyAlbum['release_date'],
            'totalTracks': spotifyAlbum['total_tracks'],
          })}');

      // Fetch tracks (in batches if necessary since Spotify might paginate tracks)
      List<dynamic> allTracks = [];
      String? tracksUrl = spotifyAlbum['tracks']['href'];

      while (tracksUrl != null) {
        final tracksResponse = await http.get(
          Uri.parse(tracksUrl),
          headers: {'Authorization': 'Bearer $token'},
        );

        if (tracksResponse.statusCode == 200) {
          final tracksData = jsonDecode(tracksResponse.body);
          allTracks.addAll(tracksData['items']);
          tracksUrl = tracksData['next']; // Move to next page or null

          // Log first track for debugging
          if (tracksData['items'].isNotEmpty) {
            final firstTrack = tracksData['items'][0];
            Logging.severe('First track sample: ${jsonEncode({
                  'id': firstTrack['id'],
                  'name': firstTrack['name'],
                  'track_number': firstTrack['track_number'],
                  'duration_ms': firstTrack['duration_ms'],
                  'artists':
                      firstTrack['artists'].map((a) => a['name']).toList(),
                  'preview_url': firstTrack['preview_url'],
                })}');
          }
        } else {
          tracksUrl = null;
        }
      }

      // Log track count
      Logging.severe(
          'Found ${allTracks.length} tracks for Spotify album $albumId');

      // Convert to standardized format - make sure all required fields are present
      final result = {
        'id': spotifyAlbum['id'],
        'collectionId': spotifyAlbum['id'],
        'name': spotifyAlbum['name'],
        'collectionName': spotifyAlbum['name'],
        'artist': spotifyAlbum['artists'][0]['name'],
        'artistName': spotifyAlbum['artists'][0]['name'],
        'artworkUrl': spotifyAlbum['images'].isNotEmpty
            ? spotifyAlbum['images'][0]['url']
            : '',
        'artworkUrl100': spotifyAlbum['images'].isNotEmpty
            ? spotifyAlbum['images'][0]['url']
            : '',
        'url': spotifyAlbum['external_urls']['spotify'],
        'platform': 'spotify',
        'releaseDate': spotifyAlbum['release_date'],
        'trackCount': spotifyAlbum['total_tracks'],
        'wrapperType': 'collection',
        'collectionType': 'Album',
        'tracks': allTracks.map((track) {
          // Extract track duration_ms in a way that safely converts to int
          int trackDuration = 0;
          if (track['duration_ms'] != null) {
            if (track['duration_ms'] is int) {
              trackDuration = track['duration_ms'];
            } else {
              trackDuration = (track['duration_ms'] as num).toInt();
            }
          }

          return {
            'id': track['id'],
            'trackId': track['id'],
            'trackNumber': track['track_number'],
            'position': track['track_number'],
            'trackName': track['name'],
            'name': track['name'],
            'trackTimeMillis': trackDuration,
            'durationMs': trackDuration,
            'kind': 'song',
            'wrapperType': 'track',
            'artistName': track['artists'][0]['name'],
            'artist': track['artists'][0]['name'],
            'previewUrl': track['preview_url'],
          };
        }).toList(),
        'metadata': spotifyAlbum,
      };

      // Final debugging before returning
      Logging.severe('Converted Spotify album to app format: ${jsonEncode({
            'id': result['id'],
            'name': result['name'],
            'artist': result['artist'],
            'tracks': 'Array with ${result['tracks'].length} tracks',
            'trackKeys': result['tracks'].isNotEmpty
                ? result['tracks'][0].keys.toList()
                : [],
          })}');

      return result;
    } catch (e, stack) {
      Logging.severe('Error fetching Spotify album', e, stack);
      return null;
    }
  }

  /// Fetch a Deezer album by ID
  static Future<Map<String, dynamic>?> fetchDeezerAlbum(String albumId) async {
    try {
      Logging.severe('Fetching Deezer album: $albumId');

      final url = Uri.parse('$_deezerAlbumEndpoint/$albumId');
      final response = await http.get(url);

      if (response.statusCode != 200) {
        Logging.severe('Failed to fetch Deezer album: ${response.statusCode}');
        return null;
      }

      final deezerAlbum = jsonDecode(response.body);

      // Log entire album response for debugging
      Logging.severe('Deezer album raw data: ${jsonEncode({
            'id': deezerAlbum['id'],
            'title': deezerAlbum['title'],
            'artist': deezerAlbum['artist']['name'],
            'cover': deezerAlbum['cover'],
            'link': deezerAlbum['link'],
            'release_date': deezerAlbum['release_date'],
            'nb_tracks': deezerAlbum['nb_tracks'],
          })}');

      // Fetch tracks
      List<dynamic> allTracks = [];
      if (deezerAlbum['tracks'] != null &&
          deezerAlbum['tracks']['data'] != null) {
        allTracks = deezerAlbum['tracks']['data'];
      }

      // Log track count
      Logging.severe(
          'Found ${allTracks.length} tracks for Deezer album $albumId');

      // For debugging, log the first track's raw data
      if (allTracks.isNotEmpty) {
        Logging.severe('First track raw data: ${jsonEncode(allTracks[0])}');
      }

      // Convert to standardized format
      final result = {
        'id': deezerAlbum['id'],
        'collectionId': deezerAlbum['id'],
        'name': deezerAlbum['title'],
        'collectionName': deezerAlbum['title'],
        'artist': deezerAlbum['artist']['name'],
        'artistName': deezerAlbum['artist']['name'],
        'artworkUrl': deezerAlbum['cover_xl'] ??
            deezerAlbum['cover_big'] ??
            deezerAlbum['cover'],
        'artworkUrl100': deezerAlbum['cover'],
        'url': deezerAlbum['link'],
        'platform': 'deezer',
        'releaseDate': deezerAlbum['release_date'],
        'trackCount': deezerAlbum['nb_tracks'],
        'wrapperType': 'collection',
        'collectionType': 'Album',
        'tracks': allTracks.map((track) {
          // Extract track duration in a safe way
          int trackDuration = 0;
          if (track['duration'] != null) {
            trackDuration = (track['duration'] as int) *
                1000; // Convert seconds to milliseconds
          }

          // Handle track position properly - gets track_position or track_number
          int trackPosition = 0;
          if (track['track_position'] != null) {
            trackPosition = track['track_position'];
          } else if (track['track_number'] != null) {
            trackPosition = track['track_number'];
          } else {
            // Try to determine position from disk and track numbers if available
            if (track['disk_number'] != null && track['track_number'] != null) {
              // Some APIs use disk_number/track_number combo
              final diskNumber = track['disk_number'] as int;
              final trackOnDisk = track['track_number'] as int;
              trackPosition = ((diskNumber - 1) * 100) + trackOnDisk;
            }
          }

          // If no position found, use index in the array + 1
          if (trackPosition == 0) {
            trackPosition = allTracks.indexOf(track) + 1;
          }

          return {
            'trackId': track['id'],
            'trackName': track['title'],
            'trackNumber': trackPosition,
            'position': trackPosition, // Add both fields for compatibility
            'trackTimeMillis': trackDuration,
            'kind': 'song',
            'wrapperType': 'track',
            'artistName':
                track['artist']?['name'] ?? deezerAlbum['artist']['name'],
            'collectionName': deezerAlbum['title'],
            'url': track['link'],
            'preview': track['preview'],
            'platform': 'deezer',
          };
        }).toList(),
        'metadata': deezerAlbum,
      };

      // Final debugging before returning
      Logging.severe('Converted Deezer album to app format: ${jsonEncode({
            'id': result['id'],
            'name': result['name'],
            'artist': result['artist'],
            'tracks': 'Array with ${result['tracks'].length} tracks',
            'trackKeys': result['tracks'].isNotEmpty
                ? result['tracks'][0].keys.toList()
                : [],
          })}');

      return result;
    } catch (e, stack) {
      Logging.severe('Error fetching Deezer album', e, stack);
      return null;
    }
  }

  /// Search for albums on iTunes with improved artist search
  static Future<List<dynamic>> searchiTunesAlbums(String query) async {
    try {
      Logging.severe('Starting iTunes search for query: "$query"');

      // 1. Perform multiple search queries for better coverage
      final responses = await Future.wait([
        // General search - highest relevance but may miss artist-specific results
        http.get(Uri.parse(
            'https://itunes.apple.com/search?term=${Uri.encodeComponent(query)}'
            '&entity=album&limit=50')),

        // Artist-specific search - better for exact artist matches
        http.get(Uri.parse(
            'https://itunes.apple.com/search?term=${Uri.encodeComponent(query)}'
            '&attribute=artistTerm&entity=album&limit=100')),

        // Album name search - better for exact album title matches
        http.get(Uri.parse(
            'https://itunes.apple.com/search?term=${Uri.encodeComponent(query)}'
            '&attribute=albumTerm&entity=album&limit=25')),
      ]);

      // 2. Collect and merge all search results
      final Map<int, dynamic> allAlbums = {};

      // Process results from each search
      for (var response in responses) {
        final data = jsonDecode(response.body);
        for (var item in data['results'] ?? []) {
          if (item['wrapperType'] == 'collection' &&
              item['collectionType'] == 'Album') {
            // Use collection ID as key to avoid duplicates
            allAlbums[item['collectionId']] = item;
          }
        }
      }

      // Convert back to list
      final List<dynamic> albums = allAlbums.values.toList();

      // Add debug logs for search results
      Logging.severe('iTunes raw search returned ${albums.length} albums');

      // Sample the first result for debugging
      if (albums.isNotEmpty) {
        Logging.severe('First album sample: ${jsonEncode({
              'id': albums[0]['collectionId'],
              'name': albums[0]['collectionName'],
              'artist': albums[0]['artistName'],
              'explicitness': albums[0]['collectionExplicitness'],
              'releaseDate': albums[0]['releaseDate'],
            })}');
      }

      // 3. Sort by relevance: exact artist matches first, then by release date
      final queryLower = query.toLowerCase();
      final exactArtistMatches = <dynamic>[];
      final partialArtistMatches = <dynamic>[];
      final otherResults = <dynamic>[];

      for (var album in albums) {
        String artistName = album['artistName']?.toString().toLowerCase() ?? '';
        String albumName =
            album['collectionName']?.toString().toLowerCase() ?? '';

        // Process clean/explicit versions
        if (album['collectionExplicitness'] == 'cleaned' &&
            !album['collectionName'].toString().endsWith(' (Clean)')) {
          album = Map<String, dynamic>.from(album);
          album['collectionName'] = "${album['collectionName']} (Clean)";
        }

        // Sort into appropriate category
        if (artistName == queryLower) {
          exactArtistMatches.add(album);
        } else if (artistName.contains(queryLower) ||
            albumName.contains(queryLower)) {
          partialArtistMatches.add(album);
        } else {
          otherResults.add(album);
        }
      }

      // Sort each group by release date (newest first)
      for (var group in [
        exactArtistMatches,
        partialArtistMatches,
        otherResults
      ]) {
        group.sort((a, b) => DateTime.parse(b['releaseDate'])
            .compareTo(DateTime.parse(a['releaseDate'])));
      }

      // 4. Combine all sorted groups
      final sortedAlbums = [
        ...exactArtistMatches,
        ...partialArtistMatches,
        ...otherResults
      ];

      // 5. Fetch track details for top results
      const maxDetailedResults = 20; // Limit for performance
      final List<dynamic> detailedAlbums = [];

      for (int i = 0; i < sortedAlbums.length && i < maxDetailedResults; i++) {
        final album = sortedAlbums[i];
        try {
          Logging.severe(
              'Fetching details for album ID: ${album['collectionId']} - "${album['collectionName']}" by ${album['artistName']}');

          final url = Uri.parse(
              'https://itunes.apple.com/lookup?id=${album['collectionId']}&entity=song');
          final response = await http.get(url);
          final data = jsonDecode(response.body);

          Logging.severe(
              'iTunes lookup status: ${response.statusCode}, result count: ${data['resultCount']}');

          if (data['results'] != null && data['results'].isNotEmpty) {
            final albumInfo = data['results'][0];

            // Debug log the raw album info
            Logging.severe(
                'Raw album info for ${albumInfo['collectionName']}: ${jsonEncode({
                  'collectionId': albumInfo['collectionId'],
                  'colName': albumInfo['collectionName'],
                  'artworkUrl': albumInfo['artworkUrl100'],
                  'trackCount': albumInfo['trackCount'],
                  'releaseDate': albumInfo['releaseDate'],
                  'explicitness': albumInfo['collectionExplicitness'],
                  'hasView': albumInfo.containsKey('collectionViewUrl'),
                })}');

            // Ensure track list is properly created even if empty
            final tracks = data['results']
                .skip(1)
                .where((item) =>
                    item['wrapperType'] == 'track' && item['kind'] == 'song')
                .toList();

            Logging.severe(
                'Found ${tracks.length} tracks for album ID: ${album['collectionId']}');

            // Sample the first track for debugging if available
            if (tracks.isNotEmpty) {
              Logging.severe('First track sample: ${jsonEncode({
                    'trackId': tracks[0]['trackId'],
                    'trackName': tracks[0]['trackName'],
                    'trackNumber': tracks[0]['trackNumber'],
                    'duration': tracks[0]['trackTimeMillis'],
                  })}');
            }

            // Always add tracks array, even if empty
            albumInfo['tracks'] = tracks;

            // Make sure other critical fields are preserved
            if (album['collectionExplicitness'] == 'cleaned' ||
                album['collectionName'].toString().contains('(Clean)')) {
              final originalName = albumInfo['collectionName'];
              albumInfo['collectionName'] =
                  album['collectionName'].toString().endsWith(' (Clean)')
                      ? album['collectionName']
                      : "${album['collectionName']} (Clean)";
              albumInfo['collectionExplicitness'] = 'cleaned';

              // Log the clean version transformation
              Logging.severe(
                  'Transformed clean album name from "$originalName" to "${albumInfo['collectionName']}"');
            }

            // Ensure platform field exists
            albumInfo['platform'] = 'itunes';

            // Make sure URL field exists
            if (!albumInfo.containsKey('url') &&
                albumInfo.containsKey('collectionViewUrl')) {
              albumInfo['url'] = albumInfo['collectionViewUrl'];
            }

            detailedAlbums.add(albumInfo);
          } else {
            // If lookup fails, add the original album with empty tracks array
            Logging.severe(
                'No results found for album ID: ${album['collectionId']} - adding with empty tracks');
            album['tracks'] = [];
            album['platform'] = 'itunes'; // Ensure platform field exists
            detailedAlbums.add(album);
          }
        } catch (e, stack) {
          Logging.severe(
              'Error fetching tracks for album ID: ${album['collectionId']}',
              e,
              stack);
          // If track fetch fails, still add the album with empty tracks array
          album['tracks'] = [];
          album['platform'] = 'itunes'; // Ensure platform field exists
          detailedAlbums.add(album);
        }
      }

      // 6. Add remaining albums without detailed tracks
      if (sortedAlbums.length > maxDetailedResults) {
        for (int i = maxDetailedResults; i < sortedAlbums.length; i++) {
          final album = sortedAlbums[i];
          // Make sure each album has at least an empty tracks array
          album['tracks'] = [];
          detailedAlbums.add(album);
        }
      }

      // 7. If we have exact artist matches, also fetch their full discography
      if (exactArtistMatches.isNotEmpty) {
        try {
          final artistId = exactArtistMatches.first['artistId'];
          final discUrl = Uri.parse(
              'https://itunes.apple.com/lookup?id=$artistId&entity=album&limit=200');
          final discResponse = await http.get(discUrl);
          final discData = jsonDecode(discResponse.body);

          // Get album IDs already in our results to avoid duplicates
          final existingIds =
              detailedAlbums.map((a) => a['collectionId']).toSet();

          // Add missing albums from discography
          for (var item in discData['results'] ?? []) {
            if (item['wrapperType'] == 'collection' &&
                item['collectionType'] == 'Album' &&
                !existingIds.contains(item['collectionId'])) {
              // Mark clean versions
              if (item['collectionExplicitness'] == 'cleaned' &&
                  !item['collectionName'].toString().endsWith(' (Clean)')) {
                item = Map<String, dynamic>.from(item);
                item['collectionName'] = "${item['collectionName']} (Clean)";
              }

              detailedAlbums.add(item);
              existingIds.add(item['collectionId']);
            }
          }
        } catch (e) {
          Logging.severe('Error fetching artist discography', e);
          // Continue without discography if it fails
        }
      }

      Logging.severe(
          'iTunes search completed - returning ${detailedAlbums.length} albums');
      return detailedAlbums;
    } catch (e, stack) {
      Logging.severe('Error searching iTunes albums', e, stack);
      return [];
    }
  }

  /// Fetch detailed album information from iTunes
  static Future<Album?> fetchiTunesAlbumDetails(int albumId) async {
    try {
      final url =
          Uri.parse('https://itunes.apple.com/lookup?id=$albumId&entity=song');
      final response = await http.get(url);
      final data = jsonDecode(response.body);

      if (data['results'].isEmpty) return null;

      // Get album info (first result)
      final albumInfo = data['results'][0];

      // Filter only audio tracks, excluding videos
      final trackList = data['results']
          .where((track) =>
              track['wrapperType'] == 'track' && track['kind'] == 'song')
          .toList();

      // Convert tracks to unified model
      final List<Track> tracks = [];
      for (var trackData in trackList) {
        tracks.add(Track(
          id: trackData['trackId'],
          name: trackData['trackName'],
          position: trackData['trackNumber'],
          durationMs: trackData['trackTimeMillis'] ?? 0,
          metadata: trackData,
        ));
      }

      // Create unified album object
      return Album(
        id: albumInfo['collectionId'],
        name: albumInfo['collectionName'],
        artist: albumInfo['artistName'],
        artworkUrl: albumInfo['artworkUrl100'],
        releaseDate: DateTime.parse(albumInfo['releaseDate']),
        platform: 'itunes',
        url: albumInfo['collectionViewUrl'] ?? '', // Add this line
        tracks: tracks,
        metadata: albumInfo,
      );
    } catch (e) {
      Logging.severe('Error fetching iTunes album details', e);
      return null;
    }
  }

  /// Fetch Bandcamp album
  static Future<Album?> fetchBandcampAlbum(String url) async {
    try {
      Logging.severe('BANDCAMP: Starting album fetch for URL: $url');
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) {
        throw Exception('Failed to load Bandcamp album');
      }

      final document = parse(response.body);
      var ldJsonScript =
          document.querySelector('script[type="application/ld+json"]');
      if (ldJsonScript == null) {
        throw Exception('Could not find album data');
      }

      final ldJson = jsonDecode(ldJsonScript.text);
      Logging.severe('BANDCAMP: Successfully parsed JSON-LD data');

      // Extract artist name first - prioritize byArtist field
      String artist = ldJson['byArtist']?['name'] ?? '';
      if (artist.isEmpty) {
        artist = document
                .querySelector('meta[property="og:site_name"]')
                ?.attributes['content'] ??
            'Unknown Artist';
      }

      // Extract album title - don't split by comma anymore
      String title = ldJson['name'] ?? 'Unknown Album';
      // Remove any "by Artist" suffix if it exists
      if (title.toLowerCase().contains(' by ${artist.toLowerCase()}')) {
        title = title
            .substring(
                0, title.toLowerCase().indexOf(' by ${artist.toLowerCase()}'))
            .trim();
      }

      Logging.severe(
          'BANDCAMP: Extracted title: "$title" and artist: "$artist"');

      // Continue with rest of album data extraction
      String artworkUrl = document
              .querySelector('meta[property="og:image"]')
              ?.attributes['content'] ??
          '';

      // Parse release date
      DateTime releaseDate;
      try {
        Logging.severe(
            'BANDCAMP: Parsing release date from: ${ldJson['datePublished']}');
        releaseDate = DateFormat("d MMMM yyyy HH:mm:ss 'GMT'")
            .parse(ldJson['datePublished']);
      } catch (e) {
        try {
          releaseDate =
              DateTime.parse(ldJson['datePublished'].replaceAll(' GMT', 'Z'));
        } catch (e) {
          Logging.severe(
              'BANDCAMP: Using fallback date due to parsing error: $e');
          releaseDate = DateTime.now();
        }
      }

      // Extract album ID with consistent generation
      int albumId = url.hashCode;
      try {
        if (ldJson['@id'] != null) {
          final idString = ldJson['@id'].toString().split('/').last;
          if (idString.isNotEmpty) {
            albumId = int.tryParse(idString) ?? url.hashCode;
          }
        }
      } catch (e) {
        Logging.severe('BANDCAMP: Using URL hash as album ID due to error: $e');
      }
      Logging.severe('BANDCAMP: Using album ID: $albumId');

      // Extract tracks with improved error handling
      final List<Track> tracks = [];
      if (ldJson['track'] != null &&
          ldJson['track']['itemListElement'] != null) {
        Logging.severe('BANDCAMP: Found track list in JSON-LD');
        var trackItems = ldJson['track']['itemListElement'] as List;
        Logging.severe('BANDCAMP: Processing ${trackItems.length} tracks');

        for (int i = 0; i < trackItems.length; i++) {
          try {
            var item = trackItems[i];
            var track = item['item'];

            // Generate consistent trackId - this is crucial for ratings to work
            int trackId = albumId * 1000 + (i + 1);
            try {
              var props = track['additionalProperty'] as List;
              var trackIdProp = props.firstWhere((p) => p['name'] == 'track_id',
                  orElse: () => {'value': null});

              if (trackIdProp['value'] != null) {
                trackId = trackIdProp['value'];
              }
            } catch (e) {
              Logging.severe(
                  'BANDCAMP: Error extracting track ID, using generated one: $e');
            }

            int position = item['position'] ?? i + 1;
            String trackName = track['name'] ?? 'Track ${i + 1}';

            // Use the new parser for duration
            String duration = track['duration'] ?? '';
            int durationMs = parseBandcampDuration(duration);

            tracks.add(Track(
              id: trackId,
              name: trackName,
              position: position,
              durationMs: durationMs, // This should now have correct duration
              metadata: {
                'trackId': trackId,
                'trackName': trackName,
                'trackNumber': position,
                'trackTimeMillis': durationMs,
                'duration': durationMs,
                'title': trackName,
              },
            ));

            Logging.severe(
                'BANDCAMP: Added track: $trackName (ID: $trackId, Position: $position)');
          } catch (e) {
            Logging.severe('BANDCAMP: Error processing track ${i + 1}: $e');
          }
        }
      } else {
        Logging.severe('BANDCAMP: No tracks found in JSON-LD');
      }

      // Create unified album object with consistent metadata
      Logging.severe(
          'BANDCAMP: Creating album object with ${tracks.length} tracks');
      return Album(
        id: albumId,
        name: title,
        artist: artist,
        artworkUrl: artworkUrl,
        releaseDate: releaseDate,
        platform: 'bandcamp',
        url: url,
        tracks: tracks,
        metadata: {
          'collectionId': albumId,
          'id': albumId,
          'collectionName': title,
          'artistName': artist,
          'artworkUrl100': artworkUrl,
          'url': url,
          'platform': 'bandcamp',
          'releaseDate': releaseDate.toIso8601String(),
          'tracks': tracks.map((t) => t.metadata).toList(),
        },
      );
    } catch (e, stack) {
      Logging.severe('BANDCAMP: Error fetching album', e, stack);
      return null;
    }
  }

  static int parseBandcampDuration(String duration) {
    try {
      // Handle Bandcamp's P00H02M23S format
      if (duration.startsWith('P')) {
        // Extract hours, minutes, seconds
        final regex = RegExp(r'P(\d+)H(\d+)M(\d+)S');
        final match = regex.firstMatch(duration);

        if (match != null) {
          final hours = int.parse(match.group(1) ?? '0');
          final minutes = int.parse(match.group(2) ?? '0');
          final seconds = int.parse(match.group(3) ?? '0');

          final totalMillis =
              ((hours * 3600) + (minutes * 60) + seconds) * 1000;
          Logging.severe('Parsed duration $duration to $totalMillis ms');
          return totalMillis;
        }
      }

      // Fallback to existing duration parsing for other formats
      return _parseDuration(duration);
    } catch (e) {
      Logging.severe('Error parsing Bandcamp duration: $duration', e);
      return 0;
    }
  }

  /// Parse ISO duration or time string to milliseconds
  static int _parseDuration(String isoDuration) {
    try {
      if (isoDuration.isEmpty) return 0;

      // Handle ISO duration format (PT1H2M3S)
      if (isoDuration.startsWith('PT')) {
        final regex = RegExp(r'(\d+)(?=[HMS])');
        final matches = regex.allMatches(isoDuration);
        final parts = matches.map((m) => int.parse(m.group(1)!)).toList();

        int totalMillis = 0;
        if (parts.length >= 3) {
          // H:M:S
          totalMillis = ((parts[0] * 3600) + (parts[1] * 60) + parts[2]) * 1000;
        } else if (parts.length == 2) {
          // M:S
          totalMillis = ((parts[0] * 60) + parts[1]) * 1000;
        } else if (parts.length == 1) {
          // S
          totalMillis = parts[0] * 1000;
        }
        return totalMillis;
      }

      // Handle MM:SS format
      final parts = isoDuration.split(':');
      if (parts.length == 2) {
        int minutes = int.tryParse(parts[0]) ?? 0;
        int seconds = int.tryParse(parts[1]) ?? 0;
        return (minutes * 60 + seconds) * 1000;
      }

      // Try parsing as seconds
      return (int.tryParse(isoDuration) ?? 0) * 1000;
    } catch (e) {
      Logging.severe('Error parsing duration: $isoDuration - $e');
      return 0;
    }
  }
}
