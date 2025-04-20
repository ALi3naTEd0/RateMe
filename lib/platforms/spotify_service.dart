import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../database/database_helper.dart';
import 'platform_service_base.dart';
import '../api_keys.dart';
import '../logging.dart';
import '../search_service.dart';

class SpotifyService extends PlatformServiceBase {
  // Token storage keys
  static const String _tokenKey = 'spotify_access_token';
  static const String _tokenExpiryKey = 'spotify_token_expiry';

  // API endpoints
  static const String _tokenEndpoint = 'https://accounts.spotify.com/api/token';
  static const String _searchEndpoint = 'https://api.spotify.com/v1/search';

  @override
  String get platformId => 'spotify';

  @override
  String get displayName => 'Spotify';

  /// Find a specific album URL
  @override
  Future<String?> findAlbumUrl(String artist, String album) async {
    try {
      Logging.severe(
          'SpotifyService: Finding album URL for "$artist - $album"');

      // Clean album name to handle EP/Single designation mismatches
      String cleanedAlbum = SearchService.removeAlbumSuffixes(album);
      Logging.severe(
          'SpotifyService: Using cleaned album name: "$cleanedAlbum"');

      final token = await _getAccessToken();
      if (token == null) {
        Logging.severe('Could not get Spotify access token');
        return null;
      }

      // Build search query - try first with exact artist and album
      String query =
          Uri.encodeComponent('album:"$cleanedAlbum" artist:"$artist"');

      // First attempt: Exact search
      String? url = await _searchForAlbumUrl(query, token);

      // If that fails, try broader search with artist and album separate
      if (url == null) {
        query = Uri.encodeComponent('$cleanedAlbum $artist');
        Logging.severe('SpotifyService: Trying broader search: "$query"');
        url = await _searchForAlbumUrl(query, token);
      }

      // If that also fails, try with just the album name (useful for compilations)
      if (url == null) {
        query = Uri.encodeComponent(cleanedAlbum);
        Logging.severe('SpotifyService: Trying album-only search: "$query"');
        url = await _searchForAlbumUrl(query, token, considerArtist: false);
      }

      return url;
    } catch (e, stack) {
      Logging.severe('Error finding Spotify album URL', e, stack);
      return null;
    }
  }

  // Helper method to search for album and select best match
  Future<String?> _searchForAlbumUrl(String query, String token,
      {bool considerArtist = true}) async {
    final searchUrl = Uri.parse(
        'https://api.spotify.com/v1/search?q=$query&type=album&limit=50');

    final response = await http.get(
      searchUrl,
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode != 200) {
      Logging.severe('Spotify API error: ${response.statusCode}');
      return null;
    }

    final data = jsonDecode(response.body);
    if (!data.containsKey('albums') || !data['albums'].containsKey('items')) {
      return null;
    }

    final List<dynamic> albums = data['albums']['items'];
    if (albums.isEmpty) {
      return null;
    }

    // If considerArtist is true, try to match the artist name
    if (considerArtist) {
      // ...existing code...
    }

    // Return URL of first result if we get this far
    if (albums.isNotEmpty) {
      final firstAlbum = albums.first;
      final albumUrl = firstAlbum['external_urls']['spotify'];
      Logging.severe(
          'SpotifyService: Found album: ${firstAlbum['name']} by ${firstAlbum['artists'][0]['name']}');
      return albumUrl;
    }

    return null;
  }

  @override
  Future<bool> verifyAlbumExists(String artist, String albumName) async {
    try {
      // Get a token
      final token = await _getAccessToken();
      if (token == null) return false;

      // Try a focused query
      final query = Uri.encodeComponent('album:"$albumName" artist:"$artist"');
      final url = Uri.parse('$_searchEndpoint?q=$query&type=album&limit=5');

      final response =
          await http.get(url, headers: {'Authorization': 'Bearer $token'});

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['albums'] != null &&
            data['albums']['items'] != null &&
            data['albums']['items'].isNotEmpty) {
          // Check similarity of the first result to ensure it's a good match
          final firstAlbum = data['albums']['items'][0];
          final albumTitle = firstAlbum['name'].toString().toLowerCase();
          final albumArtist =
              firstAlbum['artists'][0]['name'].toString().toLowerCase();

          final titleSimilarity =
              calculateStringSimilarity(albumTitle, albumName.toLowerCase());
          final artistSimilarity =
              calculateStringSimilarity(albumArtist, artist.toLowerCase());

          // If either title or artist has high similarity, consider it a match
          if (titleSimilarity > 0.7 || artistSimilarity > 0.7) {
            return true;
          }
        }
      }

