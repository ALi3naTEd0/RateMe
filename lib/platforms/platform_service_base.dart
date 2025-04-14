import 'package:rateme/logging.dart';

/// Base class for platform-specific services
abstract class PlatformServiceBase {
  /// Platform identifier (e.g., 'spotify', 'apple_music')
  String get platformId;

  /// Display name for the platform
  String get displayName;

  /// Find album URL by artist and album name
  Future<String?> findAlbumUrl(String artist, String albumName);

  /// Verify if an album exists
  Future<bool> verifyAlbumExists(String artist, String albumName);

  /// Fetch album details from a URL
  Future<Map<String, dynamic>?> fetchAlbumDetails(String url) async {
    // Default implementation returns null
    // Each platform service will override this with their implementation
    return null;
  }

  /// Normalize strings for better comparison
  String normalizeForComparison(String? input) {
    if (input == null || input.isEmpty) return '';

    // Convert to lowercase and trim
    String normalized = input.toLowerCase().trim();

    // Store the original input before removing qualifiers
    final originalNormalized = normalized;

    // Create a comparison version with removed qualifiers
    String comparisonVersion = normalized
        .replaceAll(' - ep', '')
        .replaceAll('-ep', '') // Handle no space case
        .replaceAll(' ep', '')
        .replaceAll(' - single', '')
        .replaceAll('-single', '') // Handle no space case
        .replaceAll(' single', '')
        .replaceAll(' - deluxe', '')
        .replaceAll('-deluxe', '') // Handle no space case
        .replaceAll(' deluxe', '')
        .replaceAll(' - deluxe edition', '')
        .replaceAll(' deluxe edition', '')
        .replaceAll(' - special edition', '')
        .replaceAll(' special edition', '')
        .replaceAll(' - remastered', '')
        .replaceAll(' remastered', '')
        .replaceAll(' (remastered)', '');

    // Remove special characters
    comparisonVersion = comparisonVersion.replaceAll(RegExp(r'[^\w\s]'), ' ');

    // Replace multiple spaces with a single space
    comparisonVersion =
        comparisonVersion.replaceAll(RegExp(r'\s+'), ' ').trim();

    // If using this for search, keep the original qualified version
    if (normalized.contains('deluxe') ||
        normalized.contains('ep') ||
        normalized.contains('single') ||
        normalized.contains('remastered') ||
        normalized.contains('special edition')) {
      // For search, we want to keep the qualifiers like "Deluxe Edition"
      normalized = originalNormalized;

      // Just clean up spaces and special characters
      normalized = normalized.replaceAll(RegExp(r'[^\w\s\-()]'), ' ');
      normalized = normalized.replaceAll(RegExp(r'\s+'), ' ').trim();

      // Log that we're keeping qualifiers
      Logging.severe('Keeping qualifiers in normalized version: "$normalized"');
    } else {
      // For regular comparison with no special qualifiers, use the simpler version
      normalized = comparisonVersion;
    }

    // Logging to debug
    if (normalized != input.toLowerCase().trim()) {
      Logging.severe('Normalized "$input" to "$normalized" for comparison');
    }

    return normalized;
  }

  /// Calculate similarity between two strings (0.0 to 1.0)
  double calculateStringSimilarity(String s1, String s2) {
    // Handle empty strings
    if (s1.isEmpty && s2.isEmpty) return 1.0;
    if (s1.isEmpty || s2.isEmpty) return 0.0;

    // Check for exact match after normalization
    if (s1 == s2) {
      return 1.0;
    }

    // Calculate Levenshtein distance
    int distance = _levenshteinDistance(s1, s2);
    int maxLength = s1.length > s2.length ? s1.length : s2.length;

    // Convert to similarity score (0.0 to 1.0)
    double similarity = 1.0 - (distance / maxLength);
    return similarity;
  }

  /// Compare strings for artist matching
  bool isArtistMatch(String artist1, String artist2) {
    final similarity = calculateStringSimilarity(artist1, artist2);
    return similarity >= 0.8; // 80% similarity threshold for artists
  }

  /// Compare strings for album matching
  bool isAlbumMatch(String album1, String album2) {
    final similarity = calculateStringSimilarity(album1, album2);
    return similarity >= 0.7; // 70% similarity threshold for albums
  }

  /// Get the base album name (without deluxe/edition/etc.)
  String getBaseAlbumName(String albumName) {
    // Remove common edition qualifiers
    String base = albumName
        .replaceAll(
            RegExp(
                r'\b(deluxe|edition|expanded|remastered|reissue|anniversary|special|bonus|tracks|version|vol|volume)\b',
                caseSensitive: false),
            '')
        .replaceAll(RegExp(r'\([^)]*\)'), '') // Remove anything in parentheses
        .replaceAll(RegExp(r'\[[^\]]*\]'), '') // Remove anything in brackets
        .replaceAll(
            RegExp(r'\s+'), ' ') // Replace multiple spaces with single space
        .trim();

    return base;
  }

  /// Calculate Levenshtein distance between two strings
  int _levenshteinDistance(String s1, String s2) {
    // Create a table to store results of subproblems
    List<List<int>> dp = List.generate(
      s1.length + 1,
      (i) => List.generate(s2.length + 1, (j) => 0),
    );

    // Fill the table
    for (int i = 0; i <= s1.length; i++) {
      for (int j = 0; j <= s2.length; j++) {
        if (i == 0) {
          dp[i][j] = j;
        } else if (j == 0) {
          dp[i][j] = i;
        } else if (s1[i - 1] == s2[j - 1]) {
          dp[i][j] = dp[i - 1][j - 1];
        } else {
          dp[i][j] = 1 +
              [dp[i - 1][j - 1], dp[i - 1][j], dp[i][j - 1]]
                  .reduce((a, b) => a < b ? a : b);
        }
      }
    }

    return dp[s1.length][s2.length];
  }
}
