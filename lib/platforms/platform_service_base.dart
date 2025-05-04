import 'dart:math' as math;

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

      // REMOVED: Don't log "Keeping qualifiers" messages anymore
    } else {
      // For regular comparison with no special qualifiers, use the simpler version
      normalized = comparisonVersion;
    }

    // REMOVED: No more logging of every normalization operation

    return normalized;
  }

  /// Calculate similarity between two strings (0.0 to 1.0)
  double calculateStringSimilarity(String s1, String s2) {
    // Handle empty strings
    if (s1.isEmpty && s2.isEmpty) return 1.0;
    if (s1.isEmpty || s2.isEmpty) return 0.0;

    // IMPROVED: Better handling for spaced-out artist names like "E L U C I D"
    // Only apply this when one string appears to be spaced letters (containing multiple single letters separated by spaces)
    bool isSpacedLetters1 = _isSpacedLetterFormat(s1);
    bool isSpacedLetters2 = _isSpacedLetterFormat(s2);

    if (isSpacedLetters1 || isSpacedLetters2) {
      // Remove all spaces for comparison
      String s1NoSpaces = s1.replaceAll(' ', '');
      String s2NoSpaces = s2.replaceAll(' ', '');

      // If they match exactly after removing spaces, consider it a perfect match
      if (s1NoSpaces.toLowerCase() == s2NoSpaces.toLowerCase()) {
        return 1.0;
      }

      // If not exact, but still similar after space removal, give a high score
      double noSpaceSimilarity = 1.0 -
          (_levenshteinDistance(
                  s1NoSpaces.toLowerCase(), s2NoSpaces.toLowerCase()) /
              math.max(s1NoSpaces.length, s2NoSpaces.length));
      if (noSpaceSimilarity > 0.8) {
        return noSpaceSimilarity;
      }
    }

    // Check for exact match after normalization
    if (s1 == s2) {
      return 1.0;
    }

    // Calculate Levenshtein distance for non-exact matches
    int distance = _levenshteinDistance(s1, s2);
    int maxLength = math.max(s1.length, s2.length);

    // Convert to similarity score (0.0 to 1.0)
    double similarity = 1.0 - (distance / maxLength);
    return similarity;
  }

  /// Determines if a string looks like it has intentional spaces between letters (like "E L U C I D")
  bool _isSpacedLetterFormat(String input) {
    // First check if string contains multiple spaces
    if (!input.contains(' ')) return false;

    // Count single letters followed by spaces
    List<String> parts = input.split(' ');

    // If most parts are single letters, it's probably a spaced-letter format
    int singleLetterCount = parts.where((part) => part.length == 1).length;

    // Consider it spaced-letter format if more than 60% are single letters and at least 2 single letters
    return singleLetterCount >= 2 && singleLetterCount / parts.length > 0.6;
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
