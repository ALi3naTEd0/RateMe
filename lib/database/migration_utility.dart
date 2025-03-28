import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart'; // Add this import for ConflictAlgorithm
import '../album_model.dart';
import '../logging.dart';
import 'database_helper.dart';

class MigrationUtility {
  static const String migrationCompletedKey = 'sqlite_migration_completed';

  /// Check if migration from SharedPreferences to SQLite has been completed
  static Future<bool> isMigrationCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(migrationCompletedKey) ?? false;
  }

  /// Mark migration as completed
  static Future<void> markMigrationCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(migrationCompletedKey, true);
  }

  /// Force migration status to incomplete for retries
  static Future<void> resetMigrationStatus() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(migrationCompletedKey, false);
    Logging.severe('Migration status reset to incomplete');
  }

  /// Migrate all data from SharedPreferences to SQLite
  static Future<bool> migrateToSQLite(
      {Function(String stage, double progress)? progressCallback}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stats = <String, int>{};
      final db = DatabaseHelper.instance;

      // 1. Migrate albums
      progressCallback?.call('Migrating albums...', 0.2);
      await _migrateAlbums(
        prefs,
        db,
        stats,
        (processed, total) {
          final progress = total > 0 ? processed / total : 0.0;
          progressCallback?.call('Migrating albums...', 0.2 + (progress * 0.3));
        },
      );

      // 2. Migrate ratings
      progressCallback?.call('Migrating ratings...', 0.5);
      await _migrateRatings(prefs, db, stats);

      // 3. Migrate custom lists
      progressCallback?.call('Migrating lists...', 0.7);
      await _migrateLists(prefs, db, stats);

      // 4. Migrate album order
      progressCallback?.call('Migrating album order...', 0.8);
      await _migrateAlbumOrder(prefs, db, stats);

      // 5. Migrate settings
      progressCallback?.call('Migrating settings...', 0.9);
      await _migrateSettings(prefs, db, stats);

      // Mark migration as completed
      await markMigrationCompleted();

      progressCallback?.call('Migration completed!', 1.0);

      Logging.severe('Migration completed successfully: $stats');
      return true;
    } catch (e, stack) {
      Logging.severe('Error during migration', e, stack);
      return false;
    }
  }

  /// Migrate saved albums with progress tracking
  static Future<void> _migrateAlbums(
      SharedPreferences prefs,
      DatabaseHelper db,
      Map<String, int> stats,
      Function(int processedCount, int totalCount)? progressCallback) async {
    Logging.severe('Migrating albums');

    final List<String> savedAlbums = prefs.getStringList('saved_albums') ?? [];
    if (savedAlbums.isEmpty) {
      Logging.severe('No albums to migrate');
      stats['albums'] = 0;
      return;
    }

    int successCount = 0;
    int errorCount = 0;
    int trackCount = 0;
    int totalAlbums = savedAlbums.length;

    for (int i = 0; i < savedAlbums.length; i++) {
      try {
        // Load album data
        final albumJson = jsonDecode(savedAlbums[i]);

        // Create Album object
        final album = Album.fromLegacy(albumJson);

        // Save to database - fixed void result usage
        await db.insertAlbum(album);

        // Update progress
        progressCallback?.call(i + 1, totalAlbums);

        // Count tracks
        trackCount += album.tracks.length;
        successCount++;

        Logging.severe('Migrated album: ${album.name} by ${album.artist}');
      } catch (e) {
        Logging.severe('Error migrating album at index $i: $e');
        errorCount++;
      }
    }

    // Update stats
    stats['albums'] = successCount;
    stats['tracks'] = trackCount;

    Logging.severe(
        'Album migration completed: $successCount success, $errorCount errors');
  }

  /// Migrate ratings
  static Future<void> _migrateRatings(SharedPreferences prefs,
      DatabaseHelper db, Map<String, int> stats) async {
    Logging.severe('Migrating ratings');

    int totalRatings = 0;
    int migratedRatings = 0;

    // Find all ratings keys - they start with 'saved_ratings_'
    final allKeys = prefs.getKeys();
    final ratingKeys =
        allKeys.where((key) => key.startsWith('saved_ratings_')).toList();

    for (String key in ratingKeys) {
      try {
        // Extract album ID from key
        final albumId = key.replaceFirst('saved_ratings_', '');

        // Get ratings for this album
        final ratingsList = prefs.getStringList(key) ?? [];

        for (String ratingJson in ratingsList) {
          try {
            final ratingData = jsonDecode(ratingJson);
            final trackId = ratingData['trackId'].toString();
            final rating = ratingData['rating']?.toDouble() ?? 0.0;

            // Save to database
            await db.saveRating(albumId, trackId, rating);
            migratedRatings++;
          } catch (e) {
            Logging.severe('Error migrating rating: $e');
          }
        }

        totalRatings += ratingsList.length;
      } catch (e) {
        Logging.severe('Error migrating ratings for key $key: $e');
      }
    }

    // Update stats
    stats['ratings'] = migratedRatings;

    Logging.severe(
        'Ratings migration completed: $migratedRatings of $totalRatings migrated');
  }

  /// Migrate custom lists
  static Future<void> _migrateLists(SharedPreferences prefs, DatabaseHelper db,
      Map<String, int> stats) async {
    try {
      Logging.severe('Migrating custom lists');

      final List<String> customLists =
          prefs.getStringList('custom_lists') ?? [];
      if (customLists.isEmpty) {
        Logging.severe('No custom lists to migrate');
        return;
      }

      final database = await db.database;

      // Check table schema to determine field names
      final columns =
          await database.rawQuery('PRAGMA table_info(custom_lists)');
      final columnNames = columns.map((c) => c['name'].toString()).toList();
      Logging.severe('Custom lists table schema: $columnNames');

      // Determine what timestamp fields to use
      final useSnakeCase = columnNames.contains('created_at');

      for (var listJson in customLists) {
        try {
          final listData = jsonDecode(listJson);

          // Handle field name format based on schema
          final Map<String, dynamic> insertData = {
            'id': listData['id'],
            'name': listData['name'],
            'description': listData['description'] ?? '',
          };

          // Add timestamps in the correct format
          if (useSnakeCase) {
            insertData['created_at'] = listData['createdAt'];
            insertData['updated_at'] =
                listData['updatedAt'] ?? listData['createdAt'];
          } else {
            insertData['createdAt'] = listData['createdAt'];
            insertData['updatedAt'] =
                listData['updatedAt'] ?? listData['createdAt'];
          }

          await database.insert(
            'custom_lists',
            insertData,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );

          // Insert album-list relationships
          if (listData['albumIds'] is List) {
            final albumIds = List<String>.from(listData['albumIds']);
            for (int i = 0; i < albumIds.length; i++) {
              await database.insert(
                'album_lists',
                {
                  'list_id': listData['id'],
                  'album_id': albumIds[i],
                  'position': i,
                },
                conflictAlgorithm: ConflictAlgorithm.replace,
              );
            }
          }

          stats['lists'] = (stats['lists'] ?? 0) + 1;
        } catch (e, stack) {
          Logging.severe('Error migrating list', e, stack);
        }
      }

      Logging.severe('Migrated ${stats['lists']} custom lists');
    } catch (e, stack) {
      Logging.severe('Error migrating custom lists', e, stack);
    }
  }

  /// Migrate album order
  static Future<void> _migrateAlbumOrder(SharedPreferences prefs,
      DatabaseHelper db, Map<String, int> stats) async {
    Logging.severe('Migrating album order');

    // Get album order
    final albumOrder = prefs.getStringList('album_order') ?? [];

    if (albumOrder.isNotEmpty) {
      // Save to database
      await db.saveAlbumOrder(albumOrder);

      stats['albumOrder'] = albumOrder.length;
      Logging.severe('Migrated album order with ${albumOrder.length} items');
    } else {
      stats['albumOrder'] = 0;
      Logging.severe('No album order to migrate');
    }
  }

  /// Migrate settings
  static Future<void> _migrateSettings(SharedPreferences prefs,
      DatabaseHelper db, Map<String, int> stats) async {
    Logging.severe('Migrating settings');

    int migratedSettings = 0;

    // Known settings to migrate
    final settingsToMigrate = [
      'themeMode',
      'primaryColor',
      'useDarkButtonText',
    ];

    for (String key in settingsToMigrate) {
      try {
        if (prefs.containsKey(key)) {
          final value = prefs.get(key);
          if (value != null) {
            await db.saveSetting(key, value.toString());
            migratedSettings++;
          }
        }
      } catch (e) {
        Logging.severe('Error migrating setting $key: $e');
      }
    }

    // Update stats
    stats['settings'] = migratedSettings;

    Logging.severe('Settings migration completed: $migratedSettings settings');
  }
}
