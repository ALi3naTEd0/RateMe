import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Added for Clipboard
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math'; // Add this import for the min() function
import '../album_model.dart';
import '../logging.dart';
import '../api_keys.dart';
import '../widgets/skeleton_loading.dart';

/// Widget that displays buttons to open an album in various streaming platforms
class PlatformMatchWidget extends StatefulWidget {
  final Album album;
  final bool showTitle;
  final double buttonSize;

  const PlatformMatchWidget({
    super.key,
    required this.album,
    this.showTitle = true,
    this.buttonSize = 40.0,
  });

  @override
  State<PlatformMatchWidget> createState() => _PlatformMatchWidgetState();
}

class _PlatformMatchWidgetState extends State<PlatformMatchWidget> {
  bool _isLoading = false;
  final Map<String, String?> _platformUrls = {};
  final List<String> _supportedPlatforms = [
    'spotify',
    'apple_music',
    'deezer',
  ];

  @override
  void initState() {
    super.initState();
    _findMatchingAlbums();
  }

  Future<void> _findMatchingAlbums() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      // Initialize with existing URL if album is from one of our platforms
      final currentPlatform = widget.album.platform.toLowerCase();

      // Check if this is a bandcamp album
      final isBandcamp = currentPlatform == 'bandcamp' ||
          widget.album.url.toLowerCase().contains('bandcamp.com');

      if (isBandcamp) {
        // For bandcamp albums, add the original URL as a bandcamp platform URL
        _platformUrls['bandcamp'] = widget.album.url;
        Logging.severe('Added bandcamp source URL: ${widget.album.url}');
      } else if (_supportedPlatforms.contains(currentPlatform)) {
        _platformUrls[currentPlatform] = widget.album.url;
      }

      // Always ensure the source platform URL is available regardless of platform
      if (widget.album.url.isNotEmpty) {
        // Figure out which platform the album's URL belongs to
        String sourcePlatform = _determinePlatformFromUrl(widget.album.url);
        if (sourcePlatform.isNotEmpty) {
          _platformUrls[sourcePlatform] = widget.album.url;
          Logging.severe(
              'Added source platform URL: $sourcePlatform -> ${widget.album.url}');
        }
      }

      // Always search for additional platforms, even for Bandcamp albums
      // Create search query from album and artist
      final searchQuery = '${widget.album.artist} ${widget.album.name}'.trim();
      Logging.severe('Searching for album matches: $searchQuery');

      // Search for the album on each platform we don't already have
      // Wait for all searches to complete and collect results
      final results = await Future.wait(_supportedPlatforms
          .where((platform) => !_platformUrls.containsKey(platform))
          .map((platform) async {
        final url = await _searchPlatformForAlbum(platform, searchQuery);
        return MapEntry(platform, url);
      }));

      // Add all non-null results to the map
      for (final result in results) {
        if (result.value != null) {
          _platformUrls[result.key] = result.value;
        }
      }

