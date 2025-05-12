import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/models/album_model.dart';
import '../core/services/logging.dart';
import 'database_helper.dart';

/// Service to handle safe migration of legacy data to new model format
class DataMigrationService {
  static const String _migratedVersionKey = 'data_migration_version';
  static const String _savedAlbumsKey = 'saved_albums';
  static const String _savedAlbumOrderKey = 'saved_album_order';
  static const int _currentVersion = 1;

  /// Check if migration is needed
  static Future<bool> isMigrationNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    final currentVersion = prefs.getInt(_migratedVersionKey) ?? 0;
    return currentVersion < _currentVersion;
  }

  /// Migrate one album and return the new model
  static Future<Album?> migrateAlbum(Map<String, dynamic> legacyAlbum) async {
    try {
      // Try to convert to new model
      Album newModel = Album.fromLegacy(legacyAlbum);

      // Log success
      Logging.severe(
          'Successfully converted album: ${newModel.name} to new model');

      return newModel;
    } catch (e, stack) {
      Logging.severe(
          'Failed to migrate album: ${legacyAlbum['collectionName']}',
          e,
          stack);
      return null;
    }
  }

  /// Migrate all albums in background - returns count of migrated albums
  static Future<int> migrateAllAlbums({bool forceRemigration = false}) async {
    final prefs = await SharedPreferences.getInstance();

    // Skip if migration already done (unless forced)
    if (!forceRemigration) {
      final currentVersion = prefs.getInt(_migratedVersionKey) ?? 0;
      if (currentVersion >= _currentVersion) {
        Logging.severe('Migration already completed (v$currentVersion)');
        return 0;
      }
    }

    try {
      // 1. Get all legacy albums
      List<String> savedAlbumsJson = prefs.getStringList(_savedAlbumsKey) ?? [];
      List<String> albumOrder = prefs.getStringList(_savedAlbumOrderKey) ?? [];

      if (savedAlbumsJson.isEmpty) {
        Logging.severe('No albums to migrate');
        await prefs.setInt(_migratedVersionKey, _currentVersion);
        return 0;
      }

      // 2. Create backup of existing data (IMPORTANT!)
      await prefs.setStringList('backup_saved_albums', savedAlbumsJson);
      await prefs.setStringList('backup_album_order', albumOrder);
      await prefs.setString(
          'backup_timestamp', DateTime.now().toIso8601String());

      Logging.severe('Created backup before migration');

      // 3. Convert each album and maintain a list of successfully migrated albums
      List<Album> migratedAlbums = [];
      List<String> migratedAlbumsJson = [];
      List<String> newAlbumOrder = [];

      for (String albumJson in savedAlbumsJson) {
        try {
          Map<String, dynamic> legacyAlbum = jsonDecode(albumJson);
          Album? newModel = await migrateAlbum(legacyAlbum);

          if (newModel != null) {
            migratedAlbums.add(newModel);
            migratedAlbumsJson.add(jsonEncode(newModel.toJson()));
            newAlbumOrder.add(newModel.id.toString());
          } else {
            // If migration fails for this album, keep the original data
            migratedAlbumsJson.add(albumJson);
            newAlbumOrder.add(legacyAlbum['collectionId'].toString());
          }
        } catch (e) {
          Logging.severe('Error migrating individual album', e);
          // Keep the original JSON on error
          migratedAlbumsJson.add(albumJson);
        }
      }

      // 4. Store the updated data
      if (migratedAlbumsJson.isNotEmpty) {
        // Store new format albums in separate key until we're sure everything works
        await prefs.setStringList('migrated_saved_albums', migratedAlbumsJson);
        await prefs.setStringList('migrated_album_order', newAlbumOrder);

        // Mark migration as complete
        await prefs.setInt(_migratedVersionKey, _currentVersion);

        return migratedAlbums.length;
      } else {
        Logging.severe(
            'Migration resulted in empty albums list - keeping original data');
        return 0;
      }
    } catch (e, stack) {
      Logging.severe('Error during full migration process', e, stack);
      return 0;
    }
  }

  /// Activate migrated data (replace old data with migrated data)
  static Future<bool> activateMigratedData() async {
    final prefs = await SharedPreferences.getInstance();

    try {
      // Check if migrated data exists
      List<String>? migratedAlbums =
          prefs.getStringList('migrated_saved_albums');
      List<String>? migratedOrder = prefs.getStringList('migrated_album_order');

      if (migratedAlbums == null || migratedAlbums.isEmpty) {
        Logging.severe('No migrated data to activate');
        return false;
      }

      // Replace actual data with migrated data
      await prefs.setStringList(_savedAlbumsKey, migratedAlbums);
      await prefs.setStringList(_savedAlbumOrderKey, migratedOrder ?? []);

      // Clean up temporary migration data
      await prefs.remove('migrated_saved_albums');
      await prefs.remove('migrated_album_order');

      Logging.severe('Successfully activated migrated data');
      return true;
    } catch (e) {
      Logging.severe('Error activating migrated data', e);
      return false;
    }
  }

  /// Rollback to pre-migration data if something goes wrong
  static Future<bool> rollbackMigration() async {
    final prefs = await SharedPreferences.getInstance();

    try {
      Logging.severe('Starting migration rollback');

      // Check if backup data exists
      List<String>? backupAlbums = prefs.getStringList('backup_saved_albums');
      List<String>? backupOrder = prefs.getStringList('backup_album_order');

      if (backupAlbums == null || backupAlbums.isEmpty) {
        Logging.severe('No backup data to rollback to');
        return false;
      }

      // Restore from backup
      await prefs.setStringList(_savedAlbumsKey, backupAlbums);
      await prefs.setStringList(_savedAlbumOrderKey, backupOrder ?? []);

      // Reset migration status
      await prefs.remove(_migratedVersionKey);

      // Clear any broken or partial migration data
      await prefs.remove('migrated_saved_albums');
      await prefs.remove('migrated_album_order');

      Logging.severe(
          'Successfully rolled back to backup data (${backupAlbums.length} albums)');
      return true;
    } catch (e) {
      Logging.severe('Error rolling back migration', e);
      return false;
    }
  }

  /// Migrate all albums to the new model format
  static Future<int> migrateAlbumsToNewModel() async {
    try {
      Logging.severe('Starting album model migration...');
      final db = await DatabaseHelper.instance.database;
      int migratedCount = 0;

      // Get all albums
      final albums = await db.query('albums');

      Logging.severe('Found ${albums.length} albums to check for migration');

      // Migrate each album to new format
      for (final albumMap in albums) {
        try {
          // Skip albums that already have modelVersion in their data
          final dataString = albumMap['data']?.toString() ?? '';
          if (dataString.contains('modelVersion')) {
            Logging.severe('Album ID ${albumMap['id']} already migrated');
            continue;
          }

          // Create Album object from legacy format
          final album = Album.fromJson(albumMap);

          // Convert to new format (this adds modelVersion: 1)
          final newData = album.toJson();

          // Update in database
          await db.update(
            'albums',
            {'data': newData.toString()},
            where: 'id = ?',
            whereArgs: [albumMap['id']],
          );

          migratedCount++;

          if (migratedCount % 10 == 0) {
            Logging.severe('Migrated $migratedCount albums so far');
          }
        } catch (e) {
          Logging.severe('Error migrating album ${albumMap['id']}: $e');
        }
      }

      Logging.severe(
          'Album model migration complete. Migrated $migratedCount albums.');
      return migratedCount;
    } catch (e, stack) {
      Logging.severe('Error during album model migration', e, stack);
      return 0;
    }
  }
}
