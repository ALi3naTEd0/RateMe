import 'dart:async';
import 'package:flutter/services.dart';
import 'logging.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

/// Utility class for detecting album URLs in clipboard
class ClipboardDetector {
  static Timer? _clipboardTimer;
  static bool _isProcessingClipboard = false;
  static Timer? _resetTimer;

  // Define timeouts for reset operations
  static const int _autoResetSeconds = 15; // Reset after automatic detection

  /// Start listening to clipboard for URLs
  static Timer startClipboardListener({
    required Function(String) onDetected,
    required Function(String) onSnackBarMessage,
    required Function(String, String) onUrlDetected,
    required Function(bool) onSearchCompleted,
    Duration checkInterval = const Duration(seconds: 2),
  }) {
    // Cancel any existing timer to prevent multiple instances
    stopClipboardListener();

    // Reset processing state
    _isProcessingClipboard = false;

    Logging.severe('Starting clipboard listener');

    _clipboardTimer = Timer.periodic(checkInterval, (timer) async {
      // This is just a maintenance timer - no need to check clipboard automatically
    });

    return _clipboardTimer!;
  }

  /// Check if text contains a music URL
  static bool _containsMusicUrl(String text) {
    final lowerText = text.toLowerCase();
    return lowerText.contains('music.apple.com') ||
        lowerText.contains('itunes.apple.com') ||
        lowerText.contains('apple.co') ||
        lowerText.contains('bandcamp.com') ||
        lowerText.contains('.bandcamp.') ||
        lowerText.contains('spotify.com') ||
        lowerText.contains('open.spotify') ||
        lowerText.contains('deezer.com') ||
        lowerText.contains('discogs.com');
  }

  /// Extract artist and album name from Apple Music URL
  static Future<String> _extractAppleMusicInfo(String url) async {
    try {
      // Apple Music URLs look like:
      // https://music.apple.com/us/album/album-name/id

      // Extract the album ID from the URL
      final regExp = RegExp(r'/album/[^/]+/(\d+)');
      final match = regExp.firstMatch(url);

      if (match != null && match.groupCount >= 1) {
        final albumId = match.group(1);
        Logging.severe('Extracted Apple Music album ID: $albumId');

        // Use the iTunes lookup API to get album details
        final response = await http.get(Uri.parse(
            'https://itunes.apple.com/lookup?id=$albumId&entity=song'));

        if (response.statusCode == 200) {
          final data = json.decode(response.body);

          if (data['resultCount'] > 0) {
            final albumInfo = data['results'][0];
            final artistName = albumInfo['artistName'];
            final albumName = albumInfo['collectionName'];

            Logging.severe(
                'Extracted from Apple Music: $artistName - $albumName');
            return '$artistName $albumName';
          }
        }
      }

      // If we couldn't extract using API, try to extract from URL path
      final albumPathRegExp = RegExp(r'/album/([^/]+)/');
      final albumPathMatch = albumPathRegExp.firstMatch(url);

      if (albumPathMatch != null && albumPathMatch.groupCount >= 1) {
        String albumName = albumPathMatch.group(1) ?? '';
        // Replace hyphens with spaces and clean up
        albumName = albumName.replaceAll('-', ' ').trim();

        Logging.severe('Extracted album name from URL path: $albumName');
        return albumName;
      }
    } catch (e) {
      Logging.severe('Error extracting Apple Music info', e);
    }

    return '';
  }