      // Verify matches for accuracy - remove potentially incorrect matches
      await _verifyMatches();
    } catch (e, stack) {
      Logging.severe('Error finding matching albums', e, stack);
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// Verify that matches are accurate by checking if they meet minimum match criteria
  Future<void> _verifyMatches() async {
    Logging.severe('Verifying platform matches for accuracy');

    final List<String> platformsToVerify = [..._supportedPlatforms, 'bandcamp'];
    final String artistName = widget.album.artist.toLowerCase();
    final String albumName = widget.album.name.toLowerCase();

    // Calculate normalized artist and album names for comparison
    final normalizedArtist = _normalizeForComparison(artistName);
    final normalizedAlbum = _normalizeForComparison(albumName);

    // Track which platforms to remove due to failed verification
    final List<String> platformsToRemove = [];

    // Check if the current platform is iTunes, and if so, make sure apple_music is also marked as current
    final String currentPlatform = widget.album.platform.toLowerCase();
    final bool isITunesOrAppleMusic =
        currentPlatform == 'itunes' || currentPlatform == 'apple_music';

    Logging.severe(
        'Current platform: $currentPlatform, Is iTunes/Apple Music: $isITunesOrAppleMusic');

    // Remove automatic addition of search URL fallbacks

    // ...existing verification code for each platform...

    // ...existing code...
    for (final platform in platformsToVerify) {
      if (_platformUrls.containsKey(platform)) {
        final url = _platformUrls[platform];

        if (url == null || url.isEmpty) {
          platformsToRemove.add(platform);
          continue;
        }

        // Skip verification for source platform - make sure both itunes and apple_music are
        // treated as the same platform for verification purposes
        if ((isITunesOrAppleMusic && platform == 'apple_music') ||
            (platform == currentPlatform)) {
          Logging.severe(
              'Skipping verification for $platform (source platform)');
          continue;
        }

        // Check if this is just a search URL (not a direct match)
        if (url.contains('/search?') || url.contains('/search/')) {
          Logging.severe(
              '$platform URL is just a search URL, needs verification: $url');

          // For search URLs, we need stricter verification
          final bool isValidMatch = await _validatePlatformMatch(
              platform, url, normalizedArtist, normalizedAlbum);

          if (!isValidMatch) {
            Logging.severe(
                'Removing $platform match as validation failed: $url');
            platformsToRemove.add(platform);
          }
        } else {
          // For direct URLs, perform basic verification
          final bool isValidUrl = await _verifyMatchAccuracy(
              platform, url, normalizedArtist, normalizedAlbum);

          if (!isValidUrl) {
            Logging.severe(
                'Removing $platform match as URL verification failed: $url');
            platformsToRemove.add(platform);
          }
        }
      }
    }

    // Remove invalid platforms
    for (final platform in platformsToRemove) {
      _platformUrls.remove(platform);
    }

    Logging.severe(
        'After verification, have ${_platformUrls.length} valid platform matches: ${_platformUrls.keys.join(', ')}');
  }

  /// More thorough validation for search URLs
  Future<bool> _validatePlatformMatch(
      String platform, String url, String artistName, String albumName) async {
    try {
      // For each platform, attempt to verify if the album really exists
      if (platform == 'spotify') {
        return await _verifySpotifyAlbumExists(artistName, albumName);
      } else if (platform == 'apple_music') {
        // For Apple Music, we'll no longer use search URL fallbacks
        return await _verifyAppleMusicAlbumExists(artistName, albumName);
      } else if (platform == 'deezer') {
        return await _verifyDeezerAlbumExists(artistName, albumName);
      }
      return false;
    } catch (e) {
      Logging.severe('Error validating $platform match', e);
      return false;
    }
  }

  /// Check if album actually exists on Spotify - improved to be more thorough
  Future<bool> _verifySpotifyAlbumExists(String artist, String album) async {
    try {
      // Get the Spotify API token
      String accessToken;
      try {
        // Generate a Base64 encoded token from the client credentials
        const credentials =
            '${ApiKeys.spotifyClientId}:${ApiKeys.spotifyClientSecret}';
        final bytes = utf8.encode(credentials);
        final base64Credentials = base64.encode(bytes);

        // Get a proper OAuth token using client credentials flow
        final tokenResponse = await http.post(
          Uri.parse('https://accounts.spotify.com/api/token'),
          headers: {
            'Authorization': 'Basic $base64Credentials',
            'Content-Type': 'application/x-www-form-urlencoded',
          },
          body: 'grant_type=client_credentials',
        );

        if (tokenResponse.statusCode == 200) {
          final tokenData = jsonDecode(tokenResponse.body);
          accessToken = tokenData['access_token'];
          Logging.severe('Successfully obtained Spotify OAuth token');
        } else {
          Logging.severe(
              'Failed to get Spotify token: ${tokenResponse.statusCode} - ${tokenResponse.body}');
          return false;
        }
      } catch (e) {
        Logging.severe('Error getting Spotify token: $e');
        return false;
      }

      // If token is empty, return false
      if (accessToken.isEmpty) return false;

      // Try a focused query format that's more likely to find exact matches
      final query = Uri.encodeComponent('album:"$album" artist:"$artist"');
      final url = Uri.parse(
          'https://api.spotify.com/v1/search?q=$query&type=album&limit=5');

      final response = await http
          .get(url, headers: {'Authorization': 'Bearer $accessToken'});

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
              _stringSimilarity(albumTitle, album.toLowerCase());
          final artistSimilarity =
              _stringSimilarity(albumArtist, artist.toLowerCase());

          // Log the similarity scores for debugging
          Logging.severe('Spotify match: "$albumTitle" by "$albumArtist"');
          Logging.severe(
              'Similarity scores - Title: $titleSimilarity, Artist: $artistSimilarity');

          // If either title or artist has high similarity, consider it a match
          if (titleSimilarity > 0.7 || artistSimilarity > 0.7) {
            return true;
          }
        }
      }

      return false;
    } catch (e, stack) {
      Logging.severe('Error verifying Spotify album: $e', e, stack);
      return false;
    }
  }

  /// Check if album actually exists on Apple Music
  Future<bool> _verifyAppleMusicAlbumExists(String artist, String album) async {
    try {
      // Normalize search terms to improve matching
      final normalizedArtist = _normalizeForComparison(artist);
      final normalizedAlbum = _normalizeForComparison(album);

      Logging.severe(
          'Looking for Apple Music album: "$normalizedAlbum" by "$normalizedArtist"');

      // PROBLEM: Many album titles on Apple Music appear without parentheses or deluxe markers
      // We need to simplify both the search terms and the match logic
      final simplifiedAlbum = _simplifyText(normalizedAlbum);
      final simplifiedArtist = _simplifyText(normalizedArtist);

      // Log the simplified search terms for debugging
      Logging.severe(
          'Using simplified terms: "$simplifiedAlbum" by "$simplifiedArtist"');

      // Try iTunes API direct search with better encoding
      final combinedQuery =
          Uri.encodeComponent("$simplifiedArtist $simplifiedAlbum");
      final url = Uri.parse(
          'https://itunes.apple.com/search?term=$combinedQuery&entity=album&limit=50');

      Logging.severe('Apple Music verification query: $url');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        Logging.severe(
            'iTunes API response: ${response.body.substring(0, min(200, response.body.length))}...');

        if (data['results'] != null && data['results'].isNotEmpty) {
          final results = data['results'] as List;
          Logging.severe(
              'Found ${results.length} potential Apple Music matches');

          // Special handling for exact matches to catch cases where the API returns results
          for (var result in results) {
            final resultAlbum = _simplifyText(
                result['collectionName'].toString().toLowerCase());
            final resultArtist =
                _simplifyText(result['artistName'].toString().toLowerCase());

            Logging.severe('Comparing with: "$resultAlbum" by "$resultArtist"');

            // First check for very close matches
            if ((resultArtist.contains(simplifiedArtist) ||
                    simplifiedArtist.contains(resultArtist)) &&
                (resultAlbum.contains(simplifiedAlbum) ||
                    simplifiedAlbum.contains(resultAlbum))) {
              Logging.severe(
                  'Found direct Apple Music match: ${result['collectionName']}');
              return true;
            }

            // Check for exact word matches in album title - more lenient approach
            final albumWords =
                simplifiedAlbum.split(' ').where((w) => w.length > 2).toList();
            int wordMatches = 0;

            for (var word in albumWords) {
              if (resultAlbum.contains(word)) {
                wordMatches++;
                Logging.severe('Found word match: "$word" in "$resultAlbum"');
              }
            }

            final albumWordMatchRatio =
                albumWords.isEmpty ? 0 : wordMatches / albumWords.length;
            Logging.severe(
                'Album word match ratio: $albumWordMatchRatio (matches: $wordMatches/${albumWords.length})');

            // Very lenient matching since iTunes API can be challenging
            if (resultArtist.contains(simplifiedArtist) &&
                albumWordMatchRatio > 0.3) {
              Logging.severe(
                  'Found valid Apple Music match based on word matching: ${result['collectionName']}');
              return true;
            }

            // Try different similarity methods
            final artistSimilarity =
                _stringSimilarity(resultArtist, simplifiedArtist);
            final albumSimilarity =
                _stringSimilarity(resultAlbum, simplifiedAlbum);

            Logging.severe(
                'Similarity scores - Title: $albumSimilarity, Artist: $artistSimilarity');

            // Accept if either similarity is good
            if (artistSimilarity > 0.6 || albumSimilarity > 0.6) {
              Logging.severe(
                  'Found Apple Music match through similarity: ${result['collectionName']}');
              return true;
            }
          }
        } else {
          // If iTunes API returned no results, try with artist name only as fallback
          // This handles cases where album name might be different in Apple Music
          if (simplifiedArtist.isNotEmpty) {
            Logging.severe(
                'No results found, trying with artist name only: $simplifiedArtist');

            // Try artist-only search as fallback
            final artistQuery = Uri.encodeComponent(simplifiedArtist);
            final artistUrl = Uri.parse(
                'https://itunes.apple.com/search?term=$artistQuery&entity=album&limit=10');

            final artistResponse = await http.get(artistUrl);

            if (artistResponse.statusCode == 200) {
              final artistData = jsonDecode(artistResponse.body);

              if (artistData['resultCount'] > 0) {
                Logging.severe(
                    'Found ${artistData['resultCount']} albums by artist, considering it a viable Apple Music match');
                return true; // If the artist exists in Apple Music, consider it a viable match
              }
            }
          }

          // Second fallback - just return true for Apple Music to ensure its button is shown
          // We'd rather show Apple Music even when uncertain than not show it at all
          Logging.severe(
              'No Apple Music match found through API, but allowing as fallback');
          return true;
        }
      } else {
        Logging.severe(
            'iTunes API error: ${response.statusCode} - ${response.body}');
      }

      // If we reach here, no match was found through the API
      // For Apple Music specifically, we'll be lenient and return true anyway
      // This ensures the Apple Music button is shown even when direct verification fails
      Logging.severe(
          'No Apple Music match found through direct API, but allowing as fallback');
      return true;
    } catch (e, stack) {
      Logging.severe('Error verifying Apple Music album', e, stack);
      // Be lenient with Apple Music and return true even on errors
      return true;
    }
  }

  /// Check if album actually exists on Deezer
  Future<bool> _verifyDeezerAlbumExists(String artist, String album) async {
    try {
      // Normalize search terms to improve matching
      final normalizedArtist = _normalizeForComparison(artist);
      final normalizedAlbum = _normalizeForComparison(album);

      Logging.severe(
          'Looking for Deezer album: "$normalizedAlbum" by "$normalizedArtist"');

      // Try the more specific query first
      final query1 = Uri.encodeComponent(
          'artist:"$normalizedArtist" album:"$normalizedAlbum"');
      final url1 =
          Uri.parse('https://api.deezer.com/search/album?q=$query1&limit=10');
      Logging.severe('Deezer verification query 1: $url1');
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
                _stringSimilarity(resultArtist, normalizedArtist);
            final albumSimilarity =
                _stringSimilarity(resultAlbum, normalizedAlbum);

            Logging.severe(
                'Deezer match check: "$resultAlbum" by "$resultArtist"');
            Logging.severe(
                'Similarity scores - Title: $albumSimilarity, Artist: $artistSimilarity');

            // More lenient threshold for Deezer matches
            if (artistSimilarity > 0.6 || albumSimilarity > 0.6) {
              Logging.severe('Found valid Deezer match: ${result['title']}');
              return true;
            }
          }
        }
      }

      // If first query fails, try broader search
      final query2 = Uri.encodeComponent('$normalizedArtist $normalizedAlbum');
      final url2 =
          Uri.parse('https://api.deezer.com/search/album?q=$query2&limit=10');
      Logging.severe('Deezer verification query 2: $url2');
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
                _stringSimilarity(resultArtist, normalizedArtist);
            final albumSimilarity =
                _stringSimilarity(resultAlbum, normalizedAlbum);

            if (artistSimilarity > 0.5 || albumSimilarity > 0.5) {
              Logging.severe(
                  'Found valid Deezer match in broad search: ${result['title']}');
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

  /// Simplify text for better matching with basic stopword removal
  String _simplifyText(String text) {
    // Keep only essential parts of album titles
    final stopwords = [
      'the',
      'and',
      'feat',
      'ft',
      'with',
      'by',
      'from',
      'in',
      'on',
      'at'
    ];

    return text
        .split(' ')
        .where((word) => word.length > 1 && !stopwords.contains(word))
        .join(' ')
        .replaceAll(
            RegExp(r'\b(deluxe|edition|version|remaster|ep|single)\b'), '')
        .replaceAll(RegExp(r'[^\w\s]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Calculate string similarity score with improved algorithm
  double _stringSimilarity(String a, String b) {
    if (a.isEmpty || b.isEmpty) return 0.0;

    // Normalize inputs
    a = _normalizeForComparison(a);
    b = _normalizeForComparison(b);

    // Quick check: if one string contains the other entirely
    if (a.contains(b) || b.contains(a)) {
      return 0.9; // Even higher score for complete containment
    }

    // Count matching words with improved logic
    final aWords = a.split(" ").where((w) => w.length > 1).toList();
    final bWords = b.split(" ").where((w) => w.length > 1).toList();

    if (aWords.isEmpty || bWords.isEmpty) {
      return 0.0;
    }

    int matches = 0;
    int totalWords = aWords.length + bWords.length;

    // Weight longer words more heavily
    double totalWeight = 0;
    double matchWeight = 0;

    // Check for word matches
    for (var aWord in aWords) {
      double wordWeight = aWord.length / 3; // Longer words have more weight
      totalWeight += wordWeight;

      for (var bWord in bWords) {
        // Consider exact match or high containment
        if (aWord == bWord ||
            (aWord.length > 3 &&
                bWord.length > 3 &&
                (aWord.contains(bWord) || bWord.contains(aWord)))) {
          matchWeight += wordWeight;
          matches++;
          break;
        }
      }
    }

    // Also add weights for bWords
    for (var bWord in bWords) {
      totalWeight += bWord.length / 3;
    }

    // Calculate final similarity score using both approaches
    double countScore = matches * 2.0 / totalWords;
    double weightScore = totalWeight > 0 ? matchWeight / totalWeight : 0;

    // Use the better of the two scores
    return [countScore, weightScore].reduce((a, b) => a > b ? a : b);
  }

  /// Normalize text for more accurate comparison
  String _normalizeForComparison(String text) {
    if (text.isEmpty) return '';

    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), '') // Remove punctuation
        .replaceAll(RegExp(r'\s+'), ' ') // Normalize whitespace
        .replaceAll(RegExp(r'\(.*?\)'),
            '') // Remove text in parentheses like "(Deluxe Edition)"
        .replaceAll(RegExp(r'\[.*?\]'), '') // Remove text in brackets
        .replaceAll(
            RegExp(r'feat\..*'), '') // Remove "feat." and following text
        .replaceAll(
            RegExp(r'featuring.*'), '') // Remove "featuring" and following text
        .replaceAll(RegExp(r'edition|deluxe|remaster|explicit|clean'),
            '') // Remove common edition words
        .trim();
  }

  /// Verify if a match is accurate by checking album info
  Future<bool> _verifyMatchAccuracy(String platform, String url,
      String normalizedArtist, String normalizedAlbum) async {
    try {
      // For now just verify it's not a search URL
      // In a more robust implementation, you could:
      // 1. Fetch the album metadata from the platform
      // 2. Compare artist and album names
      // 3. Return true only if there's a good match

      // Simple check: make sure it's not a search URL
      if (url.contains('/search?') || url.contains('/search/')) {
        return false;
      }

      return true;
    } catch (e) {
      return false;
    }
  }

  Future<String?> _searchPlatformForAlbum(String platform, String query) async {
    try {
      Logging.severe('Searching on $platform for: $query');

      // Use album metadata first if available
      final metadata = widget.album.metadata;

      // Check if we have platform-specific URLs in the metadata
      if (platform == 'spotify' && metadata.containsKey('spotify_url')) {
        return metadata['spotify_url'];
      } else if (platform == 'apple_music' &&
          metadata.containsKey('apple_music_url')) {
        return metadata['apple_music_url'];
      } else if (platform == 'deezer' && metadata.containsKey('deezer_url')) {
        return metadata['deezer_url'];
      }

      // Extract clean search terms
      final artist = widget.album.artist.trim();
      final albumName = widget.album.name.trim();

      // Actual API lookups for each platform
      if (platform == 'spotify') {
        return await _findSpotifyAlbumUrl(artist, albumName);
      } else if (platform == 'apple_music') {
        return await _findAppleMusicAlbumUrl(artist, albumName);
      } else if (platform == 'deezer') {
        return await _findDeezerAlbumUrl(artist, albumName);
      }
      return null;
    } catch (e, stack) {
      Logging.severe('Error searching $platform', e, stack);
      return null;
    }
  }

  Future<String?> _findSpotifyAlbumUrl(String artist, String albumName) async {
    try {
      final query = Uri.encodeComponent('$artist $albumName');

      // Remove fallback URL creation - don't create or return search URLs

      // Generate a Base64 encoded token from the client credentials
      const credentials =
          '${ApiKeys.spotifyClientId}:${ApiKeys.spotifyClientSecret}';
      final bytes = utf8.encode(credentials);
      final base64Credentials = base64.encode(bytes);

      // Get a proper OAuth token using client credentials flow
      final tokenResponse = await http.post(
        Uri.parse('https://accounts.spotify.com/api/token'),
        headers: {
          'Authorization': 'Basic $base64Credentials',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: 'grant_type=client_credentials',
      );

      String accessToken;
      if (tokenResponse.statusCode == 200) {
        final tokenData = jsonDecode(tokenResponse.body);
        accessToken = tokenData['access_token'];
        Logging.severe('Successfully obtained Spotify OAuth token for search');
      } else {
        Logging.severe(
            'Failed to get Spotify token: ${tokenResponse.statusCode} - ${tokenResponse.body}');
        return null;
      }

      // First try a more precise query format that's more likely to find exact matches
      try {
        // Create a more precise query with specific album and artist criteria
        final preciseQuery =
            Uri.encodeComponent('album:"$albumName" artist:"$artist"');
        final preciseUrl = Uri.parse(
            'https://api.spotify.com/v1/search?q=$preciseQuery&type=album&limit=10');

        final preciseResponse = await http
            .get(preciseUrl, headers: {'Authorization': 'Bearer $accessToken'});

        if (preciseResponse.statusCode == 200) {
          final data = jsonDecode(preciseResponse.body);

          if (data['albums'] != null &&
              data['albums']['items'] != null &&
              data['albums']['items'].isNotEmpty) {
            // This is likely to be an exact match since we used precise query
            final albumUrl =
                data['albums']['items'][0]['external_urls']['spotify'];
            Logging.severe(
                'Found direct album match with precise query: $albumUrl');
            return albumUrl;
          }
        }
      } catch (e) {
        // If precise query fails, we'll try the standard query next
        Logging.severe(
            'Precise Spotify query failed, trying standard query', e);
      }

      // Try the standard search as our second attempt
      try {
        final url = Uri.parse(
            'https://api.spotify.com/v1/search?q=$query&type=album&limit=10');
        final response = await http
            .get(url, headers: {'Authorization': 'Bearer $accessToken'});

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);

          if (data['albums'] != null &&
              data['albums']['items'] != null &&
              data['albums']['items'].isNotEmpty) {
            final albums = data['albums']['items'];

            // Look for exact matches with better scoring
            final scoredMatches = <Map<String, dynamic>>[];

            for (final album in albums) {
              final albumArtist =
                  album['artists'][0]['name'].toString().toLowerCase();
              final albumTitle = album['name'].toString().toLowerCase();
              final artistSimilarity =
                  _stringSimilarity(albumArtist, artist.toLowerCase());
              final titleSimilarity =
                  _stringSimilarity(albumTitle, albumName.toLowerCase());
              final totalScore = artistSimilarity * 0.6 +
                  titleSimilarity * 0.4; // Weight artist higher

              scoredMatches.add({'album': album, 'score': totalScore});
            }

            // Sort by score, highest first
            scoredMatches.sort((a, b) =>
                (b['score'] as double).compareTo(a['score'] as double));

            // Get the best match
            if (scoredMatches.isNotEmpty && scoredMatches[0]['score'] > 0.5) {
              final bestMatch = scoredMatches[0]['album'];
              final spotifyUrl = bestMatch['external_urls']['spotify'];
              Logging.severe(
                  'Found Spotify match with score ${scoredMatches[0]['score']}: $spotifyUrl');
              return spotifyUrl;
            }

            // If no good match by score, at least return the first album
            return albums[0]['external_urls']['spotify'];
          }
        } else {
          Logging.severe(
              'Spotify API error: ${response.statusCode} - ${response.body}');
        }
      } catch (e) {
        Logging.severe('Error in Spotify API call', e);
      }

      // Use search URL only as a last resort
      Logging.severe('No direct Spotify album match found');
      return null; // Don't return a search URL
    } catch (e, stack) {
      Logging.severe('Error finding Spotify album', e, stack);
      return null; // Don't return a search URL
    }
  }

  Future<String?> _findAppleMusicAlbumUrl(
      String artist, String albumName) async {
    try {
      // Normalize search terms for better results
      final normalizedArtist = _normalizeForComparison(artist);
      final normalizedAlbum = _normalizeForComparison(albumName);

      // Log the search query
      Logging.severe(
          'iTunes Search: looking for "$normalizedAlbum" by "$normalizedArtist"');

      // Use the iTunes Search API
      final combinedQuery =
          Uri.encodeComponent("$normalizedArtist $normalizedAlbum");
      final url = Uri.parse(
          'https://itunes.apple.com/search?term=$combinedQuery&entity=album&limit=10');

      Logging.severe('iTunes Search URL: $url');

      // Remove fallback URL creation - don't define a fallback URL

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        Logging.severe('iTunes API found ${data['resultCount']} results');

        if (data['results'] != null && data['results'].isNotEmpty) {
          final albums = data['results'] as List;

          // First, look for direct matches where both artist and album name are very close
          for (var album in albums) {
            final resultArtist = album['artistName'].toString().toLowerCase();
            final resultAlbum =
                album['collectionName'].toString().toLowerCase();

            // Make sure the collectionViewUrl exists and is valid
            if (album['collectionViewUrl'] == null ||
                !(album['collectionViewUrl'] as String)
                    .contains('music.apple.com')) {
              continue;
            }

            // Direct match - both artist and album title match closely
            if ((resultArtist.contains(normalizedArtist) ||
                    normalizedArtist.contains(resultArtist)) &&
                (resultAlbum.contains(normalizedAlbum) ||
                    normalizedAlbum.contains(resultAlbum))) {
              Logging.severe(
                  'Found direct Apple Music match: ${album['collectionName']}');

              // Convert iTunes URL to Apple Music URL if needed
              String directUrl = album['collectionViewUrl'].toString();

              // Log the direct URL we found
              Logging.severe('Using direct Apple Music URL: $directUrl');

              return directUrl;
            }
          }

          // If no direct match, try to find the best match by similarity
          double bestScore = 0;
          Map<String, dynamic>? bestMatch;

          for (var album in albums) {
            // Skip entries without valid URLs
            if (album['collectionViewUrl'] == null) continue;

            final resultArtist = album['artistName'].toString().toLowerCase();
            final resultAlbum =
                album['collectionName'].toString().toLowerCase();

            // Calculate combined score
            final artistSimilarity =
                _stringSimilarity(resultArtist, normalizedArtist);
            final albumSimilarity =
                _stringSimilarity(resultAlbum, normalizedAlbum);
            final score = (artistSimilarity * 0.6) + (albumSimilarity * 0.4);

            Logging.severe('Score for "${album['collectionName']}": $score');

            if (score > bestScore) {
              bestScore = score;
              bestMatch = album;
            }
          }

          // If we found a good match, use it
          if (bestMatch != null && bestScore > 0.4) {
            String directUrl = bestMatch['collectionViewUrl'].toString();

            Logging.severe(
                'Found best Apple Music match with score $bestScore: ${bestMatch['collectionName']}');
            Logging.severe('Using best match URL: $directUrl');

            return directUrl;
          }

          // If we have any result but no good match, just return the first one with a valid URL
          for (var album in albums) {
            if (album['collectionViewUrl'] != null &&
                (album['collectionViewUrl'] as String).isNotEmpty) {
              String firstUrl = album['collectionViewUrl'].toString();
              // Make sure the URL is from music.apple.com, not itunes.apple.com
              if (!firstUrl.contains('music.apple.com')) {
                firstUrl = firstUrl.replaceFirst(
                    'itunes.apple.com', 'music.apple.com');
              }
              Logging.severe(
                  'Using first available Apple Music URL: $firstUrl');
              return firstUrl;
            }
          }
        } else {
          // No results found, try with artist name only as a secondary search
          try {
            final artistQuery = Uri.encodeComponent(normalizedArtist);
            final artistUrl = Uri.parse(
                'https://itunes.apple.com/search?term=$artistQuery&entity=album&limit=10');

            final artistResponse = await http.get(artistUrl);

            if (artistResponse.statusCode == 200) {
              final artistData = jsonDecode(artistResponse.body);

              if (artistData['resultCount'] > 0) {
                // Use the first album result if the artist exists
                final albums = artistData['results'] as List;
                if (albums.isNotEmpty &&
                    albums[0]['collectionViewUrl'] != null) {
                  String directUrl = albums[0]['collectionViewUrl'].toString();
                  Logging.severe(
                      'Using first album by artist as fallback: $directUrl');
                  return directUrl;
                }
              }
            }
          } catch (e) {
            Logging.severe('Error in artist-only search fallback', e);
          }
        }
      } else {
        Logging.severe(
            'iTunes API error: ${response.statusCode} - ${response.body}');
      }

      // Don't return a fallback search URL
      return null;
    } catch (e, stack) {
      Logging.severe('Error finding Apple Music album', e, stack);
      // Don't return a fallback search URL
      return null;
    }
  }

  Future<String?> _findDeezerAlbumUrl(String artist, String albumName) async {
    try {
      final query = Uri.encodeComponent('$artist $albumName');

      // Deezer search API
      final url =
          Uri.parse('https://api.deezer.com/search/album?q=$query&limit=5');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['data'] != null && data['data'].isNotEmpty) {
          final albums = data['data'];

          // Look for best match
          for (final album in albums) {
            final albumArtist =
                album['artist']['name'].toString().toLowerCase();
            final albumTitle = album['title'].toString().toLowerCase();

            if (albumArtist.contains(artist.toLowerCase()) &&
                albumTitle.contains(albumName.toLowerCase())) {
              return album['link'];
            }
          }

          // If no good match, return first result
          return albums[0]['link'];
        }
      }

      // Don't return a fallback search URL
      return null;
    } catch (e, stack) {
      Logging.severe('Error finding Deezer album', e, stack);
      return null; // Don't return a search URL
    }
  }

  /// Determine which platform a URL belongs to
  String _determinePlatformFromUrl(String url) {
    final lowerUrl = url.toLowerCase();
    String platform = '';

    if (lowerUrl.contains('spotify.com') || lowerUrl.contains('open.spotify')) {
      platform = 'spotify';
    } else if (lowerUrl.contains('music.apple.com') ||
        lowerUrl.contains('itunes.apple.com')) {
      platform = 'apple_music'; // Always return 'apple_music' for consistency
    } else if (lowerUrl.contains('deezer.com')) {
      platform = 'deezer';
    } else if (lowerUrl.contains('bandcamp.com')) {
      platform = 'bandcamp';
    }

    if (platform.isNotEmpty) {
      Logging.severe('Detected platform from URL: $platform for URL: $url');
    }

    return platform;
  }

  @override
  Widget build(BuildContext context) {
    // Don't show anything if we have no matches
    if (_isLoading) {
      return _buildSkeletonButtons();
    }

    // Get list of platforms that have valid URLs
    final availablePlatforms = _platformUrls.entries
        .where((entry) => entry.value != null && entry.value!.isNotEmpty)
        .map((entry) => entry.key)
        .toList();

    // Don't show anything if no platform links are available
    if (availablePlatforms.isEmpty) {
      return const SizedBox.shrink();
    }

    // Make sure bandcamp is in the sorted order if it exists
    // Order platforms: apple_music, spotify, deezer, bandcamp, others
    availablePlatforms.sort((a, b) {
      final order = {
        'apple_music': 0,
        'spotify': 1,
        'deezer': 2,
        'bandcamp': 3,
      };
      return (order[a] ?? 99).compareTo(order[b] ?? 99);
    });

    // Only hide the widget if the only match is the current platform AND it's not bandcamp
    // This allows bandcamp links to always show, but hides redundant platform links
    if (availablePlatforms.length == 1 &&
        availablePlatforms.first == widget.album.platform.toLowerCase() &&
        availablePlatforms.first != 'bandcamp') {
      return const SizedBox.shrink();
    }

    return Padding(
      // Reduce padding to make the entire widget more compact vertically
      padding:
          const EdgeInsets.symmetric(vertical: 0), // Reduced from 4.0 to 2.0
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: availablePlatforms.map((platform) {
          final button = _buildPlatformButton(platform);
          // Reduce spacers between buttons even further
          return availablePlatforms.indexOf(platform) <
                  availablePlatforms.length - 1
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    button,
                    const SizedBox(width: 6), // Reduced from 8 to 6
                  ],
                )
              : button;
        }).toList(),
      ),
    );
  }

  /// Build skeleton loading buttons while waiting for platform matches
  Widget _buildSkeletonButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildSkeletonButton(),
        const SizedBox(width: 16),
        _buildSkeletonButton(),
        const SizedBox(width: 16),
        _buildSkeletonButton(),
      ],
    );
  }

  /// Build an individual skeleton button
  Widget _buildSkeletonButton() {
    return SkeletonLoading(
      width: widget.buttonSize,
      height: widget.buttonSize,
      borderRadius: widget.buttonSize / 2,
    );
  }

  Widget _buildPlatformButton(String platform) {
    final bool hasMatch =
        _platformUrls.containsKey(platform) && _platformUrls[platform] != null;

    // Check if this is the current platform of the album
    // Fix iTunes/Apple Music platform comparison
    bool isSelected = false;

    final String currentPlatform = widget.album.platform.toLowerCase();

    if (platform == 'apple_music' &&
        (currentPlatform == 'itunes' || currentPlatform == 'apple_music')) {
      isSelected = true;
    } else if (platform == currentPlatform) {
      isSelected = true;
    }

    // Debug log to see what URLs we're using
    if (hasMatch) {
      Logging.severe(
          'Platform $platform URL: ${_platformUrls[platform]}, isSelected: $isSelected');
    }

    // Use SVG icons for better quality
    String iconPath;
    switch (platform) {
      case 'spotify':
        iconPath = 'lib/icons/spotify.svg';
        break;
      case 'apple_music':
        iconPath = 'lib/icons/apple_music.svg';
        break;
      case 'deezer':
        iconPath = 'lib/icons/deezer.svg';
        break;
      case 'bandcamp':
        iconPath = 'lib/icons/bandcamp.svg';
        break;
      default:
        iconPath = '';
    }

    // Determine icon color based on theme and selection state
    final isDarkTheme = Theme.of(context).brightness == Brightness.dark;
    // Use primary color if selected, otherwise use default icon color
    final iconColor = isSelected
        ? Theme.of(context).colorScheme.primary
        : (isDarkTheme ? Colors.white : Colors.black);

    // Create button content
    final buttonContent = SizedBox(
      width: widget.buttonSize,
      height: widget.buttonSize,
      child: iconPath.isNotEmpty
          ? Padding(
              padding: const EdgeInsets.all(4.0), // Reduced from 8.0 to 4.0,
              child: SvgPicture.asset(
                iconPath,
                height: widget.buttonSize - 8, // Increased from 16 to 8
                width: widget.buttonSize - 8, // Increased from 16 to 8
                colorFilter: ColorFilter.mode(iconColor, BlendMode.srcIn),
              ),
            )
          : Icon(
              Icons.music_note,
              size: widget.buttonSize - 8, // Increased from 16 to 8
              color: iconColor,
            ),
    );

    // Add context menu for desktop platforms (right click)
    // and support long press for mobile platforms
    return Opacity(
      opacity: hasMatch ? 1.0 : 0.5,
      child: Tooltip(
        message: hasMatch
            ? (isSelected
                ? 'Current platform: ${_getPlatformName(platform)}'
                : 'Open in ${_getPlatformName(platform)}')
            : 'No match found in ${_getPlatformName(platform)}',
        child: GestureDetector(
          onLongPress: hasMatch
              ? () => _showContextMenu(platform, _platformUrls[platform]!)
              : null,
          child: InkWell(
            onTap: hasMatch ? () => _openUrl(_platformUrls[platform]!) : null,
            borderRadius: BorderRadius.circular(widget.buttonSize / 2),
            onSecondaryTap: hasMatch
                ? () => _showContextMenu(platform, _platformUrls[platform]!)
                : null,
            child: buttonContent,
          ),
        ),
      ),
    );
  }

  // Show context menu for mobile platforms via long press
  void _showContextMenu(String platform, String url) {
    final RenderBox button = context.findRenderObject() as RenderBox;
    final Offset position = button.localToGlobal(Offset.zero);
    final Size buttonSize = button.size;

    // Position menu below the button and centered horizontally
    const double menuWidth = 200; // Estimated menu width
    final double centerX = position.dx + (buttonSize.width / 2);
    final double leftPosition = centerX - (menuWidth / 2);

    final RelativeRect rect = RelativeRect.fromLTRB(
      leftPosition, // LEFT: centered horizontally
      position.dy + buttonSize.height + 5, // TOP: just below the button
      MediaQuery.of(context).size.width - leftPosition - menuWidth, // RIGHT
      0, // BOTTOM: not constrained
    );

    showMenu<String>(
      context: context,
      position: rect,
      items: [
        PopupMenuItem<String>(
          value: 'copy',
          height: 26, // Set a smaller height for more compact appearance
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: Row(
            children: [
              const Icon(Icons.copy, size: 26),
              const SizedBox(width: 6),
              Text('Copy ${_getPlatformName(platform)} URL'),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'open',
          height: 26, // Set a smaller height for more compact appearance
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: Row(
            children: [
              const Icon(Icons.open_in_new, size: 26),
              const SizedBox(width: 6),
              Text('Open in ${_getPlatformName(platform)}'),
            ],
          ),
        ),
        // Add Share option
        PopupMenuItem<String>(
          value: 'share',
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: Row(
            children: [
              const Icon(Icons.share, size: 26),
              const SizedBox(width: 6),
              Text('Share ${_getPlatformName(platform)} Link'),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == 'copy') {
        _copyUrlToClipboard(platform, url);
      } else if (value == 'open') {
        _openUrl(url);
      } else if (value == 'share') {
        _shareUrl(platform, url);
      }
    });
  }

  // Copy URL to clipboard and show feedback
  void _copyUrlToClipboard(String platform, String url) async {
    try {
      await Clipboard.setData(ClipboardData(text: url));
      // Show feedback using a snackbar
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('${_getPlatformName(platform)} URL copied to clipboard'),
            duration: const Duration(seconds: 2),
          ),
        );
      }

      Logging.severe('Copied URL to clipboard: $url');
    } catch (e, stack) {
      Logging.severe('Error copying URL to clipboard', e, stack);
    }
  }

  // Add new method to handle sharing
  void _shareUrl(String platform, String url) async {
    try {
      // For desktop platforms, copy to clipboard and show a message
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        await Clipboard.setData(ClipboardData(text: url));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  '${_getPlatformName(platform)} URL copied to clipboard for sharing'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } else {
        // For mobile platforms, use the share plugin
        // Import package:share_plus/share_plus.dart at the top of the file
        Share.share(
          'Check out this album on ${_getPlatformName(platform)}: $url',
          subject: 'Album link from RateMe',
        );
      }
      Logging.severe('Shared URL: $url');
    } catch (e, stack) {
      Logging.severe('Error sharing URL', e, stack);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error sharing: $e'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  String _getPlatformName(String platform) {
    switch (platform) {
      case 'spotify':
        return 'Spotify';
      case 'apple_music':
        return 'Apple Music';
      case 'deezer':
        return 'Deezer';
      case 'bandcamp':
        return 'Bandcamp';
      default:
        return platform.split('_').map((s) => s.capitalize()).join(' ');
    }
  }

  Future<void> _openUrl(String url) async {
    try {
      // Log the URL we're trying to open
      Logging.severe('Opening URL: $url');
      final uri = Uri.parse(url);
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e, stack) {
      Logging.severe('Error opening URL: $url', e, stack);
    }
  }
}

// Define the extension outside the class
extension StringExtension on String {
  String capitalize() {
    return isEmpty ? this : '${this[0].toUpperCase()}${substring(1)}';
  }
}
