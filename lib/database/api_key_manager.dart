import 'package:sqflite/sqflite.dart';
import '../core/services/logging.dart';
import 'database_helper.dart';

/// Manages API keys stored in the database
class ApiKeyManager {
  static final ApiKeyManager instance = ApiKeyManager._privateConstructor();

  ApiKeyManager._privateConstructor();

  /// Initialize the API key manager
  Future<void> initialize() async {
    try {
      final db = await DatabaseHelper.instance.database;

      // Create API keys table if it doesn't exist
      await db.execute('''
        CREATE TABLE IF NOT EXISTS api_keys (
          platform TEXT PRIMARY KEY,
          key TEXT,
          secret TEXT,
          created_at TEXT
        )
      '''); // Fixed: Added missing closing parenthesis here

      Logging.severe('API key manager initialized successfully');
    } catch (e, stack) {
      Logging.severe('Error initializing API key manager', e, stack);
    }
  }

  /// Save an API key for a platform
  Future<void> saveApiKey(String platform, String key, [String? secret]) async {
    try {
      final db = await DatabaseHelper.instance.database;

      await db.insert(
        'api_keys',
        {
          'platform': platform,
          'key': key,
          'secret': secret,
          'created_at': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      Logging.severe('Saved API key for platform: $platform');
    } catch (e, stack) {
      Logging.severe('Error saving API key for $platform', e, stack);
    }
  }

  /// Get an API key for a platform
  Future<Map<String, String?>> getApiKey(String platform) async {
    try {
      final db = await DatabaseHelper.instance.database;

      final results = await db.query(
        'api_keys',
        where: 'platform = ?',
        whereArgs: [platform],
      );

      if (results.isNotEmpty) {
        return {
          'key': results.first['key'] as String?,
          'secret': results.first['secret'] as String?,
        };
      }

      return {'key': null, 'secret': null};
    } catch (e, stack) {
      Logging.severe('Error getting API key for $platform', e, stack);
      return {'key': null, 'secret': null};
    }
  }

  /// Delete an API key for a platform
  Future<void> deleteApiKey(String platform) async {
    try {
      final db = await DatabaseHelper.instance.database;

      await db.delete(
        'api_keys',
        where: 'platform = ?',
        whereArgs: [platform],
      );

      Logging.severe('Deleted API key for platform: $platform');
    } catch (e, stack) {
      Logging.severe('Error deleting API key for $platform', e, stack);
    }
  }

  /// Check if an API key exists for a platform
  Future<bool> hasApiKey(String platform) async {
    try {
      final db = await DatabaseHelper.instance.database;

      final results = await db.query(
        'api_keys',
        where: 'platform = ?',
        whereArgs: [platform],
      );

      return results.isNotEmpty && results.first['key'] != null;
    } catch (e, stack) {
      Logging.severe('Error checking API key for $platform', e, stack);
      return false;
    }
  }

  /// Get all stored API keys
  Future<List<Map<String, dynamic>>> getAllApiKeys() async {
    try {
      final db = await DatabaseHelper.instance.database;
      return await db.query('api_keys');
    } catch (e, stack) {
      Logging.severe('Error getting all API keys', e, stack);
      return [];
    }
  }
}