  /// Extract artist and album name from Bandcamp URL
  static String _extractBandcampInfo(String url) {
    try {
      // Bandcamp URLs look like:
      // https://artist.bandcamp.com/album/album-name

      // Extract artist name from domain
      final domainRegExp = RegExp(r'https?://([^.]+)\.bandcamp\.com');
      final domainMatch = domainRegExp.firstMatch(url);

      // Extract album name from path
      final albumRegExp = RegExp(r'/album/([^/]+)');
      final albumMatch = albumRegExp.firstMatch(url);

      String artist = '';
      String album = '';

      if (domainMatch != null && domainMatch.groupCount >= 1) {
        artist = domainMatch.group(1) ?? '';
        artist = artist.replaceAll('-', ' ');
      }

      if (albumMatch != null && albumMatch.groupCount >= 1) {
        album = albumMatch.group(1) ?? '';
        album = album.replaceAll('-', ' ');
      }

      if (artist.isNotEmpty && album.isNotEmpty) {
        Logging.severe('Extracted from Bandcamp: $artist - $album');
        return '$artist $album';
      }
    } catch (e) {
      Logging.severe('Error extracting Bandcamp info', e);
    }

    return '';
  }

  /// Extract artist and album name from Spotify URL
  static Future<String> _extractSpotifyInfo(String url) async {
    try {
      // Spotify URLs look like:
      // https://open.spotify.com/album/albumId

      // Extract the album ID from the URL
      final regExp = RegExp(r'/album/([a-zA-Z0-9]+)');
      final match = regExp.firstMatch(url);

      if (match != null && match.groupCount >= 1) {
        final albumId = match.group(1);
        Logging.severe('Extracted Spotify album ID: $albumId');

        // We would need Spotify API credentials to look up the album details
        // For now, just return empty string since we can't easily query the Spotify API
      }
    } catch (e) {
      Logging.severe('Error extracting Spotify info', e);
    }

    return '';
  }

  /// Extract artist and album name from Deezer URL
  static Future<String> _extractDeezerInfo(String url) async {
    try {
      // Deezer URLs look like:
      // https://www.deezer.com/album/548412382

      // Extract the album ID from the URL
      final regExp = RegExp(r'/album/(\d+)');
      final match = regExp.firstMatch(url);

      if (match != null && match.groupCount >= 1) {
        final albumId = match.group(1);
        Logging.severe('Extracted Deezer album ID: $albumId');

        // Use the Deezer API to get album details
        final response = await http.get(
          Uri.parse('https://api.deezer.com/album/$albumId'),
        );

        if (response.statusCode == 200) {
          final data = json.decode(response.body);

          if (data.containsKey('title') && data.containsKey('artist')) {
            final artistName = data['artist']['name'];
            final albumName = data['title'];

            Logging.severe('Extracted from Deezer: $artistName - $albumName');
            return '$artistName $albumName';
          }
        }
      }

      // If we couldn't extract properly, just return the URL for direct processing
      return url;
    } catch (e) {
      Logging.severe('Error extracting Deezer info', e);
      return url;
    }
  }

  /// Extract artist and album name from Discogs URL
  static Future<String> _extractDiscogsInfo(String url) async {
    try {
      // Discogs URLs look like:
      // https://www.discogs.com/master/1211526 or
      // https://www.discogs.com/release/12345678

      // Extract the ID and type from the URL
      final regExp = RegExp(r'/(master|release)/(\d+)');
      final match = regExp.firstMatch(url);

      if (match != null && match.groupCount >= 2) {
        final type = match.group(1);
        final id = match.group(2);
        Logging.severe('Extracted Discogs $type ID: $id');

        // Use the Discogs API to get release details
        final apiUrl = 'https://api.discogs.com/$type' 's/$id';

        // Add simple headers for unauthenticated request
        final response = await http.get(
          Uri.parse(apiUrl),
          headers: {'User-Agent': 'RateMe/1.0'},
        );

        if (response.statusCode == 200) {
          final data = json.decode(response.body);

          String artistName = '';
          String albumName = '';

          // Handle different response structures based on type
          if (type == 'master') {
            if (data['artists'] != null && data['artists'].isNotEmpty) {
              artistName = data['artists'][0]['name'] ?? '';
            }
            albumName = data['title'] ?? '';
          } else {
            // For releases
            artistName = data['artists_sort'] ?? '';
            albumName = data['title'] ?? '';
          }

          if (artistName.isNotEmpty && albumName.isNotEmpty) {
            Logging.severe('Extracted from Discogs: $artistName - $albumName');
            return '$artistName $albumName';
          }
        }
      }
    } catch (e) {
      Logging.severe('Error extracting Discogs info', e);
    }

    return '';
  }