      return false;
    } catch (e, stack) {
      Logging.severe('Error verifying Spotify album', e, stack);
      return false;
    }
  }

  /// Get an access token from Spotify API
  Future<String?> _getAccessToken() async {
    try {
      final dbHelper = DatabaseHelper.instance;
      final storedToken = await dbHelper.getSetting(_tokenKey);
      final expiryString = await dbHelper.getSetting(_tokenExpiryKey);
      final expiryTime =
          expiryString != null ? int.tryParse(expiryString) ?? 0 : 0;

      // Check if token is still valid (with 5 minute buffer)
      if (storedToken != null &&
          expiryTime >
              DateTime.now().millisecondsSinceEpoch + (5 * 60 * 1000)) {
        return storedToken;
      }

      // Get new token
      final credentials =
          '${ApiKeys.spotifyClientId}:${ApiKeys.spotifyClientSecret}';
      final basicAuth = base64Encode(utf8.encode(credentials));

      final response = await http.post(
        Uri.parse(_tokenEndpoint),
        headers: {
          'Authorization': 'Basic $basicAuth',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: 'grant_type=client_credentials',
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final accessToken = data['access_token'] as String;
        final expiresIn = data['expires_in'] as int;

        // Save token with expiry time
        final expiry =
            DateTime.now().millisecondsSinceEpoch + (expiresIn * 1000);
        await dbHelper.saveSetting(_tokenKey, accessToken);
        await dbHelper.saveSetting(_tokenExpiryKey, expiry.toString());

        return accessToken;
      } else {
        Logging.severe(
            'Failed to get Spotify token: ${response.statusCode} ${response.body}');
        return null;
      }
    } catch (e, stack) {
      Logging.severe('Error getting Spotify token', e, stack);
      return null;
    }
  }

  @override
  Future<Map<String, dynamic>?> fetchAlbumDetails(String url) async {
    try {
      Logging.severe('Fetching Spotify album details from URL: $url');

      // Extract the album ID from the URL
      final RegExp regExp = RegExp(r'album/([a-zA-Z0-9]+)');
      final match = regExp.firstMatch(url);

      if (match == null || match.groupCount < 1) {
        Logging.severe('Invalid Spotify URL format: $url');
        return null;
      }

      final albumId = match.group(1);
      if (albumId == null) {
        Logging.severe('Could not extract album ID from URL: $url');
        return null;
      }

      // Get an access token
      final tokenResponse = await http.post(
        Uri.parse('https://accounts.spotify.com/api/token'),
        headers: {
          'Authorization': 'Basic ${ApiKeys.getSpotifyToken()}',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {
          'grant_type': 'client_credentials',
        },
      );

      if (tokenResponse.statusCode != 200) {
        Logging.severe('Spotify token error: ${tokenResponse.statusCode}');
        return null;
      }

      final tokenData = jsonDecode(tokenResponse.body);
      final accessToken = tokenData['access_token'];

      // Use the Spotify API to fetch album details
      final albumResponse = await http.get(
        Uri.parse('https://api.spotify.com/v1/albums/$albumId'),
        headers: {
          'Authorization': 'Bearer $accessToken',
        },
      );

      if (albumResponse.statusCode != 200) {
        Logging.severe('Spotify API error: ${albumResponse.statusCode}');
        return null;
      }

      final albumData = jsonDecode(albumResponse.body);

      // Extract tracks from the album data
      List<Map<String, dynamic>> tracks = [];
      if (albumData['tracks'] != null && albumData['tracks']['items'] != null) {
        for (var track in albumData['tracks']['items']) {
          tracks.add({
            'trackId': track['id'],
            'trackName': track['name'],
            'trackNumber': track['track_number'],
            'trackTimeMillis': track['duration_ms'],
          });
        }
      }

      // Create a standardized album object
      return {
        'id': albumData['id'],
        'collectionId': albumData['id'],
        'name': albumData['name'],
        'collectionName': albumData['name'],
        'artist': albumData['artists']?.first['name'] ?? 'Unknown Artist',
        'artistName': albumData['artists']?.first['name'] ?? 'Unknown Artist',
        'artworkUrl': albumData['images']?.first['url'] ?? '',
        'artworkUrl100': albumData['images']?.first['url'] ?? '',
        'releaseDate': albumData['release_date'],
        'url': url,
        'platform': 'spotify',
        'tracks': tracks,
      };
    } catch (e, stack) {
      Logging.severe('Error fetching Spotify album details', e, stack);
      return null;
    }
  }
}
