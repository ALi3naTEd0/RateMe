import 'package:http/http.dart' as http;
import 'database/api_key_manager.dart';
import 'logging.dart';
import 'package:sqflite/sqflite.dart';
import 'database/database_helper.dart';

/// Class to provide API keys for various services
class ApiKeys {
  static ApiKeys? _instance;

  // Default constructor is private
  ApiKeys._();

  // Singleton instance
  static ApiKeys get instance {
    _instance ??= ApiKeys._();
    return _instance!;
  }

  // Initialize the API key manager
  static Future<void> initialize() async {
    await ApiKeyManager.instance.initialize();
  }

  // SPOTIFY KEYS

  /// Get Spotify client ID
  static Future<String?> get spotifyClientId async {
    try {
      final db = await DatabaseHelper.instance.database;
      final result = await db.query(
        'settings',
        columns: ['value'],
        where: 'key = ?',
        whereArgs: ['spotify_client_id'],
      );

      return result.isNotEmpty ? result.first['value'] as String? : null;
    } catch (e) {
      Logging.severe('Error getting Spotify client ID: $e');
      return null;
    }
  }

  /// Get Spotify client secret
  static Future<String?> get spotifyClientSecret async {
    try {
      final db = await DatabaseHelper.instance.database;
      final result = await db.query(
        'settings',
        columns: ['value'],
        where: 'key = ?',
        whereArgs: ['spotify_client_secret'],
      );

      return result.isNotEmpty ? result.first['value'] as String? : null;
    } catch (e) {
      Logging.severe('Error getting Spotify client secret: $e');
      return null;
    }
  }

  /// Save Spotify API keys
  static Future<void> saveSpotifyKeys(
      String clientId, String clientSecret) async {
    try {
      final db = await DatabaseHelper.instance.database;

      // Save client ID
      await db.insert(
        'settings',
        {'key': 'spotify_client_id', 'value': clientId},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      // Save client secret
      await db.insert(
        'settings',
        {'key': 'spotify_client_secret', 'value': clientSecret},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      Logging.severe('Saved Spotify API keys');
    } catch (e) {
      Logging.severe('Error saving Spotify API keys: $e');
    }
  }

  /// Check if Spotify connection is working
  static Future<bool> isSpotifyConnected() async {
    try {
      final clientId = await spotifyClientId;
      final clientSecret = await spotifyClientSecret;

      if (clientId == null ||
          clientSecret == null ||
          clientId.isEmpty ||
          clientSecret.isEmpty) {
        return false;
      }

      // Try to get a token to verify credentials
      final response = await http.post(
        Uri.parse('https://accounts.spotify.com/api/token'),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {
          'grant_type': 'client_credentials',
          'client_id': clientId,
          'client_secret': clientSecret,
        },
      );

      return response.statusCode == 200;
    } catch (e) {
      Logging.severe('Error checking Spotify connection: $e');
      return false;
    }
  }

  /// Test the Spotify credentials by attempting to get a token
  static Future<bool> testSpotifyCredentials(
      String clientId, String clientSecret) async {
    try {
      Logging.severe('Testing Spotify credentials');

      // Use the same method as in _getSpotifyAccessToken - credentials in POST body
      final response = await http.post(
        Uri.parse('https://accounts.spotify.com/api/token'),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {
          'grant_type': 'client_credentials',
          'client_id': clientId,
          'client_secret': clientSecret,
        },
      );

      if (response.statusCode == 200) {
        Logging.severe('Spotify credentials test: SUCCESS');
        return true;
      } else {
        Logging.severe(
            'Spotify credentials test: FAILED - ${response.statusCode} ${response.body}');
        return false;
      }
    } catch (e) {
      Logging.severe('Error testing Spotify credentials: $e');
      return false;
    }
  }

  // Add connection status methods

  /// Check if Discogs connection is working
  static Future<bool> isDiscogsConnected() async {
    try {
      final key = await discogsConsumerKey;
      final secret = await discogsConsumerSecret;

      if (key == null || secret == null || key.isEmpty || secret.isEmpty) {
        return false;
      }

      // Use a simple Discogs API endpoint to test
      final response = await http.get(
        Uri.parse(
            'https://api.discogs.com/database/search?q=test&key=$key&secret=$secret'),
      );

      return response.statusCode == 200;
    } catch (e) {
      Logging.severe('Error checking Discogs connection: $e');
      return false;
    }
  }

  // DISCOGS KEYS

  /// Get Discogs consumer key
  static Future<String?> get discogsConsumerKey async {
    try {
      final db = await DatabaseHelper.instance.database;
      final result = await db.query(
        'settings',
        columns: ['value'],
        where: 'key = ?',
        whereArgs: ['discogs_consumer_key'],
      );

      return result.isNotEmpty ? result.first['value'] as String? : null;
    } catch (e) {
      Logging.severe('Error getting Discogs consumer key: $e');
      return null;
    }
  }

  /// Get Discogs consumer secret
  static Future<String?> get discogsConsumerSecret async {
    try {
      final db = await DatabaseHelper.instance.database;
      final result = await db.query(
        'settings',
        columns: ['value'],
        where: 'key = ?',
        whereArgs: ['discogs_consumer_secret'],
      );

      return result.isNotEmpty ? result.first['value'] as String? : null;
    } catch (e) {
      Logging.severe('Error getting Discogs consumer secret: $e');
      return null;
    }
  }

  /// Save Discogs API keys
  static Future<void> saveDiscogsKeys(
      String consumerKey, String consumerSecret) async {
    try {
      final db = await DatabaseHelper.instance.database;

      // Save consumer key
      await db.insert(
        'settings',
        {'key': 'discogs_consumer_key', 'value': consumerKey},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      // Save consumer secret
      await db.insert(
        'settings',
        {'key': 'discogs_consumer_secret', 'value': consumerSecret},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      Logging.severe('Saved Discogs API keys');
    } catch (e) {
      Logging.severe('Error saving Discogs API keys: $e');
    }
  }

  /// Check if Spotify keys are configured
  static Future<bool> get hasSpotifyKeys async {
    return await ApiKeyManager.instance.hasApiKey('spotify');
  }

  /// Check if Discogs keys are configured
  static Future<bool> get hasDiscogsKeys async {
    return await ApiKeyManager.instance.hasApiKey('discogs');
  }

  // Helper methods

  /// Delete all API keys
  static Future<void> deleteAllKeys() async {
    await ApiKeyManager.instance.deleteApiKey('spotify');
    await ApiKeyManager.instance.deleteApiKey('discogs');
    Logging.severe('All API keys deleted');
  }
}

class ApiEndpoints {
  // Discogs endpoints
  static const String discogsBaseUrl = 'https://api.discogs.com';
  static const String discogsSearch = '/database/search';
  static const String discogsReleases = '/releases';
  static const String discogsMasters = '/masters';
}