  /// Stop listening to clipboard
  static void stopClipboardListener() {
    _clipboardTimer?.cancel();
    _resetTimer?.cancel();
    _clipboardTimer = null;
    _resetTimer = null;
    _isProcessingClipboard = false;
  }

  /// Report search result to prevent looping
  static void reportSearchResult(bool success) {
    // This method is kept for API compatibility but doesn't need to do anything
  }

  /// Process text that might contain a music URL
  /// This is the main entry point that should be called when text is pasted or entered
  static Future<bool> processText(
    String text, {
    required Function(String) onDetected,
    required Function(String) onSnackBarMessage,
    required Function(String, String) onUrlDetected,
    required Function(bool) onSearchCompleted,
  }) async {
    if (text.isEmpty) return false;

    // First check if this text contains a music URL
    if (!_containsMusicUrl(text)) {
      Logging.severe('Text does not contain a music URL: $text');
      return false;
    }

    Logging.severe('Processing text that contains a music URL: $text');

    // Prevent processing while another operation is in progress
    if (_isProcessingClipboard) {
      Logging.severe('Already processing, will skip this request');
      return false;
    }

    _isProcessingClipboard = true;

    try {
      final lowerText = text.toLowerCase();

      // Platform detection
      final bool isAppleMusic = lowerText.contains('music.apple.com') ||
          lowerText.contains('itunes.apple.com') ||
          lowerText.contains('apple.co') ||
          lowerText.contains('apple music');

      final bool isBandcamp = lowerText.contains('bandcamp.com') ||
          lowerText.contains('.bandcamp.') ||
          lowerText.contains('bandcamp:');

      final bool isSpotify = lowerText.contains('spotify.com') ||
          lowerText.contains('open.spotify');

      final bool isDeezer = lowerText.contains('deezer.com');

      final bool isDiscogs = lowerText.contains('discogs.com');

      if (isAppleMusic || isBandcamp || isSpotify || isDeezer || isDiscogs) {
        String platform = 'unknown';
        if (isAppleMusic) platform = 'Apple Music';
        if (isBandcamp) platform = 'Bandcamp';
        if (isSpotify) platform = 'Spotify';
        if (isDeezer) platform = 'Deezer';
        if (isDiscogs) platform = 'Discogs';

        Logging.severe('$platform URL detected');

        // Extract search query
        String searchQuery = '';
        if (isAppleMusic) {
          searchQuery = await _extractAppleMusicInfo(text);
        } else if (isBandcamp) {
          searchQuery = _extractBandcampInfo(text);
        } else if (isSpotify) {
          searchQuery = await _extractSpotifyInfo(text);
        } else if (isDeezer) {
          searchQuery = await _extractDeezerInfo(text);
        } else if (isDiscogs) {
          searchQuery = await _extractDiscogsInfo(text);
        }

        // Handle the URL appropriately
        // We have a valid search query, but for Deezer, Bandcamp, Apple Music, or Spotify we want to handle URLs differently
        if (isDeezer) {
          // Check if it's a valid Deezer album URL (just for logging)
          final regExp = RegExp(r'/album/(\d+)');
          final match = regExp.firstMatch(text);

          if (match != null) {
            Logging.severe('Valid Deezer album URL detected');
          } else {
            Logging.severe(
                'Could not extract album ID from Deezer URL - handling as is');
          }

          // Just show a notification and use the URL as-is
          onSnackBarMessage('Deezer album found');
          onDetected(text); // Use the original URL directly
        } else if (isBandcamp) {
          // For Bandcamp, we also want to use the direct URL
          Logging.severe(
              'Bandcamp URL detected - using direct URL for fetching');
          onSnackBarMessage('Bandcamp album found');
          onDetected(text); // Use the original URL directly
        } else if (isAppleMusic) {
          // For Apple Music/iTunes, we also want direct URL handling
          // Check if it's a valid Apple Music album URL
          final regExp = RegExp(r'/album/[^/]+/(\d+)');
          final match = regExp.firstMatch(text);

          if (match != null && match.groupCount >= 1) {
            final albumId = match.group(1);
            Logging.severe(
                'Valid Apple Music album URL detected with ID: $albumId');
            onSnackBarMessage('Apple Music album found');
          } else {
            Logging.severe(
                'Apple Music URL detected - using direct URL handling');
            onSnackBarMessage('Apple Music link detected');
          }

          onDetected(text); // Use the original URL directly
        } else if (isSpotify) {
          // For Spotify, we also want direct URL handling
          // Check if it's a valid Spotify album URL
          final regExp = RegExp(r'/album/([a-zA-Z0-9]+)');
          final match = regExp.firstMatch(text);

          if (match != null && match.groupCount >= 1) {
            final albumId = match.group(1);
            Logging.severe(
                'Valid Spotify album URL detected with ID: $albumId');
            onSnackBarMessage('Spotify album found');
          } else {
            Logging.severe('Spotify URL detected - using direct URL handling');
            onSnackBarMessage('Spotify link detected');
          }

          onDetected(text); // Use the original URL directly
        } else {
          // For other platforms, use the extracted search query
          if (searchQuery.isEmpty || searchQuery == text) {
            // If extraction failed or returned the original URL, just use the URL directly
            Logging.severe(
                'Could not extract search info, using URL as search query');
            onSnackBarMessage('$platform URL detected');
            onDetected(text);
          } else {
            Logging.severe('Extracted search query from URL: $searchQuery');
            onUrlDetected(text, searchQuery);
            onSnackBarMessage(
                '$platform URL detected - searching for "$searchQuery"');
          }
        }

        // Notify about search completion
        onSearchCompleted(true);

        // Set a timer to reset state after some time
        _resetTimer?.cancel();
        _resetTimer = Timer(Duration(seconds: _autoResetSeconds), () {
          Logging.severe('Resetting clipboard detector state');
          _isProcessingClipboard = false;
        });

        _isProcessingClipboard = false;
        return true;
      } else {
        Logging.severe('No supported music platform detected in URL');
      }
    } catch (e, stack) {
      Logging.severe('Error processing text with music URL', e, stack);
    }

    _isProcessingClipboard = false;
    return false;
  }

