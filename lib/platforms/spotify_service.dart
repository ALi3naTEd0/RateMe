import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../database/database_helper.dart';
import 'platform_service_base.dart';
import '../core/api/api_keys.dart';
import '../core/services/logging.dart';
import '../core/services/search_service.dart';

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
  Future<String?> findAlbumUrl(String artist, String albumName) async {
    try {
      Logging.severe(
          'SpotifyService: Finding album URL for "$artist - $albumName"');

      // Clean album name to handle EP/Single designation mismatches
      String cleanedAlbum = SearchService.removeAlbumSuffixes(albumName);
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
      String? url =
          await _searchForAlbumUrl(query, token, artist, cleanedAlbum);

      // If that fails, try broader search with artist and album separate
      if (url == null) {
        query = Uri.encodeComponent('$cleanedAlbum $artist');
        Logging.severe('SpotifyService: Trying broader search: "$query"');
        url = await _searchForAlbumUrl(query, token, artist, cleanedAlbum);
      }

      // If that also fails, try with just the album name (useful for compilations)
      if (url == null) {
        query = Uri.encodeComponent(cleanedAlbum);
        Logging.severe('SpotifyService: Trying album-only search: "$query"');
        url = await _searchForAlbumUrl(query, token, artist, cleanedAlbum,
            considerArtist: false);
      }

      return url;
    } catch (e, stack) {
      Logging.severe('Error finding Spotify album URL', e, stack);
      return null;
    }
  }

  // Helper method to search for album and select best match
  Future<String?> _searchForAlbumUrl(
      String query, String token, String originalArtist, String originalAlbum,
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

    // Normalize original values for consistent comparison
    final normalizedOriginalArtist = normalizeForComparison(originalArtist);
    final normalizedOriginalAlbum = normalizeForComparison(originalAlbum);

    // OPTIMIZATION: First check for perfect matches before scoring everything
    for (var album in albums) {
      final albumName = album['name'] ?? '';
      final artistName = album['artists']?.isNotEmpty
          ? (album['artists'][0]['name'] ?? '')
          : '';

      // Normalize album and artist names
      final normalizedAlbum = normalizeForComparison(albumName);
      final normalizedArtist = normalizeForComparison(artistName);

      // Check for perfect match (both artist and album)
      final artistScore =
          calculateStringSimilarity(normalizedOriginalArtist, normalizedArtist);
      final albumScore =
          calculateStringSimilarity(normalizedOriginalAlbum, normalizedAlbum);

      // If we find a perfect or near-perfect match, return it immediately
      if (artistScore > 0.95 && albumScore > 0.95) {
        final albumUrl = album['external_urls']['spotify'];
        Logging.severe(
            'SpotifyService: Found perfect match: ${album['name']} by ${album['artists'][0]['name']}');
        Logging.severe(
            'Perfect match scores - artist: ${artistScore.toStringAsFixed(2)}, album: ${albumScore.toStringAsFixed(2)}');
        return albumUrl;
      }
    }

    // Score each result instead of just returning the first one
    List<Map<String, dynamic>> scoredResults = [];

    // REMOVED: Keep track of which albums we've already logged (removed for noise reduction)

    for (var album in albums) {
      final albumName = album['name'] ?? '';
      final artistName = album['artists']?.isNotEmpty
          ? (album['artists'][0]['name'] ?? '')
          : '';

      // Normalize album and artist names
      final normalizedAlbum = normalizeForComparison(albumName);
      final normalizedArtist = normalizeForComparison(artistName);

      // Calculate match scores
      final artistScore =
          calculateStringSimilarity(normalizedOriginalArtist, normalizedArtist);

      final albumScore =
          calculateStringSimilarity(normalizedOriginalAlbum, normalizedAlbum);

      // Weighted combined score - more weight to artist if considerArtist is true
      final double artistWeight = considerArtist ? 0.6 : 0.2;
      final double albumWeight = considerArtist ? 0.4 : 0.8;
      final combinedScore =
          (artistScore * artistWeight) + (albumScore * albumWeight);

      // MODIFIED: Only log very good matches (score > 0.8) to reduce noise
      if (combinedScore > 0.8) {
        Logging.severe(
            'SpotifyService match candidate: "$albumName" by "$artistName" - '
            'artistScore: ${artistScore.toStringAsFixed(2)}, '
            'albumScore: ${albumScore.toStringAsFixed(2)}, '
            'combined: ${combinedScore.toStringAsFixed(2)}');
      }

      // Add to scored results
      scoredResults.add({
        'album': album,
        'artistScore': artistScore,
        'albumScore': albumScore,
        'combinedScore': combinedScore,
      });

      // NEW: Early return if we find a very good match during scoring
      if (artistScore > 0.9 && albumScore > 0.9) {
        final albumUrl = album['external_urls']['spotify'];
        Logging.severe(
            'SpotifyService: Found excellent match: ${album['name']} by ${album['artists'][0]['name']}');
        Logging.severe(
            'Match scores - artist: ${artistScore.toStringAsFixed(2)}, album: ${albumScore.toStringAsFixed(2)}, combined: ${combinedScore.toStringAsFixed(2)}');
        return albumUrl;
      }
    }

    // Sort by combined score
    scoredResults
        .sort((a, b) => b['combinedScore'].compareTo(a['combinedScore']));

    // Determine appropriate threshold based on the source
    double requiredScore;

    // For Bandcamp URLs or any artist name containing dots or hyphens (common in Bandcamp artist names)
    // we want to be much stricter since Bandcamp often has unique artist naming patterns
    if (originalArtist.toLowerCase().contains('bandcamp') ||
        originalArtist.contains('.') ||
        originalArtist.contains(' - ')) {
      // Very high threshold for Bandcamp URLs - 0.75 as agreed
      requiredScore = 0.75;
      Logging.severe(
          'Using strict threshold (0.75) for Bandcamp or URL-pasted artist');
    } else if (!considerArtist) {
      // Updated: Higher threshold when not weighing the artist name (album-only search)
      requiredScore = 0.7; // Changed from 0.65 to 0.7
    } else {
      // Updated: Normal threshold for standard searches
      requiredScore = 0.7; // Changed from 0.55 to 0.7
    }

    // Check top result against our determined threshold
    if (scoredResults.isNotEmpty &&
        scoredResults[0]['combinedScore'] >= requiredScore) {
      final bestMatch = scoredResults[0]['album'];
      final albumUrl = bestMatch['external_urls']['spotify'];

      // Log the chosen match for debugging
      Logging.severe(
          'SpotifyService: Found album: ${bestMatch['name']} by ${bestMatch['artists'][0]['name']}');
      Logging.severe(
          'Match scores - artist: ${scoredResults[0]['artistScore'].toStringAsFixed(2)}, '
          'album: ${scoredResults[0]['albumScore'].toStringAsFixed(2)}, '
          'combined: ${scoredResults[0]['combinedScore'].toStringAsFixed(2)}');
      Logging.severe('Required threshold: $requiredScore');

      return albumUrl;
    }

    // If no match met the threshold
    Logging.severe(
        'No Spotify match met the required threshold ($requiredScore)');
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
        Logging.severe(
            'Using existing Spotify token - valid until ${DateTime.fromMillisecondsSinceEpoch(expiryTime)}');
        return storedToken;
      }

      Logging.severe('Requesting new Spotify access token');

      // Get API credentials
      final clientId = await ApiKeys.spotifyClientId;
      final clientSecret = await ApiKeys.spotifyClientSecret;

      if (clientId == null ||
          clientSecret == null ||
          clientId.isEmpty ||
          clientSecret.isEmpty) {
        Logging.severe('Missing Spotify API credentials');
        return null;
      }

      // Get new token
      final credentials = '$clientId:$clientSecret';
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

        Logging.severe(
            'Received new Spotify token, expires in $expiresIn seconds');

        // Save token with expiry time
        final expiry =
            DateTime.now().millisecondsSinceEpoch + (expiresIn * 1000);
        await dbHelper.saveSetting(_tokenKey, accessToken);
        await dbHelper.saveSetting(_tokenExpiryKey, expiry.toString());

        return accessToken;
      } else {
        Logging.severe(
            'Failed to get Spotify token: ${response.statusCode} ${response.body}');

        // If the token request failed, clear any stored tokens to force a fresh attempt next time
        await dbHelper.saveSetting(_tokenKey, '');
        await dbHelper.saveSetting(_tokenExpiryKey, '0');

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

      // Get access token - use the proper method
      final accessToken = await _getAccessToken();
      if (accessToken == null) {
        Logging.severe('Could not obtain Spotify access token');
        return null;
      }

      // Use the Spotify API to fetch album details
      final albumResponse = await http.get(
        Uri.parse('https://api.spotify.com/v1/albums/$albumId'),
        headers: {
          'Authorization': 'Bearer $accessToken',
        },
      );

      if (albumResponse.statusCode != 200) {
        Logging.severe(
            'Spotify API error: ${albumResponse.statusCode} - ${albumResponse.body}');
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
