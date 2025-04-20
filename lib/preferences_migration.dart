import 'package:shared_preferences/shared_preferences.dart';
import 'logging.dart';
import 'database/database_helper.dart';

/// Utility class to completely migrate from SharedPreferences to SQLite
class PreferencesMigration {
  /// Migrate all remaining SharedPreferences to the database
  static Future<bool> migrateRemainingPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final dbHelper = DatabaseHelper.instance;
      int migratedCount = 0;

      Logging.severe('Starting migration of remaining SharedPreferences...');

      // List of all keys to migrate
      final keysToMigrate = [
        'themeMode',
        'local_music_directory',
        'useDarkButtonText',
        'primaryColor',
        'album_sort_order',
        'music_folder_path',
        'spotify_access_token',
        'spotify_token_expiry',
        'default_platform',
        'defaultSearchPlatform',
        'searchPlatform',
        // Add any others that might be discovered
      ];

      for (final key in keysToMigrate) {
        if (prefs.containsKey(key)) {
          // Get the value from SharedPreferences
          final value = prefs.get(key);

          if (value != null) {
            // Save to database with the same key
            await dbHelper.saveSetting(key, value.toString());
            migratedCount++;

            Logging.severe('Migrated setting: $key = $value');
          }
        }
      }

      // After migrating, optionally clear SharedPreferences to avoid duplication
      for (final key in keysToMigrate) {
        await prefs.remove(key);
      }

      Logging.severe(
          'Migration complete. Migrated $migratedCount settings and cleared SharedPreferences.');
      return true;
    } catch (e, stack) {
      Logging.severe('Error migrating remaining preferences', e, stack);
      return false;
    }
  }

  /// Check if any SharedPreferences still exist
  static Future<bool> hasRemainingPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      return keys.isNotEmpty;
    } catch (e) {
      Logging.severe('Error checking remaining preferences: $e');
      return false;
    }
  }

  /// List all remaining SharedPreferences
  static Future<List<String>> getRemainingPreferenceKeys() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getKeys().toList();
    } catch (e) {
      Logging.severe('Error getting remaining preference keys: $e');
      return [];
    }
  }
}
