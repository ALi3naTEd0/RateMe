import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../album_model.dart';
import '../logging.dart';
import '../api_keys.dart';
import '../widgets/skeleton_loading.dart'; // Add this import for skeleton loading

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

      // Only search for additional platforms if not a Bandcamp-only album
      if (!isBandcamp || currentPlatform != 'bandcamp') {
        // Create search query from album and artist
        final searchQuery =
            '${widget.album.artist} ${widget.album.name}'.trim();
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

    for (final platform in platformsToVerify) {
      if (_platformUrls.containsKey(platform)) {
        final url = _platformUrls[platform];

        if (url == null || url.isEmpty) {
          platformsToRemove.add(platform);
          continue;
        }

        // Skip verification for the source platform
        if (platform == widget.album.platform.toLowerCase()) {
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
        'After verification, have ${_platformUrls.length} valid platform matches');
  }

  /// More thorough validation for search URLs
  Future<bool> _validatePlatformMatch(
      String platform, String url, String artistName, String albumName) async {
    try {
      // For each platform, attempt to verify if the album really exists
      if (platform == 'spotify') {
        return await _verifySpotifyAlbumExists(artistName, albumName);
      } else if (platform == 'apple_music') {
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
      String? accessToken;
      try {
        accessToken = await ApiKeys.getSpotifyToken();
      } catch (e) {
        return false;
      }

      if (accessToken == null) return false;

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
      final query = Uri.encodeComponent('$artist $album');
      final url = Uri.parse(
          'https://itunes.apple.com/search?term=$query&entity=album&limit=5');

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['results'] != null && data['results'].isNotEmpty) {
          for (var result in data['results']) {
            final resultArtist = result['artistName'].toString().toLowerCase();
            final resultAlbum =
                result['collectionName'].toString().toLowerCase();

            if (_stringSimilarity(resultArtist, artist) > 0.7 &&
                _stringSimilarity(resultAlbum, album) > 0.7) {
              return true;
            }
          }
        }
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Check if album actually exists on Deezer
  Future<bool> _verifyDeezerAlbumExists(String artist, String album) async {
    try {
      final query = Uri.encodeComponent('artist:"$artist" album:"$album"');
      final url =
          Uri.parse('https://api.deezer.com/search/album?q=$query&limit=5');

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['data'] != null && data['data'].isNotEmpty) {
          for (var result in data['data']) {
            final resultArtist =
                result['artist']['name'].toString().toLowerCase();
            final resultAlbum = result['title'].toString().toLowerCase();

            if (_stringSimilarity(resultArtist, artist) > 0.7 &&
                _stringSimilarity(resultAlbum, album) > 0.7) {
              return true;
            }
          }
        }
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Calculate string similarity score (simple implementation)
  double _stringSimilarity(String a, String b) {
    if (a.isEmpty || b.isEmpty) return 0.0;

    a = a.toLowerCase();
    b = b.toLowerCase();

    // Quick check: if one contains the other
    if (a.contains(b) || b.contains(a)) {
      return 0.8;
    }

    // Count matching words
    final aWords = a.split(" ").where((w) => w.isNotEmpty).toList();
    final bWords = b.split(" ").where((w) => w.isNotEmpty).toList();

    int matches = 0;
    for (var aWord in aWords) {
      for (var bWord in bWords) {
        if (aWord == bWord || aWord.contains(bWord) || bWord.contains(aWord)) {
          matches++;
          break;
        }
      }
    }

    final totalWords = aWords.length + bWords.length;
    return totalWords > 0 ? (matches * 2) / totalWords : 0.0;
  }

  /// Normalize text for more accurate comparison
  String _normalizeForComparison(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), '') // Remove punctuation
        .replaceAll(RegExp(r'\s+'), ' ') // Normalize whitespace
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

      // Create a direct search fallback URL only as last resort
      final fallbackUrl = 'https://open.spotify.com/search/$query';

      String? accessToken;
      try {
        // Get app's client credentials token specifically for APIs
        accessToken = await ApiKeys.getSpotifyToken();
        Logging.severe('Spotify API token available: ${accessToken != null}');
      } catch (e) {
        Logging.severe('Error getting Spotify app token: $e, using fallback');
        return fallbackUrl;
      }

      if (accessToken == null) {
        Logging.severe(
            'No Spotify app token available, falling back to search URL');
        return fallbackUrl;
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
      Logging.severe('No direct Spotify album match found, using search URL');
      return fallbackUrl;
    } catch (e, stack) {
      Logging.severe('Error finding Spotify album', e, stack);
      return 'https://open.spotify.com/search/${Uri.encodeComponent("$artist $albumName")}';
    }
  }

  Future<String?> _findAppleMusicAlbumUrl(
      String artist, String albumName) async {
    try {
      final query = Uri.encodeComponent('$artist $albumName');

      // Apple Music search API
      final url = Uri.parse(
          'https://itunes.apple.com/search?term=$query&entity=album&limit=5');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['results'] != null && data['results'].isNotEmpty) {
          final albums = data['results'];

          // Look for best match
          for (final album in albums) {
            final albumArtist = album['artistName'].toString().toLowerCase();
            final albumTitle = album['collectionName'].toString().toLowerCase();

            if (albumArtist.contains(artist.toLowerCase()) &&
                albumTitle.contains(albumName.toLowerCase())) {
              return album['collectionViewUrl'];
            }
          }

          // If no good match, return first result
          return albums[0]['collectionViewUrl'];
        }
      }

      // Fallback to search
      return 'https://music.apple.com/us/search?term=$query';
    } catch (e, stack) {
      Logging.severe('Error finding Apple Music album', e, stack);
      return 'https://music.apple.com/us/search?term=${Uri.encodeComponent("$artist $albumName")}';
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

      // Fallback to search
      return 'https://www.deezer.com/search/$query';
    } catch (e, stack) {
      Logging.severe('Error finding Deezer album', e, stack);
      return 'https://www.deezer.com/search/${Uri.encodeComponent("$artist $albumName")}';
    }
  }

  /// Determine which platform a URL belongs to
  String _determinePlatformFromUrl(String url) {
    final lowerUrl = url.toLowerCase();

    if (lowerUrl.contains('spotify.com') || lowerUrl.contains('open.spotify')) {
      return 'spotify';
    } else if (lowerUrl.contains('music.apple.com') ||
        lowerUrl.contains('itunes.apple.com')) {
      return 'apple_music';
    } else if (lowerUrl.contains('deezer.com')) {
      return 'deezer';
    } else if (lowerUrl.contains('bandcamp.com')) {
      return 'bandcamp'; // Note: We don't directly support Bandcamp as a platform for matching
    }

    return '';
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

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: availablePlatforms.map((platform) {
        final button = _buildPlatformButton(platform);
        // Add spacers between buttons
        return availablePlatforms.indexOf(platform) <
                availablePlatforms.length - 1
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  button,
                  const SizedBox(width: 16),
                ],
              )
            : button;
      }).toList(),
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

    // Debug log to see what URLs we're using
    if (hasMatch) {
      Logging.severe('Platform $platform URL: ${_platformUrls[platform]}');
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

    return Opacity(
      opacity: hasMatch ? 1.0 : 0.5,
      child: Tooltip(
        message: hasMatch
            ? 'Open in ${_getPlatformName(platform)}'
            : 'No match found in ${_getPlatformName(platform)}',
        child: InkWell(
          onTap: hasMatch ? () => _openUrl(_platformUrls[platform]!) : null,
          borderRadius: BorderRadius.circular(widget.buttonSize / 2),
          child: SizedBox(
            width: widget.buttonSize,
            height: widget.buttonSize,
            child: iconPath.isNotEmpty
                ? Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: SvgPicture.asset(
                      iconPath,
                      height: widget.buttonSize - 16,
                      width: widget.buttonSize - 16,
                    ),
                  )
                : Icon(
                    Icons.music_note,
                    size: widget.buttonSize - 16,
                    color: _getPlatformColor(platform),
                  ),
          ),
        ),
      ),
    );
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

  Color _getPlatformColor(String platform) {
    switch (platform) {
      case 'spotify':
        return const Color(0xFF1DB954);
      case 'apple_music':
        return const Color(0xFFFC3C44);
      case 'deezer':
        return const Color(0xFF00C7F2);
      case 'bandcamp':
        return const Color(0xFF1DA0C3);
      default:
        return Colors.grey;
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
