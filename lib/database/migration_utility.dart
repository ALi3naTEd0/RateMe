import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../album_model.dart';
import '../logging.dart';
import '../custom_lists_page.dart';
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
      Logging.severe('Starting migration from SharedPreferences to SQLite');

      // Reset migration status first to ensure it runs
      await resetMigrationStatus();

      final prefs = await SharedPreferences.getInstance();
      final db = DatabaseHelper.instance;

      // Create a stats object to track migration progress
      final migrationStats = {
        'albums': 0,
        'tracks': 0,
        'ratings': 0,
        'lists': 0,
        'listAlbums': 0,
      };

      // Check if there are albums to migrate
      final List<String> savedAlbums =
          prefs.getStringList('saved_albums') ?? [];
      if (savedAlbums.isEmpty) {
        Logging.severe('No albums found in SharedPreferences to migrate');
        return false;
      }

      progressCallback?.call('Starting migration', 0.1);

      Logging.severe('Found ${savedAlbums.length} albums in SharedPreferences');

      // 1. Migrate saved albums
      progressCallback?.call('Migrating albums', 0.2);
      await _migrateAlbums(
          prefs,
          db,
          migrationStats,
          (count, total) => progressCallback?.call(
              'Migrating albums ($count/$total)', 0.2 + (0.3 * count / total)));

      // 2. Migrate ratings
      progressCallback?.call('Migrating ratings', 0.5);
      await _migrateRatings(prefs, db, migrationStats);

      // 3. Migrate custom lists
      progressCallback?.call('Migrating custom lists', 0.7);
      await _migrateLists(prefs, db, migrationStats);

      // 4. Migrate album order
      progressCallback?.call('Migrating album order', 0.8);
      await _migrateAlbumOrder(prefs, db);

      // 5. Migrate settings
      progressCallback?.call('Migrating settings', 0.9);
      await _migrateSettings(prefs, db);

      // Verify migration was successful before marking complete
      progressCallback?.call('Verifying data', 0.95);
      final albums = await db.getAllAlbums();
      if (albums.isEmpty && savedAlbums.isNotEmpty) {
        Logging.severe(
            'Migration verification failed - no albums in database despite successful process');
        return false;
      }

      // Mark migration as completed only if verification passed
      await markMigrationCompleted();

      progressCallback?.call('Migration complete', 1.0);

      Logging.severe(
          'Migration completed successfully with the following stats:');
      Logging.severe('- Albums: ${migrationStats['albums']}');
      Logging.severe('- Tracks: ${migrationStats['tracks']}');
      Logging.severe('- Ratings: ${migrationStats['ratings']}');
      Logging.severe('- Lists: ${migrationStats['lists']}');
      Logging.severe('- Albums in lists: ${migrationStats['listAlbums']}');

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
      return;
    }

    int successCount = 0;
    int errorCount = 0;
    int trackCount = 0;
    int totalAlbums = savedAlbums.length;

    for (int i = 0; i < savedAlbums.length; i++) {
      String albumJson = savedAlbums[i];
      try {
        final Map<String, dynamic> albumData = jsonDecode(albumJson);
        Logging.severe(
            'Migrating album: ${albumData['collectionName'] ?? albumData['name'] ?? 'Unknown Album'}');

        // Convert to Album model
        Album album;
        try {
          // Try to parse as new model first
          album = Album.fromJson(albumData);
        } catch (e) {
          // Fall back to legacy format
          album = Album.fromLegacy(albumData);
        }

        // Count tracks in the album
        trackCount += album.tracks.length;

        // Insert into database
        final insertResult = await db.insertAlbum(album);
        Logging.severe('Album inserted with result: $insertResult');

        successCount++;

        // Report progress
        progressCallback?.call(i + 1, totalAlbums);
      } catch (e, stack) {
        Logging.severe('Error migrating album', e, stack);
        errorCount++;
      }
    }

    // Update stats
    stats['albums'] = successCount;
    stats['tracks'] = trackCount;

    Logging.severe(
        'Album migration complete: $successCount successful, $errorCount failed, $trackCount tracks');
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
        final List<String> ratingsJson = prefs.getStringList(key) ?? [];
        final String albumId = key.replaceFirst('saved_ratings_', '');

        for (String ratingJson in ratingsJson) {
          try {
            final Map<String, dynamic> rating = jsonDecode(ratingJson);

            // Skip if missing required fields
            if (!rating.containsKey('trackId') ||
                !rating.containsKey('rating')) {
              continue;
            }

            // Save rating to database
            await db.saveRating(
              albumId.toString(),
              rating['trackId'].toString(),
              rating['rating'].toDouble(),
            );

            migratedRatings++;
          } catch (e) {
            Logging.severe('Error parsing rating JSON: $e');
          }
          totalRatings++;
        }
      } catch (e) {
        Logging.severe('Error migrating ratings for key $key: $e');
      }
    }

    // Update stats
    stats['ratings'] = migratedRatings;

    Logging.severe(
        'Ratings migration complete: $migratedRatings of $totalRatings migrated');
  }

  /// Migrate custom lists
  static Future<void> _migrateLists(SharedPreferences prefs, DatabaseHelper db,
      Map<String, int> stats) async {
    Logging.severe('Migrating custom lists');

    final List<String> customListsJson =
        prefs.getStringList('custom_lists') ?? [];
    if (customListsJson.isEmpty) {
      Logging.severe('No custom lists to migrate');
      return;
    }

    int successCount = 0;
    int totalAlbumsInLists = 0;

    for (String listJson in customListsJson) {
      try {
        final Map<String, dynamic> listData = jsonDecode(listJson);

        // Parse as CustomList model
        final CustomList list = CustomList.fromJson(listData);

        // Insert list in database
        await db.insertCustomList({
          'id': list.id,
          'name': list.name,
          'description': list.description,
          'createdAt': list.createdAt.toIso8601String(),
          'updatedAt': list.updatedAt.toIso8601String(),
        });

        // Add album-list relationships
        for (int i = 0; i < list.albumIds.length; i++) {
          await db.addAlbumToList(list.albumIds[i], list.id, i);
        }

        // Update stats
        totalAlbumsInLists += list.albumIds.length;
        successCount++;
      } catch (e) {
        Logging.severe('Error migrating list: $e');
      }
    }

    // Update stats
    stats['lists'] = successCount;
    stats['listAlbums'] = totalAlbumsInLists;

    Logging.severe(
        'Custom lists migration complete: $successCount of ${customListsJson.length} migrated with $totalAlbumsInLists total albums in lists');
  }

  /// Migrate album order
  static Future<void> _migrateAlbumOrder(
      SharedPreferences prefs, DatabaseHelper db) async {
    Logging.severe('Migrating album order');

    final List<String> albumOrder =
        prefs.getStringList('saved_album_order') ?? [];
    if (albumOrder.isEmpty) {
      Logging.severe('No album order to migrate');
      return;
    }

    await db.saveAlbumOrder(albumOrder);

    Logging.severe(
        'Album order migration complete: ${albumOrder.length} albums in order');
  }

  /// Migrate settings
  static Future<void> _migrateSettings(
      SharedPreferences prefs, DatabaseHelper db) async {
    Logging.severe('Migrating settings');

    // List of settings keys to migrate
    final settingsKeys = [
      'themeMode',
      'primaryColor',
      'useDarkButtonText',
      // Add any other settings keys you want to migrate
    ];

    for (String key in settingsKeys) {
      if (prefs.containsKey(key)) {
        var value = prefs.get(key);
        if (value != null) {
          await db.saveSetting(key, value.toString());
          Logging.severe('Migrated setting: $key = $value');
        }
      }
    }

    Logging.severe('Settings migration complete');
  }
}
