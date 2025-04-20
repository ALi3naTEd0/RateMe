import 'package:shared_preferences/shared_preferences.dart';
import '../logging.dart';
import 'database_helper.dart';
import 'dart:convert';

/// Utility class to completely migrate from SharedPreferences to SQLite
class PreferencesMigration {
  static const String migrationCompletedKey = 'sqlite_migration_completed';

  /// Migrate all remaining SharedPreferences to the database
  static Future<bool> migrateRemainingPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final dbHelper = DatabaseHelper.instance;
      int migratedCount = 0;

      Logging.severe('Starting migration of remaining SharedPreferences...');

      // Get all remaining keys
      final allKeys = prefs.getKeys().toList();
      Logging.severe(
          'Found ${allKeys.length} keys to migrate: ${allKeys.join(", ")}');

      // Process all keys except the migration status key
      for (final key in allKeys) {
        // Skip the migration status key itself
        if (key == migrationCompletedKey) continue;

        if (prefs.containsKey(key)) {
          // Get the value from SharedPreferences based on its type
          dynamic value;

          // Try to determine the type and get the appropriate value
          if (prefs.getString(key) != null) {
            value = prefs.getString(key);
          } else if (prefs.getBool(key) != null) {
            value = prefs.getBool(key).toString();
          } else if (prefs.getInt(key) != null) {
            value = prefs.getInt(key).toString();
          } else if (prefs.getDouble(key) != null) {
            value = prefs.getDouble(key).toString();
          } else if (prefs.getStringList(key) != null) {
            value = jsonEncode(prefs.getStringList(key));
          }

          if (value != null) {
            // Save to database with the same key
            await dbHelper.saveSetting(key, value.toString());
            migratedCount++;

            Logging.severe('Migrated setting: $key = $value');
          }
        }
      }

      // After migrating, clear SharedPreferences to avoid duplication
      // but keep the migration status key
      final migrationCompleted = prefs.getBool(migrationCompletedKey) ?? false;
      await prefs.clear();
      await prefs.setBool(migrationCompletedKey, migrationCompleted);

      Logging.severe(
          'Migration complete. Migrated $migratedCount settings and cleared SharedPreferences.');
      return true;
    } catch (e, stack) {
      Logging.severe('Error migrating remaining preferences', e, stack);
      return false;
    }
  }

  /// Complete final cleanup of SharedPreferences after migration
  static Future<bool> finalCleanup() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Log all remaining keys
      final remainingKeys = prefs.getKeys();
      if (remainingKeys.isNotEmpty) {
        Logging.severe('Performing final cleanup of SharedPreferences');
        Logging.severe('Remaining keys: ${remainingKeys.join(", ")}');

        // Clear all SharedPreferences except migration status key
        await prefs.clear();

        // Set migration completed flag to true
        await prefs.setBool(migrationCompletedKey, true);

        Logging.severe('Final cleanup complete, all SharedPreferences removed');
      } else {
        Logging.severe('No SharedPreferences remain, nothing to clean up');
      }

      return true;
    } catch (e, stack) {
      Logging.severe('Error during final SharedPreferences cleanup', e, stack);
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