  /// This method is called when manual paste happens in the TextField
  static Future<bool> reportManualPaste() async {
    Logging.severe('Manual paste reported - checking clipboard for music URLs');

    try {
      // Check the clipboard for music URLs
      final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
      final text = clipboardData?.text;

      if (text != null && text.isNotEmpty && _containsMusicUrl(text)) {
        Logging.severe('Found music URL in clipboard: $text');
        return true; // Clipboard contains a music URL
      }
    } catch (e) {
      Logging.severe('Error checking clipboard on manual paste', e);
    }

    return false; // No music URL found
  }

  /// Process a manually pasted URL - redirect to the main processText method
  static Future<bool> processManualUrl(
    String url, {
    required Function(String) onDetected,
    required Function(String) onSnackBarMessage,
    required Function(String, String) onUrlDetected,
    required Function(bool) onSearchCompleted,
  }) async {
    // Always reset the processing state to ensure we can process this request
    _isProcessingClipboard = false;

    // Log that we're handling a manual URL input
    Logging.severe('Processing manually entered URL: $url');

    return processText(url,
        onDetected: onDetected,
        onSnackBarMessage: onSnackBarMessage,
        onUrlDetected: onUrlDetected,
        onSearchCompleted: onSearchCompleted);
  }

  /// Temporarily disable notifications
  static void pauseNotifications() {
    // Just a placeholder for API compatibility
  }

  /// Resume notifications
  static void resumeNotifications() {
    // Clear state to allow new processing
    _isProcessingClipboard = false;
    Logging.severe('Clipboard detector reset and ready for new content');
  }
}
